# Flint architecture

Flint is a native local-first macOS dictation utility and a Next.js website. The
native dictation path is the center of the product; optional persistence and
network work must remain outside its critical path.

## Native application

`AppCoordinator` owns application lifecycle and coordinates the core loop:

1. `ShortcutManager` recognizes the configured global shortcut.
2. `AudioRecorder` records a temporary `.m4a` and supplies audio levels to the
   notch overlay.
3. `TranscriptionEngine` reuses a WhisperKit pipeline prepared by `ModelManager`.
4. `DictionaryEngine` applies built-in and explicitly taught vocabulary from an
   immutable in-memory snapshot.
5. `CleanupEngine` applies the selected deterministic cleanup mode.
6. `DictationOutputPolicy` rejects empty output.
7. `TextInsertionEngine` inserts once using the captured target and its guarded
   fallback chain, or copies when Auto Insert is disabled.
8. Recent results and optional content-free metrics or history are updated after
   insertion.
9. The temporary recording is deleted.

### Safety invariants

- Recording, transcription, and insertion cannot wait on history, learning,
  metrics, licensing refreshes, or update checks.
- Each successful dictation is inserted no more than once.
- Clipboard fallback snapshots and restores every pasteboard item unless the
  user changes the clipboard during the operation.
- Rich web composers use paste-only protection because asynchronous
  Accessibility reads cannot safely prove a mutation failed.
- A captured rich composer is used only while focus remains in the same process.
- Generation and processing identifiers prevent stale asynchronous work from
  changing current UI state.
- Audio recordings are temporary and removed after success, failure, or
  cancellation.

### Native component map

- `AppCoordinator.swift`: application lifecycle and workflow orchestration.
- `ShortcutSettings.swift`: global event tap and shortcut state machine.
- `PermissionManager.swift`: Microphone and Accessibility readiness.
- `ModelManager.swift`: local model selection, download, and storage.
- `TranscriptionEngine.swift`: cached WhisperKit pipeline.
- `TextInsertion.swift`: Accessibility insertion and clipboard-preserving paste.
- `OverlayWindow.swift`: compact notch and external-display feedback.
- `Learning/`: explicit vocabulary and correction learning.
- `HistoryStore.swift`: optional local history and app-mode rules database.
- `LicenseRuntime.swift`: dormant signed offline-license flow for future paid
  builds.
- `UpdateManager.swift`: small daily release-manifest check in packaged builds.

The native app intentionally uses direct Swift and a small number of concrete
components. New frameworks, event buses, plugin systems, or dependency-injection
layers need more than one demonstrated use case.

## Website and service

The `landing` application is a Next.js App Router project containing:

- Marketing, support, privacy, beta-install, and legal pages.
- The interactive typing test and beta download form.
- Email OTP verification and a one-time download handoff.
- Release metadata consumed by packaged Flint builds.
- A PostgreSQL-backed license API whose native enforcement remains disabled
  during the free beta.

Server-only configuration is read from environment variables. Database URLs,
peppers, email-provider keys, webhook secrets, and private signing keys must
never be exposed through `NEXT_PUBLIC_` variables or client components.

PostgreSQL migrations under `landing/db/migrations` are append-only. Production
schema changes should be deployed and verified before code that depends on them.

## Data boundaries

The native app stores settings, downloaded models, optional history, explicit
learning, and device-bound license material locally. The website stores only the
data submitted for its beta verification and licensing workflows. Flint does not
upload dictation audio or transcript content.

See the public [Privacy Policy](https://flint.moyezrabbani.dev/privacy) and the
root [README](../README.md) for current storage locations and removal behavior.
