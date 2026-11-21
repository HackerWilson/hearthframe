import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken, DioException;
import 'package:smb_connect/smb_connect.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import 'media_cache.dart';
import 'media_download.dart';
import 'sources.dart';

export 'media_download.dart'
    show DownloadCancelled, DownloadProgress, MediaDownload;

/// Media extensions shared by all sources.
const imageExt = {
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.webp',
  '.heic',
  '.heif',
  '.bmp',
};
const videoExt = {'.mp4', '.mov', '.m4v', '.mkv', '.avi'};

String extOf(String p) {
  final i = p.lastIndexOf('.');
  return i < 0 ? '' : p.substring(i).toLowerCase();
}

bool isMediaPath(String p) =>
    imageExt.contains(extOf(p)) || videoExt.contains(extOf(p));

/// A network-backed photo source. [list] returns remote items; [prepare]
/// downloads an item into a local cache so the slideshow can render it with
/// dart:io / video_player just like a local file.
abstract class NetworkSource implements PhotoSource {
  MediaDownload download(MediaItem item);

  // Deliberately not async: existing callers rely on identical active futures.
  Future<MediaItem> prepare(MediaItem item) => download(item).result;

  Future<void> close();
}

abstract class _DownloadingSource extends NetworkSource {
  final _pending = <(String, int?, int?), MediaDownloadTask>{};
  bool _closed = false;

  /// Shares the handle (including prefetch progress) only while it is active.
  /// Cancellation removes it synchronously, allowing an immediate fresh retry.
  @override
  MediaDownload download(MediaItem item) {
    final key = (item.path, item.size, item.mtime);
    final existing = _pending[key];
    if (existing != null) return existing;
    late final MediaDownloadTask task;
    task = MediaDownloadTask(
      total: _knownSize(item.size),
      onFinished: () {
        if (identical(_pending[key], task)) _pending.remove(key);
      },
    );
    if (_closed) {
      task.cancel();
    } else {
      _pending[key] = task;
      task.start(() => _prepare(item, task));
    }
    return task;
  }

  Future<MediaItem> _prepare(MediaItem item, MediaDownloadTask task);

  @override
  Future<void> close() async {
    _closed = true;
    for (final task in _pending.values.toList()) {
      task.cancel();
    }
  }
}

/// Cache entries are keyed by remote path PLUS size/mtime, so any remote
/// change (even a same-size EXIF-only edit) lands in a fresh file instead of
/// reusing a stale copy. Old generations of the same path are pruned after
/// a successful download.
Future<File> _cacheFile(String remotePath, int? size, int? mtime) async {
  final dir = await mediaCacheDir();
  final base =
      remotePath.split('/').last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final hash = remotePath.hashCode.toRadixString(16);
  return File('${dir.path}/${hash}_${size ?? 0}_${mtime ?? 0}_$base');
}

