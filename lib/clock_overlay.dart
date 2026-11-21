import 'dart:async';

import 'package:flutter/material.dart';

/// Large, calm clock with the date underneath.
///
/// The time follows the system 12/24-hour preference unless the user pins a
/// format in settings. Material localizations provide the locale-aware layout
/// (for example `下午1:41` in Chinese and `1:41 PM` in English).
class ClockOverlay extends StatefulWidget {
  const ClockOverlay({
    super.key,
    required this.format,
    this.background = false,
    this.scale = 1.0,
  });

  /// 'auto', '24' or '12'.
  final String format;

  /// Soft translucent panel behind the time, for busy photos.
  final bool background;

  /// Size multiplier (1.0 = default).
  final double scale;

  @override
  State<ClockOverlay> createState() => _ClockOverlayState();
}

class _ClockOverlayState extends State<ClockOverlay> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // The display shows minutes only; 10 s keeps the date rollover prompt
    // without waking the device every second.
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final shortest = media.size.shortestSide;
    final timeSize = ((shortest * 0.085).clamp(40.0, 84.0) * widget.scale)
        .clamp(28.0, 118.0);
    final dateSize = (timeSize * 0.30).clamp(10.0, 34.0);
    final use24 = switch (widget.format) {
      '24' => true,
      '12' => false,
      _ => media.alwaysUse24HourFormat,
    };
    final localizations = MaterialLocalizations.of(context);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(_now),
      alwaysUse24HourFormat: use24,
    );
    final date = localizations.formatMediumDate(_now);

    return Positioned(
      top: 28,
      left: 32,
      child: IgnorePointer(
        child: Container(
          padding: widget.background
              ? const EdgeInsets.fromLTRB(18, 12, 22, 14)
              : EdgeInsets.zero,
          decoration: widget.background
              ? BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                time,
                style: TextStyle(
                  fontSize: timeSize,
                  fontWeight: FontWeight.w200,
                  height: 1.0,
                  letterSpacing: 0.5,
                  color: Colors.white.withValues(alpha: 0.94),
                  shadows: [
                    Shadow(
                      blurRadius: 18,
                      color: Colors.black.withValues(alpha: 0.45),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                date,
                style: TextStyle(
                  fontSize: dateSize,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.3,
                  color: Colors.white.withValues(alpha: 0.72),
                  shadows: [
                    Shadow(
                      blurRadius: 12,
                      color: Colors.black.withValues(alpha: 0.40),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
