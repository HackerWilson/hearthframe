import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearthframe/l10n.dart';
import 'package:hearthframe/media_details.dart';
import 'package:hearthframe/sources.dart';
import 'package:hearthframe/theme.dart';

class _Stat extends Fake implements FileStat {
  _Stat(this.size);

  @override
  final int size;

  @override
  FileSystemEntityType get type => FileSystemEntityType.file;

  @override
  DateTime get modified => DateTime(2026, 11, 19);
}

Widget _frame(MediaItem item, {String language = 'en'}) => MaterialApp(
      theme: buildHearthTheme(),
      locale: Locale(language),
      supportedLocales: const [Locale('en'), Locale('zh')],
      localizationsDelegates: const [
        AppStrings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: Scaffold(
        body: MediaDetailsSheet(item: item, sourceLabel: 'WebDAV'),
      ),
    );

String _value(WidgetTester tester, String key) =>
    tester.widget<SelectableText>(find.byKey(ValueKey(key))).data!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const metadata = MethodChannel('hearthframe/metadata');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(metadata, (_) async => null);
  });
  tearDown(() => messenger.setMockMethodCallHandler(metadata, null));

  for (final language in ['en', 'zh']) {
    testWidgets('details and capture date are localized in $language',
        (tester) async {
      var reads = 0;
      messenger.setMockMethodCallHandler(metadata, (call) async {
        reads++;
        expect(call.method, 'captureDate');
        expect(call.arguments['isVideo'], isTrue);
        return '2025:03:04 12:00:00';
      });
      const item = MediaItem('/tmp/hearthframe_cache/video.mp4',
          originalPath: '/photo/2020-01-01/family.mp4',
          isVideo: true,
          size: 1048576);
      await tester.pumpWidget(_frame(item, language: language));
      await tester.pump();
      final s = AppStrings(Locale(language));
      expect(find.text(s.mediaDetails), findsOneWidget);
      expect(find.text(s.originalFilename), findsOneWidget);
      expect(find.text(s.sourceType), findsOneWidget);
      expect(find.text(s.originalFilePath), findsOneWidget);
      expect(find.text(s.fileSize), findsOneWidget);
      expect(find.text(s.mediaDateSources), findsOneWidget);
      expect(_value(tester, 'details-filename'), 'family.mp4');
      expect(_value(tester, 'details-type'), s.video);
      expect(_value(tester, 'details-source'), 'WebDAV');
      expect(_value(tester, 'details-size'), '1.0 MB');
      expect(_value(tester, 'details-date'),
          contains(language == 'zh' ? '2025年3月4日' : 'March 4, 2025'));
      expect(reads, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'remote details remove credentials, query, fragment and cache path',
      (tester) async {
    const item = MediaItem('/tmp/hearthframe_cache/2026-11-19-secret-cache.jpg',
        originalPath:
            'https://username:password@nas.local:5006/photo/family%20photo.jpg?token=secret#credential',
        size: 2048);
    await tester.pumpWidget(_frame(item));
    await tester.pump();
    expect(_value(tester, 'details-filename'), 'family photo.jpg');
    expect(_value(tester, 'details-path'),
        'https://nas.local:5006/photo/family%20photo.jpg');
    expect(_value(tester, 'details-date'), 'Unknown');
    expect(_value(tester, 'details-type'), 'Photo');
    for (final text
        in tester.widgetList<SelectableText>(find.byType(SelectableText))) {
      expect(text.data, isNot(contains('hearthframe_cache')));
      expect(text.data, isNot(contains('username')));
      expect(text.data, isNot(contains('password')));
      expect(text.data, isNot(contains('secret')));
      expect(text.data, isNot(contains('credential')));
    }
    expect(find.text(const AppStrings(Locale('en')).mediaDateSources),
        findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cache locations without an original are never displayed',
      (tester) async {
    await tester.pumpWidget(_frame(const MediaItem(
        '/tmp/hearthframe_cache/2026-11-19/opaque.jpg',
        size: 0)));
    await tester.pump();
    expect(_value(tester, 'details-path'), 'Unknown');
    expect(_value(tester, 'details-filename'), 'Unknown');
    expect(_value(tester, 'details-date'), 'Unknown');
    expect(_value(tester, 'details-size'), '0 B');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unknown date stays unknown even when local stat has an mtime',
      (tester) async {
    final paths = <String>[];
    await IOOverrides.runZoned(() async {
      await tester.pumpWidget(_frame(const MediaItem('/photo/unknown.jpg')));
      await tester.pump();
      expect(_value(tester, 'details-date'), 'Unknown');
      expect(_value(tester, 'details-size'), '3.0 KB');
      expect(_value(tester, 'details-path'), '/photo/unknown.jpg');
      expect(paths, ['/photo/unknown.jpg']);
      await tester.pumpWidget(const SizedBox.shrink());
    }, stat: (path) async {
      paths.add(path);
      return _Stat(3072);
    });
  });

  testWidgets('source date fallback is explained without claiming capture time',
      (tester) async {
    const item = MediaItem('/tmp/hearthframe_cache/x.jpg',
        originalPath: '/photo/2024-09-02/family.jpg', size: 100);
    await tester.pumpWidget(_frame(item));
    await tester.pump();
    expect(_value(tester, 'details-date'), contains('September 2, 2024'));
    expect(find.text(const AppStrings(Locale('en')).mediaDateSources),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('source mtime, not cache mtime, is the final date fallback',
      (tester) async {
    final item = MediaItem('/tmp/hearthframe_cache/x.jpg',
        originalPath: '/photo/family.jpg',
        mtime: DateTime(2023, 4, 5).millisecondsSinceEpoch,
        size: 100);
    await tester.pumpWidget(_frame(item));
    await tester.pump();
    expect(_value(tester, 'details-date'), contains('April 5, 2023'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unavailable size is unknown; does not stat a network URL',
      (tester) async {
    var stats = 0;
    await IOOverrides.runZoned(() async {
      await tester
          .pumpWidget(_frame(const MediaItem('https://nas.local/a.jpg')));
      await tester.pump();
      expect(_value(tester, 'details-size'), 'Unknown');
      expect(stats, 0);
      await tester.pumpWidget(_frame(const MediaItem('/photo/missing.jpg')));
      await tester.pump();
      expect(_value(tester, 'details-size'), 'Unknown');
      expect(stats, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    }, stat: (_) async {
      stats++;
      throw const FileSystemException('not found');
    });
  });

  testWidgets('loading date and size can finish safely after disposal',
      (tester) async {
    final date = Completer<String?>();
    final stat = Completer<FileStat>();
    messenger.setMockMethodCallHandler(metadata, (_) => date.future);
    await IOOverrides.runZoned(() async {
      await tester.pumpWidget(_frame(const MediaItem('/photo/unknown.jpg')));
      expect(_value(tester, 'details-date'), 'Loading…');
      expect(_value(tester, 'details-size'), 'Loading…');
      await tester.pumpWidget(const SizedBox.shrink());
      date.complete('2025:03:04 12:00:00');
      stat.complete(_Stat(10));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }, stat: (_) => stat.future);
  });

  testWidgets('late metadata cannot overwrite a replacement item',
      (tester) async {
    final first = Completer<String?>();
    messenger.setMockMethodCallHandler(metadata, (call) {
      if (call.arguments['path'] == '/photo/first.jpg') return first.future;
      return Future.value('2026:11:18 10:00:00');
    });
    await tester
        .pumpWidget(_frame(const MediaItem('/photo/first.jpg', size: 20)));
    await tester
        .pumpWidget(_frame(const MediaItem('/photo/second.jpg', size: 30)));
    first.complete('2025:03:04 12:00:00');
    await tester.pump();
    expect(_value(tester, 'details-date'), contains('November 18, 2026'));
    expect(_value(tester, 'details-filename'), 'second.jpg');
    expect(_value(tester, 'details-size'), '30 B');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('320px dialog scrolls long paths and closes without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: buildHearthTheme(),
      localizationsDelegates: const [AppStrings.delegate],
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const MediaDetailsSheet(
                              item: MediaItem(
                                  '/photo/very-long-unbroken-file-name-with-many-characters-to-wrap-at-narrow-width.jpg',
                                  size: 10),
                              sourceLabel: 'WebDAV',
                            )),
                    child: const Text('Open'),
                  ))),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byType(AlertDialog));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(320));
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(MediaDetailsSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
