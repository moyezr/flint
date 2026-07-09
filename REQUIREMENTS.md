# Flint — Project Requirements

Native macOS dictation app. Hold a key, speak, release, clean text appears at the cursor. Runs 100% locally. Distributed as a `.dmg` for a one-time payment. No subscription, no cloud transcription, no account required to dictate.

Core loop — this is the whole product, get it right before anything else:

```
hold shortcut → speak → release → local transcription → cleanup → text inserted at cursor
```

VoiceInk (GPLv3) is a useful functionality benchmark. Do not port, copy, or adapt any of its code, assets, icon, name, copy, or layout — this is a clean-room, proprietary implementation. It's fine to know it exists and behaves a certain way; it's not fine to look at or reuse its source.

---

## 1. Engineering Principles

Read this before writing any code. It applies to every part of the app.

- **Optimize for a human reading the code in one pass.** Simple and slightly repetitive beats clever and abstracted.
- **Don't create types/protocols/interfaces speculatively.** Add an abstraction when there's a second real use case that needs it, not because "we might need it later."
- **Don't split code into many files/functions by default.** A single well-organized file is often easier to follow than the same logic spread across five small ones. Split when a file genuinely gets hard to navigate, not on principle.
- **No speculative generality.** No plugin systems, no config knobs for hypothetical future features, no generic engines for one concrete case. Build what the current phase needs.
- **Prefer straightforward control flow.** Avoid dependency-injection frameworks, event buses, or layers of indirection for a single-developer macOS app. Direct function calls and plain structs/classes are enough.
- **Comment only when intent isn't obvious from the code itself.** Don't narrate what the code does line by line.
- **Working and simple now beats extensible and complex for a future that may not arrive.** If a phase's success criteria are met with a plain implementation, ship that.

---

## 2. Scope

### v1 must-haves
1. Dictate into any focused text field, system-wide.
2. Start recording instantly on shortcut press.
3. Stop on release; cancel with Escape.
4. Transcribe fully locally (no network dependency to function).
5. Clean up raw transcript enough to be usable by default.
6. Insert text reliably; never lose the user's clipboard.
7. Clear recording/processing/error indicator (the overlay).
8. Install from a signed, notarized `.dmg`.
9. One-time license activation, works offline after activation.
10. Direct update mechanism (Sparkle-style).

Goal is trust and daily usability, not feature count.

### Explicitly not in v1
AI assistant mode · cloud transcription · team accounts · mobile app · meeting transcription / speaker diarization · on-device fine-tuning · cross-device sync · browser extension · agent workflows · calendar/email integrations · collaboration features.

If a feature isn't in the "must-haves" list above, assume it's later-roadmap unless this doc says otherwise.

---

## 3. Functional Requirements

### 3.1 Menu bar app
Lives in the menu bar, no dock icon requirement, no persistent window needed. Menu: Start/Pause Dictation, Current Mode, Settings, Privacy, Check for Updates, License, Quit.

### 3.2 Global shortcut / push-to-talk
- Hold to record, release to stop and insert. Escape cancels.
- Support several shortcut options (Right Option, Control+Space, Cmd+Shift+Space, custom) plus an optional toggle mode.
- Don't rely on Fn/Globe as the only option — macOS may intercept it depending on system settings.

### 3.3 Recording overlay
Small, sharp-edged, compact rectangular overlay (not a rounded bubble). States: `READY`, `LISTENING`, `PROCESSING LOCALLY`, `INSERTING`, `COPIED TO CLIPBOARD`, `CANCELLED`, `ERROR`. Show minimal text by default — recording state, an audio level indicator, current mode, a cancel hint.

```
┌──────────────────────────────┐
│ ● LISTENING                  │
│ ████████░░░░░░░░             │
│ Release to insert · Esc cancel│
└──────────────────────────────┘
```

Orange = active/recording (dot, left border, level indicator). Never a full-screen orange block. Errors use a minimal red accent — keep the UI calm, not alarming.

### 3.4 Text insertion
The single most important reliability surface in the app. Fallback chain:
1. Direct focused-field insertion where possible.
2. Accessibility-based insertion.
3. Clipboard paste fallback.
4. Copy-to-clipboard only, if insertion isn't possible at all.

Clipboard preservation when the paste fallback is used: save current clipboard → place generated text → simulate paste → restore original clipboard. Test this path heavily; it's the easiest thing to get subtly wrong.

Target field default: insert into whichever field was focused **when recording started**, with a setting to instead target the field focused when transcription finishes, and a copy-to-clipboard fallback if the original field is gone.

### 3.5 Local speech-to-text
Whisper-based, on-device (WhisperKit or whisper.cpp — pick whichever gives the cleanest Swift integration and packaging). Three model tiers: **Fast** (short dictation / older machines), **Balanced** (default), **Accurate** (longer dictation, best quality). Model manager: list installed/available models, size, recommended hardware, download, delete, set default. Don't bloat the `.dmg` — ship small or download the chosen model during onboarding.

