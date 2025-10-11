# Release Guide

This is a concise checklist for publishing iOS (TestFlight/App Store) and Android (Google Play) builds for MicroRaceDriver.

## Versioning
- Edit `pubspec.yaml` → `version: <name>+<code>`
  - iOS requires `name` to increase for each App Store submission (e.g., 1.0.2).
  - Android requires `code` to increase for each upload (e.g., +13).
- Run `flutter pub get` after changing the version.

## iOS (TestFlight/App Store)
- Prerequisites
  - Xcode signed into `john@johndoktor.dk` (Team `LD8P6KKV6Q`).
  - Apple Distribution certificate installed (Xcode → Settings → Accounts → Manage Certificates… → “Apple Distribution”).
  - `fastlane/api_key.json` present for upload automation (already in repo).

- Build IPA
  - `flutter clean && flutter pub get`
  - `flutter build ipa`
  - Artifact: `build/ios/ipa/*.ipa` (often `race_driver.ipa`).

- Upload IPA
  - Transporter app: drag `build/ios/ipa/*.ipa`.
  - OR CLI: `xcrun altool --upload-app -f build/ios/ipa/*.ipa -t ios --apiKey <key_id> --apiIssuer <issuer_id>`
  - OR Fastlane: `fastlane ios release` (build + upload) or `fastlane ios upload` (upload only).

- After upload
  - Wait for App Store Connect processing (5–30 min typically).
  - Add to TestFlight groups or submit to review.

- Troubleshooting
  - “Invalid Pre-Release Train …”: bump `version` name (left side) in `pubspec.yaml` and rebuild.
  - “No signing certificate 'iOS Distribution' found”: add Distribution cert in Xcode Accounts.
  - Warnings about `ek@nexus.dk` session expiry are harmless; sign that account in again if desired.

## Android (Google Play)
- Prerequisites
  - Keystore is configured: `android/app/upload-keystore.jks` + `android/keystore.properties` (present).
  - For automated upload: Google Play service account JSON placed at `fastlane/play.json` (or set `PLAY_JSON`/`PLAY_JSON_PATH`).

- Build AAB (prod flavor)
  - `flutter clean && flutter pub get`
  - `flutter build appbundle --release --flavor prod`
  - Artifact: `build/app/outputs/bundle/prodRelease/app-prod-release.aab`

- Upload AAB
  - Manual: Play Console → (Internal testing or Production) → Create release → upload AAB → notes → roll out.
  - Automated: `fastlane android internal` (uses `fastlane/play.json`). Adjust `track:` in `fastlane/Fastfile` for beta/production.

- Service account JSON (how to create)
  - Play Console → Setup → API access → link GCP project → create service account → grant app access → in GCP, create key (JSON) → save as `fastlane/play.json`.

## Paths & IDs
- iOS bundle id: `dk.johndoktor.racedriver`
- Android package: `dk.johndoktor.racedriver`
- iOS IPA: `build/ios/ipa/`
- Android AAB: `build/app/outputs/bundle/prodRelease/`

## Useful Commands
- iOS: `xcrun altool --upload-app -f build/ios/ipa/*.ipa -t ios --apiKey <key_id> --apiIssuer <issuer_id>`
- TestFlight upload (fastlane): `fastlane ios upload`
- Android internal upload (fastlane): `fastlane android internal`

---

Notes
- Audio is fully synthesized and cached in-memory; startup warms caches for smooth playback on iOS/Android.
- If Play shows higher versionCode, bump `+<code>` and rebuild.
