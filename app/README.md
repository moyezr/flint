# Flint

Native macOS dictation utility. The repository-level [README](../README.md)
contains the product overview, architecture, and complete contributor setup.

Requires an Apple Silicon Mac with macOS 14 or newer for the current direct beta. The current DMG is ARM64-only; Intel support is not advertised or qualified.

For the current direct-download beta release path, see
[DIRECT_BETA_RELEASE.md](./DIRECT_BETA_RELEASE.md). It produces a privately
signed DMG and checksum without requiring an Apple Developer ID certificate;
it is not a notarized production release.

## Development

Build:

```sh
swift build
```

Run:

```sh
swift run Flint
```

The app runs as a menu bar process with no dock icon. By default, hold Right Option to record, release to process and insert, and press Escape while recording to cancel. Use the Shortcut submenu to choose Right Option, Control+Space, or Cmd+Shift+Space, and use the Input Behavior submenu to choose Push-to-Talk or Toggle. Use the Current Mode submenu to choose Clean, Verbatim, Polished, Prompt, Message, or Email cleanup before insertion. Recordings are written as temporary `.m4a` files and transcribed locally through WhisperKit before being removed.

Flint captures the focused text target when recording starts and tries that target first when inserting the final text. If that target is gone or rejects direct insertion, it falls back to the current focused field, then clipboard paste with clipboard preservation, then copy-only.

Use the Permissions menu item to check Microphone and Accessibility readiness. Microphone lets Flint record your voice for local transcription. Accessibility lets Flint detect the dictation shortcut and insert text into the field you're typing in.

Flint requests macOS permissions one at a time so simultaneous system prompts cannot suppress one another. Accessibility already grants the event-listening access used by Flint's shortcut, so onboarding does not require the separate Input Monitoring permission. Each missing permission has its own Settings action, onboarding refreshes its permission state automatically while that step is visible, and it provides a Quit button for changes that require a relaunch. The public beta now uses one persistent private signing identity so future beta updates share a stable macOS privacy identity. Users migrating from an older ad-hoc beta must remove the old Flint row in System Settings, add the current `/Applications/Flint.app`, and reopen Flint once; onboarding shows those instructions when a previously configured installation cannot regain Accessibility.

Onboarding shares the landing page's design system: bundled Space Grotesk headings, Inter body copy, IBM Plex Mono labels, the warm Flint palette, square bordered surfaces, the `FLINT/` wordmark, and the subtle orange dot field. The matching SIL Open Font License texts are included with packaged builds under `Contents/Resources/FontLicenses`.

For a clean first-run test, choose **Privacy → Delete All Local Data** in Flint, quit the app, and reset Flint's macOS permission decisions with `tccutil reset All com.moyezrabbani.Flint`. The next launch starts onboarding from the beginning and macOS asks for permissions again. This removes Flint's settings, models, local databases, learning data, and license state; it does not remove unrelated applications' data.

## Local Transcription

Flint uses the official Argmax OSS Swift package and the `WhisperKit` product for on-device transcription. The transcription pipeline is initialized once and cached behind `TranscriptionEngine`, so repeated dictations reuse the same model/runtime instead of recreating it.

WhisperKit may download its default model files on first use and needs network access for that initial setup. After the model is present in WhisperKit's local cache, transcription runs locally on the Mac.

## Text Cleanup

Transcripts pass through a local dictionary replacement step before cleanup. The initial dictionary ships developer-focused defaults such as API, JSON, Postgres, Docker, Kubernetes, TypeScript, Next.js, GitHub, JavaScript, SwiftUI, and SQLite, with custom replacements persisted in `UserDefaults` for the app to expose through settings later.

Cleanup modes are deterministic and local. Clean is the default conservative mode, Verbatim trims only outer whitespace, Polished adds light casing and punctuation fixes, Prompt normalizes dictated instructions for AI and coding tools, Message keeps text concise for chat, and Email formats a simple email block only when the transcript already contains email-like cues.
