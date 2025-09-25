Fastlane setup

Files:
- Fastfile: lanes for `build`, `upload` (TestFlight), `deliver_metadata`, and `release` (build+upload).
- Appfile: app identifier prefilled (`dk.johndoktor.racedriver`).
- api_key.json (not committed): place your App Store Connect API Key here.

API key:
1) App Store Connect → Users and Access → Keys → Generate API Key.
2) Download the `.p8` and note KEY ID and ISSUER ID.
3) Create `fastlane/api_key.json` with:
{
  "key_id": "KEYID12345",
  "issuer_id": "ISSUER-ID-UUID",
  "key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----",
  "in_house": false
}

Usage:
- bundle exec fastlane build
- bundle exec fastlane upload
- bundle exec fastlane release

Notes:
- Xcode automatic signing should be enabled in Runner.
- The `gym` lane exports with `app-store` method.
