# M4 — Campaign update: camera fix, 8 levels, optimized release

A major pass focused on three things: a camera that actually works, a real
level campaign to play through, and a dramatically smaller install.

## Fixed-arena camera (the big correctness fix)

The game previously had **no camera at all** — the arena was rendered
directly in screen coordinates, so the world literally *was* the screen:
enemy travel distance, sprite proportions, ground layout and difficulty all
changed with the device, and the only "camera" was an ad-hoc shake offset.

Repel is a fixed arena (castle left, monsters march in), so it now uses a
proper **fixed virtual-resolution camera**:

- The world is defined once in virtual pixels (360 high); the camera maps it
  to the screen with a height-filling scale. Sprites, ground and castle look
  identical on every device.
- World width follows the screen aspect ratio (clamped 640–900 px), so wide
  screens show more battlefield while the enemy runway stays bounded — the
  game plays the same on a phone or a tablet.
- Screen shake is integer-quantized and applied to the world only; the HUD
  stays pinned to the screen.
- Ultra-wide screens get solid ink letterbox margins — nothing outside the
  world is ever shown.

## Eight-level campaign

- **8 levels**, each a distinct biome (palette, atmosphere wash, hills,
  castle tint, flag) built by reusing existing sprites and drawing routines —
  zero new image assets.
- New enemy variants from the same hand-drawn sprites: **runners** (fast,
  fragile) and **brutes** (slow, heavy), plus a **boss** at the end of every
  level from 2 on. Enemy colors come from each level's palette.
- Difficulty rises through composition and pacing (spawn pressure, variant
  mixes, bounded stat scales) — not endless HP inflation.
- Full loop: level select → intro → waves/fight/combo → shop between waves →
  level clear → rewards + unlock → next level / replay / menu. Defeat retries
  the wave; you can return to level select at any time.
- First-clear coin bonuses are granted **exactly once** per level (replays
  never double-pay).

## Save system (backward compatible)

- Saves now also track unlocked/cleared levels, resume point and lifetime
  stats (reps, kills, best combo).
- Old saves migrate transparently: previous coin/upgrade/wave values are
  read from the same keys as before.
- Corrupted, missing or out-of-range values are clamped to safe defaults —
  the game never crashes on a broken save.
- Coin changes are debounced and written at wave clears, purchases, level
  starts and app pause — not once per kill.

## Optimized release build

- Removed the unused `cupertino_icons` dependency (drops its 257 KB font).
- Excluded ML Kit's `pose-detection-accurate` artifact: the game only runs
  the base (lite) model, so the accurate bundle's sole unique payload — a
  6.4 MB landmark model — was dead weight in every install. (The plugin's
  accurate code path is a never-taken branch; suppressed with the exact
  `-dontwarn` rules AGP generated.)
- Enabled R8 code shrinking + resource shrinking for release builds, with
  deliberately minimal keep rules — the ML Kit AARs ship their own consumer
  rules, and broad `-keep` rules were *measured* to grow classes.dex by
  1.7 MB, so they are not used.
- Split-per-ABI builds: phones only download the code for their CPU.
- `flutter build appbundle` produces a Play-ready bundle.
- Particle spikes are hard-capped; per-frame work stays allocation-light.

Measured artifact sizes (exact bytes):

| Artifact | Before M4 | After M4 | Change |
|---|---:|---:|---:|
| Fat APK (all ABIs) | 89,929,170 | 83,705,202 | −6,223,968 (−6.9%) |
| arm64-v8a APK | 40,828,303 | 34,407,727 | −6,420,576 (−15.7%) |
| armeabi-v7a APK | 34,528,961 | 28,042,845 | −6,486,116 (−18.8%) |
| x86_64 APK | 43,446,646 | 37,026,066 | −6,420,580 (−14.8%) |
| App bundle (AAB) | — | 83,730,109 | new |

Installing on a real phone (arm64 split) is **61.7% smaller than the
original all-ABI APK**.

## Pixel-art polish

- Every level keeps the crisp nearest-neighbor, integer-scaled look; the
  camera transform preserves it (no subpixel smear, no blur).
- New shared pixel-UI kit (buttons, sprites, numbers, beveled panels) used
  by the shop, level select and victory screens for one cohesive style.

## Verification

- `flutter analyze` — clean.
- `flutter test` — **63/63 passing** (existing suites plus new camera-math,
  level-campaign and save-migration tests).
- Builds run on this machine: release fat APK, release split-per-ABI (all
  three ABIs), release appbundle, and a debug APK (confirms the dev workflow
  still builds with the ML Kit model exclusion).

*Note: gameplay, camera framing, pose counting and per-level balance were
verified by tests and code inspection — not on a physical device. Before
store release, playtest on hardware: camera framing across screen sizes,
rep counting, and that pose detection runs normally with the unused 6.4 MB
ML Kit model excluded (that path is unreachable by code inspection but has
not yet been exercised on a device).*
