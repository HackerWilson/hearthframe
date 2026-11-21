import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'settings.dart';

/// Mirror of the native automation permission state.
class AutomationStatus {
  const AutomationStatus({
    required this.notifications,
    required this.overlay,
    required this.exactAlarms,
    required this.fullScreen,
    this.miui = false,
  });

  final bool notifications;
  final bool overlay;
  final bool exactAlarms;
  final bool fullScreen;

  /// MIUI/HyperOS needs an extra manual autostart + background pop-up grant.
  final bool miui;

  static const granted = AutomationStatus(
    notifications: true,
    overlay: true,
    exactAlarms: true,
    fullScreen: true,
  );

  int get grantedCount => [
        notifications,
        overlay,
        exactAlarms,
        fullScreen,
      ].where((e) => e).length;

  bool get complete => notifications && overlay && exactAlarms && fullScreen;

  static AutomationStatus fromMap(Object? value) {
    if (value is Map) {
      bool read(String key) => value[key] == true;
      return AutomationStatus(
        notifications: read('notifications'),
        overlay: read('overlay'),
        exactAlarms: read('exactAlarms'),
        fullScreen: read('fullScreen'),
        miui: read('miui'),
      );
    }
    return granted;
  }
}

/// Thin bridge to the Kotlin automation layer, which persists the settings
/// separately so boot / charging / daily alarms work without Flutter.
class AutomationService {
  const AutomationService._();

  static const _channel = MethodChannel('hearthframe/automation');
  static bool get _supported => Platform.isAndroid;

  /// Pushes the current automation settings to native and returns the
  /// permission state it observed.
  static Future<AutomationStatus> configure(FrameSettings settings) async {
    if (!_supported) return AutomationStatus.granted;
    try {
      final value = await _channel.invokeMethod<Object?>(
        'configure',
        settings.automationConfig,
      );
      return AutomationStatus.fromMap(value);
    } catch (e) {
      debugPrint('HF automation configure failed: $e');
      return AutomationStatus.granted;
    }
  }

  static Future<AutomationStatus> status() async {
    if (!_supported) return AutomationStatus.granted;
    try {
      return AutomationStatus.fromMap(
        await _channel.invokeMethod<Object?>('status'),
      );
    } catch (_) {
      return AutomationStatus.granted;
    }
  }

  /// Opens MIUI/HyperOS autostart management.
  static Future<bool> openOemStartupSettings() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'openOemStartupSettings',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Opens MIUI/HyperOS per-app permissions (后台弹出界面 lives here).
  static Future<bool> openOemPermissionEditor() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'openOemPermissionEditor',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the next missing special permission and returns its key.
  static Future<String> requestNextPermission() async {
    if (!_supported) return 'complete';
    try {
      return await _channel.invokeMethod<String>(
            'requestNextPermission',
          ) ??
          'complete';
    } catch (_) {
      return 'complete';
    }
  }
}

/// Keeps the native copy in sync, skipping redundant writes on every slider
/// tick.
class AutomationSync {
  Map<String, Object>? _last;

  Future<void> call(FrameSettings settings) async {
    final config = settings.automationConfig;
    if (_last != null && mapEquals(_last, config)) return;
    _last = config;
    await AutomationService.configure(settings);
  }
}
