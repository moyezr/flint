# Flint Agent Guide

This is the first file an agent should read before changing Flint. It records the current product behavior, architectural boundaries, local workflows, and release state that are easy to lose between sessions.

Last reconciled with the working tree on 2026-07-20.

## Product North Star

Flint is a native, local-first macOS dictation utility and its marketing/licensing website. The core loop is:

```text
hold shortcut -> speak -> release -> local transcription -> dictionary -> cleanup -> insert at cursor
```

The dictation loop is the product. Recording must start promptly, the app must remain responsive, insertion must happen once, and optional systems such as learning, history, licensing refresh, metrics, or retention must never delay that path.

Core promises:

- The current direct beta is ARM64-only for Apple Silicon Macs running macOS 14 or newer; the app remains a menu bar utility with no Dock icon. Its status menu provides an enabled `Quit Flint` action that terminates through `NSApplication`, allowing normal shutdown cleanup to run.
- Audio and transcript processing stay on the Mac. Whisper models may require a network download before first use, and paid builds use the network for activation/occasional renewal, but dictation itself is local.
- No account is required for dictation beyond the one-time license activation planned for paid builds.
- Free public beta through a direct `.dmg`; the later paid release is planned as a one-time purchase, not a subscription.
- Preserve the user's clipboard and never insert a dictation twice.
- Personalization is local, per user, explicit, reviewable, scoped, and deletable.
- Do not copy VoiceInk or another product's code, assets, copy, name, icon, or layout. This is a clean-room proprietary implementation.

Prefer readable, direct Swift over speculative abstraction. Do not introduce plugin systems, event buses, dependency-injection frameworks, or future-proof layers without a second real use case.

## Source-of-Truth Order

Use this order when documents disagree:

1. Current source and tests.
2. This `AGENTS.md` for current product decisions and working conventions.
3. `app/FLINT_V1_IMPLEMENTATION_GUIDE.md` for explicit-personalization V1 invariants.
4. `app/SELF_IMPROVING_DICTATION_PLAN.md` for future learning gates and branches.
5. `app/PRODUCTION_READINESS.md` and `app/DIRECT_BETA_RELEASE.md` for release qualification.
6. `app/REQUIREMENTS.md` for the original product direction.

Known stale material:

- `app/REQUIREMENTS.md` still describes personalization as future work and a small rectangular overlay. Explicit personalization and the notch/Dynamic Island overlay now exist.
- Its phase checkboxes are not an accurate status report.
- `app/BLOCKERS.md` says the licensing client/backend are unimplemented. The native certificate flow and Next.js licensing API now exist; production deployment, payment fulfillment, and end-to-end qualification remain unfinished.
- The landing pricing copy says personal adaptation is only a roadmap item. Explicit vocabulary and correction learning already exist.

Update stale documents when changing the corresponding behavior. Do not silently implement the deferred passive-learning or pronunciation branches merely because an older plan mentions them.

## Repository Map

```text
app/                         Swift Package for the native macOS app
  Sources/Flint/             AppKit/SwiftUI implementation
  Sources/Flint/Learning/    Explicit local personalization
  Tests/FlintTests/          Unit and opt-in desktop integration tests
  Distribution/             Info.plist, entitlements, production icon
  Scripts/                  Packaging, notarization, and QA inventory
  REQUIREMENTS.md            Original requirements; partially stale
  PRODUCTION_READINESS.md    Compatibility/release evidence checklist
  DIRECT_BETA_RELEASE.md     Ad-hoc beta packaging path
landing/                     Next.js 16 App Router marketing/licensing app
  app/api/licenses/          Activation, validation, deactivation, transfer API
  app/lib/licenses/          Server-only licensing implementation
  db/migrations/             Append-only PostgreSQL migrations
  components/                Landing page, dot grid, and typing test
.github/workflows/           macOS app and Linux landing CI
```

The root npm workspace only orchestrates `landing/`. The Swift package lives under `app/`; run Swift commands there.

## Local Commands

Run the app:

```sh
cd app
swift run Flint
```

Stop an older CLI-launched instance with `Ctrl+C` before testing a new build. A running process does not hot-reload code.

Validate the Mac app:

```sh
cd app
swift test
MACOSX_DEPLOYMENT_TARGET=14.0 swift build -c release
```

Run the opt-in Accessibility probes only when it is safe for the test runner to control TextEdit and Safari:

```sh
cd app
FLINT_RUN_ACCESSIBILITY_INTEGRATION=1 swift test --filter TextInsertionIntegrationTests
```

Run and validate the website:

