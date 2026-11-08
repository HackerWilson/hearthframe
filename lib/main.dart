import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'nas_sources.dart';
import 'platform_image.dart';
import 'settings.dart';
import 'sources.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Attach in the launcher's portrait orientation first. Rotating during the
  // initial surface attach leaves a stale portrait crop + 90° buffer transform
  // on some OEM tablets (MIUI compat), composing the UI sideways; the transform
  // only refreshes on a later metrics recompute. So rotate after the surface is
  // fully established, which goes through that recompute path and renders
  // upright. The brief portrait boot frame is hidden behind the launch theme.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final settings = await FrameSettings.load();
  // keep_adb (opt-in via `adb shell pm grant ... WRITE_SECURE_SETTINGS`):
  // while the frame runs, write wireless debugging back on if the OEM
  // switches it off (e.g. after standby). No-op without the grant.
  if (Platform.isAndroid) {
    const channel = MethodChannel('hearthframe/adb_keep');
    Future<void> ensure() =>
        channel.invokeMethod<void>('ensure').catchError((_) {});
    await ensure();
    Timer.periodic(const Duration(seconds: 60), (_) => ensure());
  }
  runApp(HearthFrameApp(settings));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
    });
  });
}

/// HearthFrame — an original, open-source family photo frame.
/// Clean-room implementation; not affiliated with or derived from any
/// commercial photo-frame product.
class HearthFrameApp extends StatelessWidget {
  const HearthFrameApp(this.settings, {super.key});
  final FrameSettings settings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HearthFrame',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF4E8975),
        scaffoldBackgroundColor: Colors.black,
      ),
      home: ListenableBuilder(
        listenable: settings,
        builder: (_, __) => (settings.setupMode || !settings.isConfigured)
            ? SetupScreen(settings: settings)
            : SlideshowScreen(settings: settings),
      ),
    );
  }
}

