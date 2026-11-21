# HearthFrame — Architecture

This document describes how the app is put together and why the
non-obvious parts are the way they are. For product behavior see
[SPEC.md](SPEC.md); for decisions and alternatives see
[DECISIONS.md](DECISIONS.md).

## 1. Overview

```
main()
  ├─ SystemChrome.setPreferredOrientations([portraitUp])
  ├─ FrameSettings.load()                    (shared_preferences)
  ├─ automation: mirror settings to native, re-arm alarms/jobs
  ├─ keep_adb: MethodChannel 'hearthframe/adb_keep'.ensure()
  │             + Timer.periodic(60 s)
  └─ runApp(HearthFrameApp)
       ├─ !configured || setupMode → SetupScreen
       └─ else → SlideshowScreen
                    ├─ PhotoSource  (Local / WebDAV / SMB)
                    ├─ media index  (application support dir)
                    ├─ media cache  (temporary dir)
                    └─ _MediaView   (image or video)
```

The app is a single Flutter activity. There is no routing package and no
state-management package; a `ChangeNotifier` (`FrameSettings`) drives setup
versus slideshow, and the slideshow keeps its own state.

## 2. Module map

| Path | Responsibility |
| --- | --- |
| `lib/main.dart` | Entry point, app theme, setup screen, slideshow state machine, controls, clock, settings sheet, image/video rendering, Ken Burns. |
| `lib/settings.dart` | `FrameSettings`: typed getters/setters over `SharedPreferences`, defaults and `isConfigured`. |
| `lib/sources.dart` | `MediaItem`, skip rules, `PhotoSource` abstraction, `LocalFolderSource` (recursive walk). |
| `lib/nas_sources.dart` | `NetworkSource`, shared extension sets, on-device cache, `WebDavSource`, `SmbSource`. |
| `lib/media_cache.dart` | Cache directory, size accounting, 1.5 GiB LRU eviction and clearing. |
| `lib/platform_image.dart` | HEIC/HEIF detection and conversion through the `hearthframe/image` channel. |
| `lib/automation.dart` | Bridge to native automation: configure, permission status, OEM shortcut. |
| `android/.../MainActivity.kt` | Registers the method channels, starts `keep_adb`, handles stop/power receivers. |
| `android/.../FrameAutomation.kt` | Native boot/charging/schedule engine, launch notification, permissions. |
| `android/.../HeicConvert.kt` | Off-main-thread HEIC decode, EXIF handling, atomic JPEG write. |
| `android/.../AdbKeep.kt` | Opt-in wireless ADB restoration (`ensure` and boot-time `force`) and `BootReceiver`. |
| `vendor/smb_connect/` | Apache-2.0 SMB client, patched for `host:port` and 64 KiB reads (see ADR-008, ADR-013). |

## 3. Initialization and orientation

1. The engine is initialized by `WidgetsFlutterBinding.ensureInitialized()`.
2. The activity attaches in **portrait**.
3. Settings load, the keep_adb channel is pinged, and the first frame is
   scheduled.
4. After the first frame, the app waits **1200 ms** and requests
   `landscapeLeft`.

Rotating during the initial surface attach can leave the Flutter surface with
a stale portrait crop and a 90° buffer transform on some OEM builds. The UI
then composes sideways even though widgets and screenshots are upright. The
transform only refreshes on a later metrics recompute, so the app rotates
only after the surface is established. See ADR-003 for evidence and rejected
alternatives.

## 4. Setup and navigation

- `HearthFrameApp` listens to `FrameSettings`. It shows `SetupScreen` while
  `setupMode` is true or the active source is not configured; otherwise it
  shows `SlideshowScreen`.
- `SetupScreen` keeps one controller per field, validates by source type,
  requests all-files access for the local source, and persists every field
  on Start. Persisting calls `notifyListeners()`, which swaps the root widget
  to the slideshow.
- Opening the source picker from the slideshow sets `setupMode = true`.

## 5. Discovery, index and instant start

### Provider contract

```dart
abstract class PhotoSource {
  Future<List<MediaItem>> list();
  Future<void> discover(void Function(List<MediaItem> batch) onBatch);
}
```

`discover` walks directories depth-first and emits a non-empty batch after
each directory. `list` flattens and sorts, and is used only where a complete
list is required.

### Index

- File: `<applicationSupportDirectory>/media_index_<signature>.json`.
- Signature: 32-bit FNV-1a over:
  - local: `local|<folder>`
  - WebDAV: `dav|<url>|<user>|<path>`
  - SMB: `smb|<host>|<user>|<path>`
- Format: JSON array of `[path, isVideo(0|1), size, mtime]`. Older entries
  without metadata are accepted.
