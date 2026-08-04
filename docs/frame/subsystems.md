# 子系统

## 1. 备份体系（`lib/app/backup/`）

### 组件

| 组件 | 职责 |
| --- | --- |
| `BackupCoordinator` | 静态调度：`maybeBackupOnOpen`（打开/回前台）、`maybeBackupAfterEntry`（记一笔后），内部加运行锁防并发 |
| `BackupService` | 备份内容准备、手动/自动备份写入、写后校验（写回读比对）、自动备份保留清理、列出/读取备份 |
| `backup_crypto` | 纯 Dart AES-GCM 认证加密 + PBKDF2-SHA256 密钥派生；`isEncryptedBackup` 识别加密信封 |
| `backup_archive` | zip 打包：附件图片从 JSON 剥离，与 data.json 一起打包，控制备份体积 |
| `backup_storage` / `backup_storage_io` / `backup_storage_stub` | 备份目录（SAF URI）适配层，真实实现走 `AppStorageBridge` |
| `webdav_config` | WebDAV 配置（URL/用户名/密码/自动上传）、远端文件列表解析 |
| `webdav_client` / `webdav_client_io` / `webdav_client_stub` | `dart:io HttpClient` 手写 WebDAV：PUT / GET / PROPFIND / MKCOL，保留策略清理 |
| `backup_settings` | 备份频率（手动/自动）、间隔小时、保留份数 |

### 备份范围

- 包含：账目类数据（`exportDataJson()`）、个人资料、主题/面板/首页指标、默认账户、预算周期等展示偏好。
- **不包含**：应用锁、备份口令、WebDAV 密码、AI Key、设备本地设置（语言、提醒、备份目录）。
- 加密口令只存设备本地 KV（`verifin.backup_passphrase.v1`），换机需重设。

## 2. 导入体系（`lib/app/backup/import/`）

### 数据流

```text
选择平台 → 选择文件 → 解析（按平台独立入口）→ RawImportRecord 标准化
→ ImportPlanBuilder 构建 ImportPlan（映射现有账户/分类/标签）→ 导入预览页确认
→ controller.applyImportEntries / _applyImportPlan 落库
```

### 平台解析器

| 文件 | 平台/格式 |
| --- | --- |
| `alipay.dart` | 支付宝 CSV（GBK 解码） |
| `wechat.dart` | 微信账单（xlsx） |
| `qianji.dart` | 钱迹 CSV |
| `yimu.dart` | 一木记账（xls：账单 + 转账还款两个入口） |
| `tally.dart` | Tally 记账（备份 zip，无损保留精确时间与收/支/转账、二级分类、账户余额） |
| `mint.dart` | Mint CSV |
| `csv_template.dart` | 本应用 CSV 模板（严格校验表头，只允许模板列） |

### 支撑模块

- `xlsx_reader.dart`：zip/XML 手写 xlsx 解析（共享字符串表）；`xls_reader.dart`：旧版 xls。
- `text_format.dart`：GBK / UTF-16 / UTF-8 多编码解码 + CSV 字段解析（`decodeGbkBytes` / `decodeUtf16Bytes` / `CSV parser`）。
- `raw_import.dart`：`RawImportRecord` / `ParsedImport` 标准化中间表示。
- `plan_builder.dart`：`ImportPlan`，`resolveAccount` / `resolveCategory` / `resolveCategoryHierarchy` 映射到现有条目或新建；缺失分类统一归「未分类」（固定 id `uncategorized_<type>`）。

### 导入约定

- 自动跳过还款、理财等「不计收支的中性交易」；
- 各平台各走独立入口，不混用同一套表头识别；
- 预览页可对将新建的账户/分类/标签逐个改名或映射到现有条目；
- 微信「交易类型」等会作为分类候选进入映射区，不再产生「已删除的分类」。

## 3. AI 子系统（`lib/app/ai/`）

### 组成

| 模块 | 职责 |
| --- | --- |
| `ai_settings` | OpenAI 兼容配置：baseUrl / API Key / model，存 KV，仅本地 |
| `ai_client` / `ai_client_io` / `ai_client_stub` | HTTP Chat Completions（SSE 流式），自带错误分类（`AiErrorCode`） |
| `ai_entry_parser` | 「一句话记账」：prompt 构建、JSON 草稿解析（类型/金额/分类/账户/备注/日期）、`AiDraftWarning`（分类/账户未匹配）、截图/分享文本识别入口 |
| `ai_chat_engine` | 报表自然语言问答：工具调用编排（`AiChatEvent` 流式事件：toolInvoked / toolDisplay / answerDelta / completed / failed） |
| `ai_query_tool` | 只读查询工具集 |

