# HearthFrame — Product Specification

- Status: v0.1.0
- Last updated: 2026-11-08
- Audience: contributors, testers, integrators

## 1. Summary

HearthFrame turns an Android tablet or phone into an always-on family photo
frame. It plays photos and short videos full screen from a local folder or a
NAS share, with frame-style transitions and minimal interaction.

## 2. Goals

- Zero-friction frame: configure once, then the device works as an appliance.
- Support the sources families actually have: local storage, WebDAV and
  SMB/CIFS.
- Start quickly on large libraries and stay responsive while scanning.
- Never get stuck on a single broken or unsupported file.
- Keep user data local: no accounts, no telemetry, no cloud dependency.

### Non-goals

- Photo editing, albums, face recognition, sharing or social features.
- Cloud providers beyond WebDAV and SMB/CIFS.
- Remote control or companion apps (v0.1).
- iOS as a validated platform (the project ships an untested scaffold only).

## 3. Target devices

- Android tablets and phones, primarily tablets used as frames in landscape.
- Tested on a Xiaomi tablet (model 22081283G), Android 14, 2000×1200.
- Always-on use with the screen kept awake; charging is recommended.

## 4. User stories

| ID | As an owner I want… | So that… |
| --- | --- | --- |
| US-1 | to point the frame at a local folder or NAS | my photos play without copying them |
| US-2 | photos and videos in one show | I don't have to curate two libraries |
| US-3 | to swipe to skip | I can jump past a photo immediately |
| US-4 | the UI to disappear | the frame looks clean on the shelf |
| US-5 | instant start after a reboot | the frame is usable in seconds |
| US-6 | broken files to be skipped | one bad file doesn't freeze the show |

## 5. Functional requirements

### FR-1 Setup

- FR-1.1 The setup screen is shown when no valid source is configured, or
  when the user opens it from the frame controls.
- FR-1.2 The source picker offers **Local folder**, **WebDAV (NAS)** and
  **SMB / CIFS (NAS)**.
- FR-1.3 Validation before start:
  - Local: a non-empty folder path; on Android, all-files access
    (`MANAGE_EXTERNAL_STORAGE`) must be granted, requested on Start.
  - WebDAV: a non-empty server URL and folder path.
  - SMB: a non-empty host and share path.
- FR-1.4 Start persists every field, leaves setup mode and starts the
  slideshow.
- FR-1.5 Failure messages: "Enter a folder path.", "All-files access is
  required to read this folder.", "WebDAV needs a server URL and a folder
  path.", "SMB needs a host and a share path (e.g. /photo/family)."
- FR-1.6 The local folder placeholder defaults to
  `/storage/emulated/0/Pictures`.

### FR-2 Sources

- FR-2.1 Sources are scanned recursively.
- FR-2.2 Directories that never hold user media are skipped: any name
  starting with `.`, plus `@eaDir`, `#recycle`, `#snapshot` and `@tmp`.
- FR-2.3 The media extension sets are shared by all sources:
  - Images: `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`, `.heic`, `.bmp`
  - Videos: `.mp4`, `.mov`, `.m4v`, `.mkv`, `.avi`
- FR-2.4 WebDAV items carry remote size and modification time when the
  server provides them; SMB items carry size and last-modified. Local items
  carry path only.

### FR-3 Discovery and index

- FR-3.1 Discovery emits a batch per directory as soon as that directory is
  read, instead of returning the whole tree at once.
- FR-3.2 Playback starts as soon as the first batch, or a cached index, is
  available.
- FR-3.3 A persisted index is loaded first. When present, playback starts
  immediately and a background rescan refreshes it.
- FR-3.4 Fresh scan results update the metadata of known items (size, mtime)
  and append new items without interrupting playback.
- FR-3.5 After a scan, items absent from the source are removed. If the
  current item disappeared, the frame shows another item.
- FR-3.6 Index entries are deduplicated by path; malformed or legacy entries
  are tolerated.
