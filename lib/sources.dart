import 'dart:io';

/// A media item to display in the frame.
class MediaItem {
  const MediaItem(this.path, {this.isVideo = false, this.size, this.mtime});
  final String path;
  final bool isVideo;

  /// Remote byte size when known; used to invalidate stale local caches
  /// after a file is replaced on the NAS.
  final int? size;

  /// Remote modification time (source-specific units) when known; catches
  /// same-size replacements such as EXIF-only edits.
  final int? mtime;
}

/// Directories that never contain user media (NAS thumbnail / recycle bins).
/// Walking them wastes minutes and would show thumbnails as slides.
const skipDirNames = {'@eaDir', '#recycle', '#snapshot', '@tmp'};

bool skipEntryName(String name) =>
    name.startsWith('.') || skipDirNames.contains(name);

/// Abstract photo source. [list] returns everything at once; [discover]
/// emits batches as directories are scanned, so the frame can show the first
/// photo instead of waiting for the whole tree.
abstract class PhotoSource {
  Future<List<MediaItem>> list();

  Future<void> discover(void Function(List<MediaItem> batch) onBatch) async =>
      onBatch(await list());
}

/// Local folder source: recursively collects images (and videos) from a path.
class LocalFolderSource implements PhotoSource {
  LocalFolderSource(this.rootPath);
  final String rootPath;

  // Keep in sync with the network sources (see nas_sources.dart).
  static const _imageExt = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.heic',
    '.heif',
    '.bmp',
  };
  static const _videoExt = {'.mp4', '.mov', '.m4v', '.mkv', '.avi'};

  @override
  Future<List<MediaItem>> list() async {
    final out = <MediaItem>[];
    await discover(out.addAll);
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }

  @override
  Future<void> discover(void Function(List<MediaItem> batch) onBatch) async {
    final root = Directory(rootPath);
    if (!await root.exists()) return;
    await _walk(root, onBatch);
  }

  Future<void> _walk(
      Directory dir, void Function(List<MediaItem>) onBatch) async {
    final batch = <MediaItem>[];
    final subdirs = <Directory>[];
    await for (final e in dir.list(followLinks: false)) {
      final name = e.path.split('/').last;
      if (skipEntryName(name)) continue;
      if (e is Directory) {
        subdirs.add(e);
      } else if (e is File) {
        final ext = _ext(e.path);
        if (_imageExt.contains(ext)) batch.add(MediaItem(e.path));
        if (_videoExt.contains(ext)) {
          batch.add(MediaItem(e.path, isVideo: true));
        }
      }
    }
    if (batch.isNotEmpty) onBatch(batch);
    for (final d in subdirs) {
      await _walk(d, onBatch);
    }
  }

  static String _ext(String p) {
    final i = p.lastIndexOf('.');
    return i < 0 ? '' : p.substring(i).toLowerCase();
  }
}
