import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:video_player_media_kit/src/media_kit_video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  test('registration preserves the Android hardware decoding option', () {
    final previous = VideoPlayerPlatform.instance;
    addTearDown(() => VideoPlayerPlatform.instance = previous);

    MediaKitVideoPlayer.registerWith(androidHardwareDecoding: false);
    expect(
      (VideoPlayerPlatform.instance as MediaKitVideoPlayer)
          .androidHardwareDecoding,
      isFalse,
    );
    MediaKitVideoPlayer.registerWith();
    expect(
      (VideoPlayerPlatform.instance as MediaKitVideoPlayer)
          .androidHardwareDecoding,
      isTrue,
    );
  });

  test('hardware acceleration defaults on and only Android can disable it',
      () async {
    final defaultHarness = _Harness();
    await defaultHarness.create();
    expect(defaultHarness.configurations.single.enableHardwareAcceleration,
        isTrue);

    final softwareHarness = _Harness(androidHardwareDecoding: false);
    await softwareHarness.create();
    expect(softwareHarness.configurations.single.enableHardwareAcceleration,
        !UniversalPlatform.isAndroid);
  });

  test('initialization precedes pending events and is only reported once',
      () async {
    final harness = _Harness();
    final textureId = await harness.create();
    final player = harness.players.single;
    final events = <VideoEvent>[];
    final errors = <Object>[];
    harness.bridge
        .videoEventsFor(textureId)
        .listen(events.add, onError: errors.add);

    player.emitPendingEvents();
    await _flushEvents();
    expect(events, isEmpty);

    player.emitMetadata();
    await _flushEvents();
    expect(events.first.eventType, VideoEventType.initialized);
    expect(events.first.size, const Size(1920, 1080));
    expect(events.first.duration, const Duration(seconds: 10));
    expect(
        events.skip(1).map((event) => event.eventType),
        unorderedEquals([
          VideoEventType.isPlayingStateUpdate,
          VideoEventType.completed,
          VideoEventType.bufferingStart,
          VideoEventType.bufferingUpdate,
        ]));

    player.emitMetadata();
    player.emitBuffering(false);
    await _flushEvents();
    expect(
      events.where((event) => event.eventType == VideoEventType.initialized),
      hasLength(1),
    );
    expect(events.last.eventType, VideoEventType.bufferingEnd);
    expect(errors, isEmpty);
  });

  test('early errors report immediately and release gates without valid events',
      () async {
    final harness = _Harness();
    final textureId = await harness.create();
    final player = harness.players.single;
    final events = <VideoEvent>[];
    final errors = <Object>[];
    harness.bridge
        .videoEventsFor(textureId)
        .listen(events.add, onError: errors.add);

    player.emitPendingEvents();
    await _flushEvents();
    player.emitError('Could not open codec');
    await _flushEvents();
    expect(errors, hasLength(1));
    expect(
        errors.single,
        isA<PlatformException>().having(
          (error) => error.message,
          'message',
          'Could not open codec',
        ));
    expect(events, isEmpty);

    // Late metadata must not turn a completed failure gate into initialized.
    player.emitMetadata();
    player.emitPendingEvents(active: false);
    player.emitError('A second real error');
    await _flushEvents();
    expect(events, isEmpty);
    expect(errors, hasLength(2));
  });

  test('errors during open are buffered for the video_player listener',
      () async {
    final harness = _Harness(openError: 'Opening failed');
    final textureId = await harness.create();
    final events = <VideoEvent>[];
    final errors = <Object>[];
    harness.bridge
        .videoEventsFor(textureId)
        .listen(events.add, onError: errors.add);
    await _flushEvents();

    expect(events, isEmpty);
    expect(
        errors.single,
        isA<PlatformException>().having(
          (error) => error.message,
          'message',
          'Opening failed',
        ));
  });

  test('errors after initialization are not swallowed', () async {
    final harness = _Harness();
    final textureId = await harness.create();
    final player = harness.players.single;
    final events = <VideoEvent>[];
    final errors = <Object>[];
    harness.bridge
        .videoEventsFor(textureId)
        .listen(events.add, onError: errors.add);
    player.emitMetadata();
    await _flushEvents();
    expect(events.single.eventType, VideoEventType.initialized);

    player.emitError('Playback failed');
    await _flushEvents();
    player.emitPendingEvents();
    await _flushEvents();
    expect(
        errors.single,
        isA<PlatformException>().having(
          (error) => error.message,
          'message',
          'Playback failed',
        ));
    expect(events, hasLength(1));
  });

  test('dispose releases pending callbacks and disposes a player exactly once',
      () async {
    final harness = _Harness();
    final textureId = await harness.create();
    final player = harness.players.single;
    final events = <VideoEvent>[];
    final errors = <Object>[];
    final done = Completer<void>();
    harness.bridge.videoEventsFor(textureId).listen(
          events.add,
          onError: errors.add,
          onDone: done.complete,
        );
    player.emitPendingEvents();
    await _flushEvents();

    await Future.wait([
      harness.bridge.dispose(textureId),
      harness.bridge.dispose(textureId),
    ]).timeout(const Duration(seconds: 1));
    await done.future.timeout(const Duration(seconds: 1));
    await _flushEvents();
    expect(events, isEmpty);
    expect(errors, isEmpty);
    expect(player.disposeCount, 1);
    expect(player.hadListenersAtDispose, isFalse);
    expect(() => harness.bridge.videoEventsFor(textureId), throwsStateError);
    expect(() => harness.bridge.buildView(textureId), throwsStateError);
  });

  test('init disposes a snapshot of all players without waiting for listeners',
      () async {
    final harness = _Harness();
    final ids = [await harness.create(), await harness.create()];
    await harness.bridge.init().timeout(const Duration(seconds: 1));
    await harness.bridge.init();

    for (final player in harness.players) {
      expect(player.disposeCount, 1);
      expect(player.hadListenersAtDispose, isFalse);
    }
    for (final id in ids) {
      expect(() => harness.bridge.videoEventsFor(id), throwsStateError);
    }
  });

  test('a paused event listener cannot block disposal', () async {
    final harness = _Harness();
    final textureId = await harness.create();
    final subscription =
        harness.bridge.videoEventsFor(textureId).listen((_) {});
    subscription.pause();
    await harness.bridge.dispose(textureId).timeout(const Duration(seconds: 1));
    expect(harness.players.single.disposeCount, 1);
    await subscription.cancel();
  });

  test('native disposal failures propagate without a second disposal',
      () async {
    final harness = _Harness();
    final textureId = await harness.create();
    final player = harness.players.single;
    final failure = StateError('Disposal failed');
    player.disposeError = failure;

    await expectLater(
        harness.bridge.dispose(textureId), throwsA(same(failure)));
    await harness.bridge.dispose(textureId);
    expect(player.disposeCount, 1);
  });
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

