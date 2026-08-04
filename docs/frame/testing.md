# 测试体系

## 1. 概览

- 测试框架：`flutter_test`，位于 `test/`，共 78 个 `*_test.dart`（约 1.5 万行）。
- 命令：`flutter analyze`（静态检查，`flutter_lints`）+ `flutter test`（全部测试）。
- 覆盖风格：用户可见行为优先（文本渲染、按钮交互、导航、表单校验），其次领域纯函数与 Controller 操作。

## 2. 测试基础设施（`test/support/`）

| 文件 | 用途 |
| --- | --- |
| `test_harness.dart` | 共享测试脚手架（构建 Controller / 注入依赖 / 常见断言） |
| `in_memory_ledger_repository.dart` | 内存版 `LedgerRepository`，UI/Controller 测试免 SQLite |

真实 SQLite 覆盖：

- `repository_test.dart`：`sqflite_common_ffi` 内存库上的 `SqliteLedgerRepository` 全接口测试；
- `migration_matrix_test.dart`：把库推到任意中间版本再升级，验证迁移段顺序与兼容性；
- `controller_persistence_test.dart`：Controller 持久化往返（含 KV flush）。

## 3. 按领域组织的测试文件

| 领域 | 代表测试 |
| --- | --- |
| Controller 与持久化 | `controller_unit_test`、`controller_persistence_test`、`model_roundtrip_test`、`migration_matrix_test`、`default_account_test`、`entry_added_hook_test` |
| 记账 | `entries_test`、`capture_entry_test`、`entry_category_inline_test`、`number_pad_calc_test`、`calc_expression_test`、`transfer_fee_test`、`batch_operations_test` |
| 退款/报销 | `refund_test`、`refund_ui_test`、`reimbursement_test` |
| 账户/资产 | `accounts_assets_test`、`credit_card_test`、`credit_account_ui_test`、`credit_repayment_test` |
| 分类/标签 | `category_tree_test`、`category_controller_test`、`category_picker_test`、`category_icon_test`、`category_integrity_test`、`category_suggest_test`、`category_suggest_widget_test`、`tags_test` |
| 预算 | `budget_test`、`budget_cycle_test`、`budget_ring_test` |
| 报表 | `report_analysis_test`、`report_analysis_page_test`、`reports_category_test`、`chart_hit_test` |
| 周期/提醒 | `recurring_test`、`reminder_test`、`calendar_days_test` |
| 备份/导入 | `backup_test`、`backup_archive_test`、`backup_crypto_test`、`backup_coordinator_test`、`backup_settings_test`、`payment_import_test`、`transaction_import_test`、`import_preview_test`、`import_platform_sheet_test`、`import_guard_test`、`plan_builder_test`、`webdav_config_test`、`xls_reader_test` |
| AI | `ai_entry_parser_test`、`ai_entry_flow_test`、`ai_chat_engine_test`、`ai_chat_history_test`、`ai_query_tool_test`、`ai_settings_test`、`ai_chat_page_test` |
| 安全/隐私 | `app_lock_test`、`net_security_test`、`legal_test`、`privacy_consent`（合并在相关用例） |
| 导航/设置/体验 | `navigation_settings_test`、`fab_action_mode_test`、`home_metrics_test`、`home_widget_test`、`panels_test`、`onboarding_test`、`profile_grid_test`、`profile_info_test`、`journey_test`、`widget_gallery_test` |
| 其他 | `attachments_test`、`app_logger_test`、`pure_test`、`repository_contract_test`、`transaction_tile_test` |

## 4. 测试夹具（`test/fixtures/`）

- 各平台账单样例：`yimu_*.xls`（账单/转账/子分类/标签/退款折扣）、`qianji_sample.csv`。
- 用于导入解析器与预览页的端到端断言。

## 5. 测试约定

- 修改功能后至少跑 `flutter analyze` 和 `flutter test`；
- 新增用户可见行为需同步补测试；
- 日期相关用例注意用 `calendarDaysBetween` / `addCalendarDays` 的语义（避免 UTC/时区差异造成 CI 绿、用户机红）。
