import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';

import 'automation.dart';
import 'l10n.dart';
import 'settings.dart';
import 'setup_screen.dart';
import 'slideshow_screen.dart';
import 'theme.dart';

/// MIUI-derived builds need a portrait attach before rotating: an immediate
/// landscape attach leaves a stale 90° buffer transform on some of them
/// (ADR-003). Everything else, including ChromeOS/ARC, can attach in
/// landscape right away and never shows a portrait boot frame.
Future<bool> _needsPortraitAttach() async {
  if (!Platform.isAndroid) return false;
  try {
    final value = await const MethodChannel('hearthframe/device')
        .invokeMethod<bool>('needsPortraitAttach');
    // Unknown Android vendor: keep the compatibility path rather than risk a
    // sideways UI on an affected device.
    return value ?? true;
  } catch (_) {
    return true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final hardwareDecoding = !Platform.isAndroid ||
      await const MethodChannel('hearthframe/device')
              .invokeMethod<bool>('supportsHevc') ==
          true;
  VideoPlayerMediaKit.ensureInitialized(
      android: true, androidHardwareDecoding: hardwareDecoding);
  debugPrint('HF video backend media_kit hardwareDecoding=$hardwareDecoding');
  // A frame shows one photo at a time; a large default image cache would sit
  // idle in memory (visible in PSS on low-RAM TV boxes). Keep just enough for
  // the current slide plus the outgoing one during a transition.
  PaintingBinding.instance.imageCache
    ..maximumSize = 6
    ..maximumSizeBytes = 32 << 20;
  final portraitAttach = await _needsPortraitAttach();
  debugPrint('HF orientation portraitAttach=$portraitAttach');
  // Allow BOTH landscape directions: Flutter maps the pair to
  // SCREEN_ORIENTATION_USER_LANDSCAPE, so a frame mounted upside down still
  // follows the sensor instead of being pinned to one edge.
  const landscapeOrientations = [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];
  await SystemChrome.setPreferredOrientations(
    portraitAttach ? [DeviceOrientation.portraitUp] : landscapeOrientations,
  );
  final settings = await FrameSettings.load();
  // Mirror automation settings to the native layer (boot / charging /
  // schedule alarms must work while Flutter is not running).
  final automationSync = AutomationSync();
  await automationSync(settings);
  settings.addListener(() {
    automationSync(settings);
  });
  // keep_adb (opt-in via `adb shell pm grant ... WRITE_SECURE_SETTINGS`):
  // while the frame runs, write wireless debugging back on if the OEM
  // switches it off (e.g. after standby). No-op without the grant.
  if (Platform.isAndroid) {
    const channel = MethodChannel('hearthframe/adb_keep');
    Future<void> ensure() =>
        channel.invokeMethod<void>('ensure').catchError((_) {});
    await ensure();
    Timer.periodic(const Duration(seconds: 60), (_) => ensure());
  }
  runApp(HearthFrameApp(settings));
  if (portraitAttach) {
    // Rotate only after the surface is established so the metrics recompute
    // path fixes the stale crop (ADR-003).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
        // Keep the original single-landscape target for the MIUI buffer
        // transform workaround (ADR-003); the dual-landscape sensor follow
        // is only needed on non-MIUI devices.
        SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft],
        );
      });
    });
  }
}

/// HearthFrame — an original, open-source family photo frame.
/// Clean-room implementation; not affiliated with or derived from any
/// commercial photo-frame product.
class HearthFrameApp extends StatelessWidget {
  const HearthFrameApp(this.settings, {super.key});

  final FrameSettings settings;

  Locale? get _locale => switch (settings.language) {
        'en' => const Locale('en'),
        'zh' => const Locale('zh'),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'HearthFrame',
        debugShowCheckedModeBanner: false,
        theme: buildHearthTheme(),
        locale: _locale,
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: (settings.setupMode || !settings.isConfigured)
            ? SetupScreen(settings: settings)
            : SlideshowScreen(settings: settings),
      ),
    );
  }
}