### 3.6 Cleanup modes
Raw transcript isn't the final output. Modes: **Verbatim**, **Clean** (default — punctuation, casing, filler removal), **Polished**, **Prompt** (for ChatGPT/Claude/Cursor-style tools), **Message** (Slack/Discord/iMessage), **Email**. Default mode should be conservative — don't aggressively rewrite the user unless they pick a stronger mode.

### 3.7 App-aware modes (v1.5, after manual modes ship)
Detect the active app and optionally apply a default mode (e.g. Slack → Message, Gmail → Email, Cursor/ChatGPT/Claude → Prompt, Terminal → Verbatim). Build manual mode selection first; this is an enhancement on top of it.

### 3.8 Personal dictionary
Users add custom terms/replacements (names, product names, acronyms) so transcription stops mangling them. Example: `live kit → LiveKit`, `post gress → Postgres`. Applied as a replacement pass after transcription, before insertion. Ship with a small set of common dev-tool defaults (API, JSON, Postgres, Docker, Kubernetes, TypeScript, Next.js, GitHub, etc.) since early users skew technical.

### 3.9 Local history (optional)
Off by default, or opt-in during onboarding. Stores transcript/mode/app/duration — never raw audio. User controls: enable/disable, delete one, delete all, export.

### 3.10 Privacy dashboard
Shows plainly: transcription is local, whether history/telemetry is on, where data lives on disk, a "delete all local data" action. No transcript content is ever sent to a server.

### 3.11 Self-improving personalization (future, not v1)
Long-term goal: the app should get better for a given user as they correct its output (e.g. edits made right after insertion). The actual learning mechanism isn't designed yet — don't build it now. The only thing worth doing today is making sure nothing in the data model actively prevents capturing "raw transcript vs. what the user ended up with" later, behind the same privacy controls as history. Don't add speculative infrastructure for this beyond that.

---

## 4. Permissions & Onboarding

Required: Microphone, Accessibility, and Input Monitoring if needed for the chosen shortcut approach.

Onboarding order:
```
Welcome → privacy promise → choose shortcut → grant permissions
  → choose/download model → test dictation → finish
```
Permission explanations should be short and concrete (e.g. "Accessibility lets the app insert text into whatever field you're typing in"), not vague or scary.

---

## 5. UI / UX Design System

VoiceInk, Wispr Flow, Willow, Superwhisper etc. are **not** to be visually referenced. Everything below — layout, overlay, icon, onboarding — is original.

**Direction:** modern, minimal, sharp, technical, premium Mac utility. Not cute, bubbly, or "AI chatbot"-styled.

### Color
Orange is the one accent color; zinc is the neutral base (cooler and more "technical" than plain gray, and reads cleanly against orange).

```
Primary Orange     #FF6A00   → primary actions, recording state, active/selected UI, progress
Deep Orange        #E85D00   → pressed/hover state for orange elements
Soft Orange Tint   #FFF3E8   → light-mode subtle highlight backgrounds
Dark-mode Orange   #FF7A1A   → orange on dark surfaces (slightly brighter for contrast)

Zinc 950  #09090B   → dark-mode base background
Zinc 900  #18181B   → dark-mode surface/panel
Zinc 700  #3F3F46   → borders / dividers (dark)
Zinc 400  #A1A1AA   → muted/secondary text
Zinc 200  #E4E4E7   → borders / dividers (light)
Zinc 100  #F4F4F5   → light-mode surface/panel
White     #FFFFFF   → light-mode base background
```
Orange never fills large surfaces — it's for accents, actions, and state, not backgrounds.

### Shape & surfaces
- Sharp corners: 0–3px radius everywhere (buttons, panels, overlay). No pill buttons, no big rounded cards, no heavy drop shadows.
- Rectangular panels, thin 1px borders, grid-aligned layouts, generous flat spacing instead of shadow-based depth.

### Components
- **Buttons:** primary = orange fill + light text; secondary = transparent with border; danger = minimal red outline/text; disabled = muted zinc.
- **Cards/panels:** thin border, subtle surface-vs-background contrast, sharp corners, no illustration filler.
- **Settings:** left sidebar (General, Dictation, Modes, Models, Vocabulary, Privacy, License, Updates) + right content panel with sharp section headers. Should feel like a native utility, not a web dashboard.

### Typography
System font. Strong weight contrast for headings, regular for body, small/muted for helper text. Overlay state labels are short and uppercase (`LISTENING`, `PROCESSING LOCALLY`, `INSERTED`) — this is part of the utility feel, not decoration.

### Motion
Minimal and fast — for recording level, overlay state changes, processing/download progress. No bounce, no slow easing, nothing playful.

### Icon
Original mark, not a generic microphone or speech bubble. Sharp geometry, strong silhouette at small sizes, orange accent on a dark/neutral base. (Waveform-in-square, mic mark with an orange cutout, and cursor+waveform are reasonable directions to sketch from.)

---

## 6. Technical Architecture

