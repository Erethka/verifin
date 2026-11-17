import 'dart:async';

import 'package:flutter/services.dart';

import 'muse_sync_bridge.dart';
import 'veri_fin_controller.dart';

/// Foreground and JobScheduler calls share the main engine and controller.
class MuseSyncCoordinator {
  MuseSyncCoordinator(this.controller);

  final VeriFinController controller;

  Future<void> start() async {
    if (!MuseSyncBridge.supported) return;
    MuseSyncBridge.channel.setMethodCallHandler((call) async {
      if (call.method == 'sync') return sync();
      throw MissingPluginException();
    });
    try {
      await MuseSyncBridge.setEnabled(controller.museSyncConfig.enabled);
      await MuseSyncBridge.channel.invokeMethod<void>('ready');
      unawaited(sync());
    } on MissingPluginException {
      // Widget test hosts do not run Android jobs.
    } catch (_) {
      controller.reportMuseSyncError();
    }
  }

  Future<bool> sync() async {
    try {
      await controller.syncMuseBills();
      return true;
    } catch (_) {
      controller.reportMuseSyncError();
      return false;
    }
  }

  void dispose() {
    if (MuseSyncBridge.supported) {
      MuseSyncBridge.channel.setMethodCallHandler(null);
    }
  }
}
