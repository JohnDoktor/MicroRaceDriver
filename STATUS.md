**Project Overview**
- **Name:** `RaceDriver` (Flutter arcade racer)
- **Core Loop:** Ticker-driven update; `CustomPainter` renders C64-like road, cars, HUD.
- **Entry:** `lib/main.dart` → `MenuPage` → `LeMansPage`.
- **Target Platforms:** iOS (Simulator used), macOS, Android, Web (scaffolded).

**Gameplay Mechanics**
- **States:** Countdown → Running → Paused → Game Over.
- **Player:** Horizontal lane-based car; drag and/or on-screen arrow buttons.
- **World:** AI traffic, hazards (oil, puddle), fuel pickups, road curvature/width dynamics, day/night dimming, camera shake.
- **Systems:** Score, time, fuel, combo, risk-based multiplier, high score.

**Controls**
- **Drag Steering:** Always enabled when control mode allows; independent of speed.
- **Arrow Buttons:** 3× faster steering; ignored when `speed == 0`.
- **Pause:** Top-left button toggles pause; pause overlay allows difficulty/control changes.

**Recent Changes (This Session)**
- Lives system: start with 3 lives; decrement on traffic collisions, hazards, and road-edge impacts; Game Over at 0.
- HUD: three car icons at top-left (cyan = remaining, dim = spent); numeric lives also listed.
- Game Over behavior: decelerate gently to full stop; speedometer shows `0 KM/H` and can show 0 in all states.
- Road at zero speed: stop scrolling; freeze curvature and width changes; scene is completely still at `speed == 0`.
- Post-Game ambiance: while Game Over overlay is shown and speed is 0, occasionally spawn a car from the bottom that overtakes upward; normal traffic freezes; no scoring/collisions outside running.
- Controls: on-screen arrow steering is 3× faster; ignored at zero speed.

**Files of Interest**
- `lib/src/lemans/lemans_page.dart`: Game model, loop, rendering, input, audio, HUD, pause overlay.
- `lib/src/menu/menu_page.dart`: Main menu with control mode and difficulty.
- `lib/src/config.dart`: `GameConfig` (control mode, difficulty).
- `lib/src/lemans/palette.dart`: C64-inspired palette.

**Build & Run**
- Install Flutter (currently `Flutter 3.35.2`, Dart `3.9.0`).
- Fetch deps: `cd RaceDriver && flutter pub get`.
- iOS Simulator: `open -a Simulator` then `flutter devices` then run `flutter run -d "iPhone 16e"` (or pick your device).
- Hot reload/restart: In your terminal, press `r`/`R`.
- If Simulator app is already running from another session, terminate: `xcrun simctl terminate booted dk.johndoktor.racedriver`.

**Known Notes / Warnings**
- `WillPopScope` is deprecated; consider migrating to `PopScope` for back behavior.
- `flutter_native_splash` configured but not generated; run: `flutter pub run flutter_native_splash:create`.
- Some dependencies have newer versions; upgrades optional.

**Open Ideas / Next Steps**
- Styling: refine life icons (size, outline, color) or position.
- Day/Night: optionally freeze the cycle at `speed == 0` (currently continues).
- Input: add keyboard arrow support for desktop/web targets; haptics on collisions.
- Audio: upgrade `audioplayers`, add music or richer SFX.
- UX: replace `WillPopScope` with `PopScope`; improve pause/menu flow.
- Gameplay: nitro boost, checkpoints/laps, difficulty tiers, leaderboards.
- Testing: expand beyond basic HUD smoke test.

**Bundle Identifiers (iOS)**
- App: `dk.johndoktor.racedriver`
- Dev: `dk.johndoktor.racedriver.dev`

**Owner Notes**
- Lives decrement events are guarded by state; scoring/pickups/collisions only apply in `running` state.
- At Game Over + speed 0: only special overtake cars move from bottom to top.

— End of status —

