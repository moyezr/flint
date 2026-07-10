# Flint Blockers

Items here are known product gaps that need external decisions or credentials before the related requirement can be completed.

## License Activation Backend

- Requirement: Phase 4 `License activation flow + Keychain storage`
- Current state: the app has Keychain-backed license storage, a testable activation service, and a License window. The default live activation client returns a deterministic "not configured" error.
- Blocker: no production licensing backend endpoint, request schema, response schema, or validation policy is defined in the repo yet.
- Next unblock: choose the licensing provider/backend contract and wire a real HTTP activation client into `LicenseWindowController`.

## Production Update Infrastructure

- Requirement: Phase 4 `Update system wired up`
- Current state: the app can detect whether Sparkle-style update metadata is present, but it does not perform update checks.
- Blocker: production updates require packaged `.app` builds plus Sparkle appcast hosting, release signing, and public EdDSA key configuration.
- Next unblock: define the release packaging pipeline and Sparkle appcast/signing infrastructure, then wire the production updater.
