# 数据层

## 1. 总览

```text
lib/data/
├── app_database.dart        # AppDatabase：建表、schema v13、迁移注册
├── ledger_repository.dart   # LedgerRepository 接口 + SqliteLedgerRepository 实现
├── database_factory.dart    # 工厂接口（resolveDatabaseFactory / resolveDatabasePath）
├── database_factory_io.dart # 真实平台实现
└── database_factory_stub.dart

lib/local_storage/
├── local_storage.dart       # LocalKeyValueStore（条件导出）
├── local_storage_io.dart    # SharedPreferences 实现
└── local_storage_stub.dart  # 纯内存实现（测试）
```

账目类核心数据只存 SQLite；偏好类小数据（主题、触感、面板、资产排序、备份配置等）留在 KV。

## 2. SQLite：AppDatabase

### 打开与迁移

- 默认库名 `verifin.db`，`schemaVersion = 13`。
- `open({factory, path})`：测试可注入 `sqflite_common_ffi` 工厂与内存路径；真实平台由 `resolveDatabaseFactory()` / `resolveDatabasePath()` 决定。
- `_onCreate`：按 `_schemaCurrent` 全量建表。
- `_onUpgrade`：按 `(oldVersion, newVersion]` 升序逐段执行 `_migrations`；**缺段直接抛错**（宁升级即失败，也不静默跳段留残缺 schema）。
- 修改表结构 = 提升 `schemaVersion` + 同步 `_schemaCurrent` + 注册新迁移段；**禁止改动历史迁移段**（存量用户升级时仍会按序经过它们）。
- `migrations` 以 `@visibleForTesting` 暴露，供迁移矩阵测试把库推到任意中间版本。

### 表结构（v13 当前 schema）

| 表 | 用途 | 关键列 |
| --- | --- | --- |
| `ledger_books` | 账本 | id / name / created_at / is_default / sort_order |
| `entries` | 交易 | book_id / type / amount / category_id / account_id / to_account_id / note / occurred_at / tag_ids(JSON) / fee / reimbursable / refunded_amount / refund_of / settled_at |
| `accounts` | 账户 | book_id / type / group_id / initial_balance / icon_code / include_in_assets / hidden / card_last4 / card_number / card_last4_follows / credit_limit / sort_order / statement_day / due_day |
| `account_groups` | 账户分组 | book_id / name / icon_code / sort_order |
| `categories` | 分类 | label / type / icon_code / sort_order / parent_id，唯一索引 `(label, type, IFNULL(parent_id,''))` |
| `monthly_budgets` | 月度预算 | scope_key / amount |
| `category_budgets` | 分类预算 | scope_key / amount |
| `daily_budgets` | 按日预算 | scope_key / amount |
| `tags` | 标签 | id / label / sort_order |
| `attachments` | 附件 | entry_id / data_url / sort_order，索引 idx_attachments_entry |
| `recurring_rules` | 周期规则 | book_id / type / amount / category_id / account_id / to_account_id / frequency / start_date / next_run_date / active / sort_order |

### 迁移历史（v2 → v13）

| 版本 | 内容 |
| --- | --- |
| v2 | categories 增加 `parent_id`（多级分类树） |
| v3 | 标签系统：entries 增加 `tag_ids`；新建 tags 表 |
| v4 | 图片附件：新建 attachments 表 + 索引 |
| v5 | 转账手续费：entries 增加 `fee`（默认 0） |
| v6 | 报销/退款：entries 增加 `reimbursable`、`refunded_amount` |
| v7 | 周期记账：新建 recurring_rules 表 |
| v8 | 信用卡账单日/还款日：accounts 增加 `statement_day`、`due_day` |
| v9 | 按日预算：新建 daily_budgets 表（key = `bookId:yyyy-MM-dd`） |
| v10 | 分类唯一性约束：先按 (label,type,parent) 去重（改指引用后删重复），再建唯一索引 |
| v11 | 完整卡号与信用额度：accounts 增加 `card_number`、`credit_limit` |
| v12 | 「后四位跟随完整卡号」开关：accounts 增加 `card_last4_follows`（旧数据默认 0，不冲掉手填后四位） |
| v13 | 退款独立条目：entries 增加 `refund_of`、`settled_at`；历史 refunded_amount 由 controller 加载时的 `_syncRefundData()` 合并为已到账退款条目并重算缓存 |

## 3. LedgerRepository

### 接口

