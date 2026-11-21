# HearthFrame

[![CI](https://github.com/HackerWilson/hearthframe/actions/workflows/ci.yml/badge.svg)](https://github.com/HackerWilson/hearthframe/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

An original, open-source family photo frame for Android tablets and phones.
Leave a spare device on the shelf and HearthFrame plays photos and short
videos from a local folder or your NAS — full screen, always on, with no
account, no cloud dependency and no telemetry.

Built with Flutter. Clean-room code and design, MIT licensed.

## Highlights

- **One show for photos and videos.** Stills get a slow Ken Burns motion;
  videos play once (muted by default) and the frame moves on by itself.
- **Local or NAS.** Local folders, WebDAV (Synology WebDAV Server, Nextcloud,
  ownCloud, …) and SMB/CIFS shares (Synology, Windows, Samba, …). Credentials
  stay in app-private preferences on the device.
- **Fast on big libraries.** Directories are scanned incrementally and the
  first photo appears before the whole tree is read. A persisted media index
  makes later launches near-instant while a background rescan refreshes it;
  deleted items are pruned from the index.
- **Frame-style playback.** Cross-fade transitions, optional fill-screen crop
  or whole-photo view over a blurred backdrop, shuffle, clock overlay,
  immersive full screen, keep-screen-on, and controls that auto-hide after
  six seconds.
- **Made to run unattended.** Optional launch at boot, launch when power is
  connected, exit when unplugged, an active-hours gate and a daily
  start/stop schedule. Settings are mirrored to a native scheduler so they
  work while the Flutter UI is not running.
- **Gestures.** Swipe left/right for next/previous; tap to reveal controls.
- **Robust decoding.** EXIF orientation is applied exactly once, decoded
  bitmaps are bounded to the panel size, HEIC/HEIF are converted through the
  platform decoder, network downloads are written atomically, and unreadable
  items are skipped instead of wedging the show on a broken image.
- **Optional keep_adb.** On OEM builds that switch wireless debugging off,
  HearthFrame can restore it after boot or standby when explicitly granted
  `WRITE_SECURE_SETTINGS` (opt-in; a no-op otherwise).

## Automation (Android)

Settings → Automation mirrors the schedule to native code so it keeps working
when Flutter is not running. Boot and charging launches, the active-hours
gate and the daily start/stop schedule are implemented without a persistent
foreground service.

Android 10+ blocks activity starts from the background. HearthFrame uses a
high-importance notification with a full-screen intent, and also attempts a
direct start for devices/OEMs that permit it. ChromeOS/ARC has a known
platform quirk: `BatteryService` can report discharging while AC is
connected, so the charging-constrained job may not cold-start there; boot
and schedule launches still work. On first use, open Settings →
Automation → **Background permissions** and grant each item:

1. Notifications
2. Display over other apps
3. Exact alarms
4. Full-screen notifications

On MIUI/HyperOS, two extra OEM switches are required:

- **System autostart** — allow HearthFrame in the background-start list.
- **Background pop-up** — Other permissions → 后台弹出界面 → Always allow.
  Without this switch MIUI aborts background activity starts even when
  Android's `SYSTEM_ALERT_WINDOW` permission is granted.

Set the app's battery saver to unrestricted as well. These OEM allowlists are
what let a photo-frame app come up reliably while the screen is on or
unlocked.

## Source support

| Source | Fields | Notes |
| --- | --- | --- |
| Local folder | Folder path | Android: all-files access (`MANAGE_EXTERNAL_STORAGE`) is requested on Start. |
| WebDAV | Server URL, username, password, folder path | HTTP or HTTPS. The folder is an absolute path on the server, e.g. `/photo/family`. |
| SMB/CIFS | Host, username, password, optional domain, share path | The share path includes the share name, e.g. `/photo/family`. `host:port` is supported for non-standard ports. |

Images: JPEG, PNG, GIF, WebP, BMP, HEIC/HEIF. Videos: MP4, MOV, M4V, MKV, AVI.
Playback depends on the platform codecs; unsupported clips are skipped.

Android is the primary target and the only platform exercised on hardware so
far. The project includes an iOS runner scaffold, but iOS behavior has not
been validated.

## Quick start

Requirements: Flutter 3.x (stable), JDK 17 and the Android SDK.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
adb install build/app/outputs/flutter-apk/app-release.apk
```

Release builds in this repository are signed with the debug key so
`flutter run --release` works out of the box. Configure your own signing key
before distributing builds. On first launch, choose a source, fill in its
fields and press **Start photo frame**.

## Settings

| Setting | Default | Range / effect |
| --- | --- | --- |
| Slide duration | 30 s | 3–60 s; stills only (videos advance when they finish). |
| Transition | Fade | Fade, slide or zoom. |
| Shuffle | on | Random play order. |
| Favor recent media | on | Weighted shuffle: newer items appear more often. |
| Mute videos | on | Videos play without sound. |
| Clock | on | Time and date, optional backdrop and 70–140% size. |
| Keep screen on | on | Holds a wake lock while the frame is in the foreground. |
| Fill screen | on | Crops photos to the edges; off shows the whole photo over a blurred backdrop. |
| Motion effect | on | Slow Ken Burns zoom and pan on stills, 50–150% speed. |
| Automation | off | Boot launch, charging launch, unplug exit, active hours and a daily schedule. |

## Documentation

- [Product specification](docs/SPEC.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Source providers](docs/SOURCES.md)
- [Testing and verification](docs/TESTING.md)
- [Design decisions (ADRs)](docs/DECISIONS.md)
- [Contributing](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)
- [Security policy](SECURITY.md)

## Project layout

```
lib/
  main.dart           app shell, setup screen, slideshow, settings sheet
  settings.dart       persisted frame settings (shared_preferences)
  sources.dart        source abstraction and local folder scanner
  nas_sources.dart    WebDAV and SMB/CIFS sources with on-device cache
  platform_image.dart HEIC/HEIF conversion through a platform channel
  automation.dart     bridge to the native boot/charging/schedule engine
android/              Android runner, HEIC converter, keep_adb, FrameAutomation
vendor/smb_connect/   vendored Apache-2.0 SMB client (host:port + 64 KiB read patch)
test/                 unit and widget tests
docs/                 specification, architecture and testing notes
```

## Privacy and security

HearthFrame has no analytics, no telemetry and no cloud service. It talks
only to the source you configure.

- Credentials are stored in the app's private `SharedPreferences`, protected
  by the Android app sandbox. They are not additionally encrypted at rest.
- Network media is cached in the app cache directory, capped at 1.5 GiB with
  oldest-first eviction; Settings > Storage shows usage and can clear it.
- Prefer HTTPS for WebDAV. Plain HTTP is supported for trusted home networks.
- The SMB client supports SMB 1/2.0/2.1. Prefer a modern NAS configuration
  and a dedicated read-only account; SMB1 is legacy and insecure.
- The Local folder source requires all-files access on Android. If that is
  not acceptable, use a network source instead.

See [SECURITY.md](SECURITY.md) for the full security model.

## Optional: keep wireless ADB on (Android)

Some OEM builds (e.g. HyperOS) switch wireless debugging off after a reboot
or standby. HearthFrame can write it back on — a common pattern on Android TV
devices. It is opt-in and a no-op until you grant the permission once over
ADB:

```sh
adb shell pm grant dev.hearthframe.hearthframe android.permission.WRITE_SECURE_SETTINGS
```

With the grant, a boot receiver re-enables wireless debugging after the
device boots (allow the app's autostart in the OEM's security app), and the
running frame re-checks every 60 s. Without the grant nothing is written.

## License

MIT — see [LICENSE](LICENSE). The vendored `smb_connect` package in `vendor/`
keeps its upstream Apache-2.0 license; other Dart packages retain their own
licenses.

HearthFrame is an independent project, not affiliated with any commercial
photo-frame product. Product names and trademarks mentioned in documentation
belong to their respective owners.
