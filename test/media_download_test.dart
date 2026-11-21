import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearthframe/media_download.dart';
import 'package:hearthframe/sources.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('progress has an optional total and cancellation is an exception', () {
    const progress = DownloadProgress(received: 42);
    expect(progress.received, 42);
    expect(progress.total, isNull);
    expect(const DownloadCancelled(), isA<Exception>());
    expect(const DownloadCancelled().toString(), 'DownloadCancelled');
  });

  test('cancel settles immediately, aborts once, and ignores a late result',
      () async {
    var finished = 0;
    var aborted = 0;
    final io = Completer<MediaItem>();
    final task = MediaDownloadTask(onFinished: () => finished++);
    task.onCancel(() => aborted++);
    task.start(() => io.future);
    final result = task.result;
    expect(identical(result, task.result), isTrue);
    final failure = expectLater(result, throwsA(isA<DownloadCancelled>()));
    task.cancel();
    expect(task.isCancelled, isTrue);
    expect(finished, 1);
    expect(aborted, 1);
    await failure;
    task.cancel();
    io.complete(const MediaItem('/late.jpg'));
    await Future<void>.delayed(Duration.zero);
    expect(finished, 1);
    expect(aborted, 1);
    var lateAbort = false;
    task.onCancel(() => lateAbort = true);
    expect(lateAbort, isTrue);
  });

  test('a connection acquired after cancellation is closed without reading',
      () async {
    final connecting = Completer<void>();
    final task = MediaDownloadTask(onFinished: () {});
    var closed = false;
    var read = false;
    task.start(() async {
      await task.wait(connecting.future.then((_) {
        task.onCancel(() => closed = true);
        task.checkCancelled();
        read = true;
      }));
      return const MediaItem('/unreachable.jpg');
    });
    task.cancel();
    await expectLater(task.result, throwsA(isA<DownloadCancelled>()));
    expect(closed, isFalse);
    connecting.complete();
    await Future<void>.delayed(Duration.zero);
    expect(closed, isTrue);
    expect(read, isFalse);
  });

  test('stalled read can be interrupted and its later error remains observed',
      () async {
    final io = Completer<bool>();
    final task = MediaDownloadTask(onFinished: () {});
    task.start(() async {
      await task.wait(io.future);
      return const MediaItem('/unreachable.jpg');
    });
    task.cancel();
    await expectLater(task.result, throwsA(isA<DownloadCancelled>()));
    io.completeError(StateError('late socket error'));
    await Future<void>.delayed(Duration.zero);
  });

  test('unobserved prefetch errors and cancellations do not escape the zone',
      () async {
    final errors = <Object>[];
    final done = Completer<void>();
    runZonedGuarded(() async {
      final failed = MediaDownloadTask(onFinished: () {});
      failed.start(() async => throw StateError('prefetch failed'));
      final cancelled = MediaDownloadTask(onFinished: () {});
      cancelled.cancel();
      // Neither result is listened to by the caller until the next event turn.
      await Future<void>.delayed(Duration.zero);
      await expectLater(failed.result, throwsStateError);
      await expectLater(cancelled.result, throwsA(isA<DownloadCancelled>()));
      done.complete();
    }, (error, stack) => errors.add(error));
    await done.future;
    expect(errors, isEmpty);
  });

  testWidgets('180 second total deadline aborts the operation', (tester) async {
    var aborted = 0;
    var finished = 0;
    final io = Completer<MediaItem>();
    final task = MediaDownloadTask(onFinished: () => finished++);
    task.onCancel(() => aborted++);
    task.start(() => task.wait(io.future));
    final failure = expectLater(task.result, throwsA(isA<TimeoutException>()));
    await tester.pump(const Duration(seconds: 179));
    expect(task.isCancelled, isFalse);
    await tester.pump(const Duration(seconds: 1));
    await failure;
    expect(task.isCancelled, isTrue);
    expect(aborted, 1);
    expect(finished, 1);
    io.completeError(StateError('socket eventually stopped'));
    await tester.pump();
  });

  testWidgets('progress is throttled, flushed on success, and then frozen',
      (tester) async {
    final task = MediaDownloadTask(total: 1000, onFinished: () {});
    final values = <DownloadProgress>[];
    task.progress.addListener(() => values.add(task.progress.value));
    task.report(1);
    for (var received = 2; received <= 500; received++) {
      task.report(received);
    }
    expect(values.length, 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(values.length, 2);
    expect(values.last.received, 500);
    task.report(1000);
    task.complete(const MediaItem('/cached.jpg'));
    await task.result;
    expect(values.last.received, 1000);
    expect(values.last.total, 1000);
    final count = values.length;
    task.cancel();
    task.report(2000);
    await tester.pump(const Duration(milliseconds: 200));
    expect(task.isCancelled, isFalse);
    expect(values.length, count);
  });
}