### AI 查询工具（全部只读，不改数据）

- `summary`：某时间段收入/支出/净额/笔数统计
- `categoryRanking`：分类金额排行与占比
- `tagRanking`：标签金额排行与占比
- `queryTransactions`：按条件筛选具体交易（可点击查看）
- `largestTransactions`：单笔金额最大/最小若干笔

结果卡片（`AiResultDisplay` 变体）：`AiStatDisplay` / `AiRankingDisplay` / `AiTrendDisplay` / `AiTransactionsDisplay` / `AiTableDisplay`，聊天记录连同结果卡 JSON 一起存 KV（`verifin.ai_chat.v1`），可清空。

## 4. 截图/分享识别（`lib/app/screenshot_recognizer*`）

- `google_mlkit_text_recognition` 端侧离线 OCR（中文模型），**图片不出设备**；
- 只把识别出的文本交给用户自配的 AI 解析成草稿确认落账；
- **批量确认**：文本中识别出多笔交易时（`parseAiEntryDrafts`，按 `[...]` 数组或 `{"transactions":[...]}` 信封解析，最多 10 笔），按顺序逐笔弹出记账页，点击保存后自动继续下一笔；返回/取消则跳过当前这笔、继续下一笔，直至全部草稿处理完（见 `lib/pages/capture_entry.dart` 的 `_confirmDrafts`）；
- `AppCaptureBridge` 接收「分享给 Veri Fin」的图片/文本 Intent（含 `ShareReceiverActivity`），Tasker 等自动化工具可经 Intent 接口送入账单文本（见 `docs/automation.md`）。

## 5. 提醒子系统（`lib/app/reminder/`）

- `ReminderSettings`：启用 + 时:分，存 KV；
- `NotificationScheduler`（io/stub）：`flutter_local_notifications` 每日 zonedSchedule（`flutter_timezone` 取本地时区，按本地时区计算时刻）；
- 每次回前台重排（先 cancel 再排），把 Doze / force-stop / 重启 / 时区变化断掉的链重新接上。

## 6. 平台桥接（`lib/app/platform_bridge*.dart` ↔ `MainActivity.kt`）

统一 MethodChannel（channel `top.talyra42.verifin`）：

| 桥 | 能力 |
| --- | --- |
| `AppSecurityBridge` | 应用锁开启时设置 `FLAG_SECURE`（不可截屏、最近任务缩略图隐藏） |
| `AppStorageBridge` | SAF 选目录/写备份/读/列/删、保存到下载目录（text/bytes） |
| `AppCaptureBridge` | 快捷记账 Intent、分享图片/文本采集（含冷启动 pending 消费） |
| `AppUpdateBridge` | GitHub Release 检查/下载/安装（`github` flavor 启用；`play` flavor 经 `kSelfUpdateEnabled` 关闭并移除 `REQUEST_INSTALL_PACKAGES`） |
| `AppWidgetBridge` | 推送桌面小组件数据、`pinWidget` 请求添加 |

## 7. 桌面小组件与快捷磁贴（Android 原生）

- `QuickEntryWidgetProvider`：桌面「记一笔」快捷入口；
- `StatWidgetProvider`：今日支出统计小组件（数据由 `home_widget_service.pushWidgetData` 推送）；
- `QuickEntryTileService`：快捷设置磁贴；
- `WidgetData` / `WidgetRefreshReceiver`：小组件数据模型与刷新广播。

## 8. 软件日志（`lib/app/logging/`）

- `AppLogger extends ChangeNotifier`：info / warning / error 分级，上限 200 条环形存储（KV `verifin.logs.v1`），可清空、可导出文本；
- 页面 `app_log_page.dart` 展示；启动期 `FlutterError.onError` 也写入日志。

## 9. 应用锁（`lib/app/app_lock.dart` + `pages/app_lock_*`）

- `AppLockKind`：none / pin / pattern；`AppLockConfig` 存加盐哈希（`hashAppLockSecret`），**不存明文**；
- 支持生物识别快速解锁（`local_auth`，仅指纹；`biometric_auth*` 适配层）；
- `AppLockGate` 门卫：未解锁不渲染应用内容；开启后 `FLAG_SECURE` 同步。

## 10. 自更新与分发 flavor

- `github` flavor：启用自更新（下载 GitHub Release APK 自动安装）；
- `play` flavor：`--dart-define=SELF_UPDATE=false`，隐藏更新入口并移除安装权限，遵循 Play 政策；
- 本地构建/运行必须 `--flavor github`；正式包由 GitHub CI（tag `vX.Y.Z`）产出。
