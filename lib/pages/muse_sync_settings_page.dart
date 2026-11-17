import 'package:flutter/material.dart';

import '../app/common_widgets.dart';
import '../app/models.dart';
import '../app/veri_fin_scope.dart';
import '../l10n/app_localizations.dart';
import 'sheets.dart';

class MuseSyncSettingsPage extends StatefulWidget {
  const MuseSyncSettingsPage({super.key});

  @override
  State<MuseSyncSettingsPage> createState() => _MuseSyncSettingsPageState();
}

class _MuseSyncSettingsPageState extends State<MuseSyncSettingsPage> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  String? _bookId;
  bool _enabled = false;
  bool _loaded = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    final controller = VeriFinScope.of(context);
    final config = controller.museSyncConfig;
    _url.text = config.url;
    _bookId = controller.ledgerBooks.any((book) => book.id == config.bookId)
        ? config.bookId
        : controller.activeBook.id;
    _enabled = config.enabled;
    _loaded = true;
  }

  Future<void> _pickBook() async {
    final controller = VeriFinScope.of(context);
    final selected = await showOptionSheet<LedgerBook>(
      context: context,
      title: AppLocalizations.of(context).museSyncBook,
      values: controller.ledgerBooks,
      selected:
          controller.ledgerBooks
              .where((book) => book.id == _bookId)
              .firstOrNull ??
          controller.activeBook,
      labelOf: (book) => book.name,
    );
    if (!mounted || selected == null) return;
    setState(() => _bookId = selected.id);
  }

  Future<void> _save({required bool sync, bool resetProgress = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final controller = VeriFinScope.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      await controller.configureMuseSync(
        url: _url.text,
        token: _token.text.trim(),
        bookId: _bookId ?? controller.activeBook.id,
        enabled: _enabled,
        resetProgress: resetProgress,
      );
      _token.clear();
      if (sync) await controller.syncMuseBills();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sync ? l10n.museSyncDone : l10n.museSyncSaved)),
      );
    } catch (_) {
      controller.reportMuseSyncError();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.museSyncError)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.museSyncReload,
      message: l10n.museSyncReloadHint,
      confirmLabel: l10n.museSyncReload,
    );
    if (!mounted || !confirmed) return;
    await _save(sync: true, resetProgress: true);
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = VeriFinScope.of(context);
    final l10n = AppLocalizations.of(context);
    final book =
        controller.ledgerBooks
            .where((book) => book.id == _bookId)
            .firstOrNull ??
        controller.activeBook;
    return Scaffold(
      body: SafeArea(
        child: VeriPage(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
            children: [
              VeriHeader(title: l10n.museSyncTitle, showBack: true),
              const SizedBox(height: 12),
              Text(l10n.museSyncDescription),
              const SizedBox(height: 12),
              VeriCard(
                child: Column(
                  children: [
                    CompactSwitchRow(
                      icon: Icons.sync_outlined,
                      title: Text(l10n.museSyncEnabled),
                      value: _enabled,
                      onChanged: (value) {
                        if (!_busy) setState(() => _enabled = value);
                      },
                    ),
                    const Divider(height: 1),
                    SettingsRow(
                      icon: Icons.menu_book_outlined,
                      title: l10n.museSyncBook,
                      trailing: book.name,
                      trailingIcon: Icons.chevron_right,
                      onTap: _busy ? null : _pickBook,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _url,
                enabled: !_busy,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: l10n.museSyncUrl),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _token,
                enabled: !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: l10n.museSyncToken,
                  helperText: l10n.museSyncTokenHint,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : () => _save(sync: false),
                child: Text(l10n.commonSave),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy || !_enabled ? null : () => _save(sync: true),
                child: Text(l10n.museSyncNow),
              ),
              TextButton(
                onPressed: _busy || !_enabled ? null : _reload,
                child: Text(l10n.museSyncReload),
              ),
              const SizedBox(height: 12),
              if (controller.museSyncError != null)
                Text(controller.museSyncError!),
              Text(l10n.museSyncBackground),
            ],
          ),
        ),
      ),
    );
  }
}
