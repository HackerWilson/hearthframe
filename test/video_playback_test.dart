import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearthframe/l10n.dart';
import 'package:hearthframe/media_view.dart';
import 'package:hearthframe/sources.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

const _path = '/smb/cache/2026-11-18/video.mp4';
const _duration = Duration(seconds: 10);

class _FakeVideoPlatform extends VideoPlayerPlatform {
  final events = <int, StreamController<VideoEvent>>{};
  final sources = <DataSource>[];
  final disposed = <int>[];
  final plays = <int>[];
  final pauses = <int>[];
  final volumes = <int, double>{};
  final positions = <int, Duration>{};
  final seeks = <Duration>[];
  Completer<void>? mutedVolumeGate;
  Completer<void>? seekGate;
  bool completeDuringSeek = false;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = sources.length;
    sources.add(options.dataSource);
    // Complete cancellation inside the widget test's fake-async zone.
    events[id] = StreamController<VideoEvent>(onCancel: () async {});
    return id;
  }

  void initialize([int id = 0]) => events[id]!.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: _duration,
        size: const Size(1920, 1080),
      ));

  void complete([int id = 0]) =>
      events[id]!.add(VideoEvent(eventType: VideoEventType.completed));

  void fail([int id = 0]) => events[id]!.addError(
        PlatformException(code: 'video_error', message: 'SMB decoder failed'),
      );

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async => disposed.add(playerId);

  @override
  Future<void> play(int playerId) async => plays.add(playerId);

  @override
  Future<void> pause(int playerId) async => pauses.add(playerId);

  @override
  Future<void> setVolume(int playerId, double volume) async {
    volumes[playerId] = volume;
    if (volume == 0) await mutedVolumeGate?.future;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    positions[playerId] = position;
    seeks.add(position);
    if (completeDuringSeek && position < _duration) complete(playerId);
    await seekGate?.future;
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      SizedBox(key: ValueKey('video-${options.playerId}'));

  Future<void> close() async {
    for (final stream in events.values) {
      await stream.close();
    }
  }
}