class _Harness {
  _Harness({bool androidHardwareDecoding = true, String? openError}) {
    bridge = MediaKitVideoPlayer.withFactories(
      androidHardwareDecoding: androidHardwareDecoding,
      playerFactory: () {
        final platformPlayer = _FakePlatformPlayer(openError: openError);
        players.add(platformPlayer);
        return Player(platformPlayer: platformPlayer);
      },
      videoControllerFactory: (player, configuration) {
        configurations.add(configuration);
        return _FakeVideoController();
      },
    );
    addTearDown(() => bridge.init());
  }

  late final MediaKitVideoPlayer bridge;
  final players = <_FakePlatformPlayer>[];
  final configurations = <VideoControllerConfiguration>[];

  Future<int> create() async => (await bridge.create(DataSource(
        sourceType: DataSourceType.network,
        uri: 'https://example.invalid/video.mp4',
      )))!;
}

class _FakeVideoController extends Fake implements VideoController {}

class _FakePlatformPlayer extends PlatformPlayer {
  _FakePlatformPlayer({this.openError})
      : super(configuration: const PlayerConfiguration());

  final String? openError;
  int disposeCount = 0;
  bool? hadListenersAtDispose;
  Object? disposeError;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    if (openError != null) {
      errorController.add(openError!);
    }
  }

  void emitMetadata() {
    state = state.copyWith(duration: const Duration(seconds: 10));
    durationController.add(state.duration);
    videoParamsController.add(const VideoParams(dw: 1920, dh: 1080));
  }

  void emitError(String message) => errorController.add(message);

  void emitBuffering(bool buffering) => bufferingController.add(buffering);

  void emitPendingEvents({bool active = true}) {
    playingController.add(active);
    completedController.add(active);
    bufferingController.add(active);
    bufferController.add(Duration(seconds: active ? 2 : 3));
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    hadListenersAtDispose = [
      durationController.hasListener,
      videoParamsController.hasListener,
      tracksController.hasListener,
      playingController.hasListener,
      completedController.hasListener,
      bufferingController.hasListener,
      bufferController.hasListener,
      errorController.hasListener,
    ].any((value) => value);
    // Cancellation must precede native teardown events.
    errorController.add('An event emitted during teardown');
    emitPendingEvents();
    await super.dispose();
    if (disposeError != null) {
      throw disposeError!;
    }
  }
}
