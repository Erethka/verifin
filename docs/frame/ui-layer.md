# UI 层

## 1. 导航结构：VeriFinShell

根组件 `MaterialApp` → `PrivacyConsentGate`（隐私同意门卫）→ `AppLockGate`（应用锁门卫）→ `VeriFinShell`。

`VeriFinShell` 是四 Tab 主框架：

- `PageView` 横向承载四个主页：`HomePage` / `AssetsPage` / `ReportsPage` / `ProfilePage`，支持左右滑动切换；
- 自绘底部导航 `VeriBottomNav`（图标选中态放大 + 主色底）；
- 首页自绘 FAB（单 `InkWell` 同时持有点击与长按），行为按 `FabActionMode` 区分：手动记账 / AI 记账 / 点击手动·长按 AI；
- 根返回键处理：非首页先回首页，首页连按两次退出；
- 挂载时处理平台 Intent：新用户引导、快捷记账、分享截图/文本采集（`AppCaptureBridge`）。

## 2. 页面清单（`lib/pages/`，47 个文件）

| 分组 | 文件 | 职责 |
| --- | --- | --- |
| 主框架 | `shell.dart` | 四 Tab 外壳 + 底部导航 + FAB |
| 首页 | `home_page.dart` | 趋势/最近/预算/日历面板、收支统计、今日风险横幅 |
| 资产 | `assets_pages.dart` | 净资产卡（封面可换）、分组/类型两种视图、账户分组合计 |
| 报表 | `reports_page.dart` | 预算执行、分类环形图、分类排行、标签统计、日趋势、月度结构 |
| 我的 | `profile_pages.dart` / `profile_widgets.dart` / `profile_info_page.dart` | 个人页、功能宫格、资料编辑 |
| 记账 | `capture_entry.dart` / `entry_detail_page.dart` / `entry_sheets.dart` / `sheets.dart` | 快捷记一笔、截图/分享识别逐笔批量确认、交易详情/编辑、各类底部弹窗 |
| 交易 | `transactions_pages.dart` / `transaction_detail_page.dart` | 交易列表（搜索/筛选/批量）、交易详情 |
| 账户 | `add_account_page.dart` / `account_detail_page.dart` / `account_group_pages.dart` / `credit_repayment_page.dart` | 开户、账户详情/余额调整/报表、分组管理、信用卡还款 |
| 分类/标签 | `category_management_page.dart` / `tag_management_page.dart` | 分类树管理（增删改、合并、排序）、标签管理 |
| 预算 | `budget_pages.dart` / `budget_settings_page.dart` / `budget_widgets.dart` / `budget_snapshots.dart` / `budget_trend_chart.dart` | 预算总览/设置/组件/快照/趋势 |
| 周期/提醒 | `recurring_page.dart` / `reminder_settings_page.dart` | 周期记账规则、每日提醒 |
| 退款 | `refund_editor.dart` / `pending_refunds_page.dart` | 退款编辑、待到账退款清单 |
| 报表分析 | `report_analysis_page.dart` | 月/年/自定义范围 × 收支维度的统计分析与同比环比 |
| 导入 | `import_preview_page.dart` | 导入预览与分类/账户映射 |
| 数据管理 | `data_management_page.dart` / `data_management_dialogs.dart` / `ledger_books_page.dart` | 备份/恢复/清空/导出、账本管理 |
| 设置 | `settings_page.dart` / `home_metrics_settings_page.dart` / `panel_settings_page.dart` / `ai_settings_page.dart` / `app_log_page.dart` | 通用设置、首页指标、面板开关排序、AI 设置、软件日志 |
| AI | `ai_chat_page.dart` / `ai_entry_sheet.dart` / `ai_result_view.dart` | AI 对话查询、AI 记账弹窗、结果卡片渲染 |
| 安全 | `app_lock_gate.dart` / `app_lock_page.dart` | 应用锁门卫、PIN/图案/生物解锁设置与验证 |
| 其他 | `onboarding_page.dart` / `legal_pages.dart` / `privacy_consent_gate.dart` / `attachments_editor.dart` / `widget_gallery_page.dart` | 新手引导、法律条款、隐私同意、附件编辑器、组件画廊 |

