import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/ai/ai_client.dart';
import 'package:verifin/app/ai/ai_entry_parser.dart';
import 'package:verifin/app/models.dart';

AiEntryContext _context() => AiEntryContext(
  expenseCategories: const <AiOption>[
    AiOption(id: 'dining', label: '餐饮'),
    AiOption(id: 'transport', label: '交通'),
    AiOption(id: 'coffee', label: '餐饮 / 咖啡'),
  ],
  incomeCategories: const <AiOption>[AiOption(id: 'salary', label: '工资')],
  accounts: const <AiOption>[
    AiOption(id: 'cash', label: '现金'),
    AiOption(id: 'card', label: '招商银行'),
  ],
  today: DateTime(2026, 7, 5, 9, 30),
  bookId: 'default',
);

void main() {
  group('buildAiEntryPrompt', () {
    test('includes category ids, accounts and today date', () {
      final prompt = buildAiEntryPrompt(_context());
      expect(prompt, contains('2026-07-05'));
      expect(prompt, contains('09:30')); // 当前时间，供解析相对时间
      expect(prompt, contains('time')); // time 字段说明
      expect(prompt, contains('dining'));
      expect(prompt, contains('transport'));
      expect(prompt, contains('salary'));
      expect(prompt, contains('card'));
    });
  });

  group('extractJsonObject', () {
    test('extracts JSON wrapped in code fence and prose', () {
      const content =
          '好的，这是结果：\n```json\n{"type":"expense","amount":12}\n```\n谢谢';
      final json = extractJsonObject(content);
      expect(json, isNotNull);
      expect(json!['type'], 'expense');
      expect(json['amount'], 12);
    });

    test('returns null when no object present', () {
      expect(extractJsonObject('no json here'), isNull);
    });
  });

  group('extractJsonTransactionList', () {
    test('extracts array wrapped in prose', () {
      const content =
          '好的，结果如下：\n```json\n[{"type":"expense","amount":12}]\n```\n谢谢';
      final items = extractJsonTransactionList(content);
      expect(items, isNotNull);
      expect(items, hasLength(1));
      expect(items!.single['amount'], 12);
    });

    test('extracts transactions envelope object', () {
      const content =
          '{"transactions":[{"type":"expense","amount":12},{"type":"income","amount":8}]}';
      final items = extractJsonTransactionList(content);
      expect(items, hasLength(2));
      expect(items!.first['type'], 'expense');
      expect(items.last['type'], 'income');
    });

    test('returns null for single object or no json', () {
      expect(
        extractJsonTransactionList('{"type":"expense","amount":12}'),
        isNull,
      );
      expect(extractJsonTransactionList('no json here'), isNull);
    });
  });

  group('parseAiEntryDrafts', () {
    test('parses multiple transactions in order', () {
      final drafts = parseAiEntryDrafts(
        '[{"type":"expense","amount":32,"categoryId":"transport",'
        '"accountId":"cash","note":"打车","date":"2026-07-04"},'
        '{"type":"expense","amount":18,"categoryId":"dining",'
        '"accountId":"cash","note":"早餐","date":"2026-07-04"}]',
        _context(),
      );
      expect(drafts, hasLength(2));
      expect(drafts[0].amount, 32);
      expect(drafts[0].categoryId, 'transport');
      expect(drafts[1].amount, 18);
      expect(drafts[1].categoryId, 'dining');
    });

    test('parses transactions envelope object', () {
      final drafts = parseAiEntryDrafts(
        '{"transactions":['
        '{"type":"income","amount":8000,"categoryId":"salary","accountId":"card"},'
        '{"type":"expense","amount":10,"categoryId":"dining","accountId":"cash"}'
        ']}',
        _context(),
      );
      expect(drafts, hasLength(2));
      expect(drafts[0].type, EntryType.income);
      expect(drafts[1].type, EntryType.expense);
    });

    test('skips zero-amount items', () {
      final drafts = parseAiEntryDrafts(
        '[{"type":"expense","amount":0,"categoryId":"dining","accountId":"cash"},'
        '{"type":"expense","amount":15,"categoryId":"dining","accountId":"cash"}]',
        _context(),
      );
      expect(drafts, hasLength(1));
      expect(drafts.single.amount, 15);
    });

    test('all zero-amount items throw noAmount', () {
      expect(
        () => parseAiEntryDrafts(
          '[{"type":"expense","amount":0,"categoryId":"dining","accountId":"cash"},'
          '{"type":"expense","amount":0,"categoryId":"dining","accountId":"cash"}]',
          _context(),
        ),
        throwsA(
          isA<AiEntryException>().having(
            (e) => e.error,
            'error',
            AiEntryError.noAmount,
          ),
        ),
      );
    });

    test('falls back to a single object draft', () {
      final drafts = parseAiEntryDrafts(
        '{"type":"expense","amount":32,"categoryId":"transport",'
        '"accountId":"cash","note":"打车"}',
        _context(),
      );
      expect(drafts, hasLength(1));
      expect(drafts.single.amount, 32);
    });

    test('no json throws emptyResult', () {
      expect(
        () => parseAiEntryDrafts('抱歉我不明白', _context()),
        throwsA(
          isA<AiEntryException>().having(
            (e) => e.error,
            'error',
            AiEntryError.emptyResult,
          ),
        ),
      );
    });

    test('caps drafts at maxCapturedEntryDrafts', () {
      final items = List.generate(
        12,
        (i) =>
            '{"type":"expense","amount":${i + 1},"categoryId":"dining",'
            '"accountId":"cash"}',
      ).join(',');
      final drafts = parseAiEntryDrafts('[$items]', _context());
      expect(drafts, hasLength(maxCapturedEntryDrafts));
      expect(drafts.first.amount, 1);
      expect(drafts.last.amount, maxCapturedEntryDrafts.toDouble());
    });
  });

  group('parseAiEntryDraft', () {
    test('parses a valid expense with matched category and account', () {
      final draft = parseAiEntryDraft(
        '{"type":"expense","amount":32,"categoryId":"transport",'
        '"accountId":"cash","toAccountId":null,"note":"打车","date":"2026-07-04"}',
        _context(),
      );
      expect(draft.type, EntryType.expense);
      expect(draft.amount, 32);
      expect(draft.categoryId, 'transport');
      expect(draft.accountId, 'cash');
      expect(draft.note, '打车');
      expect(draft.occurredAt.year, 2026);
      expect(draft.occurredAt.month, 7);
      expect(draft.occurredAt.day, 4);
      expect(draft.warnings, isEmpty);
    });

    test('模型把字符串字段返回成数字/数组时不崩溃，降级为未识别', () {
      // categoryId 返回数字、accountId 返回数组、note 返回布尔——旧代码 as String? 会抛。
      final draft = parseAiEntryDraft(
        '{"type":"expense","amount":20,"categoryId":5,'
        '"accountId":["cash"],"note":true}',
        _context(),
      );
      expect(draft.amount, 20);
      // 非法 categoryId 降级到第一个支出分类。
      expect(draft.categoryId, 'dining');
      // 非法 accountId 视为空（无账户）。
      expect(draft.accountId, '');
      // 非法 note 视为空串。
      expect(draft.note, '');
    });

    test('income picks from income categories', () {
      final draft = parseAiEntryDraft(
        '{"type":"income","amount":8000,"categoryId":"salary","accountId":"card"}',
        _context(),
      );
      expect(draft.type, EntryType.income);
      expect(draft.categoryId, 'salary');
      expect(draft.accountId, 'card');
    });

    test('transfer keeps both accounts and empty category', () {
      final draft = parseAiEntryDraft(
        '{"type":"transfer","amount":500,"categoryId":"",'
        '"accountId":"cash","toAccountId":"card"}',
        _context(),
      );
      expect(draft.type, EntryType.transfer);
      expect(draft.accountId, 'cash');
      expect(draft.toAccountId, 'card');
      expect(draft.categoryId, '');
    });

    test('unknown category falls back to first and warns', () {
      final draft = parseAiEntryDraft(
        '{"type":"expense","amount":10,"categoryId":"nope","accountId":"cash"}',
        _context(),
      );
      expect(draft.categoryId, 'dining');
      expect(draft.warnings, contains(AiDraftWarning.categoryUnmatched));
    });

    test('unknown account becomes no-account and warns', () {
      final draft = parseAiEntryDraft(
        '{"type":"expense","amount":10,"categoryId":"dining","accountId":"???"}',
        _context(),
      );
      expect(draft.accountId, '');
      expect(draft.warnings, contains(AiDraftWarning.accountUnmatched));
    });

    test('missing account stays empty without warning', () {
      final draft = parseAiEntryDraft(
        '{"type":"expense","amount":10,"categoryId":"dining","accountId":""}',
        _context(),
      );
      expect(draft.accountId, '');
      expect(draft.warnings, isEmpty);
    });

    test('amount as string is parsed and made positive', () {
      final draft = parseAiEntryDraft(
        '{"type":"expense","amount":"-32.5","categoryId":"dining"}',
        _context(),
      );
      expect(draft.amount, 32.5);
    });

    test('missing date and time default to now', () {
      final draft = parseAiEntryDraft(
        '{"type":"expense","amount":10,"categoryId":"dining"}',
        _context(),
      );
      expect(draft.occurredAt.year, 2026);
      expect(draft.occurredAt.month, 7);
      expect(draft.occurredAt.day, 5);
      // 未提供 time → 沿用当前时刻的时分。
      expect(draft.occurredAt.hour, 9);
      expect(draft.occurredAt.minute, 30);
    });

    test('explicit time is applied on top of the date', () {
      final draft = parseAiEntryDraft(
        '{"type":"expense","amount":58,"categoryId":"dining",'
        '"date":"2026-07-04","time":"20:00"}',
        _context(),
      );
      expect(draft.occurredAt.day, 4);
      expect(draft.occurredAt.hour, 20);
      expect(draft.occurredAt.minute, 0);
    });

    test('time without a date uses today with the given time', () {
      final draft = parseAiEntryDraft(
        '{"type":"expense","amount":15,"categoryId":"dining","time":"7:05"}',
        _context(),
      );
      expect(draft.occurredAt.day, 5);
      expect(draft.occurredAt.hour, 7);
      expect(draft.occurredAt.minute, 5);
    });

    test('invalid time falls back to the current time', () {
      final draft = parseAiEntryDraft(
        '{"type":"expense","amount":15,"categoryId":"dining",'
        '"date":"2026-07-04","time":"25:99"}',
        _context(),
      );
      expect(draft.occurredAt.day, 4);
      expect(draft.occurredAt.hour, 9);
      expect(draft.occurredAt.minute, 30);
    });

    test('no amount throws noAmount', () {
      expect(
        () => parseAiEntryDraft(
          '{"type":"expense","amount":0,"categoryId":"dining"}',
          _context(),
        ),
        throwsA(
          isA<AiEntryException>().having(
            (e) => e.error,
            'error',
            AiEntryError.noAmount,
          ),
        ),
      );
    });

    test('no json throws emptyResult', () {
      expect(
        () => parseAiEntryDraft('抱歉我不明白', _context()),
        throwsA(
          isA<AiEntryException>().having(
            (e) => e.error,
            'error',
            AiEntryError.emptyResult,
          ),
        ),
      );
    });
  });

  group('AiException', () {
    test('carries an error code and optional detail', () {
      final ex = AiException(AiErrorCode.timeout);
      expect(ex.code, AiErrorCode.timeout);
      expect(ex.detail, isNull);

      final withDetail = AiException(AiErrorCode.upstream, detail: 'boom');
      expect(withDetail.code, AiErrorCode.upstream);
      expect(withDetail.detail, 'boom');
      expect(withDetail.toString(), contains('boom'));
    });
  });
}
