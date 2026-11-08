import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const _channel = MethodChannel('hearthframe/image');

bool isHeicPath(String path) {
  final i = path.lastIndexOf('.');
  if (i < 0) return false;
  final e = path.substring(i).toLowerCase();
  return e == '.heic' || e == '.heif';
}

/// Returns a path Flutter's image codec can decode. HEIC/HEIF are converted
/// once to a cached JPEG through the platform decoder (Android ImageDecoder),
/// because Skia ships no HEIC codec. Every other format passes through.
Future<String> decodablePath(String path) async {
  if (!isHeicPath(path) || !Platform.isAndroid) return path;
  final base = await getTemporaryDirectory();
  final dir = Directory('${base.path}/hearthframe_cache');
  if (!await dir.exists()) await dir.create(recursive: true);
  // Include size/mtime so replacing a local HEIC with the same name triggers a
  // fresh conversion instead of serving a stale JPEG.
  var size = 0;
  var mtime = 0;
  try {
    final st = await File(path).stat();
    size = st.size;
    mtime = st.modified.millisecondsSinceEpoch;
  } catch (_) {}
  final key = '${path.hashCode.toRadixString(16)}_${size}_$mtime';
  final dst = File('${dir.path}/heic_$key.jpg');
  if (await dst.exists() && await dst.length() > 0) return dst.path;
  try {
    final out = await _channel.invokeMethod<String>(
      'heicToJpeg',
      {'src': path, 'dst': dst.path},
    );
    return out ?? path;
  } catch (_) {
    // Undecodable even natively: pass through so the view can skip it.
    return path;
  }
}