/// Setup screen: choose a source (local / WebDAV / SMB) and configure it.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.settings});
  final FrameSettings settings;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  FrameSettings get s => widget.settings;

  late String _type;
  late final TextEditingController _localPath;
  late final TextEditingController _davUrl;
  late final TextEditingController _davUser;
  late final TextEditingController _davPass;
  late final TextEditingController _davPath;
  late final TextEditingController _smbHost;
  late final TextEditingController _smbDomain;
  late final TextEditingController _smbUser;
  late final TextEditingController _smbPass;
  late final TextEditingController _smbPath;

  bool _granted = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _type = s.sourceType;
    _localPath = TextEditingController(
        text: s.sourceFolder.isNotEmpty
            ? s.sourceFolder
            : '/storage/emulated/0/Pictures');
    _davUrl = TextEditingController(text: s.webdavUrl);
    _davUser = TextEditingController(text: s.webdavUser);
    _davPass = TextEditingController(text: s.webdavPass);
    _davPath = TextEditingController(text: s.webdavPath);
    _smbHost = TextEditingController(text: s.smbHost);
    _smbDomain = TextEditingController(text: s.smbDomain);
    _smbUser = TextEditingController(text: s.smbUser);
    _smbPass = TextEditingController(text: s.smbPass);
    _smbPath = TextEditingController(text: s.smbPath);
    _refreshPerm();
  }

  @override
  void dispose() {
    for (final c in [
      _localPath,
      _davUrl,
      _davUser,
      _davPass,
      _davPath,
      _smbHost,
      _smbDomain,
      _smbUser,
      _smbPass,
      _smbPath,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshPerm() async {
    if (!Platform.isAndroid) {
      setState(() => _granted = true);
      return;
    }
    final st = await Permission.manageExternalStorage.status;
    if (mounted) setState(() => _granted = st.isGranted);
  }

  Future<void> _requestPerm() async {
    final st = await Permission.manageExternalStorage.request();
    if (mounted) setState(() => _granted = st.isGranted);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    if (_type == 'local') {
      if (_localPath.text.trim().isEmpty) {
        setState(() => _busy = false);
        _snack('Enter a folder path.');
        return;
      }
      if (Platform.isAndroid && !_granted) {
        final st = await Permission.manageExternalStorage.request();
        _granted = st.isGranted;
        if (!mounted) return;
        if (!_granted) {
          setState(() => _busy = false);
          _snack('All-files access is required to read this folder.');
          return;
        }
      }
    } else if (_type == 'webdav') {
      if (_davUrl.text.trim().isEmpty || _davPath.text.trim().isEmpty) {
        setState(() => _busy = false);
        _snack('WebDAV needs a server URL and a folder path.');
        return;
      }
    } else if (_type == 'smb') {
      if (_smbHost.text.trim().isEmpty || _smbPath.text.trim().isEmpty) {
        setState(() => _busy = false);
        _snack('SMB needs a host and a share path (e.g. /photo/family).');
        return;
      }
    }

    await s.setSourceType(_type);
    await s.setSourceFolder(_localPath.text.trim());
    await s.setWebdavUrl(_davUrl.text.trim());
    await s.setWebdavUser(_davUser.text.trim());
    await s.setWebdavPass(_davPass.text);
    await s.setWebdavPath(_davPath.text.trim());
    await s.setSmbHost(_smbHost.text.trim());
    await s.setSmbDomain(_smbDomain.text.trim());
    await s.setSmbUser(_smbUser.text.trim());
    await s.setSmbPass(_smbPass.text);
    await s.setSmbPath(_smbPath.text.trim());
    await s.setSetupMode(false);
    // The app root rebuilds into the slideshow.
  }

  InputDecoration _dec(String label, String hint) => InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Column(
                        children: [
                          const Icon(Icons.photo_library_outlined, size: 52),
                          const SizedBox(height: 12),
                          Text('HearthFrame',
                              style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 6),
                          const Text(
                            'Turn this device into a family photo frame.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: _dec('Photo source', ''),
                      items: const [
                        DropdownMenuItem(
                            value: 'local', child: Text('Local folder')),
                        DropdownMenuItem(
                            value: 'webdav', child: Text('WebDAV (NAS)')),
                        DropdownMenuItem(
                            value: 'smb', child: Text('SMB / CIFS (NAS)')),
                      ],
                      onChanged: (v) => setState(() => _type = v ?? 'local'),
                    ),
                    const SizedBox(height: 20),
                    if (_type == 'local') ...[
                      if (Platform.isAndroid) ...[
                        Row(
                          children: [
                            Icon(
                              _granted
                                  ? Icons.check_circle
                                  : Icons.info_outline,
                              color: _granted
                                  ? Colors.greenAccent
                                  : Colors.white70,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(_granted
                                  ? 'All-files access granted'
                                  : 'Needs all-files access'),
                            ),
                            if (!_granted)
                              TextButton(
                                onPressed: _requestPerm,
                                child: const Text('Grant'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: _localPath,
                        decoration:
                            _dec('Folder path', '/storage/emulated/0/Pictures'),
                      ),
                    ] else if (_type == 'webdav') ...[
                      TextField(
                        controller: _davUrl,
                        decoration:
                            _dec('Server URL', 'http://192.168.1.5:5005'),
                        keyboardType: TextInputType.url,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _davUser,
                        decoration: _dec('Username', 'username'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _davPass,
                        decoration: _dec('Password', 'password'),
                        obscureText: true,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _davPath,
                        decoration: _dec('Folder path', '/photo/family'),
                      ),
                    ] else ...[
                      TextField(
                        controller: _smbHost,
                        decoration: _dec('Host', '192.168.1.5'),
                        keyboardType: TextInputType.url,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _smbUser,
                        decoration: _dec('Username', 'username'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _smbPass,
                        decoration: _dec('Password', 'password'),
                        obscureText: true,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _smbDomain,
                        decoration: _dec('Domain (optional)', 'WORKGROUP'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _smbPath,
                        decoration: _dec('Share path', '/photo/family'),
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Text(
                      'Photos and short videos are played full-screen. '
                      'Network sources are cached on device as they play.',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _start,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(_busy ? 'Starting…' : 'Start photo frame'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen always-on slideshow with tap-to-reveal controls.
class SlideshowScreen extends StatefulWidget {
  const SlideshowScreen({super.key, required this.settings});
  final FrameSettings settings;

  @override
  State<SlideshowScreen> createState() => _SlideshowScreenState();
}

class _SlideshowScreenState extends State<SlideshowScreen> {
  FrameSettings get s => widget.settings;

  PhotoSource? _source;
  List<MediaItem> _items = [];
  int _index = 0;
  MediaItem? _current;
  bool _loading = false;
  String? _error;
  Timer? _timer;
  Timer? _controlsTimer;
  bool _showControls = false;
  bool _paused = false;

  /// Tap reveals the control bar; it auto-hides after a few seconds so the
  /// frame returns to a clean full-screen photo.
  void _toggleControls() {
    _controlsTimer?.cancel();
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _controlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _showControls = false);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // Immersive frame mode: hide status & navigation bars; a transient
    // swipe shows them briefly and they auto-hide again (sticky).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _load();
    _applyWakelock();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controlsTimer?.cancel();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    final src = _source;
    if (src is NetworkSource) src.close();
    super.dispose();
  }

  Future<void> _applyWakelock() async {
    if (s.keepAwake) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
  }

  PhotoSource _buildSource() {
    switch (s.sourceType) {
      case 'webdav':
        return WebDavSource(
          url: s.webdavUrl,
          user: s.webdavUser,
          password: s.webdavPass,
          rootPath: s.webdavPath,
        );
      case 'smb':
        return SmbSource(
          host: s.smbHost,
          domain: s.smbDomain,
          user: s.smbUser,
          password: s.smbPass,
          rootPath: s.smbPath,
        );
      default:
        return LocalFolderSource(s.sourceFolder);
    }
  }

  Future<void> _load() async {
    final src = _buildSource();
    _source = src;
    setState(() {
      _loading = true;
      _error = null;
      _current = null;
      _items = [];
      _index = 0;
    });

    // Instant start from the persisted index of the last full scan.
    final indexFile = await _indexFile();
    final cached = await _readIndex(indexFile);
    if (!mounted) return;
    if (cached.isNotEmpty) {
      _items = cached;
      if (s.shuffle) _items.shuffle(Random());
      setState(() => _loading = false);
      await _showIndex();
      _restartTimer();
    }

    // (Re)scan in the background, emitting per-directory batches so the
    // first photo appears as soon as the first folder is read.
    final fresh = <MediaItem>[];
    try {
      await src.discover((batch) {
        fresh.addAll(batch);
        if (!mounted) return;
        if (_items.isEmpty) {
          _items = List.of(batch);
          if (s.shuffle) _items.shuffle(Random());
          _index = 0;
          setState(() => _loading = false);
          _showIndex();
          _restartTimer();
        } else {
          final known = _items.map((e) => e.path).toSet();
          final add = batch.where((e) => !known.contains(e.path)).toList();
          // Refresh remote metadata of known items so stale caches get
          // re-validated even when the instant-start index predates it.
          final meta = {for (final e in batch) e.path: e};
          setState(() {
            _items = [
              for (final it in _items)
                meta[it.path] != null
                    ? MediaItem(it.path,
                        isVideo: it.isVideo,
                        size: meta[it.path]!.size,
                        mtime: meta[it.path]!.mtime)
                    : it,
            ];
            if (add.isNotEmpty) _items.addAll(add);
          });
        }
      });
      if (!mounted) return;
      // Drop ghosts: items deleted on the remote since the last scan must
      // not keep sliding from the local cache forever.
      final live = fresh.map((e) => e.path).toSet();
      final curRemote = _items.isNotEmpty ? _items[_index].path : null;
      setState(() {
        _items.removeWhere((e) => !live.contains(e.path));
        if (_index >= _items.length) _index = 0;
      });
      if (curRemote != null && !live.contains(curRemote) && _items.isNotEmpty) {
        await _showIndex();
      }
      if (fresh.isEmpty && _items.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'No photos or videos found in this source.';
        });
      } else {
        await _writeIndex(indexFile, fresh);
      }
    } catch (e) {
      if (!mounted) return;
      if (_items.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Could not load this source.\n$e';
        });
      }
    }
  }

  /// Stable signature of the active source, used to key the index cache.
  String _sourceSig() {
    final str = switch (s.sourceType) {
      'smb' => 'smb|${s.smbHost}|${s.smbUser}|${s.smbPath}',
      'webdav' => 'dav|${s.webdavUrl}|${s.webdavUser}|${s.webdavPath}',
      _ => 'local|${s.sourceFolder}',
    };
    var h = 0x811c9dc5;
    for (final c in str.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }

  Future<File> _indexFile() async {
    final d = await getApplicationSupportDirectory();
    return File('${d.path}/media_index_${_sourceSig()}.json');
  }

  Future<List<MediaItem>> _readIndex(File f) async {
    try {
      if (!await f.exists()) return [];
      final raw = jsonDecode(await f.readAsString()) as List;
      final seen = <String>{};
      return [
        for (final e in raw)
          if (seen.add(e[0] as String))
            MediaItem(e[0] as String,
                isVideo: e[1] == 1,
                size: e.length > 2 ? e[2] as int? : null,
                mtime: e.length > 3 ? e[3] as int? : null),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeIndex(File f, List<MediaItem> items) async {
    try {
      await f.writeAsString(jsonEncode([
        for (final i in items) [i.path, i.isVideo ? 1 : 0, i.size, i.mtime],
      ]));
    } catch (_) {}
  }

  Future<void> _showIndex() async {
    if (_items.isEmpty) return;
    final item = _items[_index];
    final src = _source;
    if (src is NetworkSource) {
      if (mounted) setState(() => _loading = true);
      try {
        final prepared = await src.prepare(item);
        if (!mounted) return;
        setState(() {
          _current = prepared;
          _loading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _loading = false);
        _advance(); // skip an unreadable item
        return;
      }
    } else {
      if (mounted) {
        setState(() {
          _current = item;
          _loading = false;
        });
      }
    }
    _prefetchNext();
  }

  void _prefetchNext() {
    final src = _source;
    if (src is NetworkSource && _items.length > 1) {
      final next = _items[(_index + 1) % _items.length];
      src.prepare(next).catchError((Object _) => next);
    }
  }

  void _advance() {
    if (!mounted || _items.isEmpty) return;
    setState(() => _index = (_index + 1) % _items.length);
    _showIndex();
  }

  void _next() {
    _advance();
    _restartTimer();
  }

  void _previous() {
    if (!mounted || _items.isEmpty) return;
    setState(() => _index = (_index - 1) % _items.length);
    _showIndex();
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: s.intervalSeconds), (_) {
      if (_paused || _items.isEmpty || _loading) return;
      // Videos advance on completion, not on the photo timer.
      if (_items[_index].isVideo) return;
      _advance();
    });
  }

  Future<void> _changeSource() async {
    await s.setSetupMode(true);
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14181A),
      isScrollControlled: true,
      builder: (_) => SettingsSheet(
        settings: s,
        onChanged: (_) {
          _restartTimer();
          _applyWakelock();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        // Letterboxed videos leave empty side areas; without opaque behavior
        // taps/swipes there would fall through and do nothing.
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -200) {
            _next(); // frame convention: swipe left to advance
          } else if (v > 200) {
            _previous(); // swipe right: previous
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off, size: 48),
                      const SizedBox(height: 16),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _changeSource,
                            icon: const Icon(Icons.tune),
                            label: const Text('Change source'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else if (_current != null)
              AnimatedSwitcher(
                duration: Duration(milliseconds: s.transitionMs),
                child: _MediaView(
                  key: ValueKey(_current!.path),
                  item: _current!,
                  paused: _paused,
                  fill: s.fillScreen,
                  motion: s.motion,
                  onCompleted: _advance,
                ),
              ),
            if (_loading && _current == null && _error == null)
              const Center(child: CircularProgressIndicator()),
            if (s.showClock) const _ClockOverlay(),
            if (_showControls)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.skip_previous),
                        onPressed: _previous,
                      ),
                      IconButton(
                        icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                        onPressed: () => setState(() => _paused = !_paused),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        onPressed: _next,
                      ),
                      IconButton(
                        icon: const Icon(Icons.folder_open),
                        onPressed: _changeSource,
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _load,
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings),
                        onPressed: _openSettings,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Renders one media item: a still image, or a video that plays once and
/// then signals completion so the slideshow advances.
class _MediaView extends StatefulWidget {
  const _MediaView({
    super.key,
    required this.item,
    required this.paused,
    required this.fill,
    required this.motion,
    required this.onCompleted,
  });
  final MediaItem item;
  final bool paused;
  final bool fill;
  final bool motion;
  final VoidCallback onCompleted;

  @override
  State<_MediaView> createState() => _MediaViewState();
}

class _MediaViewState extends State<_MediaView>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  AnimationController? _kb;
  Alignment _panTarget = Alignment.center;
  bool _failed = false;
  bool _completed = false;
  bool _decodeFailed = false;
  String? _displayPath;

  @override
  void initState() {
    super.initState();
    if (widget.item.isVideo) {
      _initVideo();
    } else {
      // Non-HEIC can render immediately; HEIC waits for the platform
      // conversion so we never try (and fail) to decode the raw HEIC.
      if (!isHeicPath(widget.item.path)) _displayPath = widget.item.path;
      _resolveImage();
      if (widget.motion) {
        // Gentle Ken Burns zoom/pan; the drift direction varies per photo.
        const targets = [
          Alignment(0.5, -0.4),
          Alignment(-0.5, 0.4),
          Alignment(0.4, 0.5),
          Alignment(-0.4, -0.5),
        ];
        _panTarget = targets[widget.item.path.hashCode % targets.length];
        _kb = AnimationController(
            vsync: this, duration: const Duration(seconds: 12));
        if (!widget.paused) _kb!.forward();
      }
    }
  }

  /// Wraps a full-bleed photo in a slow zoom + drift (Ken Burns), the
  /// signature photo-frame motion. Clipped so the zoom never overflows.
  Widget _kenBurns(Widget child) {
    final c = _kb;
    if (!widget.motion || c == null) return child;
    return ClipRect(
      child: AnimatedBuilder(
        animation: c,
        builder: (_, __) {
          final t = Curves.easeInOut.transform(c.value);
          return Transform.scale(
            scale: 1.0 + 0.10 * t,
            alignment: Alignment.lerp(Alignment.center, _panTarget, t)!,
            child: child,
          );
        },
      ),
    );
  }

  Future<void> _resolveImage() async {
    // HEIC/HEIF get converted to a cached JPEG by the platform decoder;
    // everything else passes through. EXIF orientation is applied by the
    // engine's image decoder itself, so the frame must NOT rotate again —
    // doing both turns a 90° EXIF photo into 180° (upside down).
    final p = await decodablePath(widget.item.path);
    if (!mounted) return;
    setState(() {
      _displayPath = p;
    });
  }

  /// A decode failure means the cached bytes are bad (truncated download or
  /// unsupported codec). Drop the cache entry and move on so one bad file
  /// never wedges the slideshow on a broken-image icon.
  void _onDecodeError() {
    if (_decodeFailed) return;
    _decodeFailed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final p = _displayPath ?? widget.item.path;
      if (p.contains('hearthframe_cache')) {
        try {
          await File(p).delete();
        } catch (_) {}
      }
      widget.onCompleted();
    });
  }

  Future<void> _initVideo() async {
    final c = VideoPlayerController.file(File(widget.item.path));
    _controller = c;
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(_onTick);
      setState(() {});
      if (!widget.paused) await c.play();
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) widget.onCompleted();
      });
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null || _completed) return;
    final v = c.value;
    if (v.isInitialized &&
        v.duration > Duration.zero &&
        !v.isPlaying &&
        v.position >= v.duration - const Duration(milliseconds: 300)) {
      _completed = true;
      widget.onCompleted();
    }
  }

  @override
  void didUpdateWidget(covariant _MediaView old) {
    super.didUpdateWidget(old);
    final kb = _kb;
    if (kb != null) {
      if (widget.paused) {
        kb.stop();
      } else if (!kb.isAnimating) {
        kb.forward();
      }
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized || _completed) return;
    if (widget.paused && c.value.isPlaying) {
      c.pause();
    } else if (!widget.paused && !c.value.isPlaying) {
      c.play();
    }
  }

  @override
  void dispose() {
    _kb?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.item.isVideo) {
      // HEIC still converting: hold a placeholder rather than decode raw.
      if (_displayPath == null) {
        return const Center(child: CircularProgressIndicator());
      }
      final file = File(_displayPath ?? widget.item.path);
      // Bound the decoded bitmap to the panel's pixel size so a huge
      // panorama/DSLR JPEG can't exhaust memory and fail to decode.
      final mq = MediaQuery.of(context);
      final decodeWidth =
          (mq.size.longestSide * mq.devicePixelRatio).round().clamp(64, 4096);
      Widget raw = Image.file(
        file,
        cacheWidth: decodeWidth,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) {
          _onDecodeError();
          return const Center(child: Icon(Icons.broken_image, size: 48));
        },
      );
      // The engine already applies EXIF orientation to the decoded bitmap,
      // so `raw` is upright before fitting; cover-fitting it fills the panel.
      if (widget.fill) {
        // AnimatedSwitcher hands down LOOSE constraints; without tightening
        // them a FittedBox(cover) self-sizes to the child's aspect ratio and
        // degenerates into contain (side letterboxes). Force full bleed.
        return SizedBox.expand(
          child: _kenBurns(
            ClipRect(child: FittedBox(fit: BoxFit.cover, child: raw)),
          ),
        );
      }
      // Fit mode: whole photo over a blurred, dimmed copy of itself.
      return Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Image.file(
              file,
              fit: BoxFit.cover,
              cacheWidth: 48,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          Container(color: Colors.black.withValues(alpha: 0.35)),
          Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: Image.file(
                file,
                cacheWidth: decodeWidth,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) {
                  _onDecodeError();
                  return const Icon(Icons.broken_image, size: 48);
                },
              ),
            ),
          ),
        ],
      );
    }
    final c = _controller;
    if (_failed) {
      return const Center(child: Icon(Icons.broken_image, size: 48));
    }
    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio,
        child: VideoPlayer(c),
      ),
    );
  }
}