- Reads deduplicate by path and ignore corrupt files.

### Load sequence

1. Build the source and reset state.
2. Read the index. If non-empty, set it as the working list (shuffle if
   configured), show its first item, and start the timer.
3. Run `discover` in the background:
   - Before any content exists, the first batch becomes the working list.
   - Afterwards, known items get refreshed metadata and new items are
     appended without changing the current item.
4. After discovery, prune items not present in the fresh scan. If the
   current item disappeared, show the new current item.
5. Write the fresh list back to the index.
6. If the source fails and nothing is showing, display the error state. If
   cached content is already playing, keep playing.

This gives near-instant starts on big libraries while keeping the index
eventually consistent with the source.

## 6. Network cache

Both network sources download items into
`<temporaryDirectory>/hearthframe_cache`.

Cache key:

```
<path hash>_<size or 0>_<mtime or 0>_<sanitized base name>
```

- Size and mtime make any remote change land in a different file, including
  same-size edits such as EXIF-only changes.
- SMB keys hash a prefixed `smb_<path>` string to avoid collisions with
  WebDAV paths.
- Downloads stream into `<name>.part`; the file is renamed only after a
  successful transfer. Failed transfers delete the part file.
- After success, other generations with the same hash prefix are pruned.
- The next queue item is prefetched after the current item is prepared.

Item metadata can be missing (old index). SMB then stats the remote file
once to derive the key; WebDAV uses `0` placeholders until the rescan
supplies metadata.

## 7. Media rendering

### Images

1. HEIC/HEIF on Android: `decodablePath` converts to
   `<cache>/heic_<hash>_<size>_<mtime>.jpg` through the platform channel,
   then returns that path. Everything else passes through.
2. Decode width:
   `longestSide * devicePixelRatio`, clamped to 64–4096.
3. Orientation: the engine's decoder applies EXIF orientation. The app does
   **not** rotate again (ADR-004).
4. Fill mode:
   `SizedBox.expand` → `ClipRect` → `FittedBox(cover)` → `Image.file`.
   `SizedBox.expand` is required because `AnimatedSwitcher` passes loose
   constraints; otherwise `FittedBox` self-sizes and behaves like contain.
5. Contain mode: blurred (`sigma 24`) cover copy, 35% black scrim, contained
   image.
6. Ken Burns: 12 s `AnimationController`, scale 1.0 → 1.1 with `easeInOut`,
   pan target selected from four alignments by path hash. Clipped.
7. Decode failure deletes the cached file (when in `hearthframe_cache`) and
   advances immediately.

### Videos

- `VideoPlayerController.file` plays once, centred, at its aspect ratio.
- Completion: initialized, duration > 0, not playing, and position within
  300 ms of the end.
- Pause/resume is driven by `didUpdateWidget`.
- Initialization failure shows a broken-image icon for two seconds, then
  advances.

## 8. Platform channels

| Channel | Method | Purpose |
| --- | --- | --- |
| `hearthframe/image` | `heicToJpeg(src, dst)` | Decode HEIC/HEIF with Android `ImageDecoder` (API 28+) or `BitmapFactory` (fallback), apply EXIF when the decoder did not, write JPEG quality 92 atomically, return the path. |
| `hearthframe/adb_keep` | `ensure` | Restore wireless debugging if it was switched off; no-op without `WRITE_SECURE_SETTINGS`. |

HEIC conversion runs on a single-thread executor. `ImageDecoder` already
applies EXIF orientation, so the Kotlin path only rotates on the
`BitmapFactory` fallback (ADR-007).

## 8.1 Automation

`FrameSettings.automationConfig` is pushed to `FrameAutomation` on every
change. Native preferences (`frame_automation`) are the source of truth for
boot, charging and alarms, because Flutter is not running then.

- **Boot:** `BootReceiver` calls `FrameAutomation.onBoot`, re-arms the daily
  alarms and charging jobs, and launches when enabled and inside the
  active-hours/schedule windows.
- **Charging:** a persisted `JobScheduler` job with `setRequiresCharging`
  covers cold launches; a dynamic receiver in `MainActivity` handles
  unplug-exit while the frame is open.
- **Schedule:** one-shot `setExactAndAllowWhileIdle` alarms for the next
  start/stop; each receiver re-arms the following day.
- **Launch path:** a high-importance notification with a full-screen intent,
  a direct `startActivity` and a system-delivered alarm are attempted in
  order. Android 10+ blocks the direct start unless the OEM grants an
  exemption; the full-screen notification is the sanctioned fallback.
- **Gating:** the schedule window gates charging and boot launches, so the
  charging job does not reopen a frame stopped at the schedule end.
