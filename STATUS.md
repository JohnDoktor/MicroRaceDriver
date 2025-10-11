**Project Overview**
- Name: `MicroRaceDriver` (Flutter arcade racer)
- Rendering: CustomPainter road, cars, HUD; C64-inspired palette.
- Entry: `lib/main.dart` → `MenuPage` → `LeMansPage`.
- Platforms: iOS (actively tested), Android/macOS/web scaffolded.

**Core Gameplay**
- States: Countdown → Running → Game Over (timer removed).
- Player: lane-based car (drag + optional on-screen arrows). Arrows are 3× speed, disabled at `speed == 0`.
- World: AI traffic, hazards (oil/puddle), fuel + life pickups, dynamic curvature/road width, day/night, camera shake.
- Systems: Score, fuel, combo, risk-based multiplier, hi-score, 3 lives.

**Recent Changes (current session)**
- UI/Branding: App renamed to MicroRaceDriver. Custom app icon + native splash integrated.
- Performance: Low Graphics is forced on iOS; painter-driven repaints; HUD text caching; reduced blur radii.
- Night visuals: Headlight cones enabled even in Low Graphics (lighter blur). Tail light glow visible in Low Graphics (smaller/softer).
- Levels: Level increases every 2 minutes of runtime; brief banner shows “LEVEL N”; current level shown under lives (top-left).
- Perfect run multiplier: Every 1 minute without losing a life increases score multiplier by +1 (2x, 3x, …). Multiplier resets on life loss. Brief banner shows “PERFECT RUN - Nx POINTS”. Red badge under SPEED shows multiplier (>1x only).
- Continue UX: After choosing Continue on Game Over, a 3-second countdown appears before resuming.
- Lives: start with 3; lose on traffic/hazards/edge; Game Over at 0.
- Timer removed: no countdown, no time bonuses/penalties.
- HUD: top-left HI-SCORE + 3 car icons (cyan=remaining, dim=spent), level under lives. Right panel shows Score, Fuel (bar), Speed (boxes + km/h). HUD stays bright at night.
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
- Painter-driven repaints (ValueNotifier) to avoid full tree rebuilds each frame.
- Low Graphics path skips heavy glints; cones/tail glows use lighter blur.

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

Status last updated: Level system, perfect-run multiplier, countdown on Continue; headlight cones + tail glows visible in low graphics; HUD updates (level under lives, multiplier badge); performance refactors; TestFlight build 1.0.0 (8) uploaded.

**Publish Instructions**
- iOS/TestFlight:
  - Prereqs: Xcode signed into `john@johndoktor.dk` (Team `LD8P6KKV6Q`), Apple Distribution cert installed; keep `ek@nexus.dk` if needed (harmless login warnings).
  - Versioning: bump `pubspec.yaml` `version: <name>+<code>`; ensure `<name>` increases for App Store (e.g., 1.0.2) and `<code>` increments (e.g., +13).
  - Build IPA:
    - `flutter clean && flutter pub get && flutter build ipa`
    - Output: `build/ios/ipa/race_driver.ipa` (or `Runner.ipa` depending on Flutter version)
  - Upload options:
    - Transporter app: drag `build/ios/ipa/*.ipa`
    - CLI: `xcrun altool --upload-app -f build/ios/ipa/*.ipa -t ios --apiKey <key_id> --apiIssuer <issuer_id>`
    - Fastlane: `fastlane ios release` or `fastlane ios upload` (uses `fastlane/api_key.json`)
  - Notes/Troubleshooting:
    - “Invalid Pre-Release Train … 1.0.0 is closed”: bump `CFBundleShortVersionString` by editing `pubspec.yaml` version name, rebuild IPA.
    - “No signing certificate 'iOS Distribution' found”: Xcode → Settings → Accounts → your Apple ID → Manage Certificates… → add Apple Distribution.
    - Stale account warnings for `ek@nexus.dk` are safe; sign in again to silence.

- Android/Google Play:
  - Versioning: Android `versionCode` comes from the `+` number in `pubspec.yaml`, `versionName` from the left side; each upload must increase `versionCode`.
  - Build AAB (prod flavor):
    - `flutter clean && flutter pub get && flutter build appbundle --release --flavor prod`
    - Output: `build/app/outputs/bundle/prodRelease/app-prod-release.aab`
  - Signing: uses `android/app/upload-keystore.jks` with `android/keystore.properties` (already configured).
  - Manual upload:
    - Play Console → Your app → (Internal testing or Production) → Create release → upload the AAB above → enter release notes → roll out.
  - Automated upload (Fastlane):
    - Provide Google Play service account JSON at `fastlane/play.json` (or set `PLAY_JSON`/`PLAY_JSON_PATH`).
    - `fastlane android internal` (uploads to Internal track); adjust `track:` in `fastlane/Fastfile` for beta/production as needed.
  - Service account creation (summary): Play Console → Setup → API access → link GCP project → create service account → grant app access → in GCP, create JSON key → save as `fastlane/play.json`.

Quick paths
- iOS IPA: `build/ios/ipa/`
- Android AAB: `build/app/outputs/bundle/prodRelease/`

Current release baseline
- iOS: 1.0.1 (12) uploaded to TestFlight.
- Android: ready to upload `app-prod-release.aab` (1.0.1/12).
