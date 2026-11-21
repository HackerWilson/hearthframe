import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearthframe/media_date.dart';
import 'package:hearthframe/settings.dart';
import 'package:hearthframe/sources.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('hearthframe/metadata');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('capture dates support EXIF, ISO and compact video UTC timestamps', () {
    expect(parseCaptureDate('2024:02:29 23:59:59'), DateTime(2024, 2, 29));
    for (final value in ['2026-09-02T12:34:56.000Z', '20260902T123456.000Z']) {
      final local = DateTime.parse(value).toLocal();
      expect(
        parseCaptureDate(value),
        DateTime(local.year, local.month, local.day),
      );
    }
    expect(parseCaptureDate('0000:00:00 00:00:00'), isNull);
    expect(parseCaptureDate('2025:02:29 12:00:00'), isNull);
    expect(parseCaptureDate('2026-13-02T12:00:00Z'), isNull);
    expect(parseCaptureDate('broken'), isNull);
  });

  test('video epoch placeholders fall back to original source date', () async {
    for (final value in ['19040101T000000.000Z', '19700101T000000.000Z']) {
      expect(parseCaptureDate(value, isVideo: true), isNull);
      messenger.setMockMethodCallHandler(channel, (_) async => value);
      final item = const MediaItem('/photo/2026-09-02/video.mp4', isVideo: true)
          .cachedAt('/cache/video.mp4');
      expect(await readMediaDate(item), DateTime(2026, 9, 2));
    }
    expect(parseCaptureDate('1904:01:01 10:00:00'), DateTime(1904, 1, 1));
    expect(parseCaptureDate('20260902T010203.000Z', isVideo: true), isNotNull);
  });

  test(
    'uses filename before nearest dated directory, never a hash fragment',
    () {
      expect(
        dateFromMediaPath('/photo/2026-09-02/5417989/video-52f043868.mp4'),
        DateTime(2026, 9, 2),
      );
      expect(
        dateFromMediaPath('/photo/2026-09-02/IMG_20251103_135900.jpg'),
        DateTime(2025, 11, 3),
      );
      expect(
        dateFromMediaPath(r'C:\photo\2024.02.29\photo.jpg'),
        DateTime(2024, 2, 29),
      );
      expect(
        dateFromMediaPath('/photo/2026-10-10/2026-11-02/x.jpg'),
        DateTime(2026, 11, 2),
      );
      expect(dateFromMediaPath('/photo/2026-02-30/x.jpg'), isNull);
      expect(dateFromMediaPath('/photo/video-fc20261118ab.mp4'), isNull);
      expect(dateFromMediaPath('/photo/12320261118.jpg'), isNull);
    },
  );

  test(
    'cached items retain original date metadata, not cache filename date',
    () {
      final source = MediaItem(
        '/photo/2026-09-02/video.mp4',
        isVideo: true,
        size: 42,
        mtime: DateTime(2026, 11, 18).millisecondsSinceEpoch,
      );
      final cached = source.cachedAt('/cache/20261118_video.mp4');
      expect(cached.originalPath, source.path);
      expect(cached.size, 42);
      expect(cached.isVideo, isTrue);
      expect(cached.mtime, source.mtime);
      expect(fallbackMediaDate(cached), DateTime(2026, 9, 2));
      expect(
        fallbackMediaDate(
          const MediaItem(
            '/cache/20261118_file.jpg',
            originalPath: '/photo/unknown.jpg',
          ),
        ),
        isNull,
      );
      expect(source.cachedAt('/cache/v.mp4', mtime: 123).mtime, 123);
    },
  );

  test(
    'source modification date is last resort, unknown date stays hidden',
    () {
      final date = DateTime(2025, 6, 3);
      expect(
        fallbackMediaDate(
          MediaItem('/photo/a.jpg', mtime: date.millisecondsSinceEpoch),
        ),
        date,
      );
      expect(fallbackMediaDate(const MediaItem('/photo/a.jpg')), isNull);
      expect(
        fallbackMediaDate(const MediaItem('/photo/a.jpg', mtime: 0)),
        isNull,
      );
      expect(
        fallbackMediaDate(const MediaItem('/photo/a.jpg', mtime: -1)),
        isNull,
      );
      expect(
        fallbackMediaDate(
          const MediaItem('/photo/a.jpg', mtime: 9999999999999999),
        ),
        isNull,
      );
    },
  );

  test('native capture date wins for both photos and videos', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'captureDate');
      expect(call.arguments['path'], '/cache/file');
      return '2025:03:04 12:34:56';
    });
    for (final video in [false, true]) {
      final item = MediaItem(
        '/photo/2026-09-02/file',
        isVideo: video,
      ).cachedAt('/cache/file');
      expect(await readMediaDate(item), DateTime(2025, 3, 4));
    }
  });

  test(
    'missing, invalid and unreadable native metadata fall back to source',
    () async {
      const item = MediaItem('/photo/2026-09-02/a.jpg');
      for (final value in <String?>[
        null,
        '',
        '0000:00:00 00:00:00',
        'invalid',
      ]) {
        messenger.setMockMethodCallHandler(channel, (_) async => value);
        expect(await readMediaDate(item), DateTime(2026, 9, 2));
      }
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'unsupported'),
      );
      expect(await readMediaDate(item), DateTime(2026, 9, 2));
      messenger.setMockMethodCallHandler(channel, null);
      expect(await readMediaDate(item), DateTime(2026, 9, 2));
    },
  );

  test('date is on for old installs and preference survives reload', () async {
    SharedPreferences.setMockInitialValues({
      'show_clock': false,
      'interval_seconds': 30,
    });
    final settings = await FrameSettings.load();
    expect(settings.showMediaDate, isTrue);
    await settings.setShowMediaDate(false);
    expect((await FrameSettings.load()).showMediaDate, isFalse);
    expect(settings.showClock, isFalse);
    expect(settings.intervalSeconds, 30);
    await settings.setShowMediaDate(true);
    expect((await FrameSettings.load()).showMediaDate, isTrue);
    settings.dispose();
  });
}
