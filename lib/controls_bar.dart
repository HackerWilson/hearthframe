import 'dart:ui';

import 'package:flutter/material.dart';

import 'l10n.dart';
import 'theme.dart';

/// Floating control pill for the slideshow.
///
/// Only shown briefly after a tap; [visible] drives both the fade/slide
/// animation and pointer transparency, so hidden controls never swallow taps.
class SlideshowControls extends StatelessWidget {
  const SlideshowControls({
    super.key,
    required this.visible,
    required this.paused,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.onSource,
    required this.onRefresh,
    required this.onSettings,
    this.onHoverChanged,
    this.onPressChanged,
    this.onDetails,
  });

  final bool visible;
  final bool paused;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onSource;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;
  final VoidCallback? onDetails;

  /// Lets the slideshow pause its auto-hide countdown while a mouse is over
  /// the pill or a pointer is pressed on it, so a button cannot vanish
  /// between the visual target and the click.
  final ValueChanged<bool>? onHoverChanged;
  final ValueChanged<bool>? onPressChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 26,
      child: IgnorePointer(
        ignoring: !visible,
        child: ExcludeFocus(
          excluding: !visible,
          child: AnimatedSlide(
            offset: visible ? Offset.zero : const Offset(0, 0.35),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Center(
                child: MouseRegion(
                  onEnter: (_) => onHoverChanged?.call(true),
                  onExit: (_) => onHoverChanged?.call(false),
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) => onPressChanged?.call(true),
                    onPointerUp: (_) => onPressChanged?.call(false),
                    onPointerCancel: (_) => onPressChanged?.call(false),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(36),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 30,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(36),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.42),
                              borderRadius: BorderRadius.circular(36),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _PillIcon(
                                  icon: Icons.skip_previous_rounded,
                                  tooltip: s.previous,
                                  onPressed: onPrevious,
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: IconButton.filled(
                                    onPressed: onPlayPause,
                                    tooltip: paused ? s.play : s.pause,
                                    style: IconButton.styleFrom(
                                      backgroundColor: HearthPalette.primary,
                                      foregroundColor: HearthPalette.background,
                                      fixedSize: const Size(54, 54),
                                      shape: const CircleBorder(),
                                    ),
                                    iconSize: 32,
                                    icon: Icon(
                                      paused
                                          ? Icons.play_arrow_rounded
                                          : Icons.pause_rounded,
                                    ),
                                  ),
                                ),
                                _PillIcon(
                                  icon: Icons.skip_next_rounded,
                                  tooltip: s.next,
                                  onPressed: onNext,
                                ),
                                Container(
                                  width: 1,
                                  height: 26,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  color: Colors.white.withValues(alpha: 0.16),
                                ),
                                _PillIcon(
                                  icon: Icons.folder_open_rounded,
                                  tooltip: s.changeSource,
                                  onPressed: onSource,
                                  dense: true,
                                ),
                                _PillIcon(
                                  icon: Icons.refresh_rounded,
                                  tooltip: s.refresh,
                                  onPressed: onRefresh,
                                  dense: true,
                                ),
                                if (onDetails != null)
                                  _PillIcon(
                                    icon: Icons.info_outline_rounded,
                                    tooltip: s.mediaDetails,
                                    onPressed: onDetails!,
                                    dense: true,
                                  ),
                                _PillIcon(
                                  icon: Icons.settings_rounded,
                                  tooltip: s.settings,
                                  onPressed: onSettings,
                                  dense: true,
                                ),
                              ],
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
        ),
      ),
    );
  }
}

class _PillIcon extends StatelessWidget {
  const _PillIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.dense = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: dense ? 23 : 30,
      color: HearthPalette.text,
      visualDensity: dense
          ? const VisualDensity(horizontal: -1, vertical: -1)
          : VisualDensity.standard,
      icon: Icon(icon),
    );
  }
}
