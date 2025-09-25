**Project Overview**
- Name: `RaceDriver` (Flutter arcade racer)
- Rendering: CustomPainter road, cars, HUD; C64-inspired palette.
- Entry: `lib/main.dart` → `MenuPage` → `LeMansPage`.
- Platforms: iOS (actively tested), Android/macOS/web scaffolded.

**Core Gameplay**
- States: Countdown → Running → Game Over (timer removed).
- Player: lane-based car (drag + optional on-screen arrows). Arrows are 3× speed, disabled at `speed == 0`.
- World: AI traffic, hazards (oil/puddle), fuel + life pickups, dynamic curvature/road width, day/night, camera shake.
- Systems: Score, fuel, combo, risk-based multiplier, hi-score, 3 lives.

**Recent Changes (current session)**
- Lives: start with 3; lose on traffic/hazards/edge; Game Over at 0.
- Timer removed: no countdown, no time bonuses/penalties.
- HUD: top-left HI-SCORE + 3 car icons (cyan=remaining, dim=spent). Right panel shows Score, Fuel (bar), Speed (boxes + km/h). HUD stays bright at night.
- Fuel: increased spawn; fuel bar color-coded (green/amber/red).
- Pickups: Added extra-life pickup (green box with +). Spawns every 120s when lives < 3.
- Road zero-speed: road scroll/curvature/width changes freeze; scene is still.
- Post-game ambiance: stopped at Game Over → occasional overtake car passes from bottom upward; no scoring/collisions.
- Progressive difficulty: every minute ramps AI/hazards and allows slimmer roads. First minute easier (fewer spawns, no slimming). Road min width can reach ~37% of screen. Object sizes remain constant via reference-width sizing.
- Visuals: Dual headlight cones with glints; brighter red tail lights for all cars; player has white headlights + tail lights.
- Menu: removed difficulty slider and controls selector; only Music and SFX checkboxes remain.
- Music lifecycle: background chiptune stops on Game Over and restarts from beginning on new game.

**Audio (current implementation)**
- Engine: fully synthesized resonant-noise model (pulse train + two noise resonators) with smoothing; 2.0s loop length; 5ms loop fade; equal-power crossfade (~500ms) between RPM loops; volume follows speed.
- Music: longer 32-bar chiptune loop; default volume halved; can be disabled via checkbox.
- SFX: synthesized beeps/whoosh/screech/splash/crash/game-over; all file-backed (DeviceFileSource) for iOS compatibility.
- iOS audio context set to Playback at startup (plays with mute switch on).

**Controls/UX**
- On-screen arrows: larger invisible hit areas; graphics unchanged.
- Menu: only checkboxes (Music, SFX). No pause UI in-game.

**Technical Notes**
- Constant object sizing: cars/hazards/pickups size from a captured reference road width; collisions/rendering use that base size.
- Engine loops: cached per-RPM files; equal-power crossfade to avoid gaps; RPM update threshold tuned; per-frame volume updates; no restarts during steady play.
- Remove clicks: loop fade window applied; longer loops reduce repetition.

**Known Issues / Warnings**
- WillPopScope is deprecated; consider migrating to PopScope.
- Some dependencies have newer versions; optional upgrade.

**Next Steps (suggested)**
- Engine: optional filter sweep opening with speed; gear/RPM stepping if desired.
- Audio toggles persistence: save Music/SFX checkboxes with SharedPreferences.
- Input: optional keyboard/haptics for desktop/mobile.
- Polish: migrate to PopScope; tune HUD/lighting.

**Run Instructions**
- `cd RaceDriver && flutter pub get`
- iOS Simulator: `open -a Simulator`, `flutter devices`, then `flutter run -d <sim>`
- If needed: terminate existing sim app: `xcrun simctl terminate booted dk.johndoktor.racedriver`

**iOS Bundle IDs**
- App: `dk.johndoktor.racedriver`
- Dev: `dk.johndoktor.racedriver.dev`

Status last updated: committed engine smoothing (resonant-noise + crossfade), halved music volume, menu simplified. Continue by tuning engine tone/crossfade length or persisting audio settings.
