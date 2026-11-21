import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearthframe/l10n.dart';
import 'package:hearthframe/media_view.dart';
import 'package:hearthframe/settings.dart';
import 'package:hearthframe/slideshow_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  const screenChannel = MethodChannel('hearthframe/screen');
  const metadataChannel = MethodChannel('hearthframe/metadata');
  const wakelockChannel =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
  late Directory root;
  late FrameSettings settings;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hf_order_test');
    final photos = await Directory('${root.path}/photos').create();
    final sub = await Directory('${photos.path}/sub').create();
    final pixel = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAACXBIWXMAAAABAAAAAQBPJcTWAAAAEUlEQVR4nGNkqGcAAhYGMAAABiwAhQHKmNgAAAAASUVORK5CYII=');
    for (final name in [
      '${photos.path}/a.png',
      '${sub.path}/b.png',
      '${sub.path}/c.png'
    ]) {
      await File(name).writeAsBytes(pixel);
    }
    SharedPreferences.setMockInitialValues({
      'source_folder': photos.path,
      'shuffle': false,
      'seen_hint': true,
      'show_clock': false,
      'motion_effect': false,
      'show_media_date': false,
    });
    settings = await FrameSettings.load();
    messenger.setMockMethodCallHandler(pathChannel, (_) async => root.path);
    messenger.setMockMethodCallHandler(screenChannel, (_) async => null);
    messenger.setMockMethodCallHandler(metadataChannel, (_) async => null);
    messenger.setMockMessageHandler(wakelockChannel,
        (_) async => const StandardMessageCodec().encodeMessage([null]));
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(pathChannel, null);
    messenger.setMockMethodCallHandler(screenChannel, null);
    messenger.setMockMethodCallHandler(metadataChannel, null);
    messenger.setMockMessageHandler(wakelockChannel, null);
    settings.dispose();
    await root.delete(recursive: true);
  });

  Future<void> flush(WidgetTester tester) async {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump(const Duration(milliseconds: 700));
  }

  testWidgets(
      'sorting changes keep the visible media and affect the next slide',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [
        AppStrings.delegate,
        ...GlobalMaterialLocalizations.delegates
      ],
      home: SlideshowScreen(settings: settings),
    ));
    var scanned = false;
    for (var i = 0; i < 30 && !scanned; i++) {
      await flush(tester);
      scanned = root.listSync().whereType<File>().any((file) =>
          file.path.contains('media_index_') &&
          file.lengthSync() > 0 &&
          (jsonDecode(file.readAsStringSync()) as List).length == 3);
    }
    expect(scanned, isTrue);
    expect(find.byType(MediaView), findsWidgets);
    var current = tester.widget<MediaView>(find.byType(MediaView).last);
    expect(current.item.path, endsWith('/a.png'));
    final key = current.key;
    await settings.setShuffle(true);
    await tester.pump();
    await settings.setRecentWeighted(false);
    await tester.pump();
    expect(tester.widget<MediaView>(find.byType(MediaView).last).key, key);
    await settings.setShuffle(false);
    await tester.pump();
    await tester.tapAt(const Offset(400, 200));
    await tester.pump();
    await tester.tap(find.byTooltip('Next'));
    await flush(tester);
    current = tester.widget<MediaView>(find.byType(MediaView).last);
    expect(current.item.path, endsWith('/sub/b.png'));
    await tester.pumpWidget(const SizedBox.shrink());
    await flush(tester);
    expect(tester.takeException(), isNull);
  });
}
