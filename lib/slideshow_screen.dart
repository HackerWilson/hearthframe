import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'clock_overlay.dart';
import 'controls_bar.dart';
import 'l10n.dart';
import 'media_cache.dart';
import 'media_details.dart';
import 'media_order.dart';
import 'media_view.dart';
import 'nas_sources.dart';
import 'settings.dart';
import 'settings_sheet.dart';
import 'sources.dart';

/// Full-screen frame: media, clock, a hint on first run and a control pill.
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
  String? _errorKey; // 'empty' or 'load'
  String? _errorDetail;
  Timer? _timer;
  Timer? _controlsTimer;
  Timer? _hintTimer;
  Timer? _downloadHintTimer;
  bool _downloadHintVisible = false;
  bool _showControls = false;
  bool _paused = false;
  bool _hintVisible = false;
  bool _controlsHovered = false;
  bool _settingsOpen = false;
  int _loadGeneration = 0;
  int _showRequest = 0;
  int _displayRevision = 0;
  int _consecutiveFailures = 0;
  int _playbackFailures = 0;
  MediaDownload? _download;
  MediaDownload? _prefetch;
  MediaItem? _loadingItem;
  String? _prefetchPath;
  bool _mediaInteracting = false;
  late bool _lastShuffle;
  late bool _lastRecentWeighted;

  /// How long the pill stays visible without interaction. Long enough to move
  /// a mouse to it on a desktop (ChromeOS) and to survive a screenshot-then-tap
  /// workflow; hovering or pressing pauses the countdown entirely.
  static const _controlsHideDelay = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _lastShuffle = s.shuffle;
    _lastRecentWeighted = s.recentWeighted;
    s.addListener(_onSettingsChanged);
    // Immersive frame mode: hide status & navigation bars; a transient swipe
    // shows them briefly and they auto-hide again (sticky).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _load();
    _applyWakelock();
    _maybeShowHint();
  }

  @override
  void dispose() {
    s.removeListener(_onSettingsChanged);
    _timer?.cancel();
    _controlsTimer?.cancel();
    _hintTimer?.cancel();
    _downloadHintTimer?.cancel();
    _download?.cancel();
    _prefetch?.cancel();
    WakelockPlus.disable();
    _screenChannel.invokeMethod<void>(
        'setKeepOn', {'enabled': false}).catchError((Object _) {});
    activeMediaPath = null;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    final src = _source;
    if (src is NetworkSource) src.close();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    final orderChanged =
        _lastShuffle != s.shuffle || _lastRecentWeighted != s.recentWeighted;
    _lastShuffle = s.shuffle;
    _lastRecentWeighted = s.recentWeighted;
    setState(() {
      if (orderChanged) _reorderKeepingCurrent();
    });
    if (orderChanged) {
      _prefetchNext();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(AppStrings.of(context).mediaOrderUpdated),
          duration: const Duration(seconds: 2),
        ));
    }
    _applyWakelock();
    _restartTimer();
  }

  static const _screenChannel = MethodChannel('hearthframe/screen');

  Future<void> _applyWakelock() async {
    if (s.keepAwake) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
    // Belt-and-braces for OEMs that drop the window KEEP_SCREEN_ON flag on
    // pause/resume: a native screen-bright wake lock while the frame is
    // resumed. Respects the same "Keep screen on" setting.
    try {
      await _screenChannel.invokeMethod<void>(
        'setKeepOn',
        {'enabled': s.keepAwake},
      );
    } catch (_) {}
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
    final generation = ++_loadGeneration;
    ++_showRequest;
    _timer?.cancel();
    _download?.cancel();
    _prefetch?.cancel();
    _download = null;
    _prefetch = null;
    _prefetchPath = null;
    _loadingItem = null;
    _consecutiveFailures = 0;
    _playbackFailures = 0;
    final old = _source;
    if (old is NetworkSource) {
      old.close();
    }
    final src = _buildSource();
    _source = src;
    _controlsTimer?.cancel();
    setState(() {
      _loading = true;
      _errorKey = null;
      _errorDetail = null;
      _current = null;
      _items = [];
      _index = 0;
      _showControls = false;
    });
    activeMediaPath = null;

    // Instant start from the persisted index of the last full scan.
    final indexFile = await _indexFile();
    final cached = await _readIndex(indexFile);
    if (!mounted || generation != _loadGeneration) return;
    if (cached.isNotEmpty) {
      _items = cached;
      _shuffleItems();
      _index = _quickStartIndex(_items);
      setState(() => _loading = false);
      await _showIndex();
      if (!mounted || generation != _loadGeneration) return;
      _restartTimer();
    }

    // (Re)scan in the background, emitting per-directory batches so the
    // first photo appears as soon as the first folder is read.
    final fresh = <MediaItem>[];
    final scanWatch = Stopwatch()..start();
    try {
      await src.discover((batch) {
        if (!mounted || generation != _loadGeneration) return;
        fresh.addAll(batch);
        if (_items.isEmpty) {
          _items = List.of(batch);
          _shuffleItems();
          _index = _quickStartIndex(_items);
          setState(() => _loading = false);
          _showIndex();
          _restartTimer();
          debugPrint('HF scan first batch=${batch.length} '
              'videos=${batch.where((e) => e.isVideo).length} '
              'after ${scanWatch.elapsedMilliseconds}ms');
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
                    ? MediaItem(
                        it.path,
                        isVideo: it.isVideo,
                        size: meta[it.path]!.size,
                        mtime: meta[it.path]!.mtime,
                      )
                    : it,
            ];
            if (add.isNotEmpty) _items.addAll(add);
          });
        }
      });
      if (!mounted || generation != _loadGeneration) return;
      debugPrint('HF scan done items=${fresh.length} '
          'in ${scanWatch.elapsedMilliseconds}ms');
      // Drop ghosts: items deleted on the remote since the last scan must
      // not keep sliding from the local cache forever.
      final live = fresh.map((e) => e.path).toSet();
      final currentPath = _items.isNotEmpty ? _items[_index].path : null;
      setState(() {
        _items.removeWhere((e) => !live.contains(e.path));
        final retained = _items.indexWhere((e) => e.path == currentPath);
        _index = retained < 0 ? 0 : retained;
        _reorderKeepingCurrent();
      });
      _prefetchNext();
      if (currentPath != null &&
          !live.contains(currentPath) &&
          _items.isNotEmpty) {
        await _showIndex();
      }
      if (!mounted || generation != _loadGeneration) return;
      if (fresh.isEmpty && _items.isEmpty) {
        ++_showRequest;
        _download?.cancel();
        _prefetch?.cancel();
        _download = null;
        _prefetch = null;
        _prefetchPath = null;
        _loadingItem = null;
        activeMediaPath = null;
        setState(() {
          _current = null;
          _loading = false;
          _errorKey = 'empty';
        });
      } else {
        await _writeIndex(indexFile, fresh);
      }
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      if (_items.isEmpty) {
        setState(() {
          _loading = false;
          _errorKey = 'load';
          _errorDetail = e.toString();
        });
      }
    }
  }

  void _shuffleItems() {
    _items = orderMedia(_items,
        shuffle: s.shuffle, recentWeighted: s.recentWeighted);
  }

  void _reorderKeepingCurrent() {
    if (_items.isEmpty) return;
    final path = _items[_index].path;
    _shuffleItems();
    _index = _items.indexWhere((item) => item.path == path);
    if (s.shuffle && _index > 0) {
      final current = _items.removeAt(_index);
      _items.insert(0, current);
      _index = 0;
    }
  }

  /// The first scan entry is often a large video; waiting for the whole file
  /// would leave the frame black for minutes on a fresh install. Start on the
  /// first still so the frame lights up immediately — videos keep their slots
  /// and play normally when the slideshow reaches them.
  int _quickStartIndex(List<MediaItem> items) {
    final firstImage = items.indexWhere((e) => !e.isVideo);
    return firstImage < 0 ? 0 : firstImage;
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
            MediaItem(
              e[0] as String,
              isVideo: e[1] == 1,
              size: e.length > 2 ? e[2] as int? : null,
              mtime: e.length > 3 ? e[3] as int? : null,
            ),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeIndex(File f, List<MediaItem> items) async {
    try {
      await f.writeAsString(
        jsonEncode([
          for (final i in items) [i.path, i.isVideo ? 1 : 0, i.size, i.mtime],
        ]),
      );
    } catch (_) {}
  }

  Future<void> _showIndex() async {
    final request = ++_showRequest;
    if (!mounted || _items.isEmpty || _errorKey != null) return;
    _timer?.cancel();
    _downloadHintTimer?.cancel();
    _downloadHintVisible = false;
    _mediaInteracting = false;
    _scheduleHideControls();
    final item = _items[_index];
    final src = _source;
    if (_loadingItem?.path != item.path) _download?.cancel();
    if (_prefetchPath != item.path) _prefetch?.cancel();
    _prefetch = null;
    _prefetchPath = null;
    if (src is NetworkSource) {
      final download = src.download(item);
      setState(() {
        _loading = true;
        _loadingItem = item;
        _download = download;
      });
      _downloadHintTimer = Timer(const Duration(milliseconds: 350), () {
        if (mounted && request == _showRequest && _loading) {
          setState(() => _downloadHintVisible = true);
        }
      });
      debugPrint('HF show ${item.isVideo ? 'video' : 'image'} ${item.path}');
      try {
        final prepared = await download.result;
        if (!mounted || request != _showRequest) return;
        activeMediaPath = prepared.path;
        _consecutiveFailures = 0;
        _playbackFailures = 0;
        setState(() {
          _current = prepared;
          _displayRevision++;
          _loading = false;
          _loadingItem = null;
          _download = null;
        });
      } on DownloadCancelled {
        return;
      } catch (error) {
        if (!mounted || request != _showRequest) return;
        debugPrint('HF prepare failed ${item.path}: $error');
        _consecutiveFailures++;
        final exhausted = _consecutiveFailures >= _items.length;
        setState(() {
          _loading = false;
          _loadingItem = null;
          _download = null;
          if (exhausted) {
            _current = null;
            _errorKey = 'load';
            _errorDetail = error.toString();
          }
        });
        if (exhausted) {
          activeMediaPath = null;
          _timer?.cancel();
          _prefetch?.cancel();
          return;
        }
        _advance();
        return;
      }
    } else {
      activeMediaPath = null;
      setState(() {
        _current = item;
        _displayRevision++;
        _loading = false;
        _loadingItem = null;
        _download = null;
      });
    }
    _restartTimer();
    _prefetchNext();
  }

  void _prefetchNext() {
    final src = _source;
    if (src is! NetworkSource || _items.length < 2) {
      _prefetch?.cancel();
      _prefetch = null;
      _prefetchPath = null;
      return;
    }
    if (_loading || _errorKey != null) return;
    final next = _items[(_index + 1) % _items.length];
    if (_prefetchPath == next.path) return;
    _prefetch?.cancel();
    _prefetchPath = next.path;
    _prefetch = src.download(next);
    _prefetch!.result.catchError((Object _) => next);
  }

  void _advance() {
    if (!mounted || _items.isEmpty || _errorKey != null) return;
    setState(() {
      if (s.shuffle && _index == _items.length - 1 && _items.length > 1) {
        final previous = _items[_index].path;
        _shuffleItems();
        if (_items.first.path == previous) _items.add(_items.removeAt(0));
        _index = 0;
      } else {
        _index = (_index + 1) % _items.length;
      }
    });
    _showIndex();
    _restartTimer();
  }

  void _next() {
    _consecutiveFailures = 0;
    _playbackFailures = 0;
    _errorKey = null;
    _dismissHint();
    _advance();
    _showControlsBriefly();
  }

  void _previous() {
    if (!mounted || _items.isEmpty) return;
    _consecutiveFailures = 0;
    _playbackFailures = 0;
    _errorKey = null;
    _dismissHint();
    setState(() => _index = (_index - 1) % _items.length);
    _showIndex();
    _restartTimer();
    _showControlsBriefly();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (_paused || _settingsOpen || _errorKey != null) return;
    _timer = Timer.periodic(Duration(seconds: s.intervalSeconds), (_) {
      if (_paused || _items.isEmpty || _loading) return;
      // Videos advance on completion, not on the photo timer.
      if (_items[_index].isVideo) return;
      _advance();
    });
  }

  void _showControlsBriefly() {
    _controlsTimer?.cancel();
    if (!_showControls) setState(() => _showControls = true);
    _scheduleHideControls();
  }

  void _scheduleHideControls() {
    _controlsTimer?.cancel();
    if (!_showControls || _paused || _controlsHovered || _mediaInteracting) {
      return;
    }
    _controlsTimer = Timer(_controlsHideDelay, () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _onControlsHoverChanged(bool hovering) {
    _controlsHovered = hovering;
    if (hovering) {
      _controlsTimer?.cancel();
    } else {
      _scheduleHideControls();
    }
  }

  void _onMediaInteractionChanged(bool interacting) {
    _mediaInteracting = interacting;
    if (interacting) {
      _controlsTimer?.cancel();
    } else {
      _scheduleHideControls();
    }
  }

  void _onControlsPressChanged(bool pressed) {
    if (pressed) {
      _controlsTimer?.cancel();
    } else {
      _scheduleHideControls();
    }
  }

  void _toggleControls({bool force = false}) {
    _dismissHint();
    if (force) {
      _showControlsBriefly();
      return;
    }
    _controlsTimer?.cancel();
    setState(() => _showControls = !_showControls);
    _scheduleHideControls();
  }

  void _togglePause() {
    _controlsTimer?.cancel();
    setState(() {
      _paused = !_paused;
      _showControls = true;
    });
    if (_paused) {
      _timer?.cancel();
    } else {
      _restartTimer();
      _scheduleHideControls();
    }
  }

  void _maybeShowHint() {
    if (s.seenHint) return;
    _hintVisible = true;
    _hintTimer = Timer(const Duration(seconds: 6), _dismissHint);
  }

  void _dismissHint() {
    _hintTimer?.cancel();
    if (_hintVisible) {
      _hintVisible = false;
      if (mounted) setState(() {});
    }
    if (!s.seenHint) s.setSeenHint(true);
  }

  Future<void> _changeSource() async {
    _dismissHint();
    await s.setSetupMode(true);
  }

  Future<void> _openSettings() async {
    _dismissHint();
    _timer?.cancel();
    _controlsTimer?.cancel();
    setState(() => _settingsOpen = true);
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 760),
          child: SizedBox.expand(child: SettingsSheet(settings: s)),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _settingsOpen = false);
    _restartTimer();
    _showControlsBriefly();
  }

  Future<void> _openDetails() async {
    final item = _current;
    if (item == null) return;
    _timer?.cancel();
    _controlsTimer?.cancel();
    setState(() => _settingsOpen = true);
    final strings = AppStrings.of(context);
    final sourceLabel = switch (s.sourceType) {
      'smb' => strings.smb,
      'webdav' => strings.webdav,
      _ => strings.localFolder,
    };
    await showDialog<void>(
      context: context,
      builder: (_) => MediaDetailsSheet(item: item, sourceLabel: sourceLabel),
    );
    if (!mounted) return;
    setState(() => _settingsOpen = false);
    _restartTimer();
    _showControlsBriefly();
  }

  Widget _transition(Widget child, Animation<double> animation) {
    switch (s.transitionStyle) {
      case 'slide':
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: animation, child: child),
        );
      case 'zoom':
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 1.04, end: 1).animate(curved),
          child: FadeTransition(opacity: animation, child: child),
        );
      default:
        return FadeTransition(opacity: animation, child: child);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final displayedRevision = _displayRevision;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _previous,
        const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
        const SingleActivator(LogicalKeyboardKey.space): _togglePause,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _toggleControls(force: true),
      },
      child: Focus(
        autofocus: true,
        includeSemantics: false,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _toggleControls(force: true);
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                // Gesture layer: only the media and its scrims. The clock, hint,
                // error card and control pill are siblings above it so a tap on a
                // button never races the full-screen tap handler.
                GestureDetector(
                  // Letterboxed videos leave empty side areas; without opaque
                  // behavior taps/swipes there would fall through and do nothing.
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  onHorizontalDragEnd: (details) {
                    final v = details.primaryVelocity ?? 0;
                    if (v < -200) {
                      _next(); // frame convention: swipe left to advance
                    } else if (v > 200) {
                      _previous(); // swipe right to go back
                    }
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_current != null)
                        AnimatedSwitcher(
                          duration: Duration(milliseconds: s.transitionMs),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: _transition,
                          child: MediaView(
                            key: ValueKey(_displayRevision),
                            item: _current!,
                            paused: _paused || _settingsOpen || _loading,
                            showDate: s.showMediaDate,
                            controlsVisible: _showControls && !_loading,
                            onInteractionChanged: (interacting) {
                              if (_displayRevision == displayedRevision) {
                                _onMediaInteractionChanged(interacting);
                              }
                            },
                            onFailed: () {
                              if (_displayRevision != displayedRevision) return;
                              _playbackFailures++;
                              if (_playbackFailures < _items.length) return;
                              _timer?.cancel();
                              _prefetch?.cancel();
                              activeMediaPath = null;
                              setState(() {
                                _current = null;
                                _errorKey = 'load';
                                _errorDetail =
                                    AppStrings.of(context).videoUnavailable;
                              });
                            },
                            fill: s.fillScreen,
                            motion: s.motion,
                            motionSpeed: s.motionSpeed,
                            muted: s.videoMuted,
                            onCompleted: () {
                              if (_displayRevision == displayedRevision &&
                                  !_loading) {
                                _advance();
                              }
                            },
                          ),
                        ),
                      // Soft scrims keep the clock and the control pill readable
                      // on bright photos without hiding the picture.
                      IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment.topLeft,
                              radius: 1.15,
                              colors: [
                                Colors.black.withValues(alpha: 0.38),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      IgnorePointer(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            height: 240,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.42),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_errorKey != null && _current == null)
                  _ErrorPanel(
                    title: _errorKey == 'empty'
                        ? strings.noMedia
                        : strings.couldNotLoad,
                    detail: _errorDetail,
                    strings: strings,
                    retry: _load,
                    changeSource: _changeSource,
                  )
                else if (_loading && _current == null && _download == null)
                  _LoadingPanel(text: strings.loading),
                if (_loading &&
                    _downloadHintVisible &&
                    _download != null &&
                    _loadingItem != null)
                  _DownloadPanel(
                    download: _download!,
                    item: _loadingItem!,
                    onSkip: _next,
                  ),
                if (s.showClock)
                  ClockOverlay(
                    format: s.clockFormat,
                    background: s.clockBackground,
                    scale: s.clockScale,
                  ),
                _HintPill(visible: _hintVisible, text: strings.gestureHint),
                SlideshowControls(
                  visible: _showControls,
                  paused: _paused,
                  onHoverChanged: _onControlsHoverChanged,
                  onPressChanged: _onControlsPressChanged,
                  onPrevious: _previous,
                  onPlayPause: _togglePause,
                  onNext: _next,
                  onSource: _changeSource,
                  onRefresh: () {
                    _dismissHint();
                    _load();
                  },
                  onSettings: _openSettings,
                  onDetails: _current == null ? null : _openDetails,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DownloadPanel extends StatelessWidget {
  const _DownloadPanel(
      {required this.download, required this.item, required this.onSkip});

  final MediaDownload download;
  final MediaItem item;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return Positioned(
      top: width >= 700 ? 28 : 190,
      right: 24,
      width: (width - 48).clamp(0, 340),
      child: SafeArea(
        child: Material(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ValueListenableBuilder<DownloadProgress>(
              valueListenable: download.progress,
              builder: (context, progress, _) {
                final total = progress.total;
                final fraction = total != null && total > 0
                    ? (progress.received / total).clamp(0.0, 1.0)
                    : null;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Icon(
                          item.isVideo
                              ? Icons.videocam_outlined
                              : Icons.image_outlined,
                          size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(strings.loadingMedia)),
                      TextButton(
                          onPressed: onSkip, child: Text(strings.skipMedia)),
                    ]),
                    Text(item.path.split('/').last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70)),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: fraction),
                    const SizedBox(height: 8),
                    Text(
                        total == null || total <= 0
                            ? formatBytes(progress.received)
                            : '${formatBytes(progress.received)} / ${formatBytes(total)} · ${(fraction! * 100).round()}%',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _HintPill extends StatelessWidget {
  const _HintPill({required this.visible, required this.text});

  final bool visible;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 112,
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 350),
            opacity: visible ? 1 : 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.swipe_rounded,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 16),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.title,
    this.detail,
    required this.strings,
    required this.retry,
    required this.changeSource,
  });

  final String title;
  final String? detail;
  final AppStrings strings;
  final VoidCallback retry;
  final VoidCallback changeSource;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 44,
                color: Colors.white.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (detail != null) ...[
                const SizedBox(height: 10),
                Text(
                  detail!,
                  textAlign: TextAlign.center,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: retry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(strings.retry),
                  ),
                  OutlinedButton.icon(
                    onPressed: changeSource,
                    icon: const Icon(Icons.tune_rounded),
                    label: Text(strings.changeSource),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
