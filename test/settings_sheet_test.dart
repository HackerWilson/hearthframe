import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearthframe/l10n.dart';
import 'package:hearthframe/settings.dart';
import 'package:hearthframe/settings_sheet.dart';
import 'package:hearthframe/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const deviceChannel = MethodChannel('hearthframe/device');
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temporaryDirectory;
  late FrameSettings settings;
  late int changes;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await FrameSettings.load();
    changes = 0;
    temporaryDirectory =
        Directory.systemTemp.createTempSync('hf_settings_test');
    Directory('${temporaryDirectory.path}/hearthframe_cache').createSync();
    messenger.setMockMethodCallHandler(pathChannel, (call) async {
      expect(call.method, 'getTemporaryDirectory');
      return temporaryDirectory.path;
    });
    messenger.setMockMethodCallHandler(deviceChannel, (call) async {
      expect(call.method, 'appVersion');
      return '0.2.0+2026111801';
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(deviceChannel, null);
    messenger.setMockMethodCallHandler(pathChannel, null);
    temporaryDirectory.deleteSync(recursive: true);
    settings.dispose();
  });

  Finder category(String name) =>
      find.byKey(ValueKey('settings-category-$name'));
  final content = find.byKey(const ValueKey('settings-content'));
  final close = find.byKey(const ValueKey('settings-close'));

  Future<void> openSettings(
    WidgetTester tester, {
    Size screenSize = const Size(1000, 800),
    Size panelSize = const Size(900, 640),
    Locale locale = const Locale('en'),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = screenSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildHearthTheme(),
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(
                    insetPadding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: panelSize.width,
                      height: panelSize.height,
                      child: SettingsSheet(
                        settings: settings,
                        onChanged: (value) {
                          expectSync(value, same(settings));
                          changes++;
                        },
                      ),
                    ),
                  ),
                ),
                child: const Text('Open settings'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
  }

  Future<void> selectCategory(WidgetTester tester, String name) async {
    await tester.ensureVisible(category(name));
    await tester.pumpAndSettle();
    await tester.tap(category(name));
    await tester.pumpAndSettle();
  }

  SwitchListTile mediaDateSwitch(WidgetTester tester, AppStrings s) =>
      tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text(s.showMediaDate),
          matching: find.byType(SwitchListTile),
        ),
      );

  testWidgets('wide panel defaults to slideshow and switches categories',
      (tester) async {
    await openSettings(tester);
    expect(find.byKey(const ValueKey('settings-sidebar')), findsOneWidget);
    expect(find.text('Slide duration'), findsOneWidget);
    expect(find.text('Show photo/video date'), findsNothing);
    expect(tester.getTopLeft(category('slideshow')).dx,
        lessThan(tester.getTopLeft(content).dx));
    expect(category('automation'),
        Platform.isAndroid ? findsOneWidget : findsNothing);

    await selectCategory(tester, 'appearance');
    expect(find.text('Show photo/video date'), findsOneWidget);
    expect(find.text('Slide duration'), findsNothing);
    await selectCategory(tester, 'system');
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Keep screen on'), findsOneWidget);
    await selectCategory(tester, 'storage');
    expect(find.text('Media cache'), findsOneWidget);
    await selectCategory(tester, 'about');
    expect(find.text('0.2.0+2026111801'), findsOneWidget);
    expect(find.text('0.1.0'), findsNothing);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'media date defaults on and changes immediately in both directions',
      (tester) async {
    const s = AppStrings(Locale('en'));
    await openSettings(tester);
    await selectCategory(tester, 'appearance');
    expect(settings.showMediaDate, isTrue);
    expect(mediaDateSwitch(tester, s).value, isTrue);
    expect(tester.getTopLeft(find.text(s.showMediaDate)).dy,
        lessThan(tester.getTopLeft(find.text(s.showClock)).dy));
    expect(find.text(s.showMediaDateDesc), findsOneWidget);

    await tester.tap(find.text(s.showMediaDate));
    await tester.pumpAndSettle();
    expect(settings.showMediaDate, isFalse);
    expect(mediaDateSwitch(tester, s).value, isFalse);
    expect(changes, 1);
    expect((await FrameSettings.load()).showMediaDate, isFalse);

    await selectCategory(tester, 'slideshow');
    await selectCategory(tester, 'appearance');
    expect(mediaDateSwitch(tester, s).value, isFalse);
    await tester.tap(find.text(s.showMediaDate));
    await tester.pumpAndSettle();
    expect(settings.showMediaDate, isTrue);
    expect(mediaDateSwitch(tester, s).value, isTrue);
    expect(changes, 2);
  });

  testWidgets('duration presets retain long values without a clamped slider',
      (tester) async {
    await openSettings(tester);
    for (final seconds in [10, 15, 30, 60, 300, 600]) {
      final preset = find.byKey(ValueKey('settings-duration-$seconds'));
      await tester.tap(preset);
      await tester.pumpAndSettle();
      expect(settings.intervalSeconds, seconds);
      expect(tester.widget<ChoiceChip>(preset).selected, isTrue);
      expect(find.text('$seconds s'), findsNWidgets(2));
      if (seconds <= 60) {
        final slider = tester.widget<Slider>(find.byType(Slider));
        expect(slider.value, seconds.toDouble());
        expect(slider.min, 3);
        expect(slider.max, 60);
      } else {
        expect(find.byType(Slider), findsNothing);
      }
    }
    expect(changes, 6);
    await selectCategory(tester, 'about');
    await selectCategory(tester, 'slideshow');
    expect(settings.intervalSeconds, 600);
    expect(find.byType(Slider), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settings-duration-15')));
    await tester.pumpAndSettle();
    tester.widget<Slider>(find.byType(Slider)).onChanged!(3);
    await tester.pumpAndSettle();
    expect(settings.intervalSeconds, 3);
  });

  testWidgets('title stays fixed while content scrolls and categories reset it',
      (tester) async {
    await openSettings(tester, panelSize: const Size(900, 380));
    await selectCategory(tester, 'appearance');
    final closePosition = tester.getTopLeft(close);
    await tester.drag(content, const Offset(0, -400));
    await tester.pumpAndSettle();
    final scrollView = tester.widget<SingleChildScrollView>(content);
    expect(scrollView.controller!.offset, greaterThan(0));
    expect(tester.getTopLeft(close), closePosition);
    await selectCategory(tester, 'slideshow');
    expect(scrollView.controller!.offset, 0);
    expect(find.text('Slide duration').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final locale in [const Locale('en'), const Locale('zh')]) {
    testWidgets('narrow ${locale.languageCode} panel wraps without overflow',
        (tester) async {
      await openSettings(
        tester,
        screenSize: const Size(320, 640),
        locale: locale,
        textScale: 1.4,
      );
      expect(find.byKey(const ValueKey('settings-sidebar')), findsNothing);
      expect(find.byKey(const ValueKey('settings-horizontal-categories')),
          findsOneWidget);
      expect(tester.getTopLeft(category('slideshow')).dy,
          lessThan(tester.getTopLeft(content).dy));
      for (final name in [
        'appearance',
        'system',
        'storage',
        'about',
        'slideshow'
      ]) {
        await selectCategory(tester, name);
        expect(tester.takeException(), isNull, reason: '$name should fit');
        await tester.drag(content, const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$name should scroll');
        expect(close.hitTestable(), findsOneWidget);
      }
      await selectCategory(tester, 'appearance');
      final s = AppStrings(locale);
      expect(mediaDateSwitch(tester, s).value, isTrue);
      await tester.tap(find.text(s.showMediaDate));
      await tester.pumpAndSettle();
      expect(settings.showMediaDate, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [699.0, 700.0]) {
    testWidgets('category breakpoint uses panel width $width', (tester) async {
      await openSettings(tester, panelSize: Size(width, 640));
      expect(find.byKey(const ValueKey('settings-sidebar')),
          width >= 700 ? findsOneWidget : findsNothing);
      expect(find.byKey(const ValueKey('settings-horizontal-categories')),
          width < 700 ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('about shows loading until the native version resolves',
      (tester) async {
    final version = Completer<String>();
    messenger.setMockMethodCallHandler(deviceChannel, (_) => version.future);
    await openSettings(tester);
    await selectCategory(tester, 'about');
    expect(find.text('Loading…'), findsOneWidget);
    version.complete('0.3.1+42');
    await tester.pumpAndSettle();
    expect(find.text('Loading…'), findsNothing);
    expect(find.text('0.3.1+42'), findsOneWidget);
  });

  testWidgets('about shows a dash when the native version is unavailable',
      (tester) async {
    messenger.setMockMethodCallHandler(deviceChannel, (_) async {
      throw PlatformException(code: 'unavailable');
    });
    await openSettings(tester);
    await selectCategory(tester, 'about');
    expect(find.text('—'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
