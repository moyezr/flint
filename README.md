# Flint

Native macOS dictation utility prototype.

## Phase 1 Scaffold

Build:

```sh
swift build
```

Run:

```sh
swift run Flint
```

The app runs as a menu bar process with no dock icon. Hold Right Option to record, release to process and insert, and press Escape while recording to cancel. This first scaffold writes a temporary `.m4a` recording and uses a placeholder `TranscriptionEngine`; WhisperKit or whisper.cpp integration belongs behind that type later.
