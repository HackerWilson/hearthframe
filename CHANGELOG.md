# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Android automation: launch at boot, launch when charging, exit when
  unplugged, active-hours gate and a daily start/stop schedule, with a
  native scheduler and a step-by-step permission flow (including an
  MIUI/HyperOS autostart shortcut).
- Video mute, recent-weighted shuffle, clock backdrop and clock size, and
  adjustable Ken Burns speed.
- 64 KiB SMB reads (from 4 KiB), producing roughly an order-of-magnitude
  faster first frame on large NAS libraries.
- Quick-start on the first still, media-cache LRU cap (1.5 GiB), cache usage
  and clear UI, and a bounded Flutter image cache.
- Orientation attach now runs only on MIUI; ChromeOS and stock Android start
  in landscape without a portrait boot frame.
- Control bar hides after six seconds, pauses the countdown on hover/press,
  stays visible while paused, and uses 44 px dense targets.

### Changed

- Default slide duration is 30 seconds; videos are muted by default.

### Fixed

- The frame could still be locked/screen-off after the system timeout on
  MIUI even with the window flag set. A native screen-bright wake lock now
  backs up `KEEP_SCREEN_ON` while the frame is resumed, and the window asks
  the system to dismiss a non-secure keyguard.

## [0.1.0] - 2026-11-08

Initial public release.

### Added

- Full-screen photo and video frame for Android, built with Flutter.
- Sources: local folder, WebDAV and SMB/CIFS.
- Incremental directory scanning with per-directory batches, a persisted media
  index for near-instant restarts, and stale-entry pruning.
- Slideshow with cross-fade, Ken Burns motion, shuffle, clock overlay,
  immersive full screen, keep-screen-on and auto-hiding controls.
- Swipe left/right navigation and tap-to-toggle controls.
- Atomic network cache keyed by path, size and mtime, with next-item prefetch.
- HEIC/HEIF conversion through the Android platform decoder.
- Bounded image decoding, single-application EXIF orientation, and automatic
  skipping of unreadable media and broken cache entries.
- Optional `keep_adb` guard for OEM builds that disable wireless debugging.

### Fixed

- Upright UI on OEM tablets where rotating during the initial surface attach
  left a stale surface transform (attach portrait, rotate after first frame).
- EXIF orientation applied twice on some photos (the engine applies it; the
  app no longer rotates decoded photos again).
- HEIC conversion no longer applies EXIF orientation twice on API 28+.
- `FittedBox` cover no longer degenerates to contain under loose constraints.
