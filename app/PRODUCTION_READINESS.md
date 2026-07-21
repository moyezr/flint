# Flint Production Readiness

Flint is currently distributed as a free, unnotarized, ARM64-only public beta from the Flint website for Apple Silicon Macs running macOS 14 or newer. The later paid release is intended to be a one-time purchase distributed as a signed, notarized `.dmg`. Dictation does not require an account, cloud transcription, or an ongoing network connection after model preparation.

## Compatibility Matrix

Run the same push-to-talk scenario in each target before paid beta: focus a text field, dictate a short sentence, release the shortcut, verify the exact text is inserted once, then verify the original clipboard remains unchanged.

| Surface | Status | Notes |
| --- | --- | --- |
| TextEdit | Automated baseline passed | Production insertion engine and clipboard restoration pass in a disposable native document; manual voice scenario remains. |
| Notes | Pending | Native rich text. |
| Safari | Automated baseline passed | Production insertion engine and clipboard restoration pass in a local page input; manual standard-input, textarea, and contenteditable scenarios remain. |
| Chrome | Pending | Chromium needs live Flint validation; the desktop test runner cannot verify its synthetic-paste fallback. |
| Arc | Pending | Chromium accessibility behavior. |
| Firefox | Pending | Gecko accessibility behavior. |
| Gmail | Pending | Web rich-text composer. |
| Google Docs | Pending | Canvas/contenteditable document surface. |
| Notion | Pending | Web rich-text editor. |
| Linear | Pending | Web command and issue editors. |
| Slack | Pending | Native and web composer. |
| Discord | Pending | Native and web composer. |
| Cursor | Pending | Monaco editor and chat inputs. |
| VS Code | Pending | Monaco editor and terminal. |
| Xcode | Pending | Source editor and text fields. |
| Terminal | Pending | Shell prompt. |
| iTerm2 | Pending | Shell prompt. |
| Messages | Pending | Native message composer. |
| Microsoft Word | Pending | Rich document editor. |

For each result, capture the macOS version, Mac model, selected Flint model tier, target app/version, insertion method observed, and any permission state. A surface is only complete after fresh-launch and repeated-use checks both pass.

The developer reports successful ordinary browser use and sleep/wake recovery on the current Apple Silicon QA Mac. This is useful smoke evidence but does not replace the recorded per-surface matrix. Intel qualification is deferred because the current DMG contains no Intel executable and does not advertise Intel support.

Run `Scripts/compatibility-inventory.sh > qa-compatibility-inventory.md` at the start of each manual matrix run to capture the macOS, hardware, target-app versions, and local availability in a reviewable format.

### Local QA Inventory

The current QA Mac has TextEdit, Notes, Safari, Chrome, Firefox, Discord, Cursor, VS Code, Xcode, Terminal, Messages, and Microsoft Word installed. Arc, Slack, and iTerm2 are not installed. Gmail, Google Docs, Notion, and Linear require authenticated browser sessions. Installation only establishes test availability; all rows remain pending until the full manual scenario passes.

Run `FLINT_RUN_ACCESSIBILITY_INTEGRATION=1 swift test --filter TextInsertionIntegrationTests` before each release candidate. This exercises Flint's actual insertion engine in a disposable TextEdit document and an autofocused local Safari input, confirms one insertion, and verifies clipboard preservation. It is a native/browser baseline probe, not a substitute for the manual voice-dictation scenario in the full matrix.

## Reliability Checks

- Repeated shortcut press/release cycles under normal typing load.
- Left/right modifier handling, toggle mode, Escape cancellation, and shortcut changes while Flint is running.
- Short, long, and silent dictations; model preparation failure; no network after models are prepared.
- Sleep/wake, display changes, app switching during transcription, and target field changes before insertion.
- Permission denial/revocation for Microphone and Accessibility.
- Clipboard preservation for text, rich text, files, and multiple clipboard items.
- Model deletion, interrupted model download, corrupted model/tokenizer cache, and low disk space. Flint records a payload fingerprint after download, invalidates changed or empty caches, and enables a clean retry when model preparation fails.
- Packaged uninstall from a writable installed copy: verify downloaded models and other local data are deleted, Launch at Login is disabled, Flint.app moves to Trash, and Flint quits. Verify `swift run` and the read-only DMG copy refuse self-removal before deleting data.

## Free Public Beta Gates

- Package a privately signed, ARM64-only, immutable versioned DMG, verify its designated requirement against the previous beta, and describe it accurately as not Apple-notarized.
- Test Gatekeeper approval, permissions, model preparation, dictation, local-data deletion, and the packaged uninstall flow from a clean standard macOS user account.
- Complete at least one 10–15 minute dictation test on the supported Apple Silicon QA Mac; do not advertise unlimited recording length.
- Deploy migrations, production security headers, beta rate limits, legal/support pages, backup policy, monitoring, and both production smoke verifiers.
- Publish release notes, checksum, installation instructions, Privacy Policy, Public Beta Terms, Third-Party Notices, and the support email. These pages and routes are implemented in the landing application; deployment verification remains external.

## Later Signed/Paid Release Gates

- Run `Scripts/release-preflight.sh` with a Developer ID Application identity. It verifies the release icon, signing tools, and a macOS 14 deployment target before packaging.
- Produce a stable `.app` bundle with a real bundle identifier, version, Flint icon, and hardened runtime entitlements.
- Sign with a Developer ID Application certificate, package a `.dmg`, notarize it, staple the ticket, and validate installation on a clean Mac.
- Host a versioned `.dmg` and release notes on the Flint website with SHA-256 checksums.
- The beta performs one lightweight JSON manifest check at most daily and sends users to the download page when a release is available. Integrate an in-place updater such as Sparkle only after builds are Developer ID signed: signed appcast, EdDSA keys, rollback policy, and update tests from an older signed build.
- Implement the live one-time license backend: purchase-to-key fulfillment, activation/deactivation policy, offline grace/validation policy, and recovery for a replaced Mac. Dictation must remain available offline after activation.
- Review the beta terms and future purchase/refund terms for the seller's chosen jurisdiction before accepting payment. Keep crash diagnostics opt-in and never send transcript or audio content.

## Evidence Required Before Paid Beta

- Compatibility matrix completed for every listed surface.
- Signed/notarized release artifact installed and exercised on a clean user account.
- License purchase, activation, offline restart, deactivation, and update flows tested end to end against production infrastructure.
- Release candidate passes `swift test`, source lint/format checks, and manual privacy/data-deletion verification.
- macOS CI passes unit tests, a release build, and a binary deployment-target check on every change to `main`.
