import 'dart:async';
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

// Exercise the real WebDAV client, not Flutter's default HTTP 400 stub.
class _NetworkTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

// Pump frames without advancing slideshow timers; let real socket/file/decoder
// work run outside fakeAsync. A stalled download must fail rather than hang.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final watch = Stopwatch()..start();
  while (true) {
    await tester.pump();
    if (condition()) return;
    if (watch.elapsed >= timeout) {
      fail(reason);
    }
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
}

String _listing(Map<String, int> files) => '''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/photo/</d:href>
    <d:propstat>
      <d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  ${files.entries.map((file) => '''
  <d:response>
    <d:href>/photo/${file.key}</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype/>
        <d:getcontenttype>image/png</d:getcontenttype>
        <d:getcontentlength>${file.value}</d:getcontentlength>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>''').join()}
</d:multistatus>
''';

void main() {
  _NetworkTestBinding();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  const screenChannel = MethodChannel('hearthframe/screen');
  const metadataChannel = MethodChannel('hearthframe/metadata');
  const wakelockChannel =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
  final pixel = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAACXBIWXMAAAABAAAAAQBPJcTWAAAAEUlEQVR4nGNkqGcAAhYGMAAABiwAhQHKmNgAAAAASUVORK5CYII=');
  late Directory root;
  late HttpServer server;
  late StreamSubscription<HttpRequest> subscription;
  late FrameSettings settings;
  late Map<String, int> files;
  late List<String> gets;
  late List<String> propfinds;
  late List<Future<void>> handlers;
  late int completedHandlers;
  late List<Completer<void>> releases;
  late Future<void> Function(HttpRequest) serveGet;

  Completer<void> gate() {
    final release = Completer<void>();
    releases.add(release);
    return release;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hf_slideshow_network_test');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    files = {'a.png': pixel.length, 'b.png': pixel.length};
    gets = [];
    propfinds = [];
    handlers = [];
    completedHandlers = 0;
    releases = [];
    serveGet = (request) async {
      request.response.statusCode = HttpStatus.serviceUnavailable;
    };
    subscription = server.listen((request) {
      handlers.add(() async {
        try {
          await request.drain<void>();
          if (request.method == 'PROPFIND') {
            propfinds.add(request.uri.path);
            request.response.statusCode = HttpStatus.multiStatus;
            request.response.headers.contentType =
                ContentType('application', 'xml', charset: 'utf-8');
            request.response.write(_listing(files));
          } else if (request.method == 'GET') {
            gets.add(request.uri.path);
            await serveGet(request);
          } else if (request.method == 'OPTIONS') {
            request.response.headers.set('dav', '1');
            request.response.headers.set('allow', 'OPTIONS, PROPFIND, GET');
          } else {
            request.response.statusCode = HttpStatus.methodNotAllowed;
          }
          await request.response.close();
        } on SocketException {
          // Skip/disposal may abort a still-streaming response.
        } on HttpException {
          // The cancelled client need not consume the rest of the response.
        } finally {
          completedHandlers++;
        }
      }());
    });
    SharedPreferences.setMockInitialValues({
      'source_type': 'webdav',
      'webdav_url': 'http://127.0.0.1:${server.port}',
      'webdav_path': '/photo',
      'shuffle': false,
      'interval_seconds': 1,
      'transition_ms': 0,
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
    for (final release in releases) {
      if (!release.isCompleted) release.complete();
    }
    await server.close(force: true);
    await subscription.cancel();
    await Future.wait(handlers).timeout(const Duration(seconds: 5));
    messenger.setMockMethodCallHandler(pathChannel, null);
    messenger.setMockMethodCallHandler(screenChannel, null);
    messenger.setMockMethodCallHandler(metadataChannel, null);
    messenger.setMockMessageHandler(wakelockChannel, null);
    settings.dispose();
    await root.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester) async {
    // Start IO in the real zone too: merely yielding from fakeAsync does not
    // unblock all of Dio's socket setup. Timers started here use real time.
    await tester.runAsync(() => tester.pumpWidget(MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppStrings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: SlideshowScreen(settings: settings),
        )));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Gates created in fakeAsync must be released while we can still pump its
    // microtasks; waiting until tearDown strands the server's awaiting handlers.
    for (final release in releases) {
      if (!release.isCompleted) release.complete();
    }
    // Cancellation settles before asynchronous writer cleanup. Keep mocks and
    // the temporary directory alive until that cleanup has removed every part.
    await _pumpUntil(tester, () {
      final cache = Directory('${root.path}/hearthframe_cache');
      return completedHandlers == handlers.length &&
          (!cache.existsSync() ||
              cache.listSync().every((file) => !file.path.endsWith('.part')));
    }, reason: 'Cancelled downloads or server handlers did not finish cleanup');
    expect(tester.takeException(), isNull);
  }

  testWidgets('all failed GETs stop after one round and show Retry',
      (tester) async {
    try {
      await mount(tester);
      await _pumpUntil(tester, () => find.text('Retry').evaluate().isNotEmpty,
          reason: 'All failed downloads should end at the Retry panel');
      expect(propfinds, ['/photo/']);
      expect(gets, ['/photo/a.png', '/photo/b.png']);
      expect(find.text('Could not load this source.'), findsOneWidget);
      expect(find.byType(MediaView), findsNothing);
      expect(find.text('Skip'), findsNothing);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull);

      // Cross several complete slideshow intervals in BOTH clocks: mounting
      // in runAsync starts real timers, so fake-time-only pumps are not enough.
      for (var tick = 0; tick < 3; tick++) {
        await tester.pump(const Duration(milliseconds: 1100));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1100)));
        await tester.pump();
        expect(gets, ['/photo/a.png', '/photo/b.png']);
        expect(find.text('Retry'), findsOneWidget);
      }

      // Settings changes also call _restartTimer: errors must keep it stopped.
      await tester.runAsync(() => settings.setIntervalSeconds(1));
      await tester.pump(const Duration(milliseconds: 2100));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2100)));
      await tester.pump();
      expect(gets, ['/photo/a.png', '/photo/b.png']);
      expect(find.text('Could not load this source.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    } finally {
      await unmount(tester);
    }
  });

  testWidgets(
      'slow GET shows progress and Skip displays the next image immediately',
      (tester) async {
    final nextChunk = gate();
    final finishSlowGet = gate();
    files['a.png'] = 16384;
    serveGet = (request) async {
      request.response.headers.contentType = ContentType('image', 'png');
      if (request.uri.path == '/photo/a.png') {
        request.response.bufferOutput = false;
        request.response.contentLength = 16384;
        request.response.add(List.filled(4096, 1));
        await request.response.flush();
        await nextChunk.future;
        request.response.add(List.filled(4096, 2));
        await request.response.flush();
        await finishSlowGet.future;
        request.response.add(List.filled(8192, 3));
      } else {
        request.response.contentLength = pixel.length;
        request.response.add(pixel);
      }
    };
    try {
      await mount(tester);
      await _pumpUntil(tester, () => gets.contains('/photo/a.png'),
          reason: 'The first image GET should start');
      await tester.pump(const Duration(milliseconds: 350));
      await _pumpUntil(tester,
          () => find.text('4.00 KB / 16.0 KB · 25%').evaluate().isNotEmpty,
          reason: 'The download panel should show received bytes and total');
      expect(find.text('Loading media'), findsOneWidget);
      expect(find.text('a.png'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(
          tester
              .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator))
              .value,
          0.25);
      expect(find.byType(MediaView), findsNothing);

      nextChunk.complete();
      await _pumpUntil(tester,
          () => find.text('8.00 KB / 16.0 KB · 50%').evaluate().isNotEmpty,
          reason: 'The visible progress should update while GET is blocked');
      expect(
          tester
              .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator))
              .value,
          0.5);
      expect(gets, ['/photo/a.png']);

      await tester.runAsync(() => tester.tap(find.text('Skip')));
      final decodedImage = find.descendant(
        of: find.byType(MediaView),
        matching: find.byWidgetPredicate(
            (widget) => widget is RawImage && widget.image != null),
      );
      await _pumpUntil(tester, () => decodedImage.evaluate().isNotEmpty,
          reason: 'Skip must render b.png without releasing the slow a.png GET',
          timeout: const Duration(seconds: 2));
      final current = tester.widget<MediaView>(find.byType(MediaView));
      expect(current.item.originalPath, '/photo/b.png');
      expect(current.item.path, endsWith('_b.png'));
      expect(await tester.runAsync(() => File(current.item.path).readAsBytes()),
          pixel);
      expect(gets.where((path) => path == '/photo/b.png'), hasLength(1));
      // A may be prefetched again after B is displayed; neither request needs
      // its server gate released for Skip to complete.
      expect(finishSlowGet.isCompleted, isFalse);
      expect(find.text('Loading media'), findsNothing);
      expect(find.text('Skip'), findsNothing);
      expect(find.byIcon(Icons.broken_image), findsNothing);
    } finally {
      await unmount(tester);
    }
  });
}