- FR-3.7 An empty source shows "No photos or videos found in this source."
- FR-3.8 If a source fails and no cached content exists, the frame shows an
  error with **Retry** and **Change source**.

### FR-4 Playback

- FR-4.1 Still images advance every configured interval.
- FR-4.2 Videos advance when they finish, not on the photo timer.
- FR-4.3 Pause suspends the slide timer, video playback and Ken Burns motion.
- FR-4.4 Next and previous wrap around at both ends.
- FR-4.5 Transitions are cross-fades using the configured duration.
- FR-4.6 Network items are downloaded on demand; the next item is prefetched.
- FR-4.7 A video that fails to initialise is skipped after about two
  seconds.
- FR-4.8 An image that fails to decode is removed from the cache (when it is
  a cached network item) and the frame advances.

### FR-5 Image rendering

- FR-5.1 EXIF orientation is applied exactly once, by the engine, before
  fitting. The app must not rotate decoded photos again.
- FR-5.2 **Fill screen on:** cover-crop to the panel, full bleed, clipped Ken
  Burns.
- FR-5.3 **Fill screen off:** the whole image is contained over a blurred,
  dimmed cover copy of itself.
- FR-5.4 Decoded width is bounded to the panel's longest side times the
  device pixel ratio, clamped to 64–4096 px.
- FR-5.5 HEIC/HEIF are converted to a cached JPEG through the platform
  decoder on Android. Conversion is atomic (`.part` + rename) and keyed by
  path, size and mtime.

### FR-6 Video

- FR-6.1 Videos play once with sound, centred at their aspect ratio.
- FR-6.2 Completion is detected when playback has stopped within 300 ms of
  the end.
- FR-6.3 Pause and resume follow the frame pause state.

### FR-7 Controls and gestures

- FR-7.1 A tap toggles a bottom control bar: previous, play/pause, next,
  change source, refresh, settings.
- FR-7.2 The bar auto-hides after four seconds.
- FR-7.3 A horizontal swipe with velocity above 200 px/s moves to the next
  item (left) or the previous item (right).
- FR-7.4 The frame uses immersive sticky system UI; normal system UI is
  restored when the slideshow is disposed.
- FR-7.5 The clock overlay shows a 12-hour `h:mm AM/PM` time at the top left,
  updated once per second, when enabled.

### FR-8 Settings

- FR-8.1 Settings persist across restarts.
- FR-8.2 Changes apply immediately; the slide timer and wake lock are
  refreshed.
- FR-8.3 Settings are listed in section 8.

### FR-9 Resilience

- FR-9.1 Cache writes use `.part` + rename; failed transfers are deleted.
- FR-9.2 After a successful download, older cache generations of the same
  remote path are pruned.
- FR-9.3 A corrupt index is ignored (treated as empty) and rebuilt by the
  next scan.
- FR-9.4 A source failure with cached content keeps playing cached items
  until it recovers.

### FR-10 keep_adb (Android, opt-in)

- FR-10.1 The feature is a no-op unless `WRITE_SECURE_SETTINGS` has been
  granted manually over ADB.
- FR-10.2 On start and every 60 seconds, `adb_wifi_enabled` and `adb_enabled`
  are restored if the system turned them off.
- FR-10.3 On `BOOT_COMPLETED`, a forced 0→1 transition restarts the wireless
  ADB daemon, including `development_settings_enabled`.

## 6. UX flows

### First run

1. Launch → setup screen.
2. Pick a source, fill in the fields.
3. Optional: grant all-files access for the local source.
4. Start → slideshow begins with the first available photo or video.

### Returning run

1. Launch → cached index is loaded.
2. The first photo appears immediately; a background rescan refreshes the
   index.

### Controls

1. Tap anywhere → control bar appears.
2. Tap outside the bar (or wait four seconds) → the bar hides.
3. Tap pause → the current item freezes; tap play to resume.
4. Tap the folder icon → setup screen; Start applies and returns.

