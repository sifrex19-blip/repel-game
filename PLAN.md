# 🏋️ Pushup Wave Defense — App Plan

> **Elevator pitch:** You prop your phone on the floor, it watches you with the camera,
> and every pushup you do lands a hit on the monsters attacking your castle.
> No reps, no damage — the only controller is your body.

**Status:** Planning phase
**Target:** iOS + Android (single codebase — Flutter)
**Last updated:** 2026-10-22

---

## 1. Concept

A fitness game where the front/back camera + on-device AI pose detection counts your
pushups in real time. Each counted rep = 1 attack against wave-based enemies.
Between waves you spend earned currency on upgrades (more damage per rep, auto-attacks,
new abilities). It blends:

- **Wave survival combat** (enemies march at your base; you hold the line with reps)
- **Idle game progression** (upgrades, currency multipliers, offline earnings)
- **Computer-vision fitness tracking** (real rep counting, form feedback)

## 2. Core Loop

```
  ┌──────────────────────────────────────────────────────┐
  │  Get in pushup position → phone camera watches you   │
  │         ↓                                            │
  │  Do pushups → AI counts each rep → rep = 1 attack    │
  │         ↓                                            │
  │  Enemies take damage / die → you earn coins (REPS 💪) │
  │         ↓                                            │
  │  Wave cleared → shop: buy upgrades & abilities       │
  │         ↓                                            │
  │  Harder wave starts → back to pushup position ───────┘
  └──────────────────────────────────────────────
  (Rest breaks between waves = where the "idle" pacing lives)
```

**Key design rule:** the player must *always* be able to see the enemy wave AND their
own camera feed at the same time. Phone on the floor, player in front of it, screen
visible mid-pushup (angled UI + big readable elements).

## 3. Game Design Sketch

### Combat
- Enemies walk toward your "base" from the right side of the screen
- Base HP depletes if enemies reach it → wave lost → retry (no punishment, roguelite-lite)
- Each valid pushup rep = 1 attack (targeting nearest/strongest enemy by upgrade)
- Combo system: consecutive reps without long pauses = damage multiplier
- **Idle element:** slow "auto-attack" chip damage you can upgrade, so progress
  never fully stops + small offline earnings when you return

### Enemies (waves)
- Wave N gets more HP + more enemies; every 5th wave = **boss**
- Enemy types: fast weak runners, slow tanks, shielded (need X reps in a row to break), flyers (need a different exercise later)
- Losing a wave just means: upgrade more, try again

### Upgrades / Economy
- Currency = coins earned per rep and per wave
- Upgrade tree ideas:
  - **Power** — more damage per rep
  - **Speed** — auto-attack rate
  - **Fortress** — base HP
  - **Combo** — multiplier decay speed, bonus damage
  - **Special abilities** — freeze wave, double damage for 10 reps, heal
- Prestige/"new game+" layer later: permanent multipliers for restarting the campaign

### Exercises (expansion path)
- v1: **pushups only**
- later: squats, sit-ups, planks, jumping jacks — same pose-detection pipeline,
  different joint-angle classifiers → each new exercise is cheap to add
- exercise choice per enemy type keeps workouts varied

## 4. MVP Scope (what to build first)

**In MVP:**
- Camera preview with pose skeleton overlay + pushup positioning guide
- Real-time pushup rep counting (on-device, no internet needed)
- Minimal game: one enemy type, waves that scale, rep = damage, base HP
- Coins + 4 basic upgrades, saved locally
- Simple art: placeholder shapes/sprites are fine
- Rest timer between waves

**Explicitly NOT in MVP:**
- Accounts, cloud sync, leaderboards
- Multiple exercises
- Sound/music polish, fancy animations
- Monetization of any kind
- Idle offline earnings

## 5. Tech Stack

