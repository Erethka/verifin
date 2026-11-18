part of 'veri_fin_controller.dart';

mixin _ControllerMuse on _ControllerState, _ControllerOps {
  Future<int>? _museSync;
  String? _museSyncError;

  MuseSyncConfig get museSyncConfig => _museSyncConfig;
  String? get museSyncError => _museSyncError;

  void reportMuseSyncError() {
    // Transport exceptions can embed URLs or credentials. Keep diagnostics fixed.
    _logger?.error('Muse synchronization failed', source: 'muse_sync');
    _museSyncError = l10nForPreference(_localePreference).museSyncError;
    notifyListeners();
  }

  Future<void> configureMuseSync({
    required String url,
    required String token,
    required String bookId,
    required bool enabled,
    bool resetProgress = false,
  }) async {
    if (_museSync != null) throw StateError('Synchronization is running');
    final normalized = url.trim().isEmpty && !enabled
        ? ''
        : museServerUri(url).toString();
    if (enabled && !_ledgerBooks.any((book) => book.id == bookId)) {
      throw StateError('Select an existing ledger');
    }
    if (enabled && normalized != _museSyncConfig.url && token.isEmpty) {
      throw StateError('Enter a new credential when changing servers');
    }
    if (token.isNotEmpty) {
      if (!RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(token)) {
        throw const FormatException('Invalid sync credential');
      }
      await MuseSyncBridge.saveToken(normalized, token);
    }
    if (enabled && (await MuseSyncBridge.readToken(normalized)).isEmpty) {
      throw StateError('A read credential is required');
    }
    final sameServer = normalized == _museSyncConfig.url && !resetProgress;
    await MuseSyncBridge.setEnabled(enabled);
    _museSyncConfig = MuseSyncConfig(
      url: normalized,
      bookId: bookId,
      enabled: enabled,
      cursor: sameServer ? _museSyncConfig.cursor : 0,
      stream: sameServer ? _museSyncConfig.stream : '',
    );
    _store.write(_museSyncKey, _museSyncConfig.encode());
    await _store.flush();
    _museSyncError = null;
    notifyListeners();
  }

  Future<int> syncMuseBills({
    Future<Map<String, dynamic>> Function(MuseSyncConfig, String)? fetch,
  }) {
    final running = _museSync;
    if (running != null) return running;
    final future = _syncMuseBills(fetch ?? fetchMuseChanges);
    _museSync = future;
    // Keep the returned future's errors visible to the coordinator and UI.
    unawaited(
      future.then<void>(
        (_) => _museSync = null,
        onError: (Object _, StackTrace _) {
          _museSync = null;
        },
      ),
    );
    return future;
  }

  Future<int> _syncMuseBills(
    Future<Map<String, dynamic>> Function(MuseSyncConfig, String) fetch,
  ) async {
    if (!_museSyncConfig.enabled || !_privacyConsentAccepted) return 0;
    final token = await MuseSyncBridge.readToken(_museSyncConfig.url);
    if (token.isEmpty) throw StateError('No credential for this server');
    final elapsed = Stopwatch()..start();
    var imported = 0;
    // Bound one job to fit Android's background execution window.
    for (var page = 0; page < 20; page++) {
      final config = _museSyncConfig;
      if (!config.enabled || elapsed.elapsed.inSeconds >= 55) break;
      final response = await fetch(config, token);
      if (!identical(config, _museSyncConfig)) break;
      imported += await importMusePage(response, config: config);
      if (response['has_more'] == false) break;
    }
    _museSyncError = null;
    notifyListeners();
    return imported;
  }

  /// Persist the ledger before acknowledging the remote cursor. Replays upsert IDs.
  @visibleForTesting
  Future<int> importMusePage(
    Map<String, dynamic> response, {
    required MuseSyncConfig config,
  }) async {
    if (!_ledgerBooks.any((book) => book.id == config.bookId)) {
      throw StateError('Sync ledger no longer exists');
    }
    final stream = response['stream'];
    final cursor = response['cursor'];
    final rows = response['entries'];
    if (stream is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(stream) ||
        (config.stream.isNotEmpty && config.stream != stream) ||
        cursor is! int ||
        cursor < config.cursor ||
        rows is! List ||
        rows.length > 100 ||
        response['has_more'] is! bool ||
        (rows.isNotEmpty && cursor <= config.cursor) ||
        (response['has_more'] == true && rows.isEmpty)) {
      throw const FormatException(
        'Invalid sync page or changed server database',
      );
    }
    final updates = <LedgerEntry>[];
    final missingCategories = <EntryType>{};
    final ids = <String>{};
    for (final row in rows) {
      if (row is! Map ||
          row['id'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(row['id'] as String) ||
          !ids.add(row['id'] as String) ||
          row['currency'] != 'CNY' ||
          !['expense', 'income'].contains(row['type'])) {
        throw const FormatException('Invalid sync entry');
      }
      final rawAmount = row['amount'];
      if (rawAmount is! String ||
          !RegExp(r'^[0-9]{1,9}(\.[0-9]{1,2})?$').hasMatch(rawAmount)) {
        throw const FormatException('Invalid sync amount');
      }
      final amount = double.parse(rawAmount);
      final date = row['occurred_at'];
      final stamp = date is String ? DateTime.tryParse(date) : null;
      if (amount <= 0 ||
          stamp == null ||
          !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(date as String)) {
        throw const FormatException('Invalid sync amount or timestamp');
      }
      for (final field in ['category', 'merchant', 'payment_method', 'note']) {
        final value = row[field];
        if (value != null && (value is! String || value.length > 1000)) {
          throw const FormatException('Invalid sync text');
        }
      }
      final type = row['type'] == 'expense'
          ? EntryType.expense
          : EntryType.income;
      final id = 'muse_${stream}_${row['id']}';
      final index = _entries.indexWhere((entry) => entry.id == id);
      final existing = index < 0 ? null : _entries[index];
      final categoryId =
          _matchMuseCategory(row['category'] as String?, type) ??
          (existing?.type == type ? existing?.categoryId : null) ??
          uncategorizedCategoryId(type);
      if (!_categories.any((category) => category.id == categoryId)) {
        missingCategories.add(type);
      }
      final note = [
        'Muse',
        row['merchant'],
        row['payment_method'],
        row['note'],
      ].whereType<String>().where((text) => text.isNotEmpty).join(' · ');
      updates.add(
        existing?.copyWith(
              type: type,
              amount: amount,
              categoryId: categoryId,
              note: note,
              occurredAt: stamp.toLocal(),
            ) ??
            LedgerEntry(
              id: id,
              bookId: config.bookId,
              type: type,
              amount: amount,
              categoryId: categoryId,
              accountId: '',
              note: note,
              occurredAt: stamp.toLocal(),
            ),
      );
    }
    // Validate the whole page before changing any in-memory ledger data.
    for (final type in missingCategories) {
      _categories.add(buildUncategorizedCategory(type, english: _seedEnglish));
    }
    for (final entry in updates) {
      final index = _entries.indexWhere((old) => old.id == entry.id);
      if (index < 0) {
        _entries.add(entry);
      } else {
        _entries[index] = entry;
      }
    }
    _entries.sort(_compareEntriesLatestFirst);
    _syncRefundCache();
    notifyListeners();
    final categoriesWrite = _repository.saveCategories(
      List<Category>.of(_categories),
    );
    _trackWrite(categoriesWrite);
    await categoriesWrite;
    final entriesWrite = _repository.saveEntries(
      List<LedgerEntry>.of(_entries),
    );
    _trackWrite(entriesWrite);
    await entriesWrite;
    if (identical(config, _museSyncConfig)) {
      _museSyncConfig = config.copyWith(cursor: cursor, stream: stream);
      _store.write(_museSyncKey, _museSyncConfig.encode());
      await _store.flush();
    }
    if (updates.isNotEmpty) onEntryAdded?.call();
    return updates.length;
  }

  String? _matchMuseCategory(String? name, EntryType type) {
    final label = normalizedCategoryLabel(name ?? '');
    if (label.isEmpty || label == '未分类' || label == 'uncategorized') {
      return null;
    }

    final available = _categories.where((category) => category.type == type);
    final path = label.split('/').map((part) => part.trim()).join(' / ');
    final matches = available.where((category) {
      if (label.contains('/')) {
        return normalizedCategoryLabel(pathLabel(_categories, category.id)) ==
            path;
      }
      return normalizedCategoryLabel(category.label) == label;
    }).toList();
    if (matches.length == 1) return matches.single.id;
    if (matches.isNotEmpty) return null;

    const aliases = {
      '饮食': 'dining',
      '餐饮美食': 'dining',
      '外卖': 'dining',
      '交通出行': 'transport',
      '出行': 'transport',
      '日常购物': 'shopping',
      '住房': 'housing',
      '房租': 'housing',
      '休闲娱乐': 'entertainment',
      '医疗健康': 'medical',
      '薪资': 'salary',
      '薪水': 'salary',
    };
    final seeds = [
      ...defaultCategories,
      ...defaultCategoriesFor(english: true),
    ];
    final seed = seeds
        .where(
          (category) =>
              category.type == type &&
              normalizedCategoryLabel(category.label) == label,
        )
        .firstOrNull;
    final candidateId = seed?.id ?? aliases[label] ?? label;
    return available
        .where((category) => category.id == candidateId)
        .firstOrNull
        ?.id;
  }
}