- **Stay on:** while "Keep screen on" is enabled, `MainActivity` holds a
  native `SCREEN_BRIGHT_WAKE_LOCK` between resume and pause, in addition to
  the Flutter window `KEEP_SCREEN_ON` flag, and asks the window manager to
  dismiss a non-secure keyguard.

## 9. Android manifest and permissions

| Permission | Reason |
| --- | --- |
| `INTERNET`, `ACCESS_NETWORK_STATE` | WebDAV and SMB. |
| `WAKE_LOCK` | Keep the screen on in frame mode. |
| `MANAGE_EXTERNAL_STORAGE` | Read a user-chosen local folder. |
| `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO` | Media access on Android 13+. |
| `READ_EXTERNAL_STORAGE` (maxSdk 32) | Legacy media access. |
| `RECEIVE_BOOT_COMPLETED` | `keep_adb` boot receiver. |
| `WRITE_SECURE_SETTINGS` | Opt-in `keep_adb`; granted manually over ADB. |

The activity declares the configuration changes it handles and does **not**
lock orientation in the manifest; landscape is requested at runtime (ADR-003).

## 10. Storage locations

| Data | Location | Cleared by |
| --- | --- | --- |
| Settings and credentials | app-private `SharedPreferences` | clearing app data |
| Media index | application support directory | clearing app data |
| Network media cache | temporary directory `/hearthframe_cache` | clearing app cache/data, OS pressure |
| Converted HEIC JPEGs | same cache directory | clearing app cache/data |

## 11. Failure handling matrix

| Failure | Behavior |
| --- | --- |
| Source unreachable, no cache | Error panel with Retry / Change source. |
| Source unreachable, cache present | Cached items keep playing. |
| Download interrupted | `.part` deleted; item skipped via prepare failure. |
| Image decode failure | Cached file deleted; frame advances. |
| Video init failure | Placeholder for 2 s; frame advances. |
| Empty source | "No photos or videos found in this source." |
| Corrupt index | Ignored; rebuilt by the scan. |
| HEIC conversion failure | Original path returned; the image decoder error path skips it. |

## 12. Threading and performance

- Directory walks are asynchronous Dart I/O; no isolates in v0.1.
- Network transfers are streamed; the UI thread never blocks on file I/O.
- HEIC conversion runs on a Kotlin single-thread executor and returns on the
  main looper.
- The slideshow uses one periodic timer, restarted on settings changes and
  navigation; videos use player state instead of the timer.
- Prefetch keeps at most one item ahead, so memory and storage stay bounded.

## 13. Known limitations

- The index is written non-atomically; a crash during the write loses the
  cache and the next start falls back to a full scan.
- If the source is unreachable and nothing has been cached yet, the slideshow
  keeps retrying items; the spinner may persist until the source returns.
- Credentials are not encrypted beyond the OS app sandbox.
- SMB support is SMB 1/2.0/2.1, not SMB3.
- One source is active at a time; multiple shares are not aggregated yet.
- Orientation filtering ("portrait only" / "landscape only") and photo
  metadata overlays (file, location, capture time) are not implemented.
- Background auto-start depends on OEM permissions. The app surfaces the
  standard permissions and MIUI/HyperOS shortcuts, but cannot override an
  OEM that blocks background activity starts for non-allowlisted apps.
- On ChromeOS/ARC, `BatteryService` may keep `status=3` (discharging) even
  when AC is connected, so the `JobScheduler` CHARGING constraint never
  satisfies. "Launch when charging" therefore may not cold-start on ARC;
  boot and schedule launches are unaffected while the Chromebook is awake.
  The app's own `isCharging` check uses the plugged flag and is correct.
- ChromeOS may sleep after the frame exits (e.g. at the 23:00 schedule
  stop), which drops Wi-Fi/ADB; an Android `RTC_WAKEUP` alarm inside ARCVM
  cannot wake the Chromebook itself. The 07:00 schedule start therefore
  cannot be guaranteed on a sleeping Chromebook. For an always-on wall
  frame, keep ChromeOS awake while plugged in; Redmi/ordinary Android
  devices are unaffected.
- Rapidly tapping **Refresh** can start overlapping `_load()` calls. Each
  load closes the previous SMB source while a prefetch is still bound,
  which can abort a video that was just cached (observed on ChromeOS:
  ExoPlayer released after 0.25 s with
  `Bad state: StreamSink is bound to a stream`). Normal playback is not
  affected and the frame skips the item and continues. Planned fixes:
  a re-entry/debounce guard on `_load()`, an idempotent `SmbSource.close()`
  that waits for/bounds active streams, and disposing the player before
  closing the source.
- The iOS runner is a scaffold and is unverified.
- The release build is debug-signed in this repository.
