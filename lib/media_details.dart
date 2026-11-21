import 'dart:io';

import 'package:flutter/material.dart';

import 'l10n.dart';
import 'media_date.dart';
import 'sources.dart';

/// Read-only details, suitable for showDialog. Playback remains the host's job.
class MediaDetailsSheet extends StatefulWidget {
  const MediaDetailsSheet({
    super.key,
    required this.item,
    required this.sourceLabel,
  });

  final MediaItem item;
  final String sourceLabel;

  @override
  State<MediaDetailsSheet> createState() => _MediaDetailsSheetState();
}

class _MediaDetailsSheetState extends State<MediaDetailsSheet> {
  DateTime? _date;
  int? _bytes;
  bool _loadingDate = true;
  bool _loadingSize = true;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MediaDetailsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item != widget.item) _load();
  }

  void _load() {
    final revision = ++_revision;
    final item = widget.item;
    _date = null;
    _loadingDate = true;
    _bytes = item.size != null && item.size! >= 0 ? item.size : null;
    _loadingSize = _bytes == null;
    _loadDate(item, revision);
    if (_loadingSize) _loadSize(item, revision);
  }

  Future<void> _loadDate(MediaItem item, int revision) async {
    DateTime? date;
    try {
      // This is independent of the slideshow's showDate setting. Never use
      // the cached file's stat timestamps as a substitute for an unknown date.
      final metadataItem = item.originalPath == null &&
              item.path.toLowerCase().contains('hearthframe_cache')
          ? MediaItem(item.path,
              isVideo: item.isVideo, originalPath: '', mtime: item.mtime)
          : item;
      date = await readMediaDate(metadataItem);
    } catch (_) {}
    if (!mounted || revision != _revision) return;
    setState(() {
      _date = date;
      _loadingDate = false;
    });
  }

  Future<void> _loadSize(MediaItem item, int revision) async {
    int? bytes;
    try {
      // Stat only the already-local file; do not download or decode anything.
      final uri = Uri.tryParse(item.path);
      if (uri != null && (!uri.hasScheme || uri.scheme == 'file')) {
        final file = uri.scheme == 'file' ? File.fromUri(uri) : File(item.path);
        final stat = await file.stat();
        if (stat.type == FileSystemEntityType.file) bytes = stat.size;
      }
    } catch (_) {}
    if (!mounted || revision != _revision) return;
    setState(() {
      _bytes = bytes;
      _loadingSize = false;
    });
  }

  /// Remote originals may be URLs containing credentials or signed queries.
  /// Only show the location, never authentication data or an app cache path.
  String? _originalLocation() {
    final path = widget.item.originalPath ?? widget.item.path;
    if (path.isEmpty || path.toLowerCase().contains('hearthframe_cache')) {
      return null;
    }
    final uri = Uri.tryParse(path);
    if (uri == null) return null;
    if (uri.hasAuthority) {
      return Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: uri.path,
      ).toString();
    }
    if (uri.hasScheme && uri.scheme != 'file' && uri.scheme.length > 1) {
      return null;
    }
    return path.split('?').first.split('#').first;
  }

  String _filename(String path) {
    final name = path.replaceAll('\\', '/').split('/').last;
    try {
      return Uri.decodeComponent(name);
    } on FormatException {
      return name;
    }
  }

  String _sizeLabel(AppStrings s) {
    if (_loadingSize) return s.loading;
    final bytes = _bytes;
    if (bytes == null) return s.unknown;
    if (bytes < 1024) return s.mediaBytes(bytes);
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = -1;
    do {
      value /= 1024;
      unit++;
    } while (value >= 1024 && unit < units.length - 1);
    return '${value.toStringAsFixed(1)} ${units[unit]}';
  }

  Widget _field(BuildContext context, String label, String value, String key) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
            const SizedBox(height: 4),
            SelectableText(value,
                key: ValueKey(key),
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final location = _originalLocation();
    final date = _date;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      scrollable: true,
      title: Text(s.mediaDetails),
      content: SizedBox(
        width: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(
                context,
                s.originalFilename,
                location == null ? s.unknown : _filename(location),
                'details-filename'),
            _field(
                context,
                s.mediaDate,
                _loadingDate
                    ? s.loading
                    : date == null
                        ? s.unknown
                        : MaterialLocalizations.of(context)
                            .formatFullDate(date),
                'details-date'),
            if (date != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Text(s.mediaDateSources,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            _field(context, s.mediaType,
                widget.item.isVideo ? s.video : s.photo, 'details-type'),
            _field(context, s.sourceType, widget.sourceLabel, 'details-source'),
            _field(context, s.originalFilePath, location ?? s.unknown,
                'details-path'),
            _field(context, s.fileSize, _sizeLabel(s), 'details-size'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.done),
        ),
      ],
    );
  }
}
