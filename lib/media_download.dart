import 'dart:async';

import 'package:flutter/foundation.dart';

import 'sources.dart';

@immutable
class DownloadProgress {
  const DownloadProgress({required this.received, this.total});

  final int received;
  final int? total;
}

class DownloadCancelled implements Exception {
  const DownloadCancelled();

  @override
  String toString() => 'DownloadCancelled';
}

/// A shared, cancellable download. Cancelling also cancels other consumers of
/// this same handle. Completion does not dispose [progress]; listeners should
/// remove themselves when their view no longer needs the handle.
abstract class MediaDownload {
  /// Explicit cancellation fails with [DownloadCancelled]; the 180-second
  /// deadline fails with [TimeoutException]. Both abort IO and set isCancelled,
  /// without making callers wait for background resource cleanup.
  Future<MediaItem> get result;
  ValueListenable<DownloadProgress> get progress;
  void cancel();
  bool get isCancelled;
}

/// Source-side implementation. UI code only needs [MediaDownload].
class MediaDownloadTask implements MediaDownload {
  MediaDownloadTask({
    int? total,
    required void Function() onFinished,
    Duration timeout = const Duration(seconds: 180),
  })  : _onFinished = onFinished,
        _latest = DownloadProgress(received: 0, total: total),
        _progress = ValueNotifier(DownloadProgress(received: 0, total: total)) {
    // Prefetch callers may attach their listener later (or never). This observes
    // errors without replacing the original future or swallowing their errors.
    unawaited(result.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    _deadline = Timer(timeout, () {
      _stop(TimeoutException('Media download exceeded $timeout', timeout));
    });
  }

  final _completer = Completer<MediaItem>();
  final ValueNotifier<DownloadProgress> _progress;
  final void Function() _onFinished;
  final _abort = <void Function()>{};
  final _clock = Stopwatch()..start();
  late final Timer _deadline;
  Timer? _notification;
  DownloadProgress _latest;
  int _lastNotification = -100;
  Object? _cancelError;

  @override
  Future<MediaItem> get result => _completer.future;
  @override
  ValueListenable<DownloadProgress> get progress => _progress;
  @override
  bool get isCancelled => _cancelError != null;

  int? get total => _latest.total;

  void start(Future<MediaItem> Function() work) {
    unawaited(_run(work));
  }

  Future<void> _run(Future<MediaItem> Function() work) async {
    try {
      checkCancelled();
      complete(await work());
    } catch (error, stack) {
      if (!_completer.isCompleted) {
        _finish();
        _abort.clear();
        _completer.completeError(error, stack);
      }
    }
  }

  void checkCancelled() {
    if (_cancelError case final error?) throw error;
  }

  /// Register a synchronous abort trigger, not an awaited cleanup operation.
  /// A resource acquired after cancellation is aborted as soon as it arrives.
  void onCancel(void Function() abort) {
    if (isCancelled) {
      abort();
    } else if (!_completer.isCompleted) {
      _abort.add(abort);
    }
  }

  /// Interrupt a stalled network await without waiting for stream.cancel(),
  /// which can itself wait for an SMB async* generator's outstanding read.
  /// Unlike repeatedly racing a single cancellation future, this does not keep
  /// one cancellation listener per chunk for the entire lifetime of a video.
  Future<T> wait<T>(Future<T> operation) {
    final done = Completer<T>();
    void abort() {
      if (!done.isCompleted) done.completeError(_cancelError!);
    }

    operation.then<void>((value) {
      _abort.remove(abort);
      if (!done.isCompleted) done.complete(value);
    }, onError: (Object error, StackTrace stack) {
      _abort.remove(abort);
      if (!done.isCompleted) done.completeError(error, stack);
    });
    onCancel(abort);
    return done.future;
  }

  void report(int received, {int? total}) {
    if (_completer.isCompleted) return;
    _latest =
        DownloadProgress(received: received, total: total ?? _latest.total);
    final remaining = 100 - (_clock.elapsedMilliseconds - _lastNotification);
    if (remaining <= 0) {
      _notify();
    } else {
      _notification ??= Timer(Duration(milliseconds: remaining), _notify);
    }
  }

  void _notify() {
    _notification?.cancel();
    _notification = null;
    _lastNotification = _clock.elapsedMilliseconds;
    _progress.value = _latest;
  }

  /// Also used immediately after an atomic cache rename, without an async gap.
  void complete(MediaItem item) {
    if (_completer.isCompleted) return;
    _finish();
    _completer.complete(item);
    _abort.clear();
    // Completion is already committed, so a listener cancelling during this
    // final notification cannot turn a published cache entry into a failure.
    _notify();
  }

  void _finish() {
    _deadline.cancel();
    _notification?.cancel();
    _notification = null;
    _onFinished();
  }

  @override
  void cancel() => _stop(const DownloadCancelled());

  void _stop(Object error) {
    if (_completer.isCompleted) return;
    _cancelError = error;
    _finish();
    _completer.completeError(error, StackTrace.current);
    final callbacks = _abort.toList();
    _abort.clear();
    for (final abort in callbacks) {
      try {
        abort();
      } catch (_) {
        // Cancellation must remain immediate even if resource teardown fails.
      }
    }
  }
}