| Layer | Choice | Why |
|---|---|---|
| Framework | **Flutter** (Dart) | One codebase → iOS + Android; best cross-platform camera + ML support |
| Game engine | **Flame** (Flutter package) | Standard 2D engine for Flutter, has the official Flutter Casual Games Toolkit |
| Pose detection | **google_mlkit_pose_detection** | Free, on-device, real-time; proven for pushup counting (open-source examples exist) |
| Camera | **camera** Flutter package | Feeds frames to ML Kit |
| Local storage | **shared_preferences / hive** | Save game state, upgrades, best waves — no backend needed |
| State management | **Riverpod** | Clean separation of game state / camera state / UI |
| Ads/IAP (post-MVP) | RevenueCat | Standard choice when we get there |

**No backend required** for launch — everything runs on-device. Keeps it simple,
private (camera frames never leave the phone — good marketing point), and free to run.

### How the rep counting works (the hard part, simplified)
1. Camera frame → ML Kit Pose Detection → 33 body landmarks (shoulders, elbows, wrists, hips…)
2. Compute **elbow angle** from shoulder–elbow– wrist points
3. Small state machine: `UP (angle > ~160°)` → `DOWN (angle < ~90°)` → back to `UP` = **+1 rep**
4. Anti-cheat filters: require hips visible + body roughly horizontal, reject reps faster
   than ~0.5 s, require minimum depth
5. Frames are downscaled + sampled (every 2nd frame) to keep it smooth on cheap phones

## 6. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Rep counting inaccurate | Core trust broken | Build M1 milestone as *only* the counter; tune thresholds with real testing before any game work |
| Player can't see screen mid-pushup | Game unplayable | Big UI, phone-on-floor layout test in M2; consider "voice callouts" (announcer) as backup |
| Phone heat/battery from camera+ML | Session cut short | Downscale frames, pause ML when idle, session length caps |
| iOS background camera restrictions | Can't do ambient tracking | Camera only works in foreground — design sessions around it (that's fine for this genre) |
| Flailing to fake reps | Fitness cheating only — user cheats themselves | Body-position filters; light "form score" instead of strict blocking |
| Scope creep (too many features) | Never ships | MVP list above is sacred; new ideas go to a "later" backlog |

## 7. Roadmap

- **M0 — Project setup** *(~1 weekend)*
  Flutter + Flame project skeleton, run on your phone, camera preview shows

- **M1 — Rep counter** *(~1–2 weeks, the risky one)*
  Pose overlay on screen, pushup state machine, tuned rep counting
  *✅ Exit criterion: counts 20 real pushups correctly, ignores non-pushup movement*

- **M2 — Minimal game** *(~1–2 weeks)*
  Enemies walk in, reps = damage, waves scale, base HP, win/lose
  *This is the "is this actually fun?" test — play it before polishing anything*

- **M3 — Progression** *(~1–2 weeks)*
  Coins, 4 upgrades, local save, rest timer, upgrade shop UI

- **M4 — Content & polish** *(~2–4 weeks)*
  Enemy types + bosses, sounds, real art, combo system, tutorial, onboarding

- **M5 — Ship** *(~1 week)*
  App icons, store listings, screenshots, privacy policy (camera usage!),
  TestFlight + Play Console closed testing, then public release

- **M6 — Detection hardening** *(2026-10-23)*
  Pose-gate glitch tolerance (a bad pose must persist before counting
  pauses — single flickery frames can no longer drop real reps), missing
  bodies now pause counting too, per-arm outlier rejection (the confident
  arm wins when the two disagree wildly), and a REP SENSITIVITY setting
  (STRICT / NORMAL / FORGIVING) so the hold window is tunable on-device

## 8. Open Questions (decide before/during M2)

1. **Name** — ideas: *Repel* (rep + repel), *Pushup Siege*, *Flex Defense*, *Reps vs. Monsters*
2. **Theme/art style** — pixel art? cartoon? cute blobs vs. dark fantasy?
3. **Monetization** (post-MVP) — best options for this genre: cosmetic skins,
   premium upgrade pack, or rewarded ads ("watch ad = 2× coins for this wave").
   Recommendation: **no ads, one-time premium unlock** — least annoying
4. **Voice feedback** — announcer callouts ("WAVE 3 CLEARED!") would massively help
   since the player is face-down most of the time
5. **Social features** — later: friend challenges ("who can survive more waves"),
   global leaderboard of waves survived
