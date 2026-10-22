## M3 - Progression, plus recognition & landscape fixes

### Fixes requested after M2 playtesting

**Pushup recognition rewritten (adaptive calibration).**
The old counter needed your arms to look perfectly straight (150 degrees) -
but a phone lying on the floor never sees your arms that straight, so
it often never started counting. The counter now *learns your personal range
of motion* from real samples:

- it tracks the highest/lowest elbow angle you actually produce
- thresholds are placed at 25%/75% of YOUR observed range
- it recalibrates automatically after long breaks
- the debug strip (bottom left) now shows `CAL down/up` or `CALIBRATING...`

**Vibration on every counted rep** - you now *feel* each rep immediately,
no need to look at the screen. (New VIBRATE permission.)

**True landscape lock** - `sensorLandscape` is now enforced at the Android
manifest level, so the app stays horizontal even when the phone is flat on
the floor (the previous lock was easy for the OS to override).

### New in M3: progression

- **Coins**: dropped by every kill (+3 per enemy, +25 for bosses) and a wave
  clear bonus that grows with the wave (10 + 5x wave)
- **Shop between waves** - 4 upgrades, spend coins during the rest timer:
  - **POWER** - +1 damage per pushup (up to Lv10)
  - **SPEED** - auto-attack chip damage gets faster, 4s down to 0.75s
  - **FORTRESS** - +25 max base HP (up to Lv8), +25 instant heal on purchase
  - **COMBO** - longer combo hold window (3s -> 8s)
- **Combo system**: consecutive reps inside the window stack a damage
  multiplier (+0.1 per rep, caps at x2.0) - shown top right while active
- **Auto-attack**: slow automatic chip damage (blue tracers) so the fight
  keeps breathing between your reps
- **Local save**: coins, upgrade levels and best wave persist across app
  restarts (shared_preferences) - progress is never lost
- **Defeat screen** now opens the same shop: upgrade, then retry the wave
- Rest timer with live countdown in the shop header; button starts early

### Pixel-art pass (visual overhaul)

The whole game got an authentic indie-quality pixel-art pass:

- **Hand-authored sprites** - grumbler enemies (12x12) and horned bosses
  (16x16) drawn pixel by pixel, rendered as crisp integer-scaled rects
  (nearest-neighbor, no antialiasing) from cached pictures
- **Frame-based animation** - 2-frame walk cycle with per-enemy phase (a
  group never steps in sync), irregular weight-shift idles at the gate,
  attack lunge synced to the hit, white hit flash + knockback, and a
  strobe-and-sink death animation with a particle poof
- **Handcrafted world** - procedural brick castle with merlons, arched
  wooden gate with iron bands and rivets, animated torch flames (2 frames,
  unsynced rates) with drifting embers, a fluttering banner, and textured
  ground whose grass lip is drawn in front of your feet
- **Pixel UI everywhere** - Press Start 2P font (SIL OFL), square
  ink-outlined panels, beveled card faces, buttons that press *into* the
  panel, segmented HP bars, level pips, a segmented rest countdown you can
  tap to start the wave early, and purchase feedback that floats off the card
- **Responsive combat feedback** - chunky spark particles, quantized-fade
  floating damage/coin numbers in a 3x5 pixel digit font, short hit-stop on
  kills, integer-pixel screen shake on base hits (HUD stays readable), and a
  combo pop animation with tier colors
- **No new dependencies** - everything is drawn from a small hand-written
  pixel-art core (`lib/m2/pixel_art.dart`): shared palette, digit font,
  cached sprite rendering

### Under the hood

- `lib/m2/economy.dart` - all formulas (costs, effects, rewards) as pure
  functions with unit tests
- `lib/m2/pixel_art.dart` - pixel-art core (palette, sprites, digit font,
  cached rendering) with its own test suite
- 34 passing tests (13 counter + 12 economy + 9 pixel art), analyzer clean

> Debug build signed with debug keys - for testing only.
