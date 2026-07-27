import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/local_storage/local_storage.dart';

import 'support/test_harness.dart';

void main() {
  useTestDatabases();

  testWidgets('note auto-selects the category learned from history', (
    tester,
  ) async {
    final store = LocalKeyValueStore();
    final controller = await makeController(store);
    final bookId = controller.activeBook.id;
    // 历史：多笔「打车」都记在交通分类下。
    for (var i = 0; i < 4; i++) {
      controller.addEntry(
        LedgerEntry(
          id: 'hist-$i',
          bookId: bookId,
          type: EntryType.expense,
          amount: 20,
          categoryId: 'transport',
          accountId: '',
          note: '打车',
          occurredAt: DateTime(2026, 7, i + 1, 9),
        ),
      );
    }

    await pumpApp(tester, store);
    await tapBottomTab(tester, 0);
    await createQuickEntry(tester);

    // 输入含「打车」的备注 → 自动识别为交通并选中（无可见提示文本）。
    await tester.enterText(find.byKey(const Key('entry_note_field')), '打车上班');
    await tester.pump();

    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '交通'),
    );
    expect(chip.selected, isTrue);

    // 用户手动改选餐饮后，不再被自动识别覆盖。
    await tester.tap(find.widgetWithText(ChoiceChip, '餐饮'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('entry_note_field')), '打车回家');
    await tester.pump();
    final dining = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '餐饮'),
    );
    expect(dining.selected, isTrue);
  });

  testWidgets('re-entering a learned amount infers type, category and note', (
    tester,
  ) async {
    final store = LocalKeyValueStore();
    final controller = await makeController(store);
    final bookId = controller.activeBook.id;
    // 历史：88 元都记为收入·利息·备注「利息」。
    for (var i = 0; i < 2; i++) {
      controller.addEntry(
        LedgerEntry(
          id: 'inc-$i',
          bookId: bookId,
          type: EntryType.income,
          amount: 88,
          categoryId: 'interest',
          accountId: '',
          note: '利息',
          occurredAt: DateTime(2026, 7, i + 1, 9),
        ),
      );
    }

    await pumpApp(tester, store);
    await tapBottomTab(tester, 0);

    // 再次输入 88 → 类型应自动切到收入、分类利息、备注回填「利息」。
    await tester.tap(find.byKey(const Key('quick_entry_fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('number_key_8')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('number_key_8')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('number_pad_ok')));
    await tester.pumpAndSettle();

    final segmented = tester.widget<SegmentedButton<EntryType>>(
      find.byKey(const Key('entry_type_segmented_button')),
    );
    expect(segmented.selected, <EntryType>{EntryType.income});

    final interest = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '利息'),
    );
    expect(interest.selected, isTrue);

    final note = tester.widget<TextField>(
      find.byKey(const Key('entry_note_field')),
    );
    expect(note.controller?.text, '利息');
  });

  testWidgets('auto-suggest fills nothing once the setting is turned off', (
    tester,
  ) async {
    final store = LocalKeyValueStore();
    final controller = await makeController(store);
    // 默认开启：老用户升级后行为不变。
    expect(controller.autoSuggestEnabled, isTrue);
    final bookId = controller.activeBook.id;
    // 与上一个用例同样的历史（88 元 → 收入·利息·备注「利息」）。
    for (var i = 0; i < 2; i++) {
      controller.addEntry(
        LedgerEntry(
          id: 'inc-$i',
          bookId: bookId,
          type: EntryType.income,
          amount: 88,
          categoryId: 'interest',
          accountId: '',
          note: '利息',
          occurredAt: DateTime(2026, 7, i + 1, 9),
        ),
      );
    }
    controller.setAutoSuggestEnabled(false);
    expect(store.read('verifin.auto_suggest.v1'), 'false');

    await pumpApp(tester, store);
    await tapBottomTab(tester, 0);

    await tester.tap(find.byKey(const Key('quick_entry_fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('number_key_8')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('number_key_8')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('number_pad_ok')));
    await tester.pumpAndSettle();

    // 关掉后一切保持默认：类型仍是支出，备注仍为空。
    final segmented = tester.widget<SegmentedButton<EntryType>>(
      find.byKey(const Key('entry_type_segmented_button')),
    );
    expect(segmented.selected, <EntryType>{EntryType.expense});
    final note = tester.widget<TextField>(
      find.byKey(const Key('entry_note_field')),
    );
    expect(note.controller?.text, isEmpty);
    expect(find.widgetWithText(ChoiceChip, '利息'), findsNothing);
  });
}