```sh
npm install
npm run landing:dev
npm run landing:test
npm run landing:lint
npm run landing:build
```

Current verified baseline: 289 Swift tests pass, two desktop Accessibility probes are skipped by default, the release build succeeds, and landing tests/lint/build succeed.

## Native App Architecture

`AppCoordinator` is the main actor and orchestration root. Avoid moving ordinary workflow logic into a new framework. The current dictation path is:

1. `ShortcutManager` interprets Right Option, Fn, Control+Space, or Cmd+Shift+Space in push-to-talk or toggle mode. Escape cancels.
2. `AppCoordinator.startDictation()` checks local license authorization, installed/prepared model state, captures the active app and preferred AX insertion target, shows the overlay, and starts `AudioRecorder`.
3. `AudioRecorder` records a temporary `.m4a`. It exposes average and peak metering values for the visualizer.
4. `TranscriptionEngine` reuses a cached WhisperKit pipeline selected through `ModelManager`.
5. `DictionaryEngine` applies the immutable `MemorySnapshot` plus built-in developer vocabulary.
6. `CleanupEngine` applies the selected mode and explicit formatting preferences.
7. `DictationOutputPolicy` rejects empty output.
8. With Auto Insert enabled, `TextInsertionEngine` inserts once through the safe fallback chain. With it disabled, Flint copies once and makes no AX or paste mutation attempt.
9. The result is placed in the memory-only recent buffer; optional metrics, history, and usage-count writes happen afterward.
10. The temporary recording is deleted.

Important files:

- `AppCoordinator.swift`: lifecycle, menu, core loop, timeouts, model recovery, recent corrections.
- `ShortcutSettings.swift`: global event tap and shortcut state machine.
- `AudioRecorder.swift`: AVAudioRecorder and metering.
- `ModelManager.swift`: Fast (`tiny`), Balanced (`base`), and Accurate (`large-v3-v20240930_626MB`) downloads under Flint's cache root. Fresh Apple Silicon onboarding selects Accurate without a model picker; Intel onboarding defaults to Balanced and keeps the picker. Existing persisted choices are preserved.
- `TranscriptionEngine.swift`: cached WhisperKit pipelines and user-facing transcription errors.
- `ModelPreparationLifecycle.swift`: generation-based preparation/retry state. A preparation failure must be recoverable by the next shortcut press; never require a process restart.
- `CleanupEngine.swift`: Verbatim, Clean, Polished, Prompt, Message, and Email modes.
- `TextInsertion.swift`: AX insertion, rich-composer protections, paste fallback, and clipboard restoration.
- `LaunchAtLogin.swift`: installed-app-only `SMAppService.mainApp` registration and approval state. `swift run` cannot register a login item.
- `AppUninstaller.swift`: validates the packaged Flint bundle, then asks Finder to move only that bundle to Trash after the full local-data purge succeeds.
- `OverlayWindow.swift`: notch geometry, window motion, state accessories, and audio visualization.
- `SettingsWindow.swift`, `OnboardingWindow.swift`, `PrivacyWindow.swift`: user-facing configuration and data controls.
- Onboarding model downloads surface WhisperKit's real determinate progress and keep navigation disabled through first-use model preparation.
- `HistoryStore.swift` and `AppModeRuleStore.swift`: history and app-mode rules in the same SQLite database.
- `LicenseRuntime.swift`: dormant production device identity, signed offline certificate, API client, and runtime authorization; enforcement is off during the free beta.
- `UpdateManager.swift`: one small HTTPS release-manifest check at most daily in packaged builds. Offline failures are silent and never affect dictation.

The model preparation timeout is 120 seconds and processing timeout is 90 seconds. Preserve generation/processing IDs so stale async completions cannot alter current UI state.

## Insertion Safety

Text insertion is the highest-risk behavior. Preserve these rules and extend tests before changing it:

1. Default targeting is the text field captured when recording starts.
2. Standard controls try the captured AX target, then the current focused AX target, then one preserved-clipboard paste, then copy-only.
3. Rich web composers and the ChatGPT desktop composer are paste-only. An accepted AX mutation may update asynchronously; retrying another strategy can duplicate text.
4. A captured rich composer is pasted into only if the currently focused rich composer belongs to the same process. Otherwise copy to clipboard.
5. Placeholder values such as `Ask ChatGPT` must be recognized as placeholders and never appended to the dictation.
6. Paste fallback snapshots every pasteboard item/type, submits one Cmd+V, then restores after 0.75 seconds only if the user has not changed the clipboard.
7. Never infer insertion failure solely from a delayed AX value read, and never add a second mutation attempt after AX reports success.

