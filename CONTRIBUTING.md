## Contributing

Thanks for your interest in MicroRaceDriver! A few quick notes to keep contributions smooth and safe:

- Secret hygiene: never commit credentials or keystores. The repo’s pre‑push hook scans for secrets and blocks risky pushes.
  - Install the hook: `bash tools/install-hooks.sh`
  - Examples are provided in `fastlane/*.example`; do not commit real `api_key.json`, `play.json`, or keystores.
- Branching: open a feature branch from `main` and submit a PR. Keep PRs focused and small.
- Style: follow existing patterns; prefer small, surgical diffs. Run `dart format .`.
- Testing: if you change hot paths (render/audio), add a short note in your PR for manual validation steps.

Suggested areas
- Persist Music/SFX toggles (`SharedPreferences`).
- Optional input polish: keyboard/haptics.
- Minor HUD/lighting tuning.

Questions? Open an issue and we’ll figure it out together.