Widget _frame({
  bool paused = false,
  bool muted = true,
  bool showDate = false,
  bool controls = false,
  bool fill = true,
  Key displayKey = const ValueKey('display'),
  VoidCallback? onCompleted,
  VoidCallback? onParentTap,
  GestureDragEndCallback? onParentDrag,
  ValueChanged<bool>? onInteractionChanged,
}) =>
    MaterialApp(
      localizationsDelegates: const [AppStrings.delegate],
      home: Scaffold(
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onParentTap,
          onHorizontalDragEnd: onParentDrag,
          child: MediaView(
            key: displayKey,
            item: const MediaItem(_path, isVideo: true),
            paused: paused,
            fill: fill,
            motion: false,
            motionSpeed: 1,
            muted: muted,
            showDate: showDate,
            controlsVisible: controls,
            onInteractionChanged: onInteractionChanged,
            onCompleted: onCompleted ?? () {},
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeVideoPlatform platform;
  late VideoPlayerPlatform originalPlatform;
  const metadata = MethodChannel('hearthframe/metadata');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    originalPlatform = VideoPlayerPlatform.instance;
    platform = _FakeVideoPlatform();
    VideoPlayerPlatform.instance = platform;
    messenger.setMockMethodCallHandler(
        metadata, (_) async => '2025:03:04 12:00:00');
  });

  tearDown(() async {
    await platform.close();
    VideoPlayerPlatform.instance = originalPlatform;
    messenger.setMockMethodCallHandler(metadata, null);
  });

  Future<void> remove(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  final slider = find.byKey(const ValueKey('video-seek'));

  Future<TestGesture> startScrub(WidgetTester tester,
      {PointerDeviceKind kind = PointerDeviceKind.touch}) async {
    final rect = tester.getRect(slider);
    final gesture = await tester
        .startGesture(Offset(rect.left + 24, rect.center.dy), kind: kind);
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump();
    return gesture;
  }

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('$kind drag pauses, previews, seeks once, and resumes',
        (tester) async {
      var parentTaps = 0;
      var parentDrags = 0;
      final interactions = <bool>[];
      await tester.pumpWidget(_frame(
        controls: true,
        onParentTap: () => parentTaps++,
        onParentDrag: (_) => parentDrags++,
        onInteractionChanged: interactions.add,
      ));
      expect(slider, findsNothing);
      platform.initialize();
      await tester.pump();
      final controller =
          tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller;
      final gesture = await startScrub(tester, kind: kind);
      expect(controller.value.isPlaying, isFalse);
      expect(platform.seeks, isEmpty);
      expect(interactions.last, isTrue);
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      final preview = tester.widget<Slider>(slider).value.round();
      expect(preview, greaterThan(0));
      expect(platform.seeks, isEmpty);
      await gesture.up();
      await tester.pump();
      expect(platform.seeks, [Duration(milliseconds: preview)]);
      expect(controller.value.position, Duration(milliseconds: preview));
      expect(controller.value.isPlaying, isTrue);
      expect(platform.plays, [0, 0]);
      expect(platform.volumes[0], 0);
      await gesture.removePointer();
      await tester.pump();
      expect(interactions.last, isFalse);
      expect(parentTaps, 0);
      expect(parentDrags, 0);
      await remove(tester);
    });
  }

  for (final pausedBefore in [false, true]) {
    testWidgets('paused=true at release never resumes; before=$pausedBefore',
        (tester) async {
      await tester.pumpWidget(_frame(controls: true, paused: pausedBefore));
      platform.initialize();
      await tester.pump();
      final gesture = await startScrub(tester);
      final playCount = platform.plays.length;
      await tester.pumpWidget(_frame(controls: true, paused: true));
      await gesture.up();
      await tester.pump();
      expect(platform.seeks, hasLength(1));
      expect(platform.plays, hasLength(playCount));
      expect(
          tester
              .widget<VideoPlayer>(find.byType(VideoPlayer))
              .controller
              .value
              .isPlaying,
          isFalse);
      await remove(tester);
    });
  }

  testWidgets('drag preserves an already stopped controller', (tester) async {
    await tester.pumpWidget(_frame(controls: true));
    platform.initialize();
    await tester.pump();
    final controller =
        tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller;
    await controller.pause();
    final gesture = await startScrub(tester);
    await gesture.up();
    await tester.pump();
    expect(controller.value.isPlaying, isFalse);
    await tester.pumpWidget(_frame(controls: true, muted: false));
    expect(platform.plays, [0]);
    await remove(tester);
  });

  testWidgets('unpausing while dragging waits for release', (tester) async {
    await tester.pumpWidget(_frame(controls: true));
    platform.initialize();
    await tester.pump();
    final gesture = await startScrub(tester);
    await tester.pumpWidget(_frame(controls: true, paused: true));
    await tester.pumpWidget(_frame(controls: true));
    expect(platform.plays, [0]);
    await gesture.up();
    await tester.pump();
    expect(platform.plays, [0, 0]);
    await remove(tester);
  });

  testWidgets('seeking to the end does not complete or rewind the video',
      (tester) async {
    var completions = 0;
    await tester
        .pumpWidget(_frame(controls: true, onCompleted: () => completions++));
    platform.initialize();
    await tester.pump();
    final gesture = await startScrub(tester);
    final rect = tester.getRect(slider);
    await gesture.moveTo(Offset(rect.right, rect.center.dy));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(completions, 0);
    expect(platform.seeks.single, const Duration(milliseconds: 9999));
    expect(platform.plays, [0, 0]);
    // A later natural completion still advances exactly once.
    platform.complete();
    await tester.idle();
    await tester.pump();
    await tester.pump();
    expect(completions, 1);
    await remove(tester);
  });

  testWidgets('seek completion events cannot advance while a seek is pending',
      (tester) async {
    var completions = 0;
    await tester.pumpWidget(
        _frame(controls: true, paused: true, onCompleted: () => completions++));
    platform.initialize();
    await tester.pump();
    platform.seekGate = Completer<void>();
    platform.completeDuringSeek = true;
    final gesture = await startScrub(tester);
    await gesture.up();
    await tester.pump();
    expect(completions, 0);
    await tester
        .pumpWidget(_frame(controls: true, onCompleted: () => completions++));
    expect(platform.plays, isEmpty);
    platform.seekGate!.complete();
    await tester.pump();
    await tester.pumpWidget(
        _frame(controls: true, muted: false, onCompleted: () => completions++));
    await tester.pump();
    expect(completions, 0);
    expect(platform.plays, isEmpty);
    await remove(tester);
  });

  testWidgets('pending seek holds interaction; hiding releases it safely',
      (tester) async {
    final interactions = <bool>[];
    await tester.pumpWidget(
        _frame(controls: true, onInteractionChanged: interactions.add));
    platform.initialize();
    await tester.pump();
    platform.seekGate = Completer<void>();
    final gesture = await startScrub(tester);
    await gesture.up();
    await tester.pump();
    expect(interactions, [true]);
    expect(platform.plays, [0]);
    await tester.pumpWidget(_frame(onInteractionChanged: interactions.add));
    expect(interactions, [true, false]);
    platform.seekGate!.complete();
    await tester.pump();
    expect(platform.plays, [0, 0]);
    expect(platform.seeks, hasLength(1));
    expect(interactions, [true, false]);
    await remove(tester);
  });

  testWidgets('progress taps do not toggle the parent controls',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(_frame(controls: true, onParentTap: () => taps++));
    platform.initialize();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('video-elapsed')));
    await tester.tap(slider);
    await tester.pump();
    expect(taps, 0);
    expect(platform.seeks, hasLength(1));
    await remove(tester);
  });

  testWidgets('pause during pending seek wins over drag resume',
      (tester) async {
    await tester.pumpWidget(_frame(controls: true));
    platform.initialize();
    await tester.pump();
    platform.seekGate = Completer<void>();
    final gesture = await startScrub(tester);
    await gesture.up();
    await tester.pump();
    await tester.pumpWidget(_frame(controls: true, paused: true));
    platform.seekGate!.complete();
    await tester.pump();
    expect(platform.plays, [0]);
    await remove(tester);
  });

  testWidgets('hidden controls cancel drag, release hover, and remove focus',
      (tester) async {
    final interactions = <bool>[];
    Widget frame(bool controls) =>
        _frame(controls: controls, onInteractionChanged: interactions.add);
    await tester.pumpWidget(frame(true));
    platform.initialize();
    await tester.pump();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(slider));
    await tester.pump();
    expect(interactions, [true]);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(interactions, [true, false]);
    final gesture = await startScrub(tester);
    final focus = tester
        .widget<FocusableActionDetector>(find.descendant(
          of: slider,
          matching: find.byType(FocusableActionDetector),
        ))
        .focusNode!;
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester.pumpWidget(frame(false));
    await tester.pump();
    expect(slider, findsNothing);
    expect(find.byKey(const ValueKey('video-progress')), findsNothing);
    expect(interactions.last, isFalse);
    expect(focus.context?.mounted ?? false, isFalse);
    expect(FocusManager.instance.primaryFocus, isNot(same(focus)));
    await gesture.up();
    await mouse.removePointer();
    await tester.pump();
    expect(platform.seeks, isEmpty);
    expect(platform.plays, [0, 0]);
    await remove(tester);
  });

  testWidgets('pointer cancellation restores playback without seeking',
      (tester) async {
    final interactions = <bool>[];
    await tester.pumpWidget(
        _frame(controls: true, onInteractionChanged: interactions.add));
    platform.initialize();
    await tester.pump();
    final gesture = await startScrub(tester);
    await gesture.cancel();
    await tester.pump();
    expect(platform.seeks, isEmpty);
    expect(platform.plays, [0, 0]);
    expect(interactions, [true, false]);
    await remove(tester);
  });

  testWidgets('old pending seek cannot resume or notify the next display',
      (tester) async {
    final interactions = <bool>[];
    var completions = 0;
    await tester.pumpWidget(_frame(
        controls: true,
        onInteractionChanged: interactions.add,
        onCompleted: () => completions++));
    platform.initialize();
    await tester.pump();
    platform.seekGate = Completer<void>();
    final gesture = await startScrub(tester);
    await gesture.up();
    await tester.pump();
    await tester.pumpWidget(
        _frame(controls: true, displayKey: const ValueKey('next-display')));
    platform.initialize(1);
    await tester.pump();
    final notifications = List<bool>.of(interactions);
    platform.seekGate!.complete();
    await tester.pump();
    expect(platform.plays, [0, 1]);
    expect(interactions, notifications);
    expect(completions, 0);
    await remove(tester);
  });

  testWidgets('progress updates independently and avoids date at 320px',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_frame(controls: true, showDate: true));
    platform.initialize();
    await tester.pump();
    final video = tester.widget<VideoPlayer>(find.byType(VideoPlayer));
    final date = find.byKey(const ValueKey('media-date'));
    final dateWidget = tester.widget<Text>(date);
    final progress = find.byKey(const ValueKey('video-progress'));
    expect(tester.getBottomRight(date).dy,
        lessThan(tester.getTopLeft(progress).dy));
    expect(tester.getBottomRight(progress).dy, 640 - 104);
    expect(tester.getRect(progress).left, greaterThanOrEqualTo(0));
    expect(tester.getRect(progress).right, lessThanOrEqualTo(320));
    platform.positions[0] = const Duration(seconds: 4);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(tester.widget<VideoPlayer>(find.byType(VideoPlayer)), same(video));
    expect(tester.widget<Text>(date), same(dateWidget));
    expect(find.text('0:04'), findsOneWidget);
    expect(find.text('0:10'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(_frame(showDate: true));
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.getBottomRight(date).dy, greaterThan(640 - 164));
    await remove(tester);
  });

  testWidgets(
      'initializes a real controller, plays muted and displays video date',
      (tester) async {
    await tester.pumpWidget(_frame(showDate: true));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(platform.plays, isEmpty);
    expect(platform.sources.single.sourceType, DataSourceType.file);
    expect(platform.sources.single.uri, Uri.file(_path).toString());

    platform.initialize();
    await tester.pump();
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(platform.plays, [0]);
    expect(platform.volumes[0], 0);
    expect(tester.widget<Text>(find.byKey(const ValueKey('media-date'))).data,
        contains('March 4, 2025'));
    await remove(tester);
    expect(platform.disposed, [0]);
    expect(platform.events[0]!.hasListener, isFalse);
  });

  testWidgets('video decoding waits until capture metadata is released',
      (tester) async {
    final metadataResult = Completer<String?>();
    messenger.setMockMethodCallHandler(metadata, (_) => metadataResult.future);
    await tester.pumpWidget(_frame(showDate: true));
    expect(platform.sources, isEmpty);
    metadataResult.complete('2025:03:04 12:00:00');
    await tester.pump();
    expect(platform.sources, hasLength(1));
    platform.initialize();
    await tester.pump();
    expect(platform.plays, [0]);
    await remove(tester);
  });

  testWidgets('pending initialization respects current pause and mute settings',
      (tester) async {
    await tester.pumpWidget(_frame());
    await tester.pumpWidget(_frame(paused: true, muted: false));
    platform.initialize();
    await tester.pump();
    expect(platform.plays, isEmpty);
    expect(platform.volumes[0], 1);

    await tester.pumpWidget(_frame(muted: false));
    expect(platform.plays, [0]);
    expect(platform.sources, hasLength(1));
    await remove(tester);
  });

  testWidgets('settings pause and resume without recreating or rewinding video',
      (tester) async {
    await tester.pumpWidget(_frame(showDate: true));
    platform.initialize();
    await tester.pump();
    final controller =
        tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller;
    platform.positions[0] = const Duration(seconds: 4);
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.value.position, const Duration(seconds: 4));
    final pauseCount = platform.pauses.length;

    await tester.pumpWidget(
        _frame(paused: true, muted: false, controls: true, fill: false));
    expect(controller.value.isPlaying, isFalse);
    expect(platform.pauses.length, pauseCount + 1);
    expect(platform.volumes[0], 1);
    expect(find.byKey(const ValueKey('media-date')), findsNothing);
    await tester.pumpWidget(_frame(paused: true, controls: true));
    expect(platform.plays, [0]);
    expect(platform.volumes[0], 0);

    await tester.pumpWidget(_frame(showDate: true));
    expect(tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
        same(controller));
    expect(controller.value.position, const Duration(seconds: 4));
    expect(platform.plays, [0, 0]);
    expect(platform.seeks, isEmpty);
    expect(platform.sources, hasLength(1));
    expect(find.byKey(const ValueKey('media-date')), findsOneWidget);
    await remove(tester);
  });

  testWidgets('completion is post-frame, emitted once, and never replays',
      (tester) async {
    var completions = 0;
    Widget frame({bool paused = false}) =>
        _frame(paused: paused, onCompleted: () => completions++);
    await tester.pumpWidget(frame());
    platform.initialize();
    await tester.pump();
    platform.complete();
    await tester.idle();
    expect(completions, 0);
    await tester.pump();
    expect(completions, 1);
    platform.complete();
    await tester.pump();
    await tester.pumpWidget(frame(paused: true));
    await tester.pumpWidget(frame());
    expect(completions, 1);
    expect(platform.plays, [0]);
    expect(platform.seeks, isNot(contains(Duration.zero)));
    await remove(tester);
  });

  testWidgets(
      'completion while paused is delivered after unpause outside build',
      (tester) async {
    var paused = true;
    var completions = 0;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return MediaView(
          item: const MediaItem(_path, isVideo: true),
          paused: paused,
          fill: true,
          motion: false,
          motionSpeed: 1,
          muted: true,
          showDate: false,
          onCompleted: () => setState(() => completions++),
        );
      }),
    ));
    platform.initialize();
    await tester.pump();
    platform.complete();
    platform.complete();
    await tester.pump();
    expect(completions, 0);
    update(() => paused = false);
    await tester.pump();
    expect(completions, 1);
    expect(tester.takeException(), isNull);
    update(() => paused = true);
    await tester.pump();
    update(() => paused = false);
    await tester.pump();
    expect(completions, 1);
    expect(platform.plays, isEmpty);
    await remove(tester);
  });

  testWidgets(
      'pause between completion and post-frame delivery defers callback',
      (tester) async {
    var completions = 0;
    Widget frame(bool paused) =>
        _frame(paused: paused, onCompleted: () => completions++);
    await tester.pumpWidget(frame(false));
    platform.initialize();
    await tester.pump();
    platform.complete();
    await tester.idle();
    await tester.pumpWidget(frame(true));
    expect(completions, 0);
    await tester.pumpWidget(frame(false));
    expect(completions, 1);
    expect(platform.plays, [0]);
    await remove(tester);
  });

  for (final paused in [false, true]) {
    for (final timeout in [false, true]) {
      testWidgets(
          'init ${timeout ? 'timeout' : 'error'} releases once; paused=$paused',
          (tester) async {
        var completions = 0;
        final logs = <String>[];
        final print = debugPrint;
        debugPrint = (message, {wrapWidth}) {
          if (message != null) logs.add(message);
        };
        Widget frame(bool paused) =>
            _frame(paused: paused, onCompleted: () => completions++);
        try {
          await tester.pumpWidget(frame(paused));
          if (timeout) {
            await tester.pump(const Duration(seconds: 19));
            expect(platform.disposed, isEmpty);
            await tester.pump(const Duration(seconds: 1));
          } else {
            platform.fail();
            await tester.pump();
          }
        } finally {
          debugPrint = print;
        }
        expect(logs.single, contains('HF video failed $_path:'));
        expect(logs.single,
            contains(timeout ? 'TimeoutException' : 'SMB decoder failed'));
        expect(platform.disposed, [0]);
        expect(platform.events[0]!.hasListener, isFalse);
        expect(find.byIcon(Icons.videocam_off_outlined), findsOneWidget);
        expect(platform.plays, isEmpty);
        expect(completions, 0);

        // Neither a late initialization nor another failure can revive it.
        platform.initialize();
        platform.fail();
        await tester.pump(const Duration(seconds: 1));
        expect(completions, 0);
        await tester.pump(const Duration(seconds: 1));
        expect(completions, paused ? 0 : 1);
        await tester.pumpWidget(frame(false));
        expect(completions, 1);
        await tester.pumpWidget(frame(true));
        await tester.pumpWidget(frame(false));
        expect(completions, 1);
        expect(platform.plays, isEmpty);
        await remove(tester);
        expect(platform.disposed, [0]);
      });
    }

    testWidgets('playback error delays skip and defers while paused=$paused',
        (tester) async {
      var completions = 0;
      Widget frame(bool paused) =>
          _frame(paused: paused, onCompleted: () => completions++);
      await tester.pumpWidget(frame(false));
      platform.initialize();
      await tester.pump();
      if (paused) await tester.pumpWidget(frame(true));
      platform.fail();
      await tester.idle();
      await tester.pump();
      expect(find.byIcon(Icons.videocam_off_outlined), findsOneWidget);
      expect(platform.disposed, [0]);
      expect(platform.events[0]!.hasListener, isFalse);
      platform.fail();
      await tester.pump(const Duration(seconds: 1));
      expect(completions, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(completions, paused ? 0 : 1);
      await tester.pumpWidget(frame(false));
      expect(completions, 1);
      await tester.pumpWidget(frame(true));
      await tester.pumpWidget(frame(false));
      expect(completions, 1);
      expect(platform.plays, [0]);
      await remove(tester);
      expect(platform.disposed, [0]);
    });
  }

  for (final paused in [false, true]) {
    testWidgets(
        'audio-only initialization cannot play a blank video; paused=$paused',
        (tester) async {
      var completions = 0;
      Widget frame(bool paused) => _frame(
          paused: paused, controls: true, onCompleted: () => completions++);
      await tester.pumpWidget(frame(paused));
      platform.events[0]!.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: _duration,
        size: Size.zero,
      ));
      await tester.pump();
      expect(find.text('This video cannot be played on this device.'),
          findsOneWidget);
      expect(find.byType(VideoPlayer), findsNothing);
      expect(find.byKey(const ValueKey('video-seek')), findsNothing);
      expect(platform.plays, isEmpty);
      expect(platform.disposed, [0]);
      await tester.pump(const Duration(seconds: 2));
      expect(completions, paused ? 0 : 1);
      await tester.pumpWidget(frame(false));
      expect(completions, 1);
      await remove(tester);
      expect(platform.disposed, [0]);
    });
  }

  testWidgets('unpause during failure delay does not bypass the delay',
      (tester) async {
    var completions = 0;
    Widget frame(bool paused) =>
        _frame(paused: paused, onCompleted: () => completions++);
    await tester.pumpWidget(frame(false));
    platform.initialize();
    await tester.pump();
    platform.fail();
    await tester.pump();
    await tester.pumpWidget(frame(true));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(frame(false));
    expect(completions, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(completions, 1);
    await remove(tester);
  });

  testWidgets('dispose during initialization cancels deadline and late events',
      (tester) async {
    var completions = 0;
    await tester.pumpWidget(_frame(onCompleted: () => completions++));
    await remove(tester);
    expect(platform.disposed, [0]);
    expect(platform.events[0]!.hasListener, isFalse);
    platform.initialize();
    // Do not advance past the deadline: teardown also detects leaked timers.
    await tester.pump();
    expect(completions, 0);
    expect(platform.plays, isEmpty);
    expect(platform.disposed, [0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late events from disposed display cannot affect new display',
      (tester) async {
    var oldCompletions = 0;
    var newCompletions = 0;
    await tester.pumpWidget(_frame(onCompleted: () => oldCompletions++));
    await tester.pumpWidget(_frame(
        displayKey: const ValueKey('next-display'),
        onCompleted: () => newCompletions++));
    platform.initialize(0);
    platform.complete(0);
    platform.initialize(1);
    await tester.pump();
    expect(oldCompletions, 0);
    expect(newCompletions, 0);
    expect(platform.plays, [1]);
    expect(platform.disposed, [0]);
    platform.complete(1);
    await tester.pump();
    expect(newCompletions, 1);
    await remove(tester);
    expect(platform.disposed, [0, 1]);
  });

  testWidgets('dispose during volume update cannot resume or rebuild old video',
      (tester) async {
    platform.mutedVolumeGate = Completer<void>();
    await tester.pumpWidget(_frame());
    platform.initialize();
    await tester.pump();
    await remove(tester);
    platform.mutedVolumeGate!.complete();
    await tester.pump();
    expect(platform.disposed, [0]);
    expect(platform.plays, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dispose cancels pending failure skip', (tester) async {
    var completions = 0;
    await tester.pumpWidget(_frame(onCompleted: () => completions++));
    platform.initialize();
    await tester.pump();
    platform.fail();
    await tester.pump();
    await remove(tester);
    // Do not advance past the deadline: teardown also detects leaked timers.
    await tester.pump();
    expect(completions, 0);
    expect(platform.disposed, [0]);
  });

  testWidgets('dispose suppresses an already scheduled completion',
      (tester) async {
    var completions = 0;
    await tester.pumpWidget(_frame(onCompleted: () => completions++));
    platform.initialize();
    await tester.pump();
    platform.complete();
    await tester.idle();
    await remove(tester);
    expect(completions, 0);
    expect(platform.disposed, [0]);
  });
}
