# 领域模型与核心业务计算

模型按领域拆分在 `lib/app/models/`，通过 `models.dart` barrel 统一导出；外部一律 `import 'models.dart'`。

## 1. 交易（`ledger_entry.dart`）

### EntryType

| 类型 | 说明 |
| --- | --- |
| `expense` | 支出 |
| `income` | 收入 |
| `transfer` | 转账（可带手续费 `fee`） |
| `refund` | 退款：挂在某笔原始支出（`refundOf`）上的独立条目，类比喻转账——不计收支统计，仅影响账户余额（已到账 `settledAt != null` 时），并缓存冲减原始支出净额 |

`refund` 不可在普通记账页手动选择，只能从「原支出 → 添加退款」创建。

### LedgerEntry

关键字段：

| 字段 | 说明 |
| --- | --- |
| `id` / `bookId` | 主键 / 所属账本 |
| `type` / `amount` | 类型 / 金额 |
| `categoryId` / `accountId` / `toAccountId` | 分类 / 账户 / 转账目标账户 |
| `note` / `occurredAt` | 备注 / 发生时间 |
| `tagIds` | 多对多标签 |
| `fee` | 转账手续费（转出账户承担） |
| `reimbursable` | 待报销标记（仅支出） |
| `refundedAmount` | **派生缓存**：挂在本支出上的已到账退款金额之和，由 `_syncRefundData()` 重算落库，从不独立写入 |
| `refundOf` / `settledAt` | 退款专用：原始支出 id / 到账日期（null = 待到账 pending） |

核心计算：

- `netAmount`：支出净额 = `amount - refundedAmount`，钳制在 `[0, amount]`（防越界数据把支出算成收入、余额虚增）。
- `isPendingRefund` / `isSettledRefund`：待到账 / 已到账退款。
- 余额口径：支出扣全额 + 退款条目给到账账户加钱，故支持退款退回不同账户。

### 其他模型

- `RecurringRule`：周期记账规则（daily/weekly/monthly/yearly），自带 `bookId`、`nextRunDate`，生成交易落入同一账本。
- `Attachment`：交易图片附件，以压缩 JPEG data URL 存独立表。
- `Tag`：跨分类的横向归类与统计。

## 2. 账户（`account.dart`）

### AccountType

| 类型 | 能力 |
| --- | --- |
| `onlinePayment` | 网络支付（支付宝/微信等） |
| `creditAccount` | 信用账户（花呗/白条等，有额度、无实体卡号） |
| `creditCard` | 信用卡（额度 + 卡号 + 账单日/还款日） |
| `debitCard` | 储蓄卡 |
| `investment` | 投资账户 |
| `cash` | 现金 |

能力矩阵：`supportsCardLast4`（creditCard / debitCard）、`supportsCredit`（creditCard / creditAccount）。

### Account

- 基础：`id` / `bookId` / `name` / `type` / `groupId` / `initialBalance` / `iconCode` / `note` / `includeInAssets` / `hidden`。
- 卡信息：`cardLast4`（列表只显示后四位）、`cardNumber`（完整卡号，仅支持类型，详情页可一键复制）、`cardLast4Follows`（后四位是否跟随完整卡号）。
- 信用信息：`creditLimit` / `statementDay` / `dueDay`（设置后显示已用/可用额度与还款倒计时提醒）。
- `AccountGroup`：账户分组（分组视图用），含 `sortOrder`。

## 3. 分类（`category.dart`）

- `Category`：`id` / `label` / `type`（与 `EntryType` 对齐）/ `iconCode` / `parentId`，邻接表支持任意层级树。
- 树形纯函数在 `category_tree.dart`：`categoryIndex` / `rootCategories` / `childrenOf` / `ancestorIds` / `descendantIds` / `isDescendantOf` / `depthOf` / `pathLabel` / `flattenTree`（均带环检测）。
- **「未分类」固定 id 约定**：`uncategorized_<type>`，导入缺失分类与加载自愈共用同一条目；子分类与父分类 type 必须一致。

## 4. 账本（`ledger_book.dart`）

- `LedgerBook`：多账本隔离，交易/账户/分组都带 `bookId`；默认账本 id 为 `default`。
- 预算键按账本隔离：`bookId:yyyy-MM[:catId]`；旧版本无前缀数据加载/导入时归入默认账本。

## 5. 偏好与界面配置（`preferences.dart`）

- `ThemePreference`：system / light / dark。
- `LocalePreference`：system / zh / en（设备本地偏好，存 KV，不进备份）。
- `AssetAccountViewMode`：group（分组视图）/ type（类型视图）。
- `FabActionMode`：manual（点击手动记账）/ ai（点击 AI 记账）/ manualTapAiLongPress（点击手动、长按 AI）。
- `PanelPageKind` + `PagePanelSpec` / `PagePanelSetting`：首页与报表页的面板目录与开关/排序状态。

## 6. 个人资料（`user_profile.dart`）

- `UserProfile`：昵称、简介、头像 data URL、性别、生日、城市、职业；存 KV、进备份 JSON。

## 7. 核心业务计算模块

| 模块 | 职责 |
| --- | --- |
| `ledger_math.dart` | 收支/净额统计、`DateWindow` 日期窗口、账户余额计算 |
| `report_analysis.dart` | `ReportRange`（月/年/自定义）、`ReportSummary`、`ReportComparison`（同比环比）、`ReportCategoryStat`、`ReportTagStat`、`ReportTrend`（日/月粒度） |
| `budget_cycle.dart` | 预算周期起始日（1~28，默认自然月 1 日），`clampBudgetCycleStartDay` |
| `calc_expression.dart` | 数字键盘四则算式求值（`evaluateAmountExpression`，不完整返回 null） |
| `calendar_days.dart` | 日历日算术：`calendarDaysBetween` / `addCalendarDays`（避免时区引发的"少一天"） |
| `series_math.dart` | 时间序列计算 |
| `amount_format.dart` | `formatAmount` / `formatSignedAmount` / `formatCompactAmount` |
| `category_suggest.dart` | 分类联想建议 |
| `home_metrics.dart` | 首页指标（`HomeMetric` / `HomeTrendSeries` / `HomeMetricGroup` / `HomeTrendConfig`） |
| `recurring.dart` | 周期规则推进（`applyDueRecurring`） |
| `credit_card.dart` | 信用卡账单日/还款日与倒计时 |

## 8. 金额与日期约定

- 金额存 `double`，展示统一走 `amount_format.dart`；可选 `_amountForceTwoDecimals` 强制两位小数。
- 日历日（相隔几天/前后推 N 天）必须用 `calendar_days.dart`，绝对时间间隔（如"每 N 小时备份"）才用 `Duration`。
