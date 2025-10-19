# MicroRaceDriver (Flutter)

A retro, C64‑inspired top‑down racer built in Flutter. The game renders with `CustomPainter` (road, cars, HUD, night lighting) and uses fully synthesized audio (engine, SFX, music). It targets iOS and Android and is optimized for smooth frame pacing on iOS.

About
- Built and shipped with AI (zero‑code). I provided direction, testing, and distribution decisions; the AI wrote code, compiled, ran the simulator, read logs, and fixed issues.
- Full case study and devlog linked below.

Highlights
- Painter‑first rendering: dual headlight cones at night, emissive tail lights, readable HUD.
- Core loop: lane driving, AI traffic, hazards, pickups, lives, score, fuel, difficulty ramp.
- Controls: swipe‑only steering with a brief “Swipe to steer” hint.
- Nitro: boosts world flow and raises HUD top speed.
- Audio: synthesized resonant‑noise engine, chiptune music loop, crunchy SFX.
- Performance: low‑graphics path on iOS, lighter blurs, painter‑driven repaints, prewarmed audio bytes.

Case Study
- Full write‑up: https://www.johndoktor.dk/l/microracedriver-shipping-a-retro-racer-with-llm-pair-programming/

License
- MIT — see `LICENSE`.

Run (local)
- `flutter pub get`
- iOS Simulator: `open -a Simulator && flutter devices && flutter run -d <sim>`
- Android: `flutter run -d <device-id>`

Build
- iOS (IPA): `flutter build ipa`
- Android (AAB, prod flavor): `flutter build appbundle --release --flavor prod`

Notes
- Secrets and private files are intentionally excluded from the repository (see `.gitignore` and pre‑push hook). Do not commit:
  - `fastlane/api_key.json`, `fastlane/play.json`, `android/keystore.properties`, `android/app/*.jks`
  - Logs and build artifacts
- Example templates are provided at `fastlane/api_key.json.example` and `fastlane/play.json.example`.

License
- Add a license here if you intend to open‑source the project.