## 3. 面板系统

首页与报表页均由可配置面板拼装：

- 首页面板：`trend`（趋势）、`recent`（最近交易）、`budget`（预算）、`calendar`（日历）；
- 报表面板：`budget_execution`（预算执行）、`category_ring`（分类环形图）、`category_rank`（分类排行）、`tag_stats`（标签统计）、`daily_trend`（日趋势）、`monthly_structure`（月度结构）。
- 面板目录 `PagePanelSpec` 的 id 是持久化标识；设置存 KV（`_homePanelsKey` / `_reportPanelsKey`）。
- `_normalizePanelSettings`：丢弃目录外 id、新面板默认追加开启、**至少保留一个开启面板**。

## 4. 通用组件体系（`lib/app/common_widgets*.dart`）

完整目录见 `docs/dev/components.md`，核心分层：

| 类别 | 代表组件 |
| --- | --- |
| 页面脚手架 | `VeriPage`（渐变背景+居中+maxWidth 440 约束）、`VeriCard`、`VeriHeader` / `PageHeader`、`SectionTitle`、`EmptyState` |
| 页眉动作族 | `HeaderAction`、`HeaderPopupAction<T>`、`HeaderTextAction`、`HeaderInline`、`VeriSectionAction` |
| 图标渲染（唯一入口） | `CategoryIconBox` / `CategoryGlyph`、`AccountIconBox` / `VeriIconBox`（底层 `iconForCode`，渲染点禁止直调） |
| 交易展示 | `TransactionTile`、`TransactionListCard`、`DateGroupHeader`、`groupEntriesByDate` / `relativeDay` |
| 金额输入 | `showNumberPadSheet` / `NumberPadSheet`（四则算式 + 结果预览）、`evaluateAmountExpression` |
| 弹窗约定 | 底部弹窗一律 `show*Sheet(context, ...)`；确认 `showConfirmDialog`（destructive 走红）、文本输入 `showTextInputDialog`、单选 `showOptionSheet`、分类 `showCategoryPickerSheet`、账户 `showAccountPickerSheet` |
| 指标 | `SummaryMetric`（label + value[ + detail] 标准指标块） |
| 账户相关 | `AccountGroupCard`、`CardNumberFields`、`accountBalanceColor`、`accountDisplayName` |

约定：取消/未选一律返回 `null`；「特殊选项」用命名常量（如 `categoryPickerAll` / `categoryPickerTopLevel` / 空 id 哨兵 Account）；需要触感的组件在 helper 内部从 `VeriFinScope` 取，调用方不手传。

## 5. 主题（`app_theme.dart`）

- 设计令牌全部为常量：`veri*` 颜色（主色 `veriRoyal #346EDB`、支出 `veriExpense #E84D6A`、收入 `veriIncome #12B8A6`、警示 `veriWarning` 等）、圆角 `veriRadiusSm/Md/Lg`、`veriHeaderHeight=52`、`veriPageMaxWidth=440`。
- `buildVeriFinTheme(Brightness)` 生成浅/深两套 `ThemeData`；`MaterialApp.themeMode` 由 `ThemePreference` 驱动。
- 禁止裸写 `Color(0x...)` 或魔法圆角；键盘配色的局部特例需注释理由。

## 6. 图表（`chart_painters.dart` + 页面内 CustomPainter）

- 全部自绘：`TrendLinePainter`、`BarChartPainter`、`BudgetRingPainter`、报表页的环形图/标注 painter。
- 交互：`InteractiveTrendChart` / `InteractiveBarChart` 带数据气泡（tooltip），环形图带点击分段命中测试。
- 坐标固定留白 `leftInset/rightInset/bottomInset`，统一 `chartValueScale`。

## 7. 本地化（`lib/l10n/`）

- `app_zh.arb` 为模板 + `app_en.arb` 同步；`l10n.yaml` 配置 gen-l10n 生成 `AppLocalizations`。
- `AppLocalizations.of(context)` 是唯一文案入口；语言跟随系统或固定 zh/en（`LocalePreference`），`ValueNotifier<LocalePreference>` 驱动 `MaterialApp.locale` 即时切换。