Manually retest ChatGPT/browser rich editors whenever target detection or fallback ordering changes. The original failure was duplicate text at both the start and cursor plus composer placeholder text such as “Ask ChatGPT”.

## Notch / Dynamic Island UI

The compact overlay is intentionally integrated with MacBook notch geometry rather than floating as a large bottom panel.

- Anchor to `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea` when a hardware notch exists; center a compact fallback on displays without one.
- Keep height at 42 points and reserve the physical notch as the center. Expand through small left/right wings instead of covering a large part of the screen.
- Listening: pulsating orange dot on the left, seven small vertical audio bars on the right.
- Processing/preparing/inserting: pulsating dot on the left and a compact spinner on the right. Do not restore the wide horizontal loader.
- Success: check/copy icon on the left and `Fix` / `Teach` actions on the right.
- Errors: compact left icon and a bounded, single-line right message. Silent/no-speech errors must not create a large window and auto-hide after 3 seconds; actionable errors remain visible.
- Opening, resizing, and closing are animated. Auto-hide is generation-guarded so an old timer cannot hide a newer state.

The visualizer updates on the existing 50 ms timer. It reads `AVAudioRecorder` average and peak power once and derives seven independently smoothed bars from loudness, crest, and transients. It is intentionally not an FFT or true pitch analyzer; do not add a second capture pipeline merely for decoration without measuring the cost.

## Explicit Personalization V1

Personalization is implemented, local to each Mac user, and active without restarting Flint:

- `Teach Flint` creates an active vocabulary memory and publishes a rebuilt `MemorySnapshot`; it affects the next dictation.
- `Fix This Dictation` edits one of the last 10 successful outputs. `Save & Copy` stores the frozen before/after pair and copies corrected text, but never rewrites a potentially stale original field.
- Recent dictations are memory-only, capped at 10, and disappear on relaunch.
- The store is `~/Library/Application Support/Flint/Learning.sqlite`, owned by the `LearningStore` actor, using WAL and foreign keys.
- Explicit correction evidence is capped at 90 days or 2,000 rows. The learning database has a 50 MB high-water policy. Approved/user-created memories are never automatically pruned.
- The core dictation path reads only an immutable in-memory `MemorySnapshot`; it never queries SQLite.
- Learning failures degrade to built-in vocabulary and must not break dictation.
- Application-scoped entries override global entries; exact language overrides `auto`; longer phrases win.
- Active mappings are applied synchronously; usage counters and metrics write in background tasks.
- Legacy UserDefaults vocabulary is migrated idempotently and retained temporarily for rollback safety.

Avoid blind corrections for ambiguous natural language. `CorrectionMappingPolicy` marks homophones and common phrases transformed into styled entities as context-required. For example, do not learn `next year -> Next.js`; teach a distinctive spoken form such as `next jay ess -> Next.js`, preferably scoped to the relevant app. Context-required corrections may be stored as evidence but are excluded from automatic application.

Do not add these features without an explicit Gate A/Gate B decision from `SELF_IMPROVING_DICTATION_PLAN.md`:

- Passive Backspace/Delete observation.
- Global keystroke capture or Accessibility field monitoring.
- Retry-pair detection or delete-and-redictate inference.
- Word timestamps/transformation provenance solely for learning.
- Audio retention, decoder biasing, acoustic adaptation, or model fine-tuning.

Pronunciation/accent adaptation is not currently implemented or promised. Vocabulary/formatting personalization and pronunciation learning are separate product branches.

## Local Data and Privacy

Default data locations:

- Settings: `~/Library/Preferences/<bundle-id>.plist` (or `Flint.plist` for unbundled `swift run`).
- Models: `~/Library/Application Support/Flint/Models/`.
- Learning: `~/Library/Application Support/Flint/Learning.sqlite` plus WAL/SHM.
- Optional history and app-mode rules: `~/Library/Application Support/Flint/History.sqlite` plus WAL/SHM.
- License record, offline lease, and per-device Ed25519 private key: separate `ThisDeviceOnly` Keychain items.
- Recordings: temporary `.m4a` files deleted after transcription/cancellation.

During onboarding, Flint proactively requests any missing microphone, Accessibility, and Input Monitoring permissions when the permissions step first appears. The manual prompt button remains available for retries after a denial or System Settings change.

History is off by default and never stores audio. Explicit learning remains separate from history and stores only user-invoked corrections/mappings. Local metrics are content-free UserDefaults counters and are never uploaded. Telemetry is not implemented.

