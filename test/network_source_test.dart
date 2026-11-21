import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearthframe/nas_sources.dart';
import 'package:hearthframe/sources.dart';

class _NetworkTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Condition did not become true');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  _NetworkTestBinding();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory dir;
  late HttpServer server;
  late StreamSubscription<HttpRequest> subscription;
  late WebDavSource source;
  late Future<void> Function(HttpRequest) serve;
  late List<Completer<void>> releases;
  late List<Future<void>> handlers;
  late Map<String, int> requests;

  Completer<void> gate() {
    final release = Completer<void>();
    releases.add(release);
    return release;
  }

  List<File> parts() {
    final cache = Directory('${dir.path}/hearthframe_cache');
    if (!cache.existsSync()) return [];
    return cache
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.part'))
        .toList();
  }

  List<File> finished() {
    final cache = Directory('${dir.path}/hearthframe_cache');
    if (!cache.existsSync()) return [];
    return cache
        .listSync()
        .whereType<File>()
        .where((file) => !file.path.endsWith('.part'))
        .toList();
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hf_network_test');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    releases = [];
    handlers = [];
    requests = {};
    messenger.setMockMethodCallHandler(channel, (_) async => dir.path);
    serve = (request) async => request.response.add([1, 2, 3, 4]);
    subscription = server.listen((request) {
      handlers.add(() async {
        try {
          if (request.method == 'GET') {
            requests.update(request.uri.path, (n) => n + 1, ifAbsent: () => 1);
            await serve(request);
          }
          await request.response.close();
        } on SocketException {
          // Expected when the client cancels a streaming response.
        } on HttpException {
          // Expected when the client aborts before the response is finished.
        }
      }());
    });
    source = WebDavSource(
      url: 'http://127.0.0.1:${server.port}',
      user: '',
      password: '',
      rootPath: '/photo',
    );
  });

  tearDown(() async {
    await source.close();
    for (final release in releases) {
      if (!release.isCompleted) release.complete();
    }
    await server.close(force: true);
    await subscription.cancel();
    await Future.wait(handlers);
    await _until(() => parts().isEmpty);
    messenger.setMockMethodCallHandler(channel, null);
    await dir.delete(recursive: true);
  });

  test('prefetch and foreground share one future and retain source metadata',
      () async {
    final release = gate();
    serve = (request) async {
      await release.future;
      request.response.add([1, 2, 3, 4]);
    };
    const item = MediaItem('/photo/2026-09-02/a.mp4',
        isVideo: true, size: 4, mtime: 123);
    final prefetch = source.prepare(item);
    final foreground = source.prepare(item);
    final handle = source.download(item);
    expect(identical(prefetch, foreground), isTrue);
    expect(identical(prefetch, handle.result), isTrue);
    expect(identical(handle, source.download(item)), isTrue);
    await _until(() => requests[item.path] == 1);
    release.complete();
    final cached = await foreground;
    expect(requests[item.path], 1);
    expect(cached.originalPath, item.path);
    expect(cached.mtime, 123);
    expect(cached.size, 4);
    expect(cached.isVideo, isTrue);
    expect(await File(cached.path).readAsBytes(), [1, 2, 3, 4]);
    final again = source.download(item);
    expect(identical(again, handle), isFalse);
    expect((await again.result).path, cached.path);
    expect(requests[item.path], 1);
  });

  test('foreground joins prefetch progress, with known and unknown totals',
      () async {
    for (final knownTotal in [true, false]) {
      final release = gate();
      final path = '/photo/progress-$knownTotal.mp4';
      serve = (request) async {
        request.response.bufferOutput = false;
        if (knownTotal) request.response.contentLength = 16384;
        request.response.add(List.filled(8192, 7));
        await request.response.flush();
        await release.future;
        request.response.add(List.filled(8192, 8));
      };
      final item = MediaItem(path, isVideo: true);
      final prefetch = source.prepare(item);
      final handle = source.download(item);
      await _until(() => handle.progress.value.received >= 8192);
      expect(identical(prefetch, handle.result), isTrue);
      expect(handle.progress.value.total, knownTotal ? 16384 : isNull);
      final values = <int>[];
      handle.progress
          .addListener(() => values.add(handle.progress.value.received));
      release.complete();
      await handle.result;
      expect(handle.progress.value.received, 16384);
      expect(handle.progress.value.total, 16384);
      expect(values, isNotEmpty);
      expect(requests[path], 1);
    }
  });

  test('cancel settles before cleanup and another cached item is immediate',
      () async {
    const cachedItem = MediaItem('/photo/cached.jpg', size: 4, mtime: 10);
    final cached = await source.prepare(cachedItem);
    final release = gate();
    serve = (request) async {
      request.response.bufferOutput = false;
      request.response.add(List.filled(8192, 1));
      await request.response.flush();
      await release.future;
      request.response.add(List.filled(8192, 2));
    };
    const item = MediaItem('/photo/slow.mp4', isVideo: true, size: 16384);
    final handle = source.download(item);
    await _until(() => handle.progress.value.received > 0);
    expect(parts(), hasLength(1));
    final error = expectLater(handle.result, throwsA(isA<DownloadCancelled>()));
    handle.cancel();
    expect(handle.isCancelled, isTrue);
    await error.timeout(const Duration(milliseconds: 500));
    final hit = await source
        .prepare(cachedItem)
        .timeout(const Duration(milliseconds: 500));
    expect(hit.path, cached.path);
    expect(requests[cachedItem.path], 1);
    expect(release.isCompleted, isFalse);
    await _until(() => parts().isEmpty);
    expect(finished().map((f) => f.path), [cached.path]);
    // Cancelling one transfer must not close the shared scan/HTTP client.
    serve = (request) async => request.response.add([5, 6, 7, 8]);
    await source.prepare(const MediaItem('/photo/other.jpg', size: 4));
  });

  test(
      'cancel/retry uses unique parts and old cleanup cannot evict the new handle',
      () async {
    const item = MediaItem('/photo/retry.mp4', isVideo: true, size: 16384);
    final oldRelease = gate();
    final newRelease = gate();
    serve = (request) async {
      final first = requests[item.path] == 1;
      request.response.bufferOutput = false;
      request.response.add(List.filled(8192, first ? 1 : 9));
      await request.response.flush();
      await (first ? oldRelease : newRelease).future;
      request.response.add(List.filled(8192, first ? 2 : 9));
    };
    final old = source.download(item);
    await _until(() => old.progress.value.received == 8192);
    final oldPart = parts().single.path;
    old.cancel();
    final retry = source.download(item);
    expect(identical(old, retry), isFalse);
    await expectLater(old.result, throwsA(isA<DownloadCancelled>()));
    await _until(() => retry.progress.value.received == 8192);
    await _until(() => !File(oldPart).existsSync());
    expect(parts().single.path, isNot(oldPart));
    oldRelease.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(identical(source.download(item), retry), isTrue);
    expect(identical(source.prepare(item), retry.result), isTrue);
    newRelease.complete();
    final cached = await retry.result;
    expect(await File(cached.path).readAsBytes(), everyElement(9));
    expect(requests[item.path], 2);
    expect(parts(), isEmpty);
  });

  test(
      'size and mtime distinguish active downloads and prune leaves parts alone',
      () async {
    final firstRelease = gate();
    final secondRelease = gate();
    const first = MediaItem('/photo/changed.jpg', size: 4, mtime: 1);
    const second = MediaItem('/photo/changed.jpg', size: 8, mtime: 1);
    const third = MediaItem('/photo/changed.jpg', size: 8, mtime: 2);
    serve = (request) async {
      final number = requests[first.path];
      request.response.bufferOutput = false;
      request.response.add([1, 2]);
      await request.response.flush();
      if (number == 1) {
        await firstRelease.future;
        request.response.add([3, 4]);
      } else {
        await secondRelease.future;
        request.response.add([3, 4, 5, 6, 7, 8]);
      }
    };
    final a = source.download(first);
    await _until(() => a.progress.value.received == 2);
    final b = source.download(second);
    await _until(() => b.progress.value.received == 2);
    final c = source.download(third);
    await _until(() => c.progress.value.received == 2);
    expect(identical(a, b), isFalse);
    expect(identical(b, c), isFalse);
    firstRelease.complete();
    await a.result;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(parts(), hasLength(2));
    secondRelease.complete();
    await Future.wait([b.result, c.result]);
    expect(requests[first.path], 3);
  });

  test(
      'known length rejects a clean but incomplete response and a corrupt cache',
      () async {
    const item = MediaItem('/photo/incomplete.jpg', size: 8, mtime: 30);
    // HTTP itself is valid (4 bytes/chunked), but the indexed size is 8.
    await expectLater(
        source.prepare(item), throwsA(isA<FileSystemException>()));
    expect(parts(), isEmpty);
    expect(finished(), isEmpty);
    serve = (request) async => request.response.add(List.filled(8, 8));
    final cached = await source.prepare(item);
    await File(cached.path).writeAsBytes([0, 1]);
    final repaired = await source.prepare(item);
    expect(await File(repaired.path).length(), 8);
    expect(requests[item.path], 3);
  });

  test('a truncated Content-Length response is never published', () async {
    serve = (request) async {
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.add(
          'HTTP/1.1 200 OK\r\nContent-Length: 16\r\nConnection: close\r\n\r\n1234'
              .codeUnits);
      await socket.flush();
      socket.destroy();
    };
    await expectLater(source.prepare(const MediaItem('/photo/truncated.jpg')),
        throwsA(anything));
    await _until(() => parts().isEmpty);
    expect(finished(), isEmpty);
  });

  test('total deadline aborts the real transfer and cleans its part', () async {
    final release = gate();
    serve = (request) async {
      request.response.bufferOutput = false;
      request.response.add(List.filled(8192, 1));
      await request.response.flush();
      await release.future;
    };
    void Function()? expire;
    final handle = runZoned(
      () => source.download(const MediaItem('/photo/deadline.mp4')),
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          if (duration == const Duration(seconds: 180)) expire = callback;
          return parent.createTimer(zone, duration, callback);
        },
      ),
    );
    await _until(() => handle.progress.value.received > 0);
    expect(expire, isNotNull);
    final failure =
        expectLater(handle.result, throwsA(isA<TimeoutException>()));
    expire!(); // Fire the actual 180-second deadline without a three-minute test.
    await failure;
    expect(handle.isCancelled, isTrue);
    expect(release.isCompleted, isFalse);
    await _until(() => parts().isEmpty);
    expect(finished(), isEmpty);
  });

  test('cancellation from the final progress callback cannot publish a file',
      () async {
    const item = MediaItem('/photo/final-progress.jpg', size: 4);
    final handle = source.download(item);
    handle.progress.addListener(() {
      if (handle.progress.value.received == 4) handle.cancel();
    });
    await expectLater(handle.result, throwsA(isA<DownloadCancelled>()));
    await _until(() => parts().isEmpty);
    expect(finished(), isEmpty);
    final retry = await source.prepare(item);
    expect(await File(retry.path).length(), 4);
  });

  test('close cancels all active results and prevents new transfers', () async {
    final release = gate();
    serve = (request) async {
      request.response.bufferOutput = false;
      request.response.add(List.filled(8192, 1));
      await request.response.flush();
      await release.future;
    };
    final handles = [
      source.download(const MediaItem('/photo/one.mp4')),
      source.download(const MediaItem('/photo/two.mp4')),
    ];
    await _until(() => handles.every((h) => h.progress.value.received > 0));
    final errors = handles
        .map((h) => expectLater(h.result, throwsA(isA<DownloadCancelled>())))
        .toList();
    await source.close().timeout(const Duration(milliseconds: 500));
    await Future.wait(errors);
    expect(handles.every((h) => h.isCancelled), isTrue);
    await expectLater(source.prepare(const MediaItem('/photo/closed.jpg')),
        throwsA(isA<DownloadCancelled>()));
    await _until(() => parts().isEmpty);
    expect(finished(), isEmpty);
    expect(requests['/photo/closed.jpg'], isNull);
  });

  test(
      'rapid cancellation leaves no writers/parts or unhandled prefetch errors',
      () async {
    serve = (request) async {
      final release = gate();
      request.response.bufferOutput = false;
      request.response.add(List.filled(8192, 1));
      await request.response.flush();
      await release.future;
    };
    const item = MediaItem('/photo/repeated.mp4');
    for (var n = 0; n < 12; n++) {
      final task = source.download(item);
      await _until(() => task.progress.value.received > 0);
      task.cancel();
      // Deliberately do not attach a result listener to this prefetch.
    }
    await _until(() => parts().isEmpty);
    expect(finished(), isEmpty);
    // Also exercise an ignored HTTP error, then a retry on the same key.
    serve = (request) async => request.response.statusCode = 503;
    source.prepare(const MediaItem('/photo/error.jpg'));
    await _until(() => requests['/photo/error.jpg'] == 1);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    serve = (request) async => request.response.add([1, 2, 3, 4]);
    await source.prepare(const MediaItem('/photo/error.jpg'));
    expect(requests['/photo/error.jpg'], 2);
  });

  test('SMB reads a valid cache before attempting a dedicated connection',
      () async {
    const item = MediaItem('/share/cached.jpg', size: 4, mtime: 321);
    final cache = await Directory('${dir.path}/hearthframe_cache').create();
    final key = 'smb_${item.path}';
    final file = File(
        '${cache.path}/${key.hashCode.toRadixString(16)}_4_321_cached.jpg');
    await file.writeAsBytes([1, 2, 3, 4]);
    // No server/device access: this local port speaks HTTP, not SMB. A cache
    // regression would try an SMB handshake and fail the short deadline.
    final smb = SmbSource(
        host: '127.0.0.1:${server.port}',
        domain: '',
        user: '',
        password: '',
        rootPath: '/share');
    try {
      final task = smb.download(item);
      final cached =
          await task.result.timeout(const Duration(milliseconds: 500));
      expect(cached.path, file.path);
      expect(cached.originalPath, item.path);
      expect(cached.mtime, 321);
      expect(task.progress.value.received, 4);
      expect(requests, isEmpty);
    } finally {
      await smb.close();
    }
  });
}