Future<void> _pruneOldGenerations(File keep, String remotePath) async {
  final prefix = '${remotePath.hashCode.toRadixString(16)}_';
  try {
    await for (final e in keep.parent.list()) {
      final name = e.path.split('/').last;
      if (e is File &&
          e.path != keep.path &&
          e.path != activeMediaPath &&
          !name.endsWith('.part') &&
          name.startsWith(prefix)) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
  } catch (_) {}
}

int? _knownSize(int? size) => size != null && size >= 0 ? size : null;

Future<bool> _validCache(File file, int? size, MediaDownloadTask task) async {
  final exists = await file.exists();
  task.checkCancelled();
  if (!exists) return false;
  final length = await file.length();
  task.checkCancelled();
  if (length > 0 && (size == null || size == length)) {
    task.report(length, total: size ?? length);
    task.checkCancelled();
    return true;
  }
  await file.delete();
  task.checkCancelled();
  return false;
}

int _partSequence = 0;
File _newPart(File local) => File(
    '${local.path}.${pid}_${DateTime.now().microsecondsSinceEpoch}_${_partSequence++}.part');

Future<void> _quiet(Future<dynamic> Function() operation) async {
  try {
    await operation();
  } catch (_) {}
}

Future<MediaItem> _publish(
    File part, File local, String key, MediaItem item, MediaDownloadTask task,
    {int? size, int? mtime}) async {
  task.checkCancelled();
  final length = await part.length();
  task.checkCancelled();
  final expected = _knownSize(size) ?? task.total;
  if (length <= 0 || (expected != null && length != expected)) {
    throw FileSystemException(
        'Incomplete media download: expected $expected bytes, received $length',
        part.path);
  }
  task.report(length, total: expected ?? length);
  task.checkCancelled();
  // No await between this last cancellation check, atomic rename, and result
  // completion: a cancelled task must never publish over a same-key retry.
  part.renameSync(local.path);
  final cached = item.cachedAt(local.path, size: size, mtime: mtime);
  task.complete(cached);
  // Maintenance is not part of the download deadline or cancellation lifetime.
  await _pruneOldGenerations(local, key);
  await _quiet(() => noteMediaCached(local.path, isVideo: item.isVideo));
  return cached;
}

// webdav_client's read2File races cancellation against its result and does
// NOT await its whenCancel.then(async ...) writer cleanup. Track those handlers
// so our final part deletion cannot race its close/delete or leak their errors.
// This adapter leaves Dio's cancellation values/errors unchanged.
class _DownloadCancelToken extends CancelToken {
  final _handlers = <Future<void>>[];

  @override
  Future<DioException> get whenCancel =>
      _ObservedFuture(super.whenCancel, _handlers);

  Future<void> drain() async {
    if (!isCancelled) return;
    var count = 0;
    do {
      count = _handlers.length;
      await Future.wait(_handlers.toList());
    } while (_handlers.length != count);
  }
}

class _ObservedFuture<T> implements Future<T> {
  _ObservedFuture(this._future, this._handlers);
  final Future<T> _future;
  final List<Future<void>> _handlers;

  Future<R> _observe<R>(Future<R> future) {
    _handlers
        .add(future.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    return future;
  }

  @override
  Future<R> then<R>(FutureOr<R> Function(T) onValue, {Function? onError}) =>
      _observe(_future.then(onValue, onError: onError));

  @override
  Future<T> whenComplete(FutureOr<void> Function() action) =>
      _observe(_future.whenComplete(action));

  @override
  Future<T> catchError(Function onError, {bool Function(Object)? test}) =>
      _observe(_future.catchError(onError, test: test));

  @override
  Stream<T> asStream() => _future.asStream();

  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) =>
      _future.timeout(timeLimit, onTimeout: onTimeout);
}

/// WebDAV source (e.g. Synology WebDAV Server, Nextcloud, ownCloud).
class WebDavSource extends _DownloadingSource {
  WebDavSource({
    required this.url,
    required this.user,
    required this.password,
    required this.rootPath,
  });

  final String url;
  final String user;
  final String password;
  final String rootPath;

  webdav.Client? _client;
  webdav.Client get _c =>
      _client ??= webdav.newClient(url, user: user, password: password);

  @override
  Future<List<MediaItem>> list() async {
    final items = <MediaItem>[];
    await discover(items.addAll);
    items.sort((a, b) => a.path.compareTo(b.path));
    return items;
  }

  @override
  Future<void> discover(void Function(List<MediaItem> batch) onBatch) async {
    await _walk(rootPath, onBatch);
  }

  Future<void> _walk(
      String path, void Function(List<MediaItem> batch) onBatch) async {
    final entries = await _c.readDir(path);
    final batch = <MediaItem>[];
    final dirs = <String>[];
    for (final e in entries) {
      final name = e.name ?? '';
      if (name == '.' || name == '..' || skipEntryName(name)) continue;
      final p = e.path ?? '';
      if (e.isDir == true) {
        dirs.add(p);
      } else if (isMediaPath(p)) {
        batch.add(MediaItem(p,
            isVideo: videoExt.contains(extOf(p)),
            size: e.size,
            mtime: e.mTime?.millisecondsSinceEpoch));
      }
    }
    if (batch.isNotEmpty) onBatch(batch);
    for (final d in dirs) {
      await _walk(d, onBatch);
    }
  }

  @override
  Future<MediaItem> _prepare(MediaItem item, MediaDownloadTask task) async {
    final token = _DownloadCancelToken();
    task.onCancel(() => token.cancel(const DownloadCancelled()));
    final local = await _cacheFile(item.path, item.size, item.mtime);
    task.checkCancelled();
    if (await _validCache(local, _knownSize(item.size), task)) {
      task.checkCancelled();
      return item.cachedAt(local.path);
    }
    task.checkCancelled();
    final part = _newPart(local);
    try {
      // read2File pauses its response subscription while writing each chunk.
      // Cancelling this token closes only this transfer, not the scan client.
      await _c.read2File(item.path, part.path, cancelToken: token,
          onProgress: (received, total) {
        task.report(received,
            total: _knownSize(item.size) ?? _knownSize(total));
      });
      task.checkCancelled();
      return await _publish(part, local, item.path, item, task,
          size: item.size);
    } catch (_) {
      if (!token.isCancelled) token.cancel();
      rethrow;
    } finally {
      // Cancellation result is already delivered. Wait only in the background
      // for the package's writer cleanup before deleting any remaining part.
      await token.drain();
      await _quiet(() => part.delete());
    }
  }

  @override
  Future<void> close() async {
    await super.close();
    _client?.c.close(force: true);
    _client = null;
  }
}

/// Owns exactly one transfer's connection. A hard abort bypasses tree-close
/// requests, which otherwise wait behind a stalled read on the SMB mutex.
class _DownloadConnection {
  _DownloadConnection(this.client);

  final SmbConnect client;
  Future<void>? _aborting;

  void abort() {
    _aborting ??= _quiet(
        () => client.transport.close().timeout(const Duration(seconds: 2)));
  }

  Future<void> close() async {
    if (_aborting == null) {
      await _quiet(() => client.close().timeout(const Duration(seconds: 2)));
      abort();
    }
    await _aborting;
  }
}

/// SMB / CIFS source (e.g. Synology SMB share). [rootPath] is "/share/folder".
class SmbSource extends _DownloadingSource {
  SmbSource({
    required this.host,
    required this.domain,
    required this.user,
    required this.password,
    required this.rootPath,
  });

  final String host;
  final String domain;
  final String user;
  final String password;
  final String rootPath;

  // Only directory scanning uses this connection. Downloads never await it.
  SmbConnect? _conn;
  Future<SmbConnect>? _connecting;
  Future<SmbConnect> _newConnection() => SmbConnect.connectAuth(
        host: host,
        domain: domain,
        username: user,
        password: password,
      );

  Future<SmbConnect> _connect() async {
    if (_closed) throw const DownloadCancelled();
    if (_conn case final connection?) return connection;
    final pending = _connecting ??= _newConnection();
    try {
      final connection = await pending;
      if (_closed) {
        await _quiet(() =>
            connection.transport.close().timeout(const Duration(seconds: 2)));
        throw const DownloadCancelled();
      }
      return _conn = connection;
    } finally {
      if (identical(_connecting, pending)) _connecting = null;
    }
  }

  @override
  Future<List<MediaItem>> list() async {
    final items = <MediaItem>[];
    await discover(items.addAll);
    items.sort((a, b) => a.path.compareTo(b.path));
    return items;
  }

  @override
  Future<void> discover(void Function(List<MediaItem> batch) onBatch) async {
    final c = await _connect();
    final folder = await c.file(rootPath);
    await _walk(c, folder, onBatch);
  }

  Future<void> _walk(SmbConnect c, SmbFile folder,
      void Function(List<MediaItem>) onBatch) async {
    final entries = await c.listFiles(folder);
    final batch = <MediaItem>[];
    final dirs = <SmbFile>[];
    for (final e in entries) {
      if (e.name == '.' || e.name == '..' || skipEntryName(e.name)) continue;
      if (e.isDirectory()) {
        dirs.add(e);
      } else if (isMediaPath(e.path)) {
        batch.add(MediaItem(e.path,
            isVideo: videoExt.contains(extOf(e.path)),
            size: e.size,
            mtime: e.lastModified));
      }
    }
    if (batch.isNotEmpty) onBatch(batch);
    for (final d in dirs) {
      await _walk(c, d, onBatch);
    }
  }

  @override
  Future<MediaItem> _prepare(MediaItem item, MediaDownloadTask task) async {
    final key = 'smb_${item.path}';
    var size = _knownSize(item.size);
    var mtime = item.mtime;
    var local = await _cacheFile(key, size, mtime);
    task.checkCancelled();
    // Even an offline or wedged server cannot delay a known cache hit.
    if (await _validCache(local, size, task)) {
      task.checkCancelled();
      return item.cachedAt(local.path);
    }
    task.checkCancelled();

    // connectAuth exposes the transport only after authentication. The result
    // can be cancelled immediately; a connection arriving later is closed by
    // onCancel's late-registration rule, without ever calling file/openRead.
    final connection = await task.wait(_newConnection().then((c) {
      final owned = _DownloadConnection(c);
      task.onCancel(owned.abort);
      task.checkCancelled();
      return owned;
    }));
    task.checkCancelled();
    try {
      final c = connection.client;
      final remote = await task.wait(c.file(item.path));
      task.checkCancelled();
      if (size == null || mtime == null) {
        size ??= _knownSize(remote.size);
        mtime ??= remote.lastModified;
        local = await _cacheFile(key, size, mtime);
        task.checkCancelled();
        if (await _validCache(local, size, task)) {
          task.checkCancelled();
          return item.cachedAt(local.path, size: size, mtime: mtime);
        }
      }
      task.checkCancelled();
      task.report(0, total: size);
      task.checkCancelled();
      final stream = await task.wait(c.openRead(remote));
      task.checkCancelled();
      final part = _newPart(local);
      final iterator = StreamIterator(stream);
      task.onCancel(() => unawaited(_quiet(iterator.cancel)));
      RandomAccessFile? writer;
      try {
        writer = await part.open(mode: FileMode.write);
        task.checkCancelled();
        var received = 0;
        while (await task
            .wait(iterator.moveNext().timeout(const Duration(seconds: 30)))) {
          task.checkCancelled();
          final chunk = iterator.current;
          // One disk write per read, with no unbounded IOSink queue. Do not
          // race the disk write: finally must close only after it has settled.
          await writer.writeFrom(chunk);
          task.checkCancelled();
          received += chunk.length;
          task.report(received, total: size);
          task.checkCancelled();
        }
        task.checkCancelled();
        await writer.close();
        writer = null;
        task.checkCancelled();
        return await _publish(part, local, key, item, task,
            size: size, mtime: mtime);
      } finally {
        // async* cancellation can wait for the remote read. It must NOT hold
        // the local writer or .part file hostage while that read unwinds.
        unawaited(_quiet(iterator.cancel));
        if (writer != null) await _quiet(writer.close);
        await _quiet(() => part.delete());
      }
    } catch (_) {
      connection.abort();
      rethrow;
    } finally {
      await connection.close();
    }
  }

  @override
  Future<void> close() async {
    await super.close();
    final connection = _conn;
    _conn = null;
    _connecting = null;
    if (connection != null) await _DownloadConnection(connection).close();
  }
}