`Delete All Local Data` clears settings, models, history/rules, learning database, local metrics, legacy vocabulary, and license/device Keychain state. `Uninstall Flint` validates that the process is the packaged `com.moyezrabbani.Flint` app before deleting data, reuses that full purge, disables Launch at Login, asks Finder to move the validated app bundle to Trash, and quits only after Finder confirms the move. A direct Finder deletion cannot trigger application cleanup, so the website and DMG README document manual model-folder cleanup as a fallback. Preserve test coverage whenever a new persistence surface is introduced.

## Licensing and Website

The native production license flow targets `https://flint.moyezrabbani.dev/api/licenses` and bundle ID `com.moyezrabbani.Flint`.

- Each Mac creates a `ThisDeviceOnly` Ed25519 device key.
- Activation/validation/deactivation use 10-minute, single-use signed challenges.
- The server issues an Ed25519-signed certificate bound to the app bundle and device public-key hash.
- Certificates are valid offline for 90 days by default; local verification occurs at launch/at most daily, and server renewal is attempted after 30 days in background.
- One active Mac is allowed. A replacement Mac requires purchaser confirmation by email before the old activation is revoked.
- `FlintLicenseEnforcement` is deliberately `false` in `Distribution/Info.plist` until the production service is deployed and verified.

The current free beta does not require activation. The website records beta download emails and versioned beta-terms acceptance in PostgreSQL, applies short-lived HMAC-pseudonymized rate limits, issues short-lived one-time redirect tokens, and shows a mandatory pre-download Gatekeeper explanation before sending the browser to the immutable ARM64 DMG currently deployed from `landing/public/downloads`. The direct-beta DMG also contains `READ ME FIRST.txt`. Optional product-email consent is stored separately from required beta-access/terms consent. Move future binary storage to a public object/release host before repeated releases make Git history expensive.

Packaged builds fetch `https://flint.moyezrabbani.dev/api/releases/latest` at most once per 24 hours. A successful newer-version response adds a dot to the menu-bar mark and changes `Check for Updates` into a download action. Checks time out quickly, do not run for `swift run`, and never block dictation. During the unnotarized beta, installation remains user-confirmed through the website; a Sparkle-style in-place updater is deferred until releases can be Developer ID signed.

The Next.js app owns both marketing and licensing routes. Licensing secrets must remain server-only; never expose the database URL, pepper, Resend key, webhook secret, or private signing key through a `NEXT_PUBLIC_` variable. PostgreSQL migrations are append-only. The commerce webhook currently validates a placeholder HMAC and returns HTTP 501 until a payment provider is chosen.

Landing-specific behavior:

- Next.js 16, React 19, Tailwind CSS 4, App Router.
- Canvas/GSAP dot grid uses subtle transparent orange at rest and stronger orange near the pointer. Content sections must remain above it (`relative z-10`) so text stays selectable and accessible to crawlers.
- Smooth scrolling is enabled, with reduced-motion fallback.
- Navbar and hero download actions link to `#download`; the typing-test target still uses `scroll-mt-[calc(50svh-204px)]` to approximately center the component.
- Typing test uses one of eight predefined passages, a 15-second timer, early completion, cancel/retry, and per-letter green/red feedback. Completed runs with at least 15 characters show a concise WPM comparison against a clearly labeled roughly-130-WPM speech pace and a monthly time-value estimate with visible assumptions; formulas are collapsed by default. Results enter with a short upward fade and a lightly staggered pace comparison, disabled under reduced-motion preferences. Faster-than-baseline and insufficient-input runs use honest non-financial states. A calculated monthly time value is also surfaced in the free early-access pricing block for that page session.
- `POST /api/beta-signups` requires current beta-terms acceptance, stores a normalized email, enforces short-lived database-backed abuse limits, and returns a 15-minute one-time download handoff. `GET /api/beta-download` consumes it and redirects to the current versioned DMG. Run `npm run landing:beta:export` to export collected emails as CSV.

Native onboarding uses Flint's orange accent, warm gradients, rounded material cards, SF Symbol illustrations, and short friendly guidance. Keep this visual language when adding setup steps; do not regress it to an unstyled form sheet.
- `/privacy`, `/terms`, `/third-party-notices`, `/support`, and `/beta` are the public legal/support/install surfaces. `moyezrabbani.work@gmail.com` is the intentionally simple support contact.
- Global response security headers are configured in `next.config.ts`. Run `npm run landing:production:verify` after deployment; run `npm run landing:db:backup` only with an explicit private backup directory.

## Testing Expectations

