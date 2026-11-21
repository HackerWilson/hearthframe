# HearthFrame — Design Decisions (ADRs)

Short records of decisions that are easy to undo by accident. Each entry
states the context, the decision and the consequences.

## ADR-001 — Clean-room implementation, MIT license

**Context.** The project recreates the core experience of a commercial
photo-frame app without copying code, assets, branding or behavior that
requires a license.

**Decision.** All code and design are original. The project ships under MIT.
The vendored SMB client keeps its upstream Apache-2.0 license. No third-party
product name, logo or asset is used as branding.

**Consequences.** The repository is safe to publish and fork. Features are
implemented from observed behavior only; contributors must not paste code
from unlicensed or copyleft sources.

## ADR-002 — Flutter

**Context.** The target is an Android tablet used as a frame; the app needs
image/video playback, smooth fades and a path to other platforms.

**Decision.** Build with Flutter and a thin Kotlin layer for platform
services.

**Consequences.** One codebase and quick iteration. The platform layer is
needed for HEIC and wireless-ADB handling. The iOS runner is scaffold-only
until validated.

## ADR-003 — Attach portrait, rotate after the first frame

**Context.** On some OEM builds the UI rendered sideways on cold launch:
SurfaceFlinger showed a stale portrait crop with a 90° buffer transform.
Manifest orientation locks, immediate runtime rotation, a delayed Java
`recreate()`, and disabling Impeller all failed to fix it. A metrics
recompute on an established surface did fix it.

**Decision.** Only on MIUI-derived builds (detected natively via
manufacturer/brand plus `ro.miui.ui.version.name`) attach in `portraitUp`,
then request `landscapeLeft` 1200 ms after the first frame. Stock Android
and ChromeOS/ARC attach in landscape immediately, requesting both
`landscapeLeft` and `landscapeRight`; the pair maps to
`SCREEN_ORIENTATION_USER_LANDSCAPE`, so a frame mounted upside down follows
the sensor instead of staying pinned to one edge. Do not lock orientation in
the manifest.

**Consequences.** The UI is upright on cold launch (verified 3/3 on the
affected tablet). MIUI still shows a brief portrait boot frame hidden by the
launch theme; ChromeOS no longer does (confirmed on ARC, 2026-11-08).
Upside-down mounting now rotates the whole window, matching the reference
frame app (portrait/landscape sensor behavior).

## ADR-004 — Apply EXIF orientation once, in the engine

**Context.** A manual `RotatedBox` on top of the engine's EXIF handling
rendered 90° photos as 180° (vertical reversed bands).

**Decision.** Do not rotate decoded images in app code. Let the engine apply
EXIF before fitting.

**Consequences.** Photos are upright without extra state. Any future
orientation handling must be verified against 90/180/270 cases.

## ADR-005 — Atomic, metadata-keyed network cache

**Context.** Interrupted downloads produced truncated files that looked valid
and wedged the frame. Same-size remote replacements could reuse stale bytes.

**Decision.** Download to `.part`, rename on success, and key the cache by
path hash plus remote size and mtime. Prune older generations after success.

**Consequences.** Broken transfers never publish. Replaced files refresh.
Cache entries accumulate per version but are pruned; clearing app storage
resets everything.

## ADR-006 — Persisted media index for instant start

**Context.** Recursively scanning a large NAS library takes minutes. A frame
must be usable in seconds.

**Decision.** Persist a per-source index after each scan and load it before
scanning. Show the first cached item immediately and rescan in the
background with per-directory batches.

**Consequences.** Near-instant restarts. The index can briefly contain
deleted items until the scan finishes; ghost pruning handles that. A corrupt
index only costs a slower start.

## ADR-007 — HEIC via the platform decoder

**Context.** Flutter's image codec has no HEIC support, while Android's
`ImageDecoder` does.

**Decision.** Convert HEIC/HEIF to a cached JPEG through a method channel,
atomically, keyed by path, size and mtime. Apply EXIF only on the
`BitmapFactory` fallback because `ImageDecoder` already does it.

**Consequences.** HEIC photos display on Android. Conversion costs one
decode per version. On API <28 the fallback path is slower and handles
rotation but not mirrored orientations.

## ADR-008 — Vendor `smb_connect` for `host:port`

**Context.** The upstream SMB client hard-codes port 445, which breaks
non-standard test servers and some NAS setups.

**Decision.** Vendor version 0.0.9 under `vendor/`, keep its Apache-2.0
license, and patch the transport to accept `host:port`.

**Consequences.** The patch is visible and reviewable. Upstream updates must
be re-applied manually. The dependency override keeps normal `pub get`
working.

## ADR-009 — Immersive sticky UI with auto-hiding controls

**Context.** A frame should look like a photo on the wall, not an app.

**Decision.** Use `SystemUiMode.immersiveSticky`, show a bottom control bar
only on tap, and hide it after six seconds. Hover or a pointer press suspends
the countdown; pause keeps the bar visible.

**Consequences.** Clean full-screen output. Controls remain discoverable by
tapping. System UI is restored when leaving the slideshow.

## ADR-010 — Opt-in `keep_adb`

**Context.** Some OEM builds disable wireless debugging after reboot or
standby, which breaks remote management of a mounted frame.

**Decision.** Offer a no-op-unless-granted feature that writes the secure
settings back. Grant is manual via `adb shell pm grant`. A boot receiver
forces a 0→1 transition to restart the daemon.

