# 记账数据接入

## 截图与分享

用户从相册选图，或将账单图片、文本分享给 Veri Fin。图片先由本机离线 OCR 提取文字，再由用户配置的 AI 服务解析成草稿，交给记账页面确认保存。

- OCR 位于 `lib/app/screenshot_recognizer_*.dart`。
- AI 草稿解析位于 `lib/app/ai/ai_entry_parser.dart`。
- 页面入口位于 `lib/pages/capture_entry.dart`。
- Android 分享入口为 `ShareReceiverActivity`，转发到 `MainActivity`。

## 外部意图接口

自动化工具可以将用户选定的账单文本通过显式 Intent 送入 Veri Fin。应用复用相同的草稿解析与确认流程。接口和示例见 [自动化接入](../automation.md)。

## Muse 账单同步

Muse 的专用对话整理逐笔账单，通过连接器提交到用户配置的 HTTPS 服务。Veri Fin 下载明细后按固定来源和编号保存或更新账单。部署与授权见 [Muse 账单同步](../muse-sync.md)。

Android 界面和后台同步任务通过 `LedgerRuntime` 共用 Flutter 引擎与控制器。设备上的废弃采集偏好和待处理文字在应用启动时清理。

## 验收

- 分享图片或文本后检查草稿内容，确认保存后检查账本。
- 测试外部 Intent 在冷启动和前台状态下打开草稿。
- 空白图片、非账单文本和识别失败时显示相应提示。
- Muse 明细验证新增、重复提交、修正、断网重试与后台同步。
