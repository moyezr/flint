# Flint

Native macOS dictation utility prototype.

Requires an Apple Silicon Mac with macOS 14 or newer for the current direct beta. The current DMG is ARM64-only; Intel support is not advertised or qualified.

For the current direct-download beta release path, see
[DIRECT_BETA_RELEASE.md](./DIRECT_BETA_RELEASE.md). It produces an ad-hoc-signed
DMG and checksum without requiring an Apple Developer ID certificate; it is not
a notarized production release.

## Phase 1 Scaffold

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

Use the Permissions menu item to check Microphone, Accessibility, and Input Monitoring readiness. Microphone lets Flint record your voice for local transcription. Accessibility lets Flint insert text into the field you're typing in. Input Monitoring lets Flint detect your dictation shortcut.

Flint requests macOS permissions one at a time so simultaneous system prompts cannot suppress one another. The Core Graphics Input Monitoring API only potentially shows a prompt; after its one-time prompt has been consumed, **Prompt for Missing Permissions** opens the relevant Privacy & Security pane instead. The direct beta is ad-hoc signed, so macOS may retain a permission entry for an older Flint build after the app is replaced. If Accessibility or Input Monitoring is visibly enabled but Flint still reports it as missing, remove the old Flint row in System Settings, add the current `/Applications/Flint.app` again, and reopen Flint. Onboarding refreshes its permission state automatically while that step is visible.

For a clean first-run test, choose **Privacy → Delete All Local Data** in Flint, quit the app, and reset Flint's macOS permission decisions with `tccutil reset All com.moyezrabbani.Flint`. The next launch starts onboarding from the beginning and macOS asks for permissions again. This removes Flint's settings, models, local databases, learning data, and license state; it does not remove unrelated applications' data.

## Local Transcription

Flint uses the official Argmax OSS Swift package and the `WhisperKit` product for on-device transcription. The transcription pipeline is initialized once and cached behind `TranscriptionEngine`, so repeated dictations reuse the same model/runtime instead of recreating it.

WhisperKit may download its default model files on first use and needs network access for that initial setup. After the model is present in WhisperKit's local cache, transcription runs locally on the Mac.

## Text Cleanup

Transcripts pass through a local dictionary replacement step before cleanup. The initial dictionary ships developer-focused defaults such as API, JSON, Postgres, Docker, Kubernetes, TypeScript, Next.js, GitHub, JavaScript, SwiftUI, and SQLite, with custom replacements persisted in `UserDefaults` for the app to expose through settings later.

Cleanup modes are deterministic and local. Clean is the default conservative mode, Verbatim trims only outer whitespace, Polished adds light casing and punctuation fixes, Prompt normalizes dictated instructions for AI and coding tools, Message keeps text concise for chat, and Email formats a simple email block only when the transcript already contains email-like cues.
