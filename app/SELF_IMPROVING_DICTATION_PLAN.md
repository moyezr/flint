# Self-Improving Dictation Plan

## Document Structure and Status

This document is the strategic source of truth: product boundaries, decision gates, deferred branches, safety constraints, and long-term performance/storage policy.

The current build-ready scope lives in [`FLINT_V1_IMPLEMENTATION_GUIDE.md`](./FLINT_V1_IMPLEMENTATION_GUIDE.md). Only Explicit V1 and the Phase 0 spikes in that guide are approved for scheduling. Gate A and Gate B are closed until the V1 review; passive observation, provenance, re-dictation capture, decoder biasing, and acoustic adaptation remain unscheduled.

If the two documents appear to conflict about V1 implementation details, the implementation guide controls V1. This strategic plan controls what may happen after the gates.

## Objective

Flint should improve from a user's corrections without making dictation slower, less predictable, or less private.

The central rule is:

> Dictation is the product. Learning is optional background work and must never compete with recording, transcription, cleanup, or insertion.

Backspace and Delete are weak signals. They do not prove that recognition was wrong or reveal the intended replacement. Flint should begin with explicit correction mechanisms, validate whether passive observation adds enough value, and only then build the more complex inference system.

## Product Boundaries

Vocabulary personalization and pronunciation adaptation are different products.

- **Vocabulary personalization** teaches written preferences such as `post grass` → `Postgres`, names, casing, jargon, and application-specific terminology. Flint can deliver this early through explicit vocabulary and deterministic correction.
- **Procedural personalization** captures formatting preferences such as terminal punctuation, filler removal, Markdown, or email structure. Most of this can begin as ordinary settings.
- **Pronunciation adaptation** teaches the system how a particular user speaks. It requires correctly paired audio and intended text, substantially more data, and eventually an acoustic retrieval or model-adaptation mechanism.

Early Flint should promise vocabulary and formatting improvement. It should only promise accent or pronunciation adaptation if the pronunciation branch described below is deliberately selected and funded.

## Non-Negotiable Design Principles

1. **Explicit before implicit.** Ship mechanisms the user deliberately invokes before watching fields and inferring intent.
2. **High precision before high coverage.** Unknown edits should remain unknown. Missing a learning opportunity is safer than learning the wrong behavior.
3. **Reversible behavior.** Every applied memory must be attributable, reviewable, disableable, and deletable.
4. **Scoped evidence.** Cursor evidence must not promote a Notes-specific coincidence into a global rule.
5. **Bounded work and storage.** Queues, caches, database tables, logs, and audio must have limits from their first release.
6. **No learning on the dictation critical path.** Learning failures must never prevent transcription or insertion.

## V1: Ship Explicit Personalization First

These features require no passive Accessibility observer, correction classifier, word timestamps, or transformation ledger. They should ship before the research phases below.

### Teach Flint a Word

Add a Settings action with:

- Spoken or commonly misrecognized form.
- Preferred written form.
- Language.
- Scope: global or a selected application.
- Optional category or domain.

The entry writes into the existing dictionary system and becomes active immediately. It remains visible in the same review and deletion UI used by future learned memories.

### Static Formatting Preferences

Expose useful formatting behavior as settings before trying to infer it:

- Terminal punctuation on or off.
- Filler removal.
- Numerals versus written numbers.
- Markdown-friendly output.
- Message, prompt, and email formatting behavior.
- Application-specific cleanup mode.

The app already has cleanup modes and app-aware mode infrastructure, so static controls offer value without classifier risk.

### Fix This Dictation

Add a user-invoked action available immediately after insertion through the menu, overlay, or configurable shortcut.

Suggested flow:

1. Flint keeps a bounded in-memory ring of the 10 most recent successful insertions; it is cleared on relaunch.
2. The user invokes **Fix This Dictation** and selects the relevant recent entry, defaulting to the newest.
3. A lightweight Flint panel shows the exact frozen text Flint inserted and a prefilled editable correction field.
4. The user edits the correction once.
5. Flint saves the explicit pair and, when a small reusable substitution can be extracted, asks the user to approve that exact mapping and scope.
6. V1 offers **Save & Copy** rather than attempting to rewrite a potentially changed target field from stale Accessibility state.

