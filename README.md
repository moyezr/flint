# Flint

<p align="center">
  <img src="assets/brand/Flint%20Logo%20Orange%20Bg.png" alt="Flint logo" width="96" height="96">
</p>

Flint is a local-first macOS dictation app. Hold a shortcut, speak, and release;
Flint transcribes on your Mac, cleans up the result, and inserts it at the
cursor.

This monorepo contains the native menu-bar app, the public website, and the
optional download and licensing services used by the official Flint deployment.
The code is available under the [MIT License](./LICENSE).

> [!NOTE]
> The current public beta is built for Apple Silicon Macs running macOS 14 or
> newer. Official beta builds are not notarized, so macOS shows its standard
> unverified-developer warning on first launch.

## What Flint does

- Runs transcription locally with WhisperKit after the selected speech model is
  downloaded.
- Supports push-to-talk and toggle shortcuts, including Right Option and Fn.
- Inserts dictated text at the captured cursor target while preserving the
  clipboard and preventing duplicate insertion.
- Provides Verbatim, Clean, Polished, Prompt, Message, and Email cleanup modes.
- Offers explicit, local vocabulary and correction learning that takes effect on
  the next dictation.
- Keeps history optional and stores no audio after a dictation finishes.
- Runs as a native menu-bar utility with no Dock icon.

## How it works

```mermaid
flowchart LR
    Shortcut[Global shortcut] --> Audio[Temporary audio recording]
    Audio --> Whisper[WhisperKit transcription]
    Whisper --> Dictionary[Local vocabulary]
    Dictionary --> Cleanup[Cleanup mode]
    Cleanup --> Policy[Output safety checks]
    Policy --> Insert[Exact-once insertion or copy]
    Insert -. after the core path .-> LocalData[Optional local history, metrics, and learning]
```

The dictation path is intentionally direct. Optional history, metrics, learning,
licensing refreshes, and update checks must never delay recording, transcription,
or insertion. See [Architecture](./docs/ARCHITECTURE.md) for the component map and
the invariants contributors should preserve.

## Repository layout

```text
app/                         Native Swift/AppKit/SwiftUI application
  Sources/Flint/             Application source
  Tests/FlintTests/          Unit and opt-in desktop integration tests
  Distribution/             Bundle metadata, entitlements, and generated icon
  Scripts/                  Packaging and release verification
landing/                     Next.js marketing site and server routes
  app/api/                   Beta download and optional licensing APIs
  db/migrations/             Append-only PostgreSQL migrations
  components/                Landing page and interactive components
assets/brand/                Canonical Flint logo masters
.github/workflows/           Native and web continuous integration
```

## Run the macOS app locally

### Requirements

- An Apple Silicon Mac running macOS 14 or newer
- Xcode or Xcode Command Line Tools with Swift 5.9 or newer
- An internet connection for Swift dependencies and the first speech-model
  download

Clone and run Flint:

```sh
git clone https://github.com/moyezr/flint.git
cd flint/app
swift run Flint
```

Flint appears in the macOS menu bar. Onboarding asks for:

- **Microphone**, to record speech for local transcription.
- **Accessibility**, to observe the configured shortcut and insert text into the
  active field.

Fresh Apple Silicon onboarding selects the Accurate model. The first run
downloads that model and shows its progress; subsequent runs reuse the local
copy.

Running through Swift Package Manager is best for development. macOS permission
records for a development executable can differ from those for an installed
`/Applications/Flint.app`, and Launch at Login is available only to a packaged
app. Use the direct-beta packaging workflow only when testing installation or
update behavior.

Run the native checks:

```sh
cd app
swift test
MACOSX_DEPLOYMENT_TARGET=14.0 swift build -c release
```

The Accessibility integration probes control real applications and are disabled
by default. Run them only on a test desktop where Flint may control TextEdit and
Safari:

```sh
cd app
FLINT_RUN_ACCESSIBILITY_INTEGRATION=1 swift test --filter TextInsertionIntegrationTests
```

## Run the website locally

The website uses Node.js 24, Next.js 16, and PostgreSQL for beta signup and
licensing routes.

For the marketing UI:

```sh
npm ci --prefix landing
npm run landing:dev
```

Open [http://localhost:3000](http://localhost:3000). Static marketing pages work
without production credentials. Email verification, downloads, and licensing
routes require PostgreSQL and the server-only values documented in
[`landing/.env.example`](./landing/.env.example).

For the complete service:

```sh
cp landing/.env.example landing/.env
# Fill in local PostgreSQL, Resend, pepper, and signing-key values.
npm run landing:db:migrate
npm run landing:dev
```

Never prefix a database URL, private signing key, email-provider key, pepper, or
webhook secret with `NEXT_PUBLIC_`. More detail is available in
[Landing development](./landing/README.md) and the
[Licensing API guide](./landing/LICENSE_API.md).

Run the website checks:

```sh
npm run landing:test
npm run landing:lint
npm run landing:build
```

## Privacy and local data

Dictation audio and transcript processing stay on the Mac. Flint uses the network
to download speech models, check official release metadata, and—only when enabled
in a future paid build—activate or renew a license. The free beta does not require
activation.

Default local data locations include:

- Models: `~/Library/Application Support/Flint/Models/`
- Learning: `~/Library/Application Support/Flint/Learning.sqlite`
- Optional history and app rules: `~/Library/Application Support/Flint/History.sqlite`
- Settings: the macOS preferences domain for Flint
- Device and license material: ThisDeviceOnly macOS Keychain items

Recordings are temporary and deleted after processing or cancellation. Flint's
Privacy screen can remove all local data, and its in-app uninstall action removes
local data before moving the packaged app to Trash.

## Releases

The official beta download archive under `landing/public/downloads` retains the
latest five immutable DMGs and their SHA-256 checksums. When a sixth version is
published, the oldest pair is removed from the current branch. Release
credentials and the private beta-signing identity are maintainer-owned local
secrets and are never required to build Flint from source.

The current direct beta is privately signed to preserve its macOS permission
identity across updates, but it is not Developer ID signed, notarized, or
Apple-verified. See [Direct beta release](./app/DIRECT_BETA_RELEASE.md) for the
maintainer workflow.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](./CONTRIBUTING.md) before making
a change, especially if it affects shortcuts, Accessibility, insertion, local
data, or the core dictation path. Security issues should be reported privately as
described in [SECURITY.md](./SECURITY.md).

## License and branding

Flint's original source code is licensed under the [MIT License](./LICENSE).
Third-party components retain their respective licenses. The license does not
grant permission to imply that a fork or modified build is an official Flint
release; see [TRADEMARKS.md](./TRADEMARKS.md).