**Consequences.** No effect for users who don't grant the permission. The
feature is explicitly documented as opt-in and OEM-specific.

## ADR-011 — Tighten constraints for fill mode

**Context.** `FittedBox(cover)` inside `AnimatedSwitcher` received loose
constraints and self-sized to the child's aspect ratio, producing side
letterboxes instead of a full bleed.

**Decision.** Wrap fill-mode images in `SizedBox.expand` before `FittedBox`.

**Consequences.** Cover behavior is stable across transitions. Do not remove
the `SizedBox.expand`.

## ADR-012 — Videos advance on completion

**Context.** A single interval timer cannot match video lengths.

**Decision.** Stills use the periodic timer; videos advance when the player
reports the end (within 300 ms). A failed video advances after two seconds.

**Consequences.** Videos play in full. Pause must suspend both mechanisms,
which `didUpdateWidget` and the timer's pause check handle.

## ADR-013 — 64 KiB SMB read blocks

**Context.** The vendored SMB client requested 4 KiB per SMB2 READ. On a
low-power ARM device a single video slide meant tens of thousands of round
trips; the first frame could take minutes while one core stayed busy.

**Decision.** Patch `smbOpenRead` to read 64 KiB blocks (the client's internal
block size), copy each yielded chunk because the buffer is reused, and stop on
short reads. No public API change.

**Consequences.** Much faster video prefetch and first frame at lower CPU.
The patch stays inside the vendored Apache-2.0 copy and must be re-applied
when updating upstream.

## ADR-014 — Start on a still, bound the download cache

**Context.** The first scan entry is often a large video, so a cold start
waits for the whole file. Unbounded caching also fills storage on a frame
that runs for months.

**Decision.** On a cold scan (or cached index) start at the first still;
videos keep their slots and play when reached. Prune the media cache to
1.5 GiB by last-modified time after downloads and expose usage plus a Clear
action in Settings.

**Consequences.** The frame lights up quickly even on a virgin install.
Videos still download fully before their first play. Cache growth is bounded;
clearing removes files for slides that will re-download on demand.

## ADR-015 — Automation lives in native code

**Context.** A photo frame must come up after boot, when the charger is
connected and on a daily schedule. Flutter may not be running at those
moments. Android 10+ also blocks background activity starts, and Android 8+
does not deliver `ACTION_POWER_CONNECTED` to manifest receivers.

**Decision.** Mirror the automation settings to native `SharedPreferences`
through the `hearthframe/automation` channel. `FrameAutomation` owns the
daily `AlarmManager` alarms, a charging-constrained `JobScheduler` job, the
boot receiver and the power receiver registered while the frame runs. A
launch is attempted through a high-importance notification with a
full-screen intent, a direct `startActivity` and a system-delivered alarm;
the first path that the OS permits wins. The schedule window gates charging
and boot launches so a finished schedule is not reopened by the charging
job. Jobs are not re-added while already pending: re-adding a
charging-constrained periodic job while charging makes it run immediately.

**Consequences.** Automation survives the Flutter process. On MIUI/HyperOS
the user must grant the four special permissions in Settings and also allow
autostart and, critically, **后台弹出界面 → 始终允许** in the OEM permission
editor; without the latter MIUI aborts background activity starts even with
`SYSTEM_ALERT_WINDOW` granted (verified on the Redmi tablet, 2026-11-08).
The app provides a step-by-step grant flow plus shortcuts to both OEM
screens. Full-screen notifications may be the only reliable path when the
screen is on and the OEM denies background activity starts.

## ADR-016 — Defaults aligned with a family frame

**Context.** The reference frame app the family uses is configured with a
30-second slide, muted videos, a 24-hour clock and a shuffle biased toward
recent memories.

**Decision.** New installs default to 30 s slides, muted videos and a
recent-weighted shuffle (weight 1–5 by mtime rank, sampled without
replacement). Existing preferences are never migrated over the user's
choices; the settings sheet exposes each option.

**Consequences.** A fresh install behaves like the family's current frame.
Libraries without mtime metadata fall back to a plain shuffle. The recent
bias changes the order but not the membership: every item still plays.

## ADR-017 — Screen stay-on uses a native wake lock

**Context.** `FLAG_KEEP_SCREEN_ON` (applied by `wakelock_plus`) is normally
enough, but MIUI/HyperOS can drop or ignore the window flag across pauses and
its own lock-screen policy. On the Redmi tablet the frame was reported to
lock and turn the screen off after the 120 s system timeout even while
plugged in, despite the window holding `KEEP_SCREEN_ON`.

**Decision.** Keep the Flutter "Keep screen on" setting as the source of
truth. While enabled, `MainActivity` also holds a
`SCREEN_BRIGHT_WAKE_LOCK` named `HearthFrame:frame` between `onResume` and
`onPause`, and the window adds the deprecated `FLAG_DISMISS_KEYGUARD` so a
non-secure lock screen does not stay above the frame. Both are released on
pause/destroy; nothing is held when the frame is backgrounded.

**Consequences.** With a 15 s test timeout the screen stayed awake for 30 s
and no keyguard appeared (Redmi, 2026-11-08). A secure keyguard cannot be
dismissed without credentials and remains the user's choice; the wake lock
still keeps the display on so the frame is visible again on resume. On
battery, this intentionally prevents screen-off while the frame is running,
matching a photo frame's purpose; the setting can be turned off.
