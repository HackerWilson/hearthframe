# HearthFrame — Testing and Verification

## 1. Automated checks

CI runs on every push to `main` and on pull requests:

```sh
flutter pub get
flutter analyze
flutter test
```

Locally, use the same commands. `flutter analyze` must be clean; `vendor/` is
excluded because it is third-party code.

### Unit tests

`test/widget_test.dart` covers the local source:

- recursive collection of images and videos;
- case-insensitive extension matching;
- non-media files ignored;
- a missing folder returns an empty list;
- `@eaDir` and hidden directories are skipped.

## 2. Test fixtures

Create fixtures outside the repository and never commit personal photos or
credentials.

### Videos (FFmpeg)

```sh
# Landscape, 6 s, H.264/AAC
ffmpeg -f lavfi -i testsrc2=size=1280x720:rate=30 \
       -f lavfi -i sine=frequency=440 -t 6 \
       -pix_fmt yuv420p -c:v libx264 -c:a aac clip_landscape.mp4

# Portrait, 6 s
ffmpeg -f lavfi -i testsrc2=size=720x1280:rate=30 \
       -f lavfi -i sine=frequency=440 -t 6 \
       -pix_fmt yuv420p -c:v libx264 -c:a aac clip_portrait.mp4
```

### EXIF orientation

```sh
magick -size 800x600 gradient:red-cyan rotated6.jpg
exiftool -overwrite_original -Orientation=6 -n rotated6.jpg
```

The stored pixels are the upright gradient; a correct viewer rotates the
image 90° clockwise. With the old double-rotation bug the bands appeared
vertical-reversed (net 180°).

### HEIC (macOS)

```sh
sips -s format heic input.jpg --out sample.heic
```

### Broken file

```sh
head -c 20000 valid.jpg > broken.jpg
```

A valid header with a truncated body exercises the decode-failure path.

### Local test servers (optional)

```sh
# WebDAV
rclone serve webdav ./album --addr 127.0.0.1:8080 --dir-cache-time 0

# SMB (impacket), credentials are placeholders
python smbserver.py -ip 127.0.0.1 -port 4455 -smb2support \
  -username frame -password '<password>' album ./album
```

Stop the servers and delete fixtures afterwards. Never reuse real NAS
credentials for test servers.

## 3. Manual checklist

| Area | Steps | Expected |
| --- | --- | --- |
| First run | Install, launch | Setup screen, upright, no keyboard on its own. |
| Local source | Pick Local, grant access, start | Photos and videos from the folder play. |
| WebDAV | Configure URL/user/password/path, start | Album plays; credentials persist after restart. |
| SMB | Configure host/share path, start | Album plays; `host:port` works for a non-standard port. |
| Slow source | Start on a large tree | First photo appears before the scan finishes. |
| Warm start | Force-stop, relaunch | First photo appears from the index in a few seconds. |
| Slideshow | Wait | Stills advance at the configured interval; videos finish then advance. |
| Swipe | Swipe left / right | Next / previous item, with wrap-around. |
| Controls | Tap | Bar appears with six buttons; hides after 4 s. |
| Pause | Tap, then pause | Image and video freeze; Ken Burns stops; play resumes. |
| Settings | Change duration/transition/toggles | Changes apply immediately and persist. |
| Fill off | Disable Fill screen | Whole photo over a blurred backdrop. |
| Clock | Toggle | 12-hour clock at the top left, once per second. |
| EXIF | Include an Orientation=6 JPEG | Photo upright, not 180°. |
| HEIC | Include a HEIC file | Converted image displays; no broken icon. |
| Broken media | Include a truncated JPEG | Skipped automatically; the show continues. |
| Unsupported video | Include an exotic codec | Placeholder, then advance after ~2 s. |
| Empty source | Point at an empty folder | "No photos or videos found in this source." |
| Source error | Use a wrong password, no cache | Error panel with Retry / Change source. |
| Source error with cache | Break the network while cached items play | Playback continues from cache. |
| Ghost pruning | Delete a remote item, refresh | The item disappears after the scan. |
| keep_adb | Grant `WRITE_SECURE_SETTINGS`; disable wireless debugging | The running frame restores it within 60 s; after boot, the receiver restores it. |
| Immersive | Enter the frame | Status/navigation bars hidden; restored after leaving. |

## 4. Verified device

Results in [SPEC.md](SPEC.md#10-acceptance-criteria-verified-2026-11-08) were
recorded on:

- Xiaomi tablet, model 22081283G
- Android 14
- 2000×1200 panel
- OEM wireless-debugging quirk (HyperOS family)

Re-verify on additional devices when changing orientation, decoding or the
surface setup.

## 5. Regression traps

1. **EXIF double rotation.** The engine applies EXIF orientation. Never wrap
   a decoded image in a manual rotation; a 90° photo becomes 180°.
2. **HEIC double rotation.** `ImageDecoder` (API 28+) already applies EXIF.
   Rotate only on the `BitmapFactory` fallback.
3. **Sideways UI.** Do not lock orientation in the manifest or rotate before
   the surface is established. Keep the portrait attach + delayed landscape
   request. See ADR-003.
4. **Loose constraints.** `AnimatedSwitcher` passes loose constraints; wrap
   fill-mode images in `SizedBox.expand`, or cover degrades to contain.
5. **Video advance.** Detect completion at the end position, not on the
   periodic still timer.
6. **Broken cache.** Keep `.part` + rename and delete a cached file when its
   decode fails, otherwise one truncated download wedges the frame forever.
7. **Stale cache.** Keep size and mtime in the cache key; same-size
   replacements must invalidate the cache.
8. **Ghost items.** Prune index entries that the fresh scan no longer sees.

## 6. Cleanup

- Kill test servers (WebDAV/SMB) and confirm their ports are closed.
- Delete fixtures, screenshots and logs.
- Never leave credentials in `/tmp`, shells, logs or the repository.
- Restore any device settings you changed for testing.
