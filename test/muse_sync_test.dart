import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/app/muse_sync_bridge.dart';
import 'package:verifin/app/muse_sync_config.dart';
import 'package:verifin/app/veri_fin_controller.dart';
import 'package:verifin/app/veri_fin_scope.dart';
import 'package:verifin/local_storage/local_storage.dart';
import 'package:verifin/pages/muse_sync_settings_page.dart';

import 'support/in_memory_ledger_repository.dart';
import 'support/test_harness.dart';

const stream = '0123456789abcdef0123456789abcdef';
const config = MuseSyncConfig(
  url: 'https://bills.example.com:9443',
  bookId: 'default',
  enabled: true,
);

Map<String, dynamic> page({
  String amount = '12.50',
  int cursor = 1,
  String? category,
}) => {
  'stream': stream,
  'cursor': cursor,
  'has_more': false,
  'entries': [
    {
      'id': 'lunch',
      'occurred_at': '2026-11-16T12:30:00+08:00',
      'type': 'expense',
      'amount': amount,
      'currency': 'CNY',
      if (category != null) 'category': category,
      'merchant': '面馆',
      'payment_method': 'Alipay',
      'note': '午饭',
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useTestDatabases();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MuseSyncBridge.channel, (call) async {
          if (call.method == 'readToken') return 'r' * 43;
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MuseSyncBridge.channel, null);
  });

  LocalKeyValueStore store() => LocalKeyValueStore()
    ..write('verifin.privacy_consent.v1', 'true')
    ..write('verifin.muse_sync.v1', config.encode());

  test(
    'startup clears obsolete capture preferences and loads Muse settings',
    () async {
      final kv = store()..write('verifin.auto_payment.v1', 'true');
      final controller = await VeriFinController.create(
        kv,
        repository: InMemoryLedgerRepository(),
      );
      expect(kv.read('verifin.auto_payment.v1'), isNull);
      expect(controller.museSyncConfig.enabled, isTrue);
      expect(controller.museSyncConfig.url, config.url);
    },
  );

  testWidgets('settings saves server and passes credential to native storage', (
    tester,
  ) async {
    final controller = await makeController();
    String? storedToken;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MuseSyncBridge.channel, (call) async {
          if (call.method == 'saveToken') {
            final payload = call.arguments as Map;
            expect(payload['origin'], config.url);
            storedToken = payload['token'] as String;
          }
          if (call.method == 'readToken') {
            expect(call.arguments, config.url);
            return storedToken ?? '';
          }
          return null;
        });
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(home: const MuseSyncSettingsPage()),
      ),
    );
    await tester.enterText(find.byType(TextField).first, config.url);
    await tester.enterText(find.byType(TextField).last, 'r' * 43);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, '保存');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(controller.museSyncConfig.enabled, isTrue);
    expect(controller.museSyncConfig.url, config.url);
    expect(storedToken, 'r' * 43);
    expect(
      (tester.widget<TextField>(find.byType(TextField).last)).controller!.text,
      isEmpty,
    );
    expect(controller.museSyncConfig.encode(), isNot(contains(storedToken!)));
  });

  test(
    'Muse classifies a previously uncategorized bill without duplicating it',
    () async {
      final repo = InMemoryLedgerRepository();
      final controller = await VeriFinController.create(
        store(),
        repository: repo,
        systemIsEnglish: true,
      );
      await controller.syncMuseBills(fetch: (_, _) async => page());
      final id = controller.entries.single.id;
      expect(
        controller.entries.single.categoryId,
        uncategorizedCategoryId(EntryType.expense),
      );

      await controller.syncMuseBills(
        fetch: (_, _) async => page(cursor: 2, category: ' 外卖 '),
      );
      expect(controller.entries.single.id, id);
      expect(controller.entries.single.categoryId, 'dining');

      await controller.syncMuseBills(
        fetch: (_, _) async => page(cursor: 3, amount: '15.00'),
      );
      final persisted = (await repo.loadEntries()).single;
      expect(persisted.id, id);
      expect(persisted.categoryId, 'dining');
      expect(persisted.amount, 15);
    },
  );

  test(
    'resetting read progress replays the server without duplicating entries',
    () async {
      final controller = await VeriFinController.create(
        store(),
        repository: InMemoryLedgerRepository(),
      );
      await controller.syncMuseBills(fetch: (_, _) async => page());
      await controller.configureMuseSync(
        url: config.url,
        token: '',
        bookId: config.bookId,
        enabled: true,
        resetProgress: true,
      );
      expect(controller.museSyncConfig.cursor, 0);
      await controller.syncMuseBills(fetch: (_, _) async => page());
      expect(controller.entries, hasLength(1));
    },
  );

  test(
    'failed server change never sends its new credential to the old origin',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var storedOrigin = config.url;
      var storedToken = 'r' * 43;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MuseSyncBridge.channel, (call) async {
            if (call.method == 'saveToken') {
              final payload = call.arguments as Map;
              storedOrigin = payload['origin'] as String;
              storedToken = payload['token'] as String;
            }
            if (call.method == 'readToken') {
              return call.arguments == storedOrigin ? storedToken : '';
            }
            if (call.method == 'setEnabled') {
              throw PlatformException(code: 'SCHEDULER_UNAVAILABLE');
            }
            return null;
          });
      final controller = await VeriFinController.create(
        store(),
        repository: InMemoryLedgerRepository(),
      );
      await expectLater(
        controller.configureMuseSync(
          url: 'https://new.example.com',
          token: 'n' * 43,
          bookId: config.bookId,
          enabled: true,
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(controller.museSyncConfig.url, config.url);
      var calls = 0;
      await expectLater(
        controller.syncMuseBills(
          fetch: (_, _) async {
            calls++;
            return page();
          },
        ),
        throwsStateError,
      );
      expect(calls, 0);
    },
  );

  test('requires HTTPS without embedded credentials, paths or query', () {
    expect(museServerUri('https://bills.example.com:9443/').port, 9443);
    for (final bad in [
      'http://bills.example.com',
      'https://user:secret@host',
      'https://host/path',
      'https://host?token=secret',
      'https://host/#key',
    ]) {
      expect(() => museServerUri(bad), throwsFormatException);
    }
  });

  test(
    'imports, persists cursor, corrects stable ID and survives restart',
    () async {
      final kv = store();
      final repo = InMemoryLedgerRepository();
      final controller = await VeriFinController.create(kv, repository: repo);
      await controller.syncMuseBills(
        fetch: (cfg, token) async {
          expect(cfg.cursor, 0);
          expect(token.length, 43);
          return page();
        },
      );
      expect(controller.entries.single.amount, 12.5);
      expect(controller.entries.single.accountId, isEmpty);
      expect(controller.entries.single.note, contains('Alipay'));
      expect(controller.museSyncConfig.cursor, 1);
      final originalId = controller.entries.single.id;
      final restarted = await VeriFinController.create(kv, repository: repo);
      await restarted.syncMuseBills(
        fetch: (cfg, _) async {
          expect(cfg.cursor, 1);
          return page(amount: '19.90', cursor: 2);
        },
      );
      expect(restarted.entries, hasLength(1));
      expect(restarted.entries.single.id, originalId);
      expect(restarted.entries.single.amount, 19.9);
      expect((await repo.loadEntries()).single.amount, 19.9);
      expect(restarted.exportDataJson(), isNot(contains(config.url)));
    },
  );

  test('failed storage keeps cursor and retries without duplicating', () async {
    final repo = _FailOnceRepository();
    final controller = await VeriFinController.create(
      store(),
      repository: repo,
    );
    repo.failNextSave = true;
    await expectLater(
      controller.syncMuseBills(fetch: (_, _) async => page()),
      throwsStateError,
    );
    expect(controller.museSyncConfig.cursor, 0);
    await controller.syncMuseBills(fetch: (_, _) async => page());
    expect(controller.entries, hasLength(1));
    expect(controller.museSyncConfig.cursor, 1);
    expect(await repo.loadEntries(), hasLength(1));
  });

  test(
    'validates the whole page before importing and rejects stream changes',
    () async {
      final controller = await VeriFinController.create(
        store(),
        repository: InMemoryLedgerRepository(),
      );
      final malformed = page();
      (malformed['entries'] as List).add({'id': 'bad'});
      await expectLater(
        controller.syncMuseBills(fetch: (_, _) async => malformed),
        throwsFormatException,
      );
      expect(controller.entries, isEmpty);
      expect(controller.museSyncConfig.cursor, 0);
      await controller.syncMuseBills(fetch: (_, _) async => page());
      final changedStream = page(cursor: 2)..['stream'] = 'f' * 32;
      await expectLater(
        controller.syncMuseBills(fetch: (_, _) async => changedStream),
        throwsFormatException,
      );
      expect(controller.museSyncConfig.cursor, 1);
      expect(controller.entries, hasLength(1));
    },
  );

  test(
    'concurrent triggers share one fetch and disabled sync makes no request',
    () async {
      final controller = await VeriFinController.create(
        store(),
        repository: InMemoryLedgerRepository(),
      );
      final pending = Completer<Map<String, dynamic>>();
      var calls = 0;
      Future<Map<String, dynamic>> fetch(MuseSyncConfig cfg, String token) {
        calls++;
        return pending.future;
      }

      final first = controller.syncMuseBills(fetch: fetch);
      final second = controller.syncMuseBills(fetch: fetch);
      expect(identical(first, second), isTrue);
      pending.complete(page());
      await Future.wait([first, second]);
      expect(calls, 1);
      controller.resetAllData();
      await controller.waitForPendingWrites();
      expect(controller.museSyncConfig.enabled, isFalse);
      await controller.syncMuseBills(fetch: fetch);
      expect(calls, 1);
    },
  );

  test(
    'reset during fetch prevents an old response from repopulating ledger',
    () async {
      final controller = await VeriFinController.create(
        store(),
        repository: InMemoryLedgerRepository(),
      );
      final started = Completer<void>();
      final response = Completer<Map<String, dynamic>>();
      final sync = controller.syncMuseBills(
        fetch: (_, _) {
          started.complete();
          return response.future;
        },
      );
      await started.future;
      controller.resetAllData();
      response.complete(page());
      await sync;
      expect(controller.entries, isEmpty);
      expect(controller.museSyncConfig.enabled, isFalse);
    },
  );
}

class _FailOnceRepository extends InMemoryLedgerRepository {
  bool failNextSave = false;

  @override
  Future<void> saveEntries(List<LedgerEntry> entries) async {
    if (failNextSave) {
      failNextSave = false;
      throw StateError('Test disk failure');
    }
    await super.saveEntries(entries);
  }
}