```
macOS App
  ├── MenuBarController
  ├── OnboardingController
  ├── PermissionManager
  ├── ShortcutManager
  ├── AudioRecorder
  ├── TranscriptionEngine
  ├── ModelManager
  ├── CleanupEngine
  ├── DictionaryEngine
  ├── ModeManager
  ├── ActiveAppDetector
  ├── TextInsertionEngine
  ├── ClipboardManager
  ├── HistoryStore
  ├── PrivacyManager
  ├── LicenseManager
  └── UpdateManager
```
This is a map of responsibilities, not a mandate to create one file per box — group related responsibilities into one file where that's more readable (see Engineering Principles).

**Stack:** Swift, SwiftUI (+ AppKit where SwiftUI can't do it), AVAudioEngine for audio, WhisperKit or whisper.cpp for STT, SQLite + UserDefaults for storage, Keychain for license/secrets, Sparkle-style framework for updates, signed + notarized `.dmg` for packaging.

---

## 7. Local Data Model

```
settings
- selected_shortcut, selected_model, default_mode, language
- launch_at_login, show_overlay, play_start_sound, play_stop_sound
- store_history, auto_insert, paste_target_behavior
- created_at, updated_at

custom_vocabulary
- id, heard_phrase, preferred_replacement, category, usage_count
- created_at, updated_at

dictation_history            # only written if store_history is on
- id, created_at, active_app_name, active_app_bundle_id, mode
- raw_transcript, final_text, duration_ms, model_name, language

app_mode_rules                # v1.5 (app-aware modes)
- id, app_bundle_id, url_pattern, mode, enabled, created_at, updated_at

license                       # Keychain, not SQLite
- license_key_hash, activation_id, status, activated_at, last_checked_at
```

---

## 8. Distribution & Licensing

- Direct download outside the Mac App Store: signed, notarized, hardened-runtime `.dmg`.
- Auto-updates via a Sparkle-style direct-update framework.
- One-time purchase, no subscription. Target range **$29–$49**; suggested default is a $29 early-access price moving to a $49 launch price. Final number TBD, not a blocker for building the app.
- Flow: buy on website → download `.dmg` → activate license key in-app → key stored in Keychain → dictation works fully offline after activation, with occasional online re-validation.
- Payment/licensing backend (Lemon Squeezy, Paddle, or Stripe + custom licensing) is a website/backend concern, not part of the app build.

---

## 9. Build Phases — Progress Checklist

Track progress here directly by checking items off as they're completed.

### Phase 1 — Core Prototype
Goal: prove the core loop works at all.
- [ ] Native macOS app shell + menu bar icon
- [ ] Hardcoded shortcut triggers recording
- [ ] Microphone recording works
- [ ] Local transcription produces text
- [ ] Text pastes into the active field
- [ ] Minimal overlay (no polish needed yet)

**Success:** can dictate into TextEdit, Chrome, Slack, Cursor, and Apple Notes.

### Phase 2 — Daily-Usable Alpha
Goal: usable by the developer every day, without hand-holding.
- [x] Configurable shortcut, push-to-talk + toggle modes
- [x] Permission onboarding flow
- [x] Clipboard preservation implemented and tested
- [x] Real recording overlay with all states
- [x] Cleanup modes (at least Verbatim + Clean)
- [x] Error handling for common failure paths
- [x] Local settings persisted
- [x] Model manager (download/select/delete)
- [x] Personal dictionary v1

**Success:** 10 alpha users can use it daily without developer help.

### Phase 3 — Polish & Reliability Pass
Goal: the core loop is trustworthy across real apps.
- [ ] Test across TextEdit, Notes, Safari, Chrome, Arc, Firefox, Slack, Discord, Gmail, Google Docs, Notion, Linear, Cursor, VS Code, Xcode, Terminal, iTerm2, Messages, Word
- [ ] Recording overlay always appears, never silently fails
- [ ] Shortcut start/stop is reliable under real-world use
- [ ] Long dictation doesn't freeze the UI
- [x] Missing-permission and no-focused-field cases handled gracefully
- [x] Remaining cleanup modes (Polished, Prompt, Message, Email)

**Success:** core dictation loop is reliable enough to charge for.

### Phase 4 — Paid Beta
Goal: validate the commercial path end to end.
- [ ] `.dmg` packaging, code signing, notarization
- [ ] License activation flow + Keychain storage
- [ ] Update system wired up
- [ ] Privacy dashboard
- [ ] Local history (optional, off by default)

**Success:** a user can buy, download, activate, and dictate with zero manual help.

### Phase 5 — Public v1
Goal: ship the polished paid product.
- [ ] App-aware modes (v1.5 feature)
- [ ] Stable across the full compatibility list
- [ ] Onboarding is fast and clear (value understood in under a minute)

**Success:** reliable daily-driver dictation app, ready to be sold at the chosen price.

---

## 10. Not Now

- **Website/landing page:** Next.js 16 + Tailwind, built after the app itself is working. Not part of the current build target.
- **Self-improving personalization algorithm:** see §3.11 — deliberately undesigned for now.
