# Repel 💪🎮

**A fitness wave-defense game. You prop your phone on the floor, the camera watches you,
and every pushup you do lands a hit on the monsters attacking your castle.**

No reps, no damage. The only controller is your body.

## How it works

```
Do pushups → on-device AI counts each rep → rep = 1 attack
        → enemies die → earn coins → buy upgrades → harder wave
```

- **All AI runs on-device** (Google ML Kit pose detection) — video never leaves your phone
- Camera frames are only read for body landmarks, never stored or uploaded
- One codebase for **Android + iOS** (Flutter + Flame)

## Tech stack

| Layer | Choice |
|---|---|
| Framework | Flutter |
| Game engine | Flame |
| Pose detection | google_mlkit_pose_detection |
| Camera | camera + permission_handler |

## Roadmap

- [x] **M0** — Project skeleton + live camera preview
- [x] **M1** — Pushup rep counting via pose detection *(needs on-device tuning)*
- [x] **M2** — Minimal combat prototype (reps = damage, waves, base HP)
- [ ] **M3** — Coins, upgrades, save system, rest timer
- [ ] **M4** — Enemy types, bosses, sounds, real art, tutorial
- [ ] **M5** — App store release

See [PLAN.md](PLAN.md) for the full design document.

## Running locally

```bash
flutter pub get
flutter run          # with an Android phone connected (USB debugging on)
```

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) and
Android Studio (for the Android SDK).