Every behavior change needs focused tests plus the full relevant validation. At minimum before checkpointing app work:

```sh
cd app
swift test
MACOSX_DEPLOYMENT_TARGET=14.0 swift build -c release
```

Before checkpointing landing work:

```sh
npm run landing:test
npm run landing:lint
npm run landing:build
```

CI runs landing checks on Ubuntu/Node 24 and Swift checks on the macOS 15 runner while preserving Flint's macOS 14 deployment target. The newer runner SDK is required by the pinned Argmax dependency. Do not treat unit tests as proof of system-wide insertion. Before release, run the opt-in probes and the manual compatibility matrix in `app/PRODUCTION_READINESS.md`.

For insertion QA, verify exact-once output and unchanged clipboard contents on fresh launch and repeated use. Record macOS version, Mac hardware, model tier, target app/version, observed insertion method, and permissions.

## Release Paths

Ad-hoc direct beta (not Apple-verified):

```sh
cd app
FLINT_VERSION=0.1.0-beta.1 Scripts/package-direct-beta-dmg.sh
```

Production path:

```sh
cd app
FLINT_SIGNING_IDENTITY="Developer ID Application: ..." Scripts/release-preflight.sh
FLINT_VERSION=1.0.0 FLINT_BUILD=1 FLINT_SIGNING_IDENTITY="Developer ID Application: ..." Scripts/package-dmg.sh
FLINT_DMG_PATH=dist/Flint-1.0.0.dmg FLINT_NOTARY_PROFILE=<profile> Scripts/notarize-dmg.sh
```

Never describe the ad-hoc beta as signed/notarized or Apple-verified. Never modify a published DMG in place; publish a new version and checksum.

## Current Launch Gates

These are the material remaining items as of the date at the top of this file:

1. Complete the remaining Apple Silicon manual reliability evidence: a clean-standard-user onboarding pass, a 10–15 minute dictation, silence, permission revocation, model interruption/corruption/low-disk recovery, target switching, and recorded exact-once/clipboard checks. Ordinary browser use and sleep/wake have developer smoke coverage but the formal matrix remains incomplete.
2. The free beta may remain transparently ad-hoc signed and unnotarized because no Apple Developer Program membership is available. Developer ID signing/notarization remains a later paid/lower-friction release gate, not a claim for the current beta.
3. Deploy migration `0003`, the hardened landing build, and the ARM64 release metadata with production PostgreSQL, HTTPS, backups, monitoring, and abuse controls. Run both production verifiers and one restore drill against real infrastructure.
4. Payment selection, commerce fulfillment, and license activation are deliberately deferred until the free beta has validated retention and a paid release is chosen.
5. Enable `FlintLicenseEnforcement` only after the deployed API and a real beta key pass activation/renewal/offline tests.
6. Replace the beta manifest/download prompt with a signed in-place updater only after Developer ID signing is available; the current daily manifest check is the safe unnotarized-beta path.
7. Replace remaining placeholder product media when the developer supplies the launch assets, then verify responsive/accessibility/SEO behavior on production.
8. The Privacy Policy, Public Beta Terms, Third-Party Notices, support page/email, Gatekeeper instructions, release notes, and checksum are implemented. Before accepting payment, obtain jurisdiction-specific review and publish separate purchase/refund terms.
9. `launchAtLogin` and `autoInsert` are implemented and user-facing. `showOverlay` remains persisted but unused; hiding the overlay would also remove listening/error feedback and Fix/Teach actions, so remove it or define a safe reduced-feedback experience before exposing it. URL-pattern app rules remain unable to match until safe URL detection exists.
10. Intel is not in the current beta scope because the published DMG is a thin ARM64 executable. Do not advertise Intel support unless a universal build and physical qualification become available.

Classifier/Accessibility research and pronunciation adaptation are post-launch product gates, not blockers for shipping explicit personalization. Do not market accent learning before Gate B has been deliberately funded and implemented.

## Git and Workspace Discipline

- The main branch is `main`; remote is `origin` on GitHub.
- The user prefers small tested checkpoints committed and pushed after completed implementation work.
- Inspect `git status` before and after edits. Preserve unrelated or untracked user files.
- `.vscode/` is currently untracked user configuration. Do not stage, edit, delete, or commit it unless explicitly requested.
- Stage only task-owned paths. Do not use destructive reset/checkout commands.
- Documentation-only changes still require `git diff --check`; run build/test validation when documentation describes current verified status or release behavior.

When handing off, lead with what changed, list validation evidence, include the commit hash if committed, and tell the user to restart `swift run Flint` when runtime code changed.
