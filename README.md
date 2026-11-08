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
  videos play once with sound and the frame moves on by itself.
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
  four seconds.
- **Gestures.** Swipe left/right for next/previous; tap to reveal controls.
- **Robust decoding.** EXIF orientation is applied exactly once, decoded
  bitmaps are bounded to the panel size, HEIC/HEIF are converted through the
  platform decoder, network downloads are written atomically, and unreadable
  items are skipped instead of wedging the show on a broken image.
- **Optional keep_adb.** On OEM builds that switch wireless debugging off,
  HearthFrame can restore it after boot or standby when explicitly granted
  `WRITE_SECURE_SETTINGS` (opt-in; a no-op otherwise).

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
| Slide duration | 8 s | 3–60 s; stills only (videos advance when they finish). |
| Transition | 600 ms | 0–2000 ms cross-fade. |
| Shuffle | on | Random play order. |
| Show clock | on | 12-hour clock, top left. |
| Keep screen on | on | Holds a wake lock while the frame is in the foreground. |
| Fill screen | on | Crops photos to the edges; off shows the whole photo over a blurred backdrop. |
| Motion effect | on | Slow Ken Burns zoom and pan on stills. |

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
android/              Android runner, HEIC converter, keep_adb guard
vendor/smb_connect/   vendored Apache-2.0 SMB client (host:port patch)
test/                 unit and widget tests
docs/                 specification, architecture and testing notes
```

## Privacy and security

HearthFrame has no analytics, no telemetry and no cloud service. It talks
only to the source you configure.

- Credentials are stored in the app's private `SharedPreferences`, protected
  by the Android app sandbox. They are not additionally encrypted at rest.
- Network media is cached in the app cache directory; clearing app storage
  removes it.
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