This is user-initiated, so a correction panel does not unexpectedly interrupt flow. It yields much cleaner labels than passive inference and works even when an editor exposes poor Accessibility values.

V1 should persist only explicit corrections and memories—not every normal dictation.

## Decision Gates

### Gate A: Does Passive Observation Earn Its Complexity?

Run V1 with initial testers before committing to passive correction tracking. Measure:

- How often users invoke **Fix This Dictation** after a bad result.
- Completion rate once the flow is opened.
- Number of useful memories produced per 100 dictations.
- Whether testers report that explicit correction is too burdensome.
- Important correction types the explicit flow fails to capture.

Build passive observation only if it is likely to add meaningful correction coverage beyond **Teach Flint a Word** and **Fix This Dictation**. If explicit mechanisms cover the testers' real needs, stop there until usage scale justifies more automation.

The initial review window is two weeks and at least 300 real dictations across testers. Do not build passive observation when fewer than 5% of dictations produce an explicit correction action and testers cannot name a recurring correction category the explicit tools miss. Consider it only when correction burden is frequent or testers identify a repeatable class that the explicit workflow structurally fails to capture. The sample threshold prevents premature decisions; it is not a permanent product KPI.

### Gate B: Is Pronunciation Adaptation In Scope?

This gate must produce a real architecture fork.

If the answer is **vocabulary and formatting only**:

- Do not add retry-pair detection.
- Do not retain audio after normal transcription cleanup.
- Do not build word-timestamp storage.
- Do not build full transformation provenance.
- Continue with text correction and memory only.

If the answer is **pronunciation adaptation**:

- Add structured Whisper output and word timestamps.
- Add transformation provenance.
- Detect delete-then-re-dictate attempts.
- Offer a separate local audio-retention opt-in.
- Store bounded, paired acoustic examples for later evaluation.

The vocabulary branch must not pay the engineering, runtime, privacy, or storage cost of a future pronunciation feature.

## Phase 0: Validate the Risks in Parallel With V1

### Correction Classifier Feasibility

Collect and hand-label 50–100 real before/after examples from normal use. Include:

- Correct output that was not edited.
- Names and vocabulary substitutions.
- Casing, punctuation, and whitespace changes.
- Ordinary rewriting and changed intent.
- Undo and full rejection.
- Full replacement by typing.
- Delete-then-re-dictate behavior if pronunciation is being considered.

Start with a deterministic, versioned heuristic classifier. Possible outputs are:

- `vocabularySubstitution`
- `formattingPreference`
- `contentRevision`
- `continuation`
- `rejection`
- `redictationCandidate`
- `unknown`

Candidate features include:

- Overlap with Flint's inserted span.
- Time between insertion and edit.
- Character- and token-level edit distance.
- Number and contiguity of changed words.
- Casing-, punctuation-, and whitespace-only changes.
- Append versus replacement behavior.
- Application, target, focus, and anchor stability.
- Phonetic similarity for supported languages.
- Repetition of the same correction in the same scope.
- A new Flint dictation immediately following a large deletion.
- Whisper probability and timing only in the pronunciation branch.

The initial fixture is a feasibility test, not launch evidence. A one-person English technical dataset does not establish general reliability.

Use a paired gate rather than precision alone:

- Provisional auto-learn precision target: at least 95% on eligible categories.
- Provisional recall target: at least 40% of genuinely eligible corrections.
- Require enough positive examples per category to report a meaningful result.
- Report classifier activity rate so high precision cannot be achieved by returning `unknown` for everything.
- Before passive auto-application, expand the fixture to at least a few testers with different accents, vocabularies, and editing styles, and report per-user results.

These numerical targets are provisional engineering gates, not claims of population-level reliability.

