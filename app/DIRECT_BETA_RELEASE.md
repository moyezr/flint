# Direct Beta Release

This path is for Flint's direct-download beta while no Developer ID certificate
is available. It does not produce a notarized release and it must not be
described as Apple-verified.

The current direct beta is ARM64-only and must be advertised for Apple Silicon
Macs with macOS 14 or newer. Do not claim Intel compatibility for this artifact.

## Package

Create the private beta signing identity once on the release Mac:

```sh
cd app
Scripts/setup-beta-signing-identity.sh
```

The setup script stores the identity, dedicated keychain, password, public
certificate, and encrypted `.p12` backup under
`~/Library/Application Support/Flint Beta Signing`. It refuses to place them
inside the repository. Back up that directory securely and never regenerate
the identity while this beta channel remains active.

Then package a release:

```sh
cd app
FLINT_VERSION=0.1.0-beta.1 Scripts/package-direct-beta-dmg.sh
```

The script creates these files in `app/dist`:

- `Flint-<version>.dmg`
- `Flint-<version>.dmg.sha256`

The DMG includes only Flint and an Applications shortcut. Gatekeeper,
onboarding, and manual cleanup guidance lives on the public `/beta` page linked
from the mandatory pre-download notice. Readable third-party license/notices
files remain bundled inside Flint.app. Packaged builds contain the stable
release-manifest URL used for a lightweight daily update check.

It uses the persistent private `Flint Beta Signing` identity so macOS can treat
successive beta builds as the same code for privacy permissions. Packaging
fails instead of falling back to an anonymous ad-hoc signature when that
identity is unavailable. This private identity does not identify Flint to
Gatekeeper and does not replace Developer ID signing or notarization.

## Before Uploading

1. Download the exact DMG from its intended public host using a clean standard
   macOS user account.
2. Verify the published SHA-256 checksum.
3. Confirm the first-launch Gatekeeper instructions on `/beta` are accurate for
   the current macOS release and that the DMG contains only Flint and the
   Applications shortcut.
4. Verify Microphone and Accessibility permission flows, including shortcut monitoring after Accessibility is granted.
5. Compare the previous and new privately signed DMGs before publishing:

   ```sh
   Scripts/verify-beta-update-identity.sh <previous.dmg> <new.dmg>
   ```

   The verifier requires identical certificate-backed designated requirements
   and proves that each app satisfies the other build's requirement.
6. Install the packaged app, download a model, run Privacy → Uninstall Flint,
   and verify the model cache is cleared, Launch at Login is disabled, the app
   moves to Trash, and Flint quits. Reinstall before continuing release QA.
7. Publish versioned release notes, the checksum, installation instructions,
   privacy policy, beta terms, third-party notices, and a support contact
   alongside the download.

8. Publish both files from a durable public artifact host. Beta 11 is temporarily served from `landing/public/downloads`; move later builds to public object storage rather than accumulating binaries in Git history.
9. Update `landing/app/lib/beta/latest-release.ts` (or the corresponding production environment overrides), deploy the landing site, and run:

   ```sh
   FLINT_BETA_TEST_URL=https://flint.moyezrabbani.dev npm run landing:beta:verify
   ```

10. Run `npm run landing:production:verify` against the deployed domain and
   confirm the release response contains `supportedArchitectures: ["arm64"]`.

Every new beta build may require a new Gatekeeper approval. The first release
using the private identity also requires existing ad-hoc beta users to remove
the old Flint Accessibility row and add `/Applications/Flint.app` once. Later
privately signed betas must retain the same macOS privacy identity. Never modify
a published DMG in place; publish a new version instead.

Do not enable licensing for the free public beta. When a later paid release has a deployed and tested licensing API, set
`FlintLicenseEnforcement` to `true` in `Distribution/Info.plist` before
packaging a paid beta. Flint then validates its local license certificate at
launch and at most once per day, never during the push-to-talk shortcut path.
