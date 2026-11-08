import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:smb_connect/smb_connect.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import 'sources.dart';

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
  Future<MediaItem> prepare(MediaItem item);
  Future<void> close();
}

Future<Directory> _cacheDir() async {
  final base = await getTemporaryDirectory();
  final d = Directory('${base.path}/hearthframe_cache');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

/// Cache entries are keyed by remote path PLUS size/mtime, so any remote
/// change (even a same-size EXIF-only edit) lands in a fresh file instead of
/// reusing a stale copy. Old generations of the same path are pruned after
/// a successful download.
Future<File> _cacheFile(String remotePath, int? size, int? mtime) async {
  final dir = await _cacheDir();
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
      if (e is File && e.path != keep.path && name.startsWith(prefix)) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
  } catch (_) {}
}

/// WebDAV source (e.g. Synology WebDAV Server, Nextcloud, ownCloud).
class WebDavSource implements NetworkSource {
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
  Future<MediaItem> prepare(MediaItem item) async {
    final local = await _cacheFile(item.path, item.size, item.mtime);
    if (await local.exists() && await local.length() > 0) {
      return MediaItem(local.path, isVideo: item.isVideo);
    }
    // Download to a .part file and only publish it on success, so an
    // interrupted transfer never leaves a truncated "valid" cache entry
    // (which would render as a permanently broken image).
    final part = File('${local.path}.part');
    try {
      await _c.read2File(item.path, part.path);
      await part.rename(local.path);
      await _pruneOldGenerations(local, item.path);
    } catch (e) {
      try {
        await part.delete();
      } catch (_) {}
      rethrow;
    }
    return MediaItem(local.path, isVideo: item.isVideo);
  }

  @override
  Future<void> close() async {}
}

/// SMB / CIFS source (e.g. Synology SMB share). [rootPath] is "/share/folder".
class SmbSource implements NetworkSource {
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

  SmbConnect? _conn;
  Future<SmbConnect> _connect() async => _conn ??= await SmbConnect.connectAuth(
        host: host,
        domain: domain,
        username: user,
        password: password,
      );

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
  Future<MediaItem> prepare(MediaItem item) async {
    final key = 'smb_${item.path}';
    var size = item.size;
    var mtime = item.mtime;
    final c = await _connect();
    if (size == null || mtime == null) {
      // Old index without metadata: stat once to key the cache correctly.
      final remote = await c.file(item.path);
      size = remote.size;
      mtime = remote.lastModified;
    }
    final local = await _cacheFile(key, size, mtime);
    if (await local.exists() && await local.length() > 0) {
      return MediaItem(local.path, isVideo: item.isVideo);
    }
    final remote = await c.file(item.path);
    final stream = await c.openRead(remote);
    // Stream into a .part file, publish only on success (see WebDavSource).
    final part = File('${local.path}.part');
    final sink = part.openWrite();
    try {
      await for (final chunk in stream) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      await part.rename(local.path);
      await _pruneOldGenerations(local, key);
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      try {
        await part.delete();
      } catch (_) {}
      rethrow;
    }
    return MediaItem(local.path, isVideo: item.isVideo);
  }

  @override
  Future<void> close() async {
    await _conn?.close();
    _conn = null;
  }
}