class _ClockOverlay extends StatelessWidget {
  const _ClockOverlay();
  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 24,
      left: 24,
      child: StreamBuilder(
        stream:
            Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
        builder: (_, snap) {
          final now = snap.data ?? DateTime.now();
          final t = TimeOfDay.fromDateTime(now);
          return Text(
            '${t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod}:${t.minute.toString().padLeft(2, '0')} '
            '${t.period == DayPeriod.am ? 'AM' : 'PM'}',
            style:
                const TextStyle(fontSize: 28, color: Colors.white70, shadows: [
              Shadow(blurRadius: 8, color: Colors.black54),
            ]),
          );
        },
      ),
    );
  }
}

/// The "core + useful" settings sheet.
class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key, required this.settings, this.onChanged});
  final FrameSettings settings;
  final ValueChanged<FrameSettings>? onChanged;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (_, __) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('Slide duration: ${settings.intervalSeconds}s'),
            Slider(
              value: settings.intervalSeconds.toDouble(),
              min: 3,
              max: 60,
              divisions: 57,
              onChanged: (v) async {
                await settings.setIntervalSeconds(v.round());
                onChanged?.call(settings);
              },
            ),
            Text('Transition: ${settings.transitionMs}ms'),
            Slider(
              value: settings.transitionMs.toDouble(),
              min: 0,
              max: 2000,
              divisions: 40,
              onChanged: (v) async {
                await settings.setTransitionMs(v.round());
                onChanged?.call(settings);
              },
            ),
            SwitchListTile(
              title: const Text('Shuffle'),
              value: settings.shuffle,
              onChanged: (v) async {
                await settings.setShuffle(v);
                onChanged?.call(settings);
              },
            ),
            SwitchListTile(
              title: const Text('Show clock'),
              value: settings.showClock,
              onChanged: (v) async {
                await settings.setShowClock(v);
                onChanged?.call(settings);
              },
            ),
            SwitchListTile(
              title: const Text('Keep screen on'),
              value: settings.keepAwake,
              onChanged: (v) async {
                await settings.setKeepAwake(v);
                onChanged?.call(settings);
              },
            ),
            SwitchListTile(
              title: const Text('Fill screen'),
              subtitle: const Text(
                  'Crop photos to the edges; off shows the whole photo over a blurred backdrop.'),
              value: settings.fillScreen,
              onChanged: (v) async {
                await settings.setFillScreen(v);
                onChanged?.call(settings);
              },
            ),
            SwitchListTile(
              title: const Text('Motion effect'),
              subtitle: const Text(
                  'Slow Ken Burns zoom & pan on photos, like a living frame.'),
              value: settings.motion,
              onChanged: (v) async {
                await settings.setMotion(v);
                onChanged?.call(settings);
              },
            ),
          ],
        ),
      ),
    );
  }
}
