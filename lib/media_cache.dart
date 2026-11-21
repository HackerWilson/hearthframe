import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Upper bound for the on-device media cache. Oldest files are evicted first,
/// so a frame that runs for months cannot fill the user's storage.
const mediaCacheLimitBytes = 1536 * 1024 * 1024; // 1.5 GiB

/// Absolute path of the file currently on screen. Eviction and clearing skip
/// it so a playing video is never unlinked underneath the player.
String? activeMediaPath;

/// Directory holding downloaded images and videos.
Future<Directory> mediaCacheDir() async {
  final base = await getTemporaryDirectory();
  final d = Directory('${base.path}/hearthframe_cache');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

/// Total size of finished entries in [dir] (partial downloads excluded).
Future<int> cacheBytesIn(Directory dir) async {
  var total = 0;
  try {
    await for (final e in dir.list()) {
      if (e is File && !e.path.endsWith('.part')) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
  } catch (_) {}
  return total;
}

/// Total size of all finished cache entries.
Future<int> mediaCacheBytes() async => cacheBytesIn(await mediaCacheDir());

/// Deletes stale partial downloads left behind by a crash or force-stop.
Future<void> _removeStaleParts(
  Directory dir, {
  Duration maxAge = const Duration(hours: 24),
}) async {
  final cutoff = DateTime.now().subtract(maxAge);
  try {
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.part')) continue;
      try {
        if ((await e.lastModified()).isBefore(cutoff)) await e.delete();
      } catch (_) {}
    }
  } catch (_) {}
}

/// Deletes least-recently-used entries in [dir] until it is under [maxBytes].
/// [keep] and [activePath] are never removed; in-flight `.part` downloads are
/// left alone (a failed transfer cleans itself up).
Future<void> pruneCacheDir(
  Directory dir, {
  Set<String> keep = const {},
  int maxBytes = mediaCacheLimitBytes,
  String? activePath,
}) async {
  await _removeStaleParts(dir);
  final entries = <(File, DateTime, int)>[];
  var total = 0;
  try {
    await for (final e in dir.list()) {
      if (e is! File || e.path.endsWith('.part')) continue;
      try {
        final stat = await e.stat();
        total += stat.size;
        entries.add((e, stat.modified, stat.size));
      } catch (_) {}
    }
  } catch (_) {
    return;
  }
  if (total <= maxBytes) return;
  entries.sort((a, b) => a.$2.compareTo(b.$2));
  for (final (file, _, size) in entries) {
    if (total <= maxBytes) break;
    if (keep.contains(file.path) || file.path == activePath) continue;
    try {
      await file.delete();
      total -= size;
    } catch (_) {}
  }
}

/// Prunes the app's media cache. Images defer the check; videos (which
/// dominate the size) trigger it immediately.
int _downloadsSincePrune = 0;

Future<void> noteMediaCached(String path, {required bool isVideo}) async {
  _downloadsSincePrune++;
  if (!isVideo && _downloadsSincePrune % 20 != 0) return;
  await pruneCacheDir(
    await mediaCacheDir(),
    keep: {path},
    activePath: activeMediaPath,
  );
}

/// Removes every finished entry in [dir]. Returns bytes freed.
Future<int> clearCacheDir(Directory dir, {String? activePath}) async {
  var freed = 0;
  try {
    await for (final e in dir.list()) {
      if (e is! File || e.path.endsWith('.part')) continue;
      if (e.path == activePath) continue;
      try {
        final size = await e.length();
        await e.delete();
        freed += size;
      } catch (_) {}
    }
  } catch (_) {}
  return freed;
}

/// Removes every finished media cache entry. Returns bytes freed.
Future<int> clearMediaCache() async =>
    clearCacheDir(await mediaCacheDir(), activePath: activeMediaPath);

/// Human-readable size for the settings sheet.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}