## 7. Media support matrix

| Extension | Type | Notes |
| --- | --- | --- |
| `.jpg`, `.jpeg` | Image | EXIF orientation applied by the engine. |
| `.png`, `.gif`, `.webp`, `.bmp` | Image | Animated GIF/WebP play while the slide is shown; BMP is static. |
| `.heic`, `.heif` | Image | Converted to JPEG on Android; `heif` is treated like `heic`. |
| `.mp4`, `.m4v` | Video | Hardware codecs recommended. |
| `.mov` | Video | Playback depends on platform codecs. |
| `.mkv`, `.avi` | Video | Container support varies by device; failures are skipped. |

## 8. Settings specification

| Key | Type | Default | Range | Effect |
| --- | --- | --- | --- | --- |
| `interval_seconds` | int | 8 | 3–60 | Time per still image. |
| `transition_ms` | int | 600 | 0–2000 | Cross-fade duration. |
| `shuffle` | bool | true | — | Random order on load and rescan start. |
| `show_clock` | bool | true | — | Clock overlay. |
| `keep_awake` | bool | true | — | Wakelock while the frame is shown. |
| `fill_screen` | bool | true | — | Cover-crop instead of contain on a blurred backdrop. |
| `motion_effect` | bool | true | — | Ken Burns zoom/pan on stills. |
| `source_type` | string | `local` | `local`, `webdav`, `smb` | Active source. |
| `setup_mode` | bool | false | — | Force the setup screen. |
| `source_folder` | string | `''` | — | Local folder path. |
| `webdav_url`, `webdav_user`, `webdav_pass`, `webdav_path` | string | `''` | — | WebDAV configuration. |
| `smb_host`, `smb_domain`, `smb_user`, `smb_pass`, `smb_path` | string | `''` | — | SMB configuration. |

## 9. Non-functional requirements

- **NFR-1 Startup:** with a warm index, the first photo appears within about
  three seconds of a cold launch on the tested tablet (including the
  orientation settle described in the architecture document).
- **NFR-2 Memory:** decoded bitmaps are bounded to panel resolution; no
  unbounded full-resolution decode.
- **NFR-3 Network:** traffic goes only to the configured source. No
  analytics, telemetry or update checks.
- **NFR-4 Security:** credentials are stored only in app-private
  preferences, never logged and never committed to the repository.
- **NFR-5 Reliability:** the frame can run continuously; unreadable media is
  skipped without user action.
- **NFR-6 Accessibility:** control targets are standard Material icon
  buttons; larger clock/text options are future work.

## 10. Acceptance criteria (verified 2026-11-08)

| Criterion | Result | Method |
| --- | --- | --- |
| UI upright after a cold launch | 3/3 | Cold launch on a Xiaomi Android 14 tablet; screenshot. |
| EXIF orientation 6 photo upright | Pass | Synthetic 800×600 JPEG with Orientation=6; expected horizontal bands. |
| HEIC photo renders | Pass | 2.67 MB HEIC sample converted and displayed full bleed. |
| Truncated JPEG skipped | Pass | Corrupt file auto-skipped without blocking the show. |
| Videos play and advance | Pass | Landscape and portrait MP4 test clips. |
| Swipe next/previous; pause | Pass | ADB input events; screenshots. |
| Real SMB library plays | Pass | NAS share with mixed photos and videos. |
| Warm-index cold start | ~3 s to first photo | Real SMB share; cold launch. |
| Static analysis and tests | Pass | `flutter analyze`, `flutter test`. |

Results depend on library size, network speed and device.

## 11. Future work

- Sleep schedule and per-day source rotation.
- Additional transitions (slide, zoom fade).
- SMB3 and encrypted credential storage.
- Configurable clock size/format and burn-in-safe positioning.
- Branded launcher icon and documentation screenshots.
- iOS validation.
