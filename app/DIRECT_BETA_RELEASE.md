# Direct Beta Release

This path is for Flint's direct-download beta while no Developer ID certificate
is available. It does not produce a notarized release and it must not be
described as Apple-verified.

## Package

```sh
cd app
FLINT_VERSION=0.1.0-beta.1 Scripts/package-direct-beta-dmg.sh
```

The script creates these files in `app/dist`:

- `Flint-<version>.dmg`
- `Flint-<version>.dmg.sha256`

It uses an anonymous ad-hoc code signature solely to seal the local bundle. It
does not identify Flint to Gatekeeper and does not replace Developer ID signing
or notarization.

## Before Uploading

1. Download the exact DMG from its intended public host using a clean standard
   macOS user account.
2. Verify the published SHA-256 checksum.
3. Confirm the first-launch Gatekeeper instructions are accurate for the
   current macOS release.
4. Verify Microphone, Accessibility, and Input Monitoring permission flows.
5. Publish versioned release notes, the checksum, installation instructions,
   privacy policy, support contact, and refund terms alongside the download.

Every new beta build may require a new Gatekeeper approval. Never modify a
published DMG in place; publish a new version instead.

When the licensing API has been deployed and tested, set
`FlintLicenseEnforcement` to `true` in `Distribution/Info.plist` before
packaging a paid beta. Flint then validates its local license certificate at
launch and at most once per day, never during the push-to-talk shortcut path.
