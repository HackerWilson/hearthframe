# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
