import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'l10n.dart';
import 'media_date.dart';
import 'platform_image.dart';
import 'sources.dart';
import 'theme.dart';

/// Renders one media item: a still image, or a video that plays once and then
/// signals completion so the slideshow advances.
class MediaView extends StatefulWidget {
  const MediaView({
    super.key,
    required this.item,
    required this.paused,
    required this.fill,
    required this.motion,
    required this.motionSpeed,
    required this.muted,
    required this.onCompleted,
    this.showDate = true,
    this.controlsVisible = false,
    this.onInteractionChanged,
    this.onFailed,
  });

  final MediaItem item;
  final bool paused;
  final bool fill;
  final bool motion;
  final double motionSpeed;
  final bool muted;
  final VoidCallback onCompleted;
  final bool showDate;
  final bool controlsVisible;
  final ValueChanged<bool>? onInteractionChanged;
  final VoidCallback? onFailed;

  @override
  State<MediaView> createState() => _MediaViewState();
}

class _MediaViewState extends State<MediaView>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  AnimationController? _kb;
  Alignment _panTarget = Alignment.center;
  bool _failed = false;
  bool _completed = false;
  bool _completionPending = false;
  bool _completionScheduled = false;
  Timer? _videoInitTimer;
  Timer? _videoFailureTimer;
  bool _decodeFailed = false;
  String? _displayPath;
  DateTime? _mediaDate;
  bool _dateRequested = false;
  final _scrubPosition = ValueNotifier<double?>(null);
  bool _scrubbing = false;
  bool _seeking = false;
  bool _ignoreSeekCompletion = false;
  bool _hoveringProgress = false;
  bool _interacting = false;
  bool _resumeAfterScrub = false;
  int _scrubRevision = 0;
  Future<void>? _scrubPause;

  void _notifyInteraction({bool afterFrame = false}) {
    final active =
        widget.controlsVisible && (_hoveringProgress || _scrubbing || _seeking);
    if (_interacting == active) return;
    _interacting = active;
    if (afterFrame) {
      // Hiding controls can happen in the parent's build. Never ask it to
      // rebuild synchronously, or let an old display clear a new interaction.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _interacting == active) {
          widget.onInteractionChanged?.call(active);
        }
      });
    } else {
      widget.onInteractionChanged?.call(active);
    }
  }

  void _beginScrub(double position) {
    final c = _controller;
    if (c == null ||
        !widget.controlsVisible ||
        !c.value.isInitialized ||
        _completed ||
        _seeking ||
        _scrubbing) {
      return;
    }
    _scrubRevision++;
    _scrubbing = true;
    _ignoreSeekCompletion = false;
    _resumeAfterScrub = c.value.isPlaying;
    _completionPending = false;
    _scrubPosition.value = position;
    // Capture playing state before pause changes the controller's value.
    _scrubPause = c.pause().catchError((Object _) {});
    _notifyInteraction();
  }

  Future<void> _finishScrub(double? position, {bool afterFrame = false}) async {
    if (!_scrubbing) return;
    final c = _controller!;
    final revision = _scrubRevision;
    final resume = _resumeAfterScrub;
    _scrubbing = false;
    _seeking = true;
    _notifyInteraction(afterFrame: afterFrame);
    bool ownsController() =>
        mounted && _controller == c && _scrubRevision == revision;
    try {
      await _scrubPause;
      if (!ownsController()) return;
      if (position != null) {
        // Seeking exactly to duration marks VideoPlayerValue completed and
        // play() would rewind to zero. Stay on the last playable millisecond.
        final end = c.value.duration.inMilliseconds;
        final target = position.round().clamp(0, end > 0 ? end - 1 : 0);
        await c.seekTo(Duration(milliseconds: target));
        if (!ownsController()) return;
      }
      if (resume && !widget.paused && !c.value.isCompleted) {
        await c.play();
        if (!ownsController()) return;
        if (widget.paused) await c.pause();
      }
    } catch (_) {
      // A platform failure is handled by the existing controller listener.
    } finally {
      if (ownsController()) {
        // A native seek can also emit a completed event. Do not let its
        // lingering flag advance the slide on a later volume/settings update.
        _ignoreSeekCompletion = _ignoreSeekCompletion || c.value.isCompleted;
        _seeking = false;
        _scrubPosition.value = null;
        _notifyInteraction(afterFrame: afterFrame);
      }
    }
  }

  Future<void> _resolveDate() async {
    if (_dateRequested || !widget.showDate) return;
    _dateRequested = true;
    final date = await readMediaDate(widget.item);
    if (mounted) setState(() => _mediaDate = date);
  }

  Future<void> _prepareVideo() async {
    await _resolveDate();
    if (mounted) await _initVideo();
  }

  @override
  void initState() {
    super.initState();
    if (widget.item.isVideo) {
      _prepareVideo();
    } else {
      _resolveDate();
      // Non-HEIC can render immediately; HEIC waits for the platform
      // conversion so we never try (and fail) to decode the raw HEIC.
      if (!isHeicPath(widget.item.path)) _displayPath = widget.item.path;
      _resolveImage();
      if (widget.motion) _startKenBurns();
    }
  }

  Duration get _kenBurnsDuration => Duration(
        milliseconds: (12000 / widget.motionSpeed.clamp(0.5, 1.5)).round(),
      );

  /// Gentle Ken Burns zoom/pan; the drift direction varies per photo.
  void _startKenBurns() {
    const targets = [
      Alignment(0.5, -0.4),
      Alignment(-0.5, 0.4),
      Alignment(0.4, 0.5),
      Alignment(-0.4, -0.5),
    ];
    _panTarget = targets[widget.item.path.hashCode % targets.length];
    _kb = AnimationController(vsync: this, duration: _kenBurnsDuration);
    if (!widget.paused) _kb!.forward();
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
    // Unlike Future.timeout, this deadline can be cancelled on disposal.
    _videoInitTimer = Timer(const Duration(seconds: 20), () {
      _failVideo(c, initError: TimeoutException('initialization exceeded 20s'));
    });
    try {
      await c.initialize();
      if (!mounted || _controller != c) return;
      if (c.value.size.isEmpty) {
        throw StateError('No supported video track (${c.value.size})');
      }
      _videoInitTimer?.cancel();
      _videoInitTimer = null;
      c.addListener(_onTick);
      _onTick();
      if (_controller != c || _completionPending || _completed) return;
      await _applyVolume(c);
      // Initialization or volume changes may finish after timeout/disposal.
      if (!mounted || _controller != c || _completionPending || _completed) {
        return;
      }
      debugPrint('HF video ready ${c.value.duration.inMilliseconds}ms '
          '${c.value.size.width.toInt()}x${c.value.size.height.toInt()} '
          '${widget.item.path}');
      setState(() {});
      if (!widget.paused && !c.value.isPlaying) await c.play();
    } catch (error) {
      _failVideo(c, initError: error);
    }
  }

  void _disposeVideo() {
    _scrubRevision++;
    _scrubbing = false;
    _seeking = false;
    _hoveringProgress = false;
    _notifyInteraction(afterFrame: true);
    _videoInitTimer?.cancel();
    _videoInitTimer = null;
    final c = _controller;
    // Relinquish ownership before awaiting disposal, so no path disposes twice.
    _controller = null;
    if (c != null) {
      c.removeListener(_onTick);
      unawaited(c.dispose());
    }
  }

  void _failVideo(VideoPlayerController c, {Object? initError}) {
    if (!mounted || _controller != c) return;
    final error = initError ?? c.value.errorDescription;
    debugPrint('HF video failed ${widget.item.path}: $error');
    _disposeVideo();
    setState(() => _failed = true);
    widget.onFailed?.call();
    _videoFailureTimer = Timer(const Duration(seconds: 2), () {
      _videoFailureTimer = null;
      if (!mounted || _completed) return;
      _completionPending = true;
      _scheduleCompletion();
    });
  }

  void _scheduleCompletion() {
    if (!mounted ||
        widget.paused ||
        _scrubbing ||
        _seeking ||
        !_completionPending ||
        _completed ||
        _completionScheduled) {
      return;
    }
    _completionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _completionScheduled = false;
      // Pause can change between receiving the event and this frame.
      if (!mounted ||
          widget.paused ||
          _scrubbing ||
          _seeking ||
          !_completionPending ||
          _completed) {
        return;
      }
      _completionPending = false;
      _completed = true;
      widget.onCompleted();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _applyVolume(VideoPlayerController c) async {
    try {
      await c.setVolume(widget.muted ? 0 : 1);
    } catch (_) {}
  }

  void _onTick() {
    final c = _controller;
    if (c == null || _completed || _completionPending) return;
    final v = c.value;
    if (_scrubbing || _seeking) {
      if (v.isCompleted) _ignoreSeekCompletion = true;
    } else if (!v.isCompleted && v.isPlaying) {
      _ignoreSeekCompletion = false;
    }
    if (v.hasError) {
      _failVideo(c);
    } else if (v.isInitialized &&
        v.isCompleted &&
        !_scrubbing &&
        !_seeking &&
        !_ignoreSeekCompletion) {
      _completionPending = true;
      _scheduleCompletion();
    }
  }

  @override
  void didUpdateWidget(covariant MediaView old) {
    super.didUpdateWidget(old);
    if (!widget.controlsVisible) {
      _hoveringProgress = false;
      unawaited(_finishScrub(null, afterFrame: true));
      _notifyInteraction(afterFrame: true);
    }
    _resolveDate();
    // Apply a change of the motion setting without reloading the photo.
    if (!widget.item.isVideo) {
      if (widget.motion && _kb == null) {
        _startKenBurns();
      } else if (!widget.motion && _kb != null) {
        _kb!.dispose();
        _kb = null;
      }
    }
    final kb = _kb;
    if (kb != null) {
      if (kb.duration != _kenBurnsDuration) kb.duration = _kenBurnsDuration;
      if (widget.paused) {
        kb.stop();
      } else if (!kb.isAnimating) {
        kb.forward();
      }
    }
    _scheduleCompletion();
    final c = _controller;
    if (c == null ||
        !c.value.isInitialized ||
        _completed ||
        _completionPending) {
      return;
    }
    if (widget.muted != old.muted) _applyVolume(c);
    if (widget.paused && c.value.isPlaying) {
      c.pause();
    } else if (old.paused &&
        !widget.paused &&
        !_scrubbing &&
        !_seeking &&
        !c.value.isPlaying) {
      c.play();
    }
  }

  @override
  void dispose() {
    _kb?.dispose();
    _videoFailureTimer?.cancel();
    _disposeVideo();
    _scrubPosition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final date = _mediaDate;
    final c = _controller;
    final showProgress = widget.item.isVideo &&
        widget.controlsVisible &&
        c != null &&
        c.value.isInitialized;
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildMedia(context),
        if (showProgress) _buildProgress(c),
        if (widget.showDate && date != null)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            left: 32,
            right: 32,
            bottom: showProgress ? 164 : (widget.controlsVisible ? 112 : 28),
            child: IgnorePointer(
              child: SafeArea(
                top: false,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 650),
                    curve: Curves.easeOut,
                    builder: (context, stamp, child) => Opacity(
                      opacity: stamp,
                      child: Transform.scale(
                        scale: 0.96 + 0.04 * stamp,
                        alignment: Alignment.bottomLeft,
                        child: child,
                      ),
                    ),
                    child: Text(
                      MaterialLocalizations.of(context).formatFullDate(date),
                      key: const ValueKey('media-date'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.8,
                        shadows: const [
                          Shadow(
                              color: Colors.black87,
                              blurRadius: 3,
                              offset: Offset(0, 1)),
                          Shadow(color: Colors.black45, blurRadius: 12),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _playbackTime(Duration time) {
    final seconds = time.isNegative ? 0 : time.inSeconds;
    final minutes = (seconds ~/ 60).toString();
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    if (seconds < 3600) return '$minutes:$remainder';
    return '${seconds ~/ 3600}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:$remainder';
  }

  Widget _buildProgress(VideoPlayerController c) => Positioned(
        left: 16,
        right: 16,
        bottom: 104,
        child: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: MouseRegion(
                onEnter: (_) {
                  _hoveringProgress = true;
                  _notifyInteraction();
                },
                onExit: (_) {
                  _hoveringProgress = false;
                  _notifyInteraction();
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Claim the padding and time labels too, not just the slider.
                  onTap: () {},
                  onHorizontalDragStart: (_) {},
                  child: Listener(
                    onPointerCancel: (_) => unawaited(_finishScrub(null)),
                    child: Material(
                      key: const ValueKey('video-progress'),
                      color: Colors.black.withValues(alpha: 0.48),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: ValueListenableBuilder<VideoPlayerValue>(
                          valueListenable: c,
                          builder: (context, value, _) =>
                              ValueListenableBuilder<double?>(
                            valueListenable: _scrubPosition,
                            builder: (context, preview, _) {
                              final end = value.duration.inMilliseconds;
                              final position = (preview ??
                                      value.position.inMilliseconds.toDouble())
                                  .clamp(0.0, end > 0 ? end.toDouble() : 0.0);
                              return Row(
                                children: [
                                  Text(
                                    _playbackTime(Duration(
                                        milliseconds: position.round())),
                                    key: const ValueKey('video-elapsed'),
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12),
                                  ),
                                  Expanded(
                                    child: Semantics(
                                      label:
                                          AppStrings.of(context).videoProgress,
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 3,
                                          trackShape:
                                              const RoundedRectSliderTrackShape(),
                                          activeTrackColor:
                                              HearthPalette.primary,
                                          inactiveTrackColor: Colors.white24,
                                          thumbColor: HearthPalette.primary,
                                          overlayColor: HearthPalette.primary
                                              .withValues(alpha: 0.16),
                                          thumbShape:
                                              const RoundSliderThumbShape(
                                                  enabledThumbRadius: 7),
                                          overlayShape:
                                              const RoundSliderOverlayShape(
                                                  overlayRadius: 16),
                                        ),
                                        child: Slider(
                                          key: const ValueKey('video-seek'),
                                          value: position,
                                          max: end > 0 ? end.toDouble() : 1,
                                          onChangeStart: _beginScrub,
                                          onChanged: end > 0
                                              ? (position) {
                                                  if (_scrubbing) {
                                                    _scrubPosition.value =
                                                        position;
                                                  }
                                                }
                                              : null,
                                          onChangeEnd: (position) =>
                                              unawaited(_finishScrub(position)),
                                          semanticFormatterCallback:
                                              (position) => _playbackTime(
                                                  Duration(
                                                      milliseconds:
                                                          position.round())),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _playbackTime(value.duration),
                                    key: const ValueKey('video-duration'),
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _buildMedia(BuildContext context) {
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
            ClipRect(
              child: FittedBox(fit: BoxFit.cover, child: raw),
            ),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text(AppStrings.of(context).videoUnavailable,
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
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
