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
- Enabled R8 code shrinking + resource shrinking for release builds.
- Split-per-ABI builds: phones only download the code for their CPU.
- `flutter build appbundle` produces a Play-ready bundle.
- Particle spikes are hard-capped; per-frame work stays allocation-light.

## Pixel-art polish

- Every level keeps the crisp nearest-neighbor, integer-scaled look; the
  camera transform preserves it (no subpixel smear, no blur).
- New shared pixel-UI kit (buttons, sprites, numbers, beveled panels) used
  by the shop, level select and victory screens for one cohesive style.

## Verification

- `flutter analyze` — clean.
- `flutter test` — **63/63 passing** (existing suites plus new camera-math,
  level-campaign and save-migration tests).
- Release builds (fat + split-per-ABI + appbundle) verified on this machine.

*Note: gameplay and balance were verified by tests and code inspection; a
real-device playtest (camera framing, pose counting, per-level feel) is still
recommended before store release.*
