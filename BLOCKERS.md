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

## Direct Download Signing Credentials

- Requirement: signed and notarized `.dmg` distribution from the Flint website.
- Current state: `Scripts/package-dmg.sh`, `Scripts/notarize-dmg.sh`, and `Scripts/release-preflight.sh` create and validate the intended release path with a macOS 14 deployment target.
- Blocker: the current login keychain has Apple Development identities only. A Developer ID Application certificate and an App Store Connect notarytool keychain profile are required to sign and notarize a public build.
- Next unblock: install the Developer ID Application certificate on the release machine, create a notarytool keychain profile, add `Distribution/Flint.icns`, then run the preflight, package, and notarization scripts against a release candidate.