Reference: [Microsoft Research: Unsupervised Learning from Users' Error Correction in Speech Dictation](https://www.microsoft.com/en-us/research/publication/unsupervised-learning-from-users-error-correction-in-speech-dictation/)

### Accessibility Coverage Spike

Probe the applications used for daily dictation before designing passive observation around ideal text fields:

- Terminal and an alternate terminal, if regularly used.
- Cursor or VS Code.
- Slack and Mail.
- Safari or Chrome fields.
- Notes.

For each surface, record:

- Whether `kAXValueChangedNotification` arrives reliably.
- Whether `kAXValueAttribute` returns the editable value or a document/scrollback blob.
- Whether selected ranges and focused elements remain stable.
- Whether prefix/suffix anchors survive edits.
- Whether insertion used Accessibility or clipboard paste fallback.
- Event latency, duplication, and coalescing behavior.

Assign a support tier:

- **Tier A:** reliable implicit observation.
- **Tier B:** usable with bounded polling or surface-specific handling.
- **Tier C:** explicit correction only.

If important applications fall into Tier C, **Fix This Dictation** is core UX rather than a fallback.

References:

- [Apple: kAXValueChangedNotification](https://developer.apple.com/documentation/applicationservices/kaxvaluechangednotification)
- [Apple: kAXValueAttribute](https://developer.apple.com/documentation/applicationservices/kaxvalueattribute)

## Optional Passive Observation Architecture

Build this section only if Gate A passes.

### Correction Session

After Flint inserts text, create a short-lived in-memory session containing:

- Dictation ID.
- Application and bundle identifier.
- Accessibility target.
- Text immediately before insertion.
- Replaced selection and inserted range.
- Inserted text.
- Stable local prefix/suffix anchors.
- Language, cleanup mode, and model.

Observe only that target for approximately 20–30 seconds. Stop on focus change, target invalidation, another unrelated dictation, submission where detectable, or timeout.

Accessibility callbacks only enqueue the newest target value. They do not diff text, classify edits, write SQLite, or run memory consolidation.

### Localized Diff and Classification

Background processing should:

1. Locate the inserted span using its tracked range and anchors.
2. Diff only a bounded window around that span.
3. Ignore additions outside the span.
4. Debounce changes for approximately 500–800 milliseconds.
5. Classify the settled edit.
6. Persist evidence only if a correction candidate exists or diagnostic sampling is enabled.

Large rewrites should remain `unknown` unless they came through the explicit correction flow or satisfy the optional re-dictation criteria.

### Re-Dictation Capture

Build this only if Gate B selected pronunciation adaptation.

A re-dictation candidate requires:

- At least 80% of Flint's insertion was deleted or replaced.
- A new Flint dictation started within 10–15 seconds.
- Application, target, and nearby anchors still match.
- The new insertion overlaps or immediately follows the deleted span.

Link the attempts as evidence; do not convert them directly into a vocabulary rule. The user may have changed their mind.

Under text correction learning, retain only the paired transcripts and relationship. Under the separate pronunciation opt-in, retain bounded local audio clips for both attempts.

## Structured Transcription and Provenance

Build this only for the pronunciation branch or when a demonstrated correction use case requires it.

Flint currently flattens WhisperKit results into a string and deletes audio after insertion. WhisperKit can provide word timestamps, segment boundaries, probabilities, and decoder prompt tokens.

Reference: [WhisperKit decoding configuration](https://github.com/argmaxinc/whisperkit/blob/main/Sources/WhisperKit/Core/Configurations.swift)

Use a structured result in memory:

```swift
struct FlintTranscription {
    let rawText: String
    let words: [TimedWord]
    let language: String
    let segments: [Segment]
}
```

Record transformations as spans:

```text
raw span → dictionary span → cleanup span → inserted span
```

Persist word/provenance artifacts only for explicit corrections, passive correction candidates, or consented pronunciation examples. Do not create one permanent database row per word of every dictation.

## Memory Model

### Semantic Memory

Stable vocabulary:

```text
"post grass" → "Postgres"
"moyez rabbani" → "Moyez Rabbani"
"flint" → "Flint"
```

### Procedural Memory

Formatting behavior scoped by application or cleanup mode:

- Terminal punctuation.
- Filler removal.
- Markdown formatting.
- Message, prompt, and email structure.

Begin with explicit settings. Promote inferred procedural rules only after passive observation is proven useful.

### Episodic Evidence

Individual correction pairs support or contradict a proposed memory. Evidence is not itself permanent behavior.

Evidence counts must use the same scope as the proposed memory. A rule may become global only after compatible evidence appears across contexts without contradictions.

### Promotion Policy

1. An explicit **Teach Flint a Word** entry becomes active immediately.
2. An explicit **Fix This Dictation** pair creates a reviewable proposal or strengthens matching evidence.
3. Passive evidence remains episodic after the first occurrence.
4. Repeated compatible evidence in the same scope creates a proposal.
5. Proposals appear in a review screen, menu badge, or quiet post-flow toast—never a blocking mid-dictation dialog.
6. User approval activates the memory.
7. Contradictions lower confidence.
8. Reverting an applied memory disables it and surfaces it for review.

## Applying Personalization Safely

### Layer 1: Deterministic Mappings

Apply explicit or approved exact mappings after transcription. This is the V1 application layer.

### Layer 2: Scoped Formatting

Apply explicit formatting settings by application and cleanup mode.

### Layer 3: Decoder Prompting

Only after deterministic memory proves valuable, test a small set of relevant vocabulary as Whisper prompt tokens. Limit prompt terms by scope, recency, and confidence.

References:

- [OpenAI Whisper transcription implementation](https://github.com/openai/whisper/blob/main/whisper/transcribe.py)
- [CB-Whisper: Contextual Biasing Whisper Using Open-Vocabulary Keyword-Spotting](https://aclanthology.org/2024.lrec-main.262/)

### Layer 4: Confidence-Aware Candidates

Low Whisper confidence is not permission to snap output to the nearest learned term. That can turn genuine uncertainty about a new word into a confident, repeated mistake.

An automatic correction should require all of the following:

- An explicit or approved confusion mapping, not merely a phonetically close memory.
- Matching language and scope.
- Sufficient repeated evidence without a contradiction.
- A strong match to the mapping's known heard form.
- A clear score margin over other learned candidates.

If these conditions are not satisfied, Flint should leave the transcript unchanged or offer a non-blocking suggestion. It should not silently choose a familiar term just because Whisper was uncertain.

### Layer 5: Acoustic Adaptation

Consider offline model adaptation only after enough explicitly consented audio/text pairs exist. Train or evaluate in batches, preserve the base model, and reject candidates that improve personal examples while degrading the general regression corpus.

References:

- [Google Research: Personalized ASR Trained on Small Disordered Speech Datasets](https://research.google/pubs/personalized-automatic-speech-recognition-trained-on-small-disordered-speech-datasets/)
- [Continual Learning for Monolingual End-to-End Automatic Speech Recognition](https://arxiv.org/abs/2112.09427)

## Runtime Performance Architecture

### Critical-Path Isolation

The user-visible path remains:

```text
record → transcribe → dictionary → cleanup → insert
```

Learning may add only two synchronous operations:

- Read a bounded, already-cached snapshot of active memory during dictionary/cleanup.
- Create a small in-memory correction-session descriptor and enqueue it after insertion.

Do not perform Accessibility diffing, classifier work, database writes, retention cleanup, compression, audio copying, or model adaptation on the main actor or before insertion completes.

Initial performance budgets, to be validated on supported Intel and Apple Silicon hardware:

- Observer callback: no more than 1 ms of work; enqueue or coalesce only.
- Active-memory lookup and deterministic application: under 10 ms at p95 for a normal dictation.
- Session creation/enqueue after insertion: under 2 ms at p95.
- No measurable regression in recording startup, transcription time, or insertion success rate.

These are engineering targets, not user-facing guarantees. If a target is exceeded, learning work should be skipped or deferred rather than delaying dictation.

### Learning Coordinator

Use a dedicated actor or serial worker with utility/background priority:

- Keep a bounded queue, initially no more than 32 pending session updates.
- Coalesce repeated AX changes so only the newest value per session is processed.
- Cancel or suspend learning work as soon as recording or transcription begins.
- Resume only after insertion and an idle period.
- Drop low-value diagnostics under backpressure; never drop or delay dictation work.
- Batch SQLite writes into short transactions after debounce.
- Make every task cancellable and idempotent.

Heavy acoustic evaluation or training must never run concurrently with Whisper transcription. It should require explicit user initiation or a conservative idle policy that checks thermal pressure and low-power state, and it must yield immediately when dictation starts.

### Bounded Retrieval

Do not scan every historic correction for each transcript.

- Maintain a compact immutable index of active memories keyed by language and scope.
- Swap index snapshots atomically after background updates.
- Use exact-token lookup, a trie, or another bounded matcher for deterministic vocabulary.
- Load only active memories into the hot index; episodic evidence stays in SQLite.
- Limit decoder prompt candidates, initially to roughly 20–50 highly relevant terms.
- Set an initial active-index memory budget, such as 5 MB, and measure it.

As vocabulary grows, replace repeated per-entry regex scans with a combined or indexed matcher so application cost depends primarily on transcript length rather than total historical evidence.

### Database Behavior

- Use a single background database owner.
- Enable WAL mode and keep transactions small.
- Add indexes only for actual retrieval and pruning queries.
- Checkpoint WAL and run incremental cleanup only while Flint is idle.
- Avoid blocking `VACUUM` during ordinary use.
- Record schema and classifier versions for migrations and reproducibility.

## Storage and Retention Policy

Persist evidence-producing sessions only. A normal, unedited dictation should leave no learning rows behind.

### Simplified Data Model

#### `memory_items`

Compact, user-visible behavior:

- Type and scope.
- Heard and preferred forms.
- Confidence and aggregate evidence counts.
- Status: proposed, active, disabled, or rejected.
- Origin: seeded, explicit correction, or inferred.
- Last-used and updated timestamps.

#### `correction_evidence`

Only localized evidence:

- Original and corrected text.
- Application, language, and cleanup scope.
- Explicit or inferred source.
- Classifier output, version, and confidence.
- Optional compact encoded word/provenance artifact.

#### `retry_pairs`

Created only in the pronunciation branch:

- Original and retry session metadata.
- Timing, target, anchor, and overlap evidence.
- Confirmation and confidence.
- Optional audio-example references.

#### `audio_examples`

Created only with pronunciation improvement enabled:

- Bounded clip location and duration.
- Source/retry relationship.
- Consent and retention metadata.

Do not maintain permanent `dictation_sessions`, `word_hypotheses`, or `transformation_events` rows for every dictation. Keep ordinary session state in memory and attach compact artifacts only to evidence that survives filtering.

### Default Retention Bounds

| Data | Default retention |
| --- | --- |
| Recent explicit-correction candidates | Memory-only ring of 10 successful insertions; clear on relaunch |
| Shadow/unknown classifier sample | 7 days or 250 records, whichever comes first |
| Unconsolidated correction evidence | 90 days or 2,000 records |
| Word timing/provenance artifact | Only with evidence; delete after 30 days unless needed by a retained pronunciation pair |
| Evidence consolidated into memory | Keep aggregate counts and at most a few representative examples; remove redundant raw events |
| Explicitly seeded or user-approved memory | Keep until the user deletes it |
| Rejected proposal | Keep a compact scoped fingerprint to prevent repeated prompts; discard verbose evidence after 30 days |
| Retry text pair | 90 days or 500 pairs, pronunciation branch only |
| Audio examples | Off by default; when enabled, 30 days or 500 MB, whichever comes first |
| Diagnostic learning logs | 7 days or 5 MB |

Initial metadata storage should have a default high-water mark, such as 50 MB. When a limit is reached, prune in this order:

1. Diagnostic logs.
2. Unknown/shadow samples.
3. Old unconsolidated low-confidence evidence.
4. Redundant representative examples.
5. Old retry pairs without confirmation.

Never automatically delete user-seeded or approved memories. Audio and metadata limits should be configurable later if real adaptation needs justify it, but bounded defaults must exist first.

Retention should run as small incremental jobs while idle. The Privacy screen should show counts and disk usage, expose retention settings, and support deletion by category as well as Delete All Local Data.

## Privacy Requirements

- Learning is a separate opt-in from transcript history.
- Pronunciation/audio learning is a second, more explicit opt-in.
- Never record global keystrokes.
- Observe only a target into which Flint just inserted text and only for the correction window.
- Never observe secure or password fields.
- Never persist surrounding document contents.
- Keep normal audio deletion as the default.
- When pronunciation learning is enabled, persist only bounded local clips or short retry attempts.
- Make memories, evidence, retry pairs, and audio inspectable and deletable.
- Allow per-application exclusions.
- Do not upload learning content to a server.

## Phased Delivery

### Ship Now: Explicit V1

- Teach Flint a Word.
- Static formatting preferences.
- Fix This Dictation.
- Minimal `memory_items` and `correction_evidence` storage.
- Storage caps and privacy controls for those tables.

### Phase 0: Parallel Research

- Label classifier examples.
- Test provisional precision, recall, and activity gates.
- Spike Accessibility coverage and assign support tiers.
- Gather data from more than one editing style before passive auto-application.

### Gate Review

- Decide whether passive observation adds enough over explicit V1.
- Decide independently whether pronunciation adaptation is in scope.
- Stop work on either branch if its evidence does not justify its cost.

### Passive Text Branch

- Add ephemeral correction sessions.
- Run localized diffs and the classifier in shadow mode.
- Persist candidates only.
- Compare passive incremental yield against explicit corrections.
- Add reviewable proposals before any automatic application.

### Pronunciation Branch

- Add structured Whisper output and word timing.
- Add transformation provenance only for evidence-producing sessions.
- Add retry-pair detection.
- Add separate bounded audio consent and storage.
- Collect examples without modifying model weights.

### Safe Application

- Apply approved deterministic vocabulary.
- Apply explicit scoped formatting.
- Track attribution, reversions, and false replacements.
- Keep uncertain low-confidence candidates as suggestions rather than silent replacements.

### Later Experiments

- Decoder vocabulary biasing.
- Confidence-aware candidate evaluation.
- Offline acoustic retrieval or adaptation.
- Personalized model deployment only with general-regression and rollback gates.

## Evaluation

### Product Value

- Correction effort per 1,000 dictated characters.
- Useful memories created per 100 dictations.
- Explicit correction invocation and completion rates.
- Passive incremental yield beyond explicit mechanisms.
- Learned-rule acceptance and reversal rates.
- Rare-term correction rate.

### Classifier Quality

- Per-category precision and recall.
- Activity and `unknown` rates.
- Confusion matrix.
- Results per tester, language, accent, application, and editing style.
- Re-dictation detection precision and confirmation rate when enabled.

### Safety

- False automatic replacement rate.
- Rate of low-confidence output incorrectly snapped to a familiar term.
- Contradiction and rollback rate.
- General word-error regression on a fixed corpus.

### Performance and Storage

- Recording-start and end-to-insertion latency before versus after learning.
- p50/p95 memory lookup and observer callback time.
- Background queue depth, coalescing rate, and dropped diagnostic work.
- CPU, memory, thermal, and energy impact while idle and while dictating.
- SQLite and WAL size over simulated months of use.
- Daily evidence growth and pruning duration.
- Active-memory index size and lookup scaling.

The primary release criterion remains:

> Correction effort declines without slower dictation or more unwanted replacements.

## Recommended Order of Work

1. Ship **Teach Flint a Word**, static formatting settings, and **Fix This Dictation**.
2. Add bounded memory/evidence storage and privacy controls.
3. Run classifier and Accessibility spikes in parallel.
4. Measure whether passive observation adds enough value to proceed.
5. Decide whether pronunciation adaptation is truly in scope.
6. Build only the branches that pass their gates.
7. Introduce reviewable passive proposals before automatic behavior.
8. Add decoder biasing only after deterministic personalization is proven.
9. Consider acoustic adaptation only after substantial, explicitly consented paired data exists.

The differentiating feature is not silent background complexity. It is that Flint improves in ways the user understands and controls while remaining an excellent dictation app even when every learning subsystem is disabled, busy, corrupted, or deleted.