```dart
abstract class LedgerRepository {
  Future<List<LedgerEntry>> loadEntries();       Future<void> saveEntries(List<LedgerEntry>);
  Future<List<LedgerBook>> loadBooks();          Future<void> saveBooks(...);
  Future<List<Account>> loadAccounts();          Future<void> saveAccounts(...);
  Future<List<AccountGroup>> loadAccountGroups();Future<void> saveAccountGroups(...);
  Future<List<Category>> loadCategories();       Future<void> saveCategories(...);
  Future<List<Tag>> loadTags();                  Future<void> saveTags(...);
  Future<List<Attachment>> loadAttachments();    Future<void> saveAttachments(...);
  Future<List<RecurringRule>> loadRecurringRules();Future<void> saveRecurringRules(...);
  Future<Map<String, double>> loadMonthlyBudgets();  Future<void> saveMonthlyBudgets(...);
  Future<Map<String, double>> loadCategoryBudgets(); Future<void> saveCategoryBudgets(...);
  Future<Map<String, double>> loadDailyBudgets();    Future<void> saveDailyBudgets(...);

  Future<void> replaceAllLedgerData(LedgerDataSnapshot snapshot);
  Future<bool> hasAnyData();
}
```

### SqliteLedgerRepository 实现要点

- 每个实体一行 `toRow` / `fromRow` 映射，`toJson` 字段（camelCase）与 SQL 列（snake_case）之间显式转换。
- 全量保存走 `_replaceInTxn` 事务（先删后插）；导入/恢复走 `_incrementalReplace` / `_replaceAll`，预算类用 `_saveBudgetMap`。
- `replaceAllLedgerData(LedgerDataSnapshot)` 用于备份恢复；`hasAnyData()` 用于判断是否全新库（决定是否播种默认数据）。

## 4. KV：LocalKeyValueStore

- 接口：`read(String)` / `write(String, String)` / `delete(String)` / `flush()`。
- 真实平台 `SharedPreferences.getInstance()`；测试构造器为纯内存。
- `write` 采用写穿（write-through）+ 追踪挂起 Future，`flush()` 等全部落盘（切后台时调用）。

### KV 键清单（`verifin.*.v1`）

| 键 | 内容 |
| --- | --- |
| `verifin.theme.v1` | 主题偏好 |
| `verifin.locale.v1` | 语言偏好 |
| `verifin.profile.v1` | 个人资料 |
| `verifin.active_book.v1` | 当前账本 |
| `verifin.asset_cover.v1` | 资产封面 |
| `verifin.haptics.v1` | 触感开关 |
| `verifin.privacy_consent.v1` | 隐私同意 |
| `verifin.app_lock.v1` | 应用锁配置（哈希格式在 app_lock.dart） |
| `verifin.asset_view_mode.v1` / `asset_section_collapsed.v1` / `asset_account_order.v1` / `asset_section_order.v1` | 资产页视图/折叠/排序 |
| `verifin.home_panels.v1` / `report_panels.v1` | 首页/报表面板配置 |
| `verifin.backup_settings.v1` / `backup_passphrase.v1` | 备份设置 / 备份口令 |
| `verifin.webdav.v1` | WebDAV 配置 |
| `verifin.reminder.v1` | 记账提醒 |
| `verifin.fab_action.v1` | FAB 行为 |
| `verifin.default_account.v1` | 各账本默认付款账户 |
| `verifin.budget_cycle.v1` | 各账本预算周期起始日 |
| `verifin.amount_format.v1` | 金额强制两位小数 |
| `verifin.auto_suggest.v1` | 分类联想 |
| `verifin.ai.v1` / `verifin.ai_chat.v1` | AI 设置 / AI 聊天历史 |
| `verifin.home_metrics.v1` | 首页趋势配置 |
| `verifin.onboarding.v1` | 新用户引导完成 |

另有自管例外键：`verifin.logs.v1`（软件日志，`logging/app_logger.dart` 自管写）。

## 5. 备份 JSON 数据键白名单

`_knownBackupDataKeys`（`veri_fin_controller.dart`）用于校验导入内容是否为本应用备份，避免"格式合法但非本应用"的 JSON 静默覆盖初始数据：

`ledgerBooks`、`activeBookId`、`entries`、`accounts`、`accountGroups`、`categories`、`tags`、`attachments`、`recurringRules`、`monthlyBudgets`、`categoryBudgets`、`dailyBudgets`、`profile`、`themePreference`、`homePanels`、`reportPanels`。

密钥类（应用锁、备份口令、WebDAV 密码、AI Key）与设备本地设置（语言、提醒、备份目录）**不进备份**，换机后需重设。

## 6. 测试注入点

- `AppDatabase.open(factory:, path:)`：注入 `sqflite_common_ffi` 内存库（见 `test/repository_test.dart`、`test/migration_matrix_test.dart`）。
- `LocalKeyValueStore()`：纯内存实现。
- `LedgerRepository`：测试可另写内存实现（`test/support/in_memory_ledger_repository.dart`）。
