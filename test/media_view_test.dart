import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearthframe/media_view.dart';
import 'package:hearthframe/sources.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const metadata = MethodChannel('hearthframe/metadata');
  tearDown(() => messenger.setMockMethodCallHandler(metadata, null));

  Widget frame(
          {bool showDate = true,
          bool controls = false,
          String path = '/photo/2026-09-02/a.heic'}) =>
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: MediaView(
            key: ValueKey(path),
            item: MediaItem(path),
            paused: true,
            fill: true,
            motion: false,
            motionSpeed: 1,
            muted: true,
            showDate: showDate,
            controlsVisible: controls,
            onCompleted: () {},
          ),
        ),
      );

  testWidgets(
      'date uses capture metadata, moves above controls, and toggles live',
      (tester) async {
    messenger.setMockMethodCallHandler(
        metadata, (_) async => '2025:03:04 12:00:00');
    await tester.pumpWidget(frame());
    await tester.pump();
    final date = find.byKey(const ValueKey('media-date'));
    expect(date, findsOneWidget);
    expect(tester.widget<Text>(date).data, contains('2025年3月4日'));
    final bottom = tester.getTopLeft(date).dy;

    await tester.pumpWidget(frame(controls: true));
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.getTopLeft(date).dy, lessThan(bottom));

    await tester.pumpWidget(frame(showDate: false));
    expect(date, findsNothing);
    await tester.pumpWidget(frame());
    expect(date, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('photo date remains readable at 320px without video progress',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    messenger.setMockMethodCallHandler(
        metadata, (_) async => '2025:03:04 12:00:00');
    await tester.pumpWidget(frame(controls: true));
    await tester.pump();
    final date = find.byKey(const ValueKey('media-date'));
    expect(date, findsOneWidget);
    expect(find.byKey(const ValueKey('video-progress')), findsNothing);
    expect(find.byType(Slider), findsNothing);
    final bounds = tester.getRect(date);
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(320));
    expect(bounds.bottom, lessThanOrEqualTo(640 - 112));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late metadata from previous slide cannot label the next slide',
      (tester) async {
    final first = Completer<String?>();
    messenger.setMockMethodCallHandler(metadata, (call) {
      if ((call.arguments['path'] as String).endsWith('a.heic')) {
        return first.future;
      }
      return Future.value('2026:11:18 10:00:00');
    });
    await tester.pumpWidget(frame());
    await tester.pumpWidget(frame(path: '/photo/b.heic'));
    await tester.pump();
    first.complete('2025:03:04 12:00:00');
    await tester.pump();
    final label =
        tester.widget<Text>(find.byKey(const ValueKey('media-date'))).data!;
    expect(label, contains('2026年11月18日'));
    expect(label, isNot(contains('2025')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unknown dates stay hidden and disabling skips metadata work',
      (tester) async {
    var reads = 0;
    messenger.setMockMethodCallHandler(metadata, (_) async {
      reads++;
      return null;
    });
    await tester
        .pumpWidget(frame(showDate: false, path: '/photo/unknown.heic'));
    await tester.pump();
    expect(reads, 0);
    await tester.pumpWidget(frame(path: '/photo/unknown.heic'));
    await tester.pump();
    expect(reads, 1);
    expect(find.byKey(const ValueKey('media-date')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
