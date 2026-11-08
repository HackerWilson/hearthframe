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

**Decision.** Attach in `portraitUp`, then request `landscapeLeft` 1200 ms
after the first frame. Do not lock orientation in the manifest.

**Consequences.** The UI is upright on cold launch (verified 3/3 on the
affected tablet). There is a brief portrait boot frame hidden by the launch
theme and a short settle delay before landscape.

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
only on tap, and hide it after four seconds.

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
