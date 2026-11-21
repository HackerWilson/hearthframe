import 'dart:async';

import 'package:flutter/services.dart';

import 'sources.dart';

const _metadataChannel = MethodChannel('hearthframe/metadata');

DateTime? _calendarDate(int year, int month, int day) {
  if (year < 1900 || year > 9999 || month < 1 || month > 12 || day < 1) {
    return null;
  }
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}

DateTime? parseCaptureDate(String? value, {bool isVideo = false}) {
  if (value == null) return null;
  final text = value.trim();
  final match =
      RegExp(r'^(\d{4})[:-]?(\d{2})[:-]?(\d{2})(?:$|[ T])').firstMatch(text);
  if (match == null) return null;
  final date = _calendarDate(
    int.parse(match[1]!),
    int.parse(match[2]!),
    int.parse(match[3]!),
  );
  if (date == null) return null;
  // Zero MP4/Unix timestamps describe missing metadata, not a recording date.
  if (isVideo &&
      date.month == 1 &&
      date.day == 1 &&
      (date.year == 1904 || date.year == 1970)) {
    return null;
  }
  if (text.contains('T')) {
    final timestamp = DateTime.tryParse(text);
    if (timestamp == null) return null;
    final local = timestamp.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
  // EXIF without a timezone records the camera's local calendar date.
  return date;
}

DateTime? dateFromMediaPath(String path) {
  final pattern = RegExp(
    r'(?:^|[^A-Za-z0-9])((?:19|20)\d{2})([-_.]?)(\d{2})\2(\d{2})(?=$|[^0-9])',
  );
  for (final component in path.replaceAll('\\', '/').split('/').reversed) {
    for (final match in pattern.allMatches(component)) {
      final date = _calendarDate(
        int.parse(match[1]!),
        int.parse(match[3]!),
        int.parse(match[4]!),
      );
      if (date != null) return date;
    }
  }
  return null;
}

DateTime? fallbackMediaDate(MediaItem item) {
  final pathDate = dateFromMediaPath(item.originalPath ?? item.path);
  if (pathDate != null) return pathDate;
  final mtime = item.mtime;
  if (mtime == null || mtime <= 0 || mtime > 253402214400000) return null;
  final date = DateTime.fromMillisecondsSinceEpoch(mtime);
  return _calendarDate(date.year, date.month, date.day);
}

Future<DateTime?> readMediaDate(MediaItem item) async {
  try {
    final value = await _metadataChannel.invokeMethod<String>('captureDate', {
      'path': item.path,
      'isVideo': item.isVideo,
    }).timeout(const Duration(seconds: 3));
    final date = parseCaptureDate(value, isVideo: item.isVideo);
    if (date != null) return date;
  } on PlatformException {
    return fallbackMediaDate(item);
  } on MissingPluginException {
    return fallbackMediaDate(item);
  } on TimeoutException {
    // Metadata must never hold up playback.
  }
  return fallbackMediaDate(item);
}
