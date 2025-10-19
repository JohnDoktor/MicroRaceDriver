## Security and Secret Handling

This repo is sanitized for public sharing. The following policies and tooling help prevent accidental leaks of credentials or private files.

Key points
- No secrets in git: API keys, service accounts, keystores, and passwords must never be committed.
- Ignored by default: `docs/` and `pw/` are ignored and scrubbed from history; keep private notes or passwords there only locally.
- Examples only: `fastlane/api_key.json.example` and `fastlane/play.json.example` are templates. Copy them locally without committing real values.
- History scrubbed: previous sensitive paths and build artifacts were removed with `git filter-repo`.

Pre‑push secret scan (recommended)
- A pre‑push hook can block accidental pushes that include secrets or private folders.
- Install:
  - `bash tools/install-hooks.sh`
- Usage:
  - On every `git push`, the hook scans outgoing commits for common secret patterns and restricted paths.
  - To temporarily bypass (not recommended): `SKIP_SECRET_SCAN=1 git push`

Manual scans (optional)
- Gitleaks (fast, broad):
  - macOS: `brew install gitleaks`
  - Run: `gitleaks detect --no-banner --redact`
- TruffleHog (deep search):
  - `pipx install trufflehog`
  - Run: `trufflehog filesystem --no-update .`

Where to store secrets (local only)
- App Store Connect key: `fastlane/api_key.json` (based on `.example`)
- Google Play service JSON: `fastlane/play.json` (optional for automated uploads)
- Android keystore: `android/app/upload-keystore.jks`
- Keystore config: `android/keystore.properties`

Rotation and cleanup
- If a secret was ever committed/pushed:
  1) Rotate it (generate a new key, revoke the old one).
  2) Remove it from history with `git filter-repo`.
  3) Force‑push the cleaned history and invalidate any leaked tokens.

Questions
- If you need the docs/ content online, publish selected pages separately to a website repo; this project’s `docs/` remains local‑only by policy.
