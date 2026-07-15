# Flint Explicit Personalization V1 Implementation Guide

## Status and Authority

This is the build-ready companion to [`SELF_IMPROVING_DICTATION_PLAN.md`](./SELF_IMPROVING_DICTATION_PLAN.md).

Only the following work is approved from this guide:

1. Teach Flint a Word.
2. Static formatting preferences.
3. Fix This Dictation.
4. Minimal bounded storage, privacy integration, and performance instrumentation.
5. The classifier and Accessibility Phase 0 spikes, run in parallel and not blocking items 1–4.

Do not schedule passive observation, transformation provenance, retry-pair detection, decoder biasing, audio retention, or acoustic adaptation until Gate A and Gate B are explicitly reviewed.

## V1 Non-Goals

- No passive Accessibility value monitoring in production.
- No automatic inference from Backspace or Delete.
- No word timestamps or per-word database rows.
- No persisted normal-dictation history for learning.
- No re-dictation pairing.
- No audio retention.
- No learned formatting rules.
- No decoder prompting or model-weight changes.
- No automatic target-field rewrite from stale Accessibility state.
- No server telemetry or learning-data upload.

## Existing Flint Starting Point

V1 extends existing behavior rather than replacing the working dictation pipeline:

- `DictionaryEngine` already supports default and custom phrase replacements.
- Settings already exposes heard/preferred vocabulary entry fields.
- `CleanupEngine` already implements cleanup modes, filler removal, and terminal punctuation.
- `AppCoordinator` owns the complete raw → dictionary → cleanup → insertion flow and the active application context.
- `PrivacyManager` already enumerates local data and supports Delete All Local Data.
- `HistoryStore` and `AppModeRuleStore` already use SQLite, but learning must remain independently optional.

The existing custom-vocabulary UI is therefore **extended and migrated**, not rebuilt from zero.

## Final V1 Architecture

```text
Settings / Fix panel
        ↓ async write
LearningStore actor ─── Learning.sqlite
        ↓ immutable rebuild
MemorySnapshot held by AppCoordinator
        ↓ synchronous bounded read
DictionaryEngine
        ↓
CleanupEngine
        ↓
TextInsertionEngine
        ↓
RecentDictationBuffer (memory only, max 10)
```

The dictation path never reads SQLite. A failed or delayed learning write cannot block or fail dictation.

## File Structure

```text
Sources/Flint/
  Learning/
    LearningModels.swift
    LearningStore.swift
    MemorySnapshot.swift
    RecentDictationBuffer.swift
    CorrectionDiffExtractor.swift
    LearningRetentionPolicy.swift
    LearningMetrics.swift
  LearningSettingsView.swift
  FixThisDictationPanel.swift
  AppCoordinator.swift              # orchestration and current snapshot
  DictionaryEngine.swift            # snapshot-aware application
  CleanupEngine.swift               # explicit formatting preferences
  AppSettings.swift                 # formatting flags
  SettingsWindow.swift              # integrates learning settings
  PrivacyManager.swift              # learning DB visibility/deletion

Tests/FlintTests/
  LearningStoreTests.swift
  MemorySnapshotTests.swift
  RecentDictationBufferTests.swift
  CorrectionDiffExtractorTests.swift
  LearningRetentionPolicyTests.swift
  LearningIntegrationTests.swift
```

Exact file boundaries may be combined when a type is small, but the responsibilities must remain separated.

## Storage Decision

Use a dedicated database:

```text
~/Library/Application Support/Flint/Learning.sqlite
```

Do not add learning tables to `History.sqlite` because:

- History can be disabled while explicit vocabulary remains enabled.
- Learning deletion and retention differ from history retention.
- A separate database avoids contention with history and app-mode operations.
- Privacy reporting can describe the learning store independently.

Enable foreign keys and WAL when opening the database. All access is owned by `LearningStore`.

## V1 Schema

V1 persists active vocabulary and explicit correction evidence. Static formatting preferences remain in `AppSettingsStore` and do not use `memory_items`.

```sql
PRAGMA foreign_keys = ON;

CREATE TABLE memory_items (
    id               TEXT PRIMARY KEY,
    memory_type      TEXT NOT NULL DEFAULT 'vocabulary'
                     CHECK (memory_type = 'vocabulary'),
    scope_kind       TEXT NOT NULL
                     CHECK (scope_kind IN ('global', 'application')),
    scope_value      TEXT NOT NULL DEFAULT '',
    language         TEXT NOT NULL DEFAULT 'auto',
    heard_form       TEXT NOT NULL,
    heard_key        TEXT NOT NULL,
    preferred_form   TEXT NOT NULL,
    confidence       REAL NOT NULL DEFAULT 1.0,
    evidence_count   INTEGER NOT NULL DEFAULT 1,
    usage_count      INTEGER NOT NULL DEFAULT 0,
    status           TEXT NOT NULL DEFAULT 'active'
                     CHECK (status IN ('proposed', 'active', 'disabled', 'rejected')),
    origin           TEXT NOT NULL
                     CHECK (origin IN ('seeded', 'explicit_correction')),
    created_at       INTEGER NOT NULL,
    updated_at       INTEGER NOT NULL,
    last_used_at     INTEGER,
    CHECK (
        (scope_kind = 'global' AND scope_value = '') OR
        (scope_kind = 'application' AND length(scope_value) > 0)
    )
);

CREATE UNIQUE INDEX idx_memory_unique_mapping
    ON memory_items(memory_type, scope_kind, scope_value, language, heard_key);

CREATE INDEX idx_memory_active_scope
    ON memory_items(status, language, scope_kind, scope_value);

CREATE TABLE correction_evidence (
    id                    TEXT PRIMARY KEY,
    memory_item_id        TEXT REFERENCES memory_items(id) ON DELETE SET NULL,
    original_text         TEXT NOT NULL,
    corrected_text        TEXT NOT NULL,
    application_bundle_id TEXT NOT NULL DEFAULT '',
    language              TEXT NOT NULL DEFAULT 'auto',
    cleanup_mode          TEXT,
    source                TEXT NOT NULL DEFAULT 'explicit_fix'
                          CHECK (source = 'explicit_fix'),
    created_at            INTEGER NOT NULL
);

CREATE INDEX idx_evidence_memory_item
    ON correction_evidence(memory_item_id);

CREATE INDEX idx_evidence_created_at
    ON correction_evidence(created_at);
```

`scope_value` is non-null because SQLite unique indexes allow multiple `NULL` values. An empty string is the canonical global scope. `heard_key` is the normalized, case-folded, whitespace-collapsed key used for uniqueness; `heard_form` preserves the user's display input.

Teach Flint a Word writes only `memory_items`. It does not create artificial correction evidence.

Classifier columns and provenance blobs are excluded from V1. Add nullable columns through a later migration only if Gate A passes.

## Existing Vocabulary Migration

Current custom replacements live in UserDefaults. Migrate them once:

1. If the learning migration marker is absent, read `DictionaryEngine.listCustomReplacements()`.
2. Insert each item as global, `language = 'auto'`, `origin = 'seeded'`, and `status = 'active'`.
3. Preserve UUID, display forms, usage count, and timestamps where available.
4. Commit all inserts in one transaction.
5. Set the migration marker only after the transaction succeeds.
6. Keep the old UserDefaults payload until at least one successful reload from `Learning.sqlite`.
7. Make the migration idempotent through the unique key and original IDs.

Default built-in developer replacements remain code-defined in `DictionaryEngine`.

## MemorySnapshot and Dictation Integration

`MemorySnapshot` is an immutable, `Sendable` value containing active vocabulary grouped by language and scope.

`AppCoordinator`, already `@MainActor`, owns the current snapshot:

- Load it asynchronously at startup.
- Replace it on the main actor after a successful learning-store write.
- Pass it by value to `DictionaryEngine.apply` with the captured `ActiveAppInfo` and language.
- Never `await` a store read during transcription cleanup.

Matching precedence:

1. Application-scoped mapping.
2. Global mapping.
3. Longer heard phrases before shorter phrases.
4. Existing built-in defaults after user mappings, unless an explicit conflict rule says otherwise.

User mappings must be able to override defaults intentionally.

`DictionaryEngine.apply` should return both the updated text and matched memory IDs. Usage increments are enqueued to `LearningStore` after insertion; they are not written synchronously while applying the dictionary.

If the snapshot cannot load, Flint continues with built-in replacements and normal dictation.

## Teach Flint a Word

Extend the existing Settings vocabulary form with:

- Heard form.
- Preferred form.
- Language, defaulting to the current Flint language setting.
- Scope, defaulting to global.
- Application selector when application scope is chosen, populated from recent dictation applications and currently running applications.

Validation:

- Both forms are required after trimming.
- Heard and preferred forms must not be identical after exact comparison.
- Application scope requires a non-empty bundle identifier.
- Upserting the same normalized key updates the preferred form rather than creating a duplicate.
- A conflicting existing mapping requires an explicit replace confirmation.

Save flow:

1. Validate on the main actor.
2. Write asynchronously through `LearningStore`.
3. Rebuild and publish `MemorySnapshot` after commit.
4. Show success or error in Settings.
5. Never mutate the hot snapshot before persistence succeeds.

## Static Formatting Preferences

V1 adds only preferences supported by the existing cleanup pipeline:

- Remove filler words.
- Add terminal punctuation.

Store them in `AppSettings`/UserDefaults, with defaults preserving today's behavior. Apply them to cleanup-derived modes; `verbatim` remains verbatim.

Existing cleanup-mode selection and app-aware mode rules remain the mechanism for prompt/message/email behavior. Numeral conversion, Markdown rewriting, and inferred formatting are out of V1.

## RecentDictationBuffer

The buffer belongs to learning orchestration, not `TextInsertionEngine`, because `AppCoordinator` has the raw transcript, final output, active application, language, mode, and delivery result.

```swift
struct RecentDictation: Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let rawText: String
    let insertedText: String
    let applicationName: String?
    let applicationBundleID: String?
    let language: String
    let cleanupMode: CleanupMode
    let deliveryResult: TextInsertionResult
}
```

Rules:

- Capacity is exactly 10.
- Append only completed, usable outputs after delivery is attempted.
- Evict oldest first.
- Clear on relaunch.
- Never persist buffer entries unless the user saves an explicit correction.
- Do not retain `AXUIElement` references or live target values.
- The menu action is disabled when the buffer is empty.

## Fix This Dictation

### Panel

The panel contains:

1. A compact picker for the 10 recent entries, newest first, showing application, age, and a short preview.
2. Read-only **Flint wrote** text from the frozen buffer entry.
3. Editable **You meant** text, prefilled with the frozen text.
4. A scope control defaulting to that entry's application, with global as an explicit alternative.
5. A visible reusable mapping proposal when the diff extractor finds one.
6. **Save & Copy** and **Cancel**.

Never re-read the target field. The user is declaring what Flint should have produced, not asking Flint to infer which later field edits were corrections.

V1 copies the corrected full text on save. It does not automatically rewrite the original target, because the target may have changed and the frozen buffer deliberately contains no live Accessibility reference.

### CorrectionDiffExtractor

An explicit correction still needs a bounded rule for deciding whether it contains a reusable mapping.

V1 extraction is deliberately narrow:

1. Compute the smallest single contiguous changed span using a Unicode-safe common-prefix/common-suffix diff.
2. Require non-empty original and replacement spans.
3. Require each changed span to be no more than 80 characters and five whitespace-delimited words.
4. Reject changes that consume most of a long sentence unless the changed sentence itself is within those bounds.
5. Preserve the exact preferred form while normalizing only the heard lookup key.

When eligible, show:

```text
Learn “post grass” → “Postgres” in Cursor
```

The user explicitly confirms or disables that mapping before save. Confirmed mappings become active immediately with `origin = 'explicit_correction'`. Ineligible or disabled mappings still create `correction_evidence`, but do not alter future output.

Save is disabled when the corrected full text is unchanged. Empty corrected text may be saved as rejection evidence in a later phase; V1 does not create a memory from it.

### Save Transaction

Use one store transaction:

1. Upsert the confirmed memory, if any.
2. Insert `correction_evidence` and link its memory ID when applicable.
3. Apply retention limits.
4. Commit.

After commit:

- Rebuild/publish the snapshot if a memory changed.
- Copy the corrected full text to the clipboard.
- Close the panel and show a quiet confirmation.

If persistence fails, leave the panel open with the user's text intact. Dictation remains unaffected.

## Retention and Database Limits

V1 retention:

| Data | Bound |
| --- | --- |
| Recent dictations | Memory-only, 10 entries, cleared on relaunch |
| Correction evidence | 90 days or 2,000 rows, whichever comes first |
| Active/disabled user memories | Retained until user deletion |
| Rejected mapping fingerprints | Defer until proposals exist beyond explicit V1 |
| Learning database | 50 MB high-water mark |

Pruning runs:

- After a successful explicit write when a cheap size/count check indicates a limit may be exceeded.
- Once after startup, delayed until Flint is idle.
- In small transactions on `LearningStore`.

Prune oldest correction evidence first. Never prune user-created memories automatically. Use WAL checkpointing and incremental cleanup; do not run blocking `VACUUM` during ordinary use.

## Performance Rules

- The dictation path reads only `MemorySnapshot`.
- SQLite writes, snapshot rebuilds, retention, and metrics persistence happen after insertion or from explicit UI actions.
- No store operation is awaited between transcription completion and insertion.
- Snapshot application target: under 10 ms at p95 for normal dictation.
- Recent-buffer append target: under 2 ms at p95.
- An unavailable learning database degrades to built-in dictionary behavior.
- Usage-count writes are coalesced and background-only.
- No learning job runs Core ML or competes with Whisper in V1.

Add a debug performance probe that can apply a snapshot containing at least 1,000 mappings to representative transcripts. It need not be a flaky wall-clock CI assertion; record and review benchmark results during release qualification.

## Privacy Integration

Add Learning to `PrivacyManager`:

- Learning database path.
- Active vocabulary count.
- Correction-evidence count.
- Current database size.
- Explanation that only explicit corrections are stored in V1.

Add actions to:

- Delete an individual memory.
- Delete correction evidence while preserving active vocabulary.
- Delete all learning data.
- Include `Learning.sqlite`, WAL, and SHM files in Delete All Local Data.

Learning data remains separate from transcript history. No surrounding application text, audio, Accessibility event stream, or normal dictation record is stored by V1.

## Local Gate Metrics

Use aggregate counters only; do not add content telemetry.

Suggested counters:

- Completed usable dictations.
- Teach-word saves.
- Fix panel opens.
- Fix saves.
- Fix cancellations.
- Eligible reusable mappings shown.
- Explicit mappings accepted.
- Active memories applied.

Store counters locally, separately from user content, and provide a manual summary/export for the Gate A review. Do not transmit them automatically.

Initial Gate A review:

- Run for at least two weeks.
- Include at least 300 real dictations across testers.
- Do not build passive observation if fewer than 5% of dictations produce an explicit correction action and testers cannot identify a recurring missed category.
- Consider passive observation only when correction burden is frequent or there is a named, repeatable pattern the explicit flow structurally fails to capture.

The threshold guides a small pilot; it is not a permanent population-level rule.

Gate B is independent: decide whether pronunciation adaptation belongs in the product promise. If not, do not build provenance, retry pairs, or audio storage.

## Phase 0 Spikes

Run these in parallel without blocking V1.

### Classifier Fixture

- Hand-label 50–100 real before/after examples.
- Include non-errors, vocabulary, casing, punctuation, rewriting, Undo, rejection, and full replacement.
- Keep a held-out subset.
- Record precision, recall, activity, and `unknown` rate by category.
- Treat 95% precision and 40% recall as provisional feasibility targets only.
- Add examples from multiple testers before any passive auto-application decision.

### Accessibility Coverage

Probe Terminal, Cursor or VS Code, Slack, Mail, Safari or Chrome, and Notes.

For each surface record value-change reliability, value shape, selected-range stability, anchor stability, insertion method, event latency, and duplication. Assign Tier A/B/C as defined in the strategic plan.

Spike code is diagnostic and does not ship enabled in production V1.

## Testing Requirements

### LearningStore

- Schema creation and migration.
- Foreign-key and status constraints.
- Global-scope uniqueness despite SQLite null semantics.
- Application-scoped coexistence with global mappings.
- Atomic memory/evidence transaction.
- Evidence retention by age and count.
- 50 MB high-water behavior.
- Database/WAL/SHM deletion.
- Idempotent UserDefaults vocabulary migration.

### MemorySnapshot and DictionaryEngine

- App-specific mapping overrides global.
- User mapping overrides built-in default intentionally.
- Longer phrase wins over shorter phrase.
- Disabled memories never apply.
- Language scope is respected.
- Matched IDs are returned without synchronous usage writes.
- Empty or failed snapshot preserves normal dictation.

### RecentDictationBuffer

- Capacity remains 10.
- Oldest entry is evicted.
- Frozen text never changes.
- No persistence occurs without explicit save.
- Copied-to-clipboard delivery can still be corrected.

### CorrectionDiffExtractor

- Single-word and multi-word substitutions.
- Casing-only correction.
- Punctuation correction.
- Unicode grapheme safety.
- Insertion-only, deletion-only, unchanged, multi-region, and large-rewrite rejection.
- Five-word and 80-character boundaries.

### UI and Integration

- Teach word validation, conflict replacement, scope, and snapshot refresh.
- Formatting settings preserve existing defaults.
- Recent-entry selection and frozen panel contents.
- Save & Copy creates evidence and optional memory exactly once.
- Persistence failure preserves panel input.
- Privacy counts and deletion.
- Dictation succeeds when `Learning.sqlite` is absent, locked, corrupt, or unavailable.

## Acceptance Criteria

V1 is complete when:

- Existing custom vocabulary migrates without loss.
- A seeded global or application-scoped term affects the next matching dictation.
- Formatting toggles preserve current defaults and alter only their intended cleanup behavior.
- The last 10 outputs can be selected for explicit correction without persistent logging.
- Fix This Dictation stores the frozen before/after pair and never silently captures live application text.
- Only a visible, explicitly confirmed bounded substitution becomes an active memory.
- No database operation occurs on the user-visible dictation critical path.
- Retention and the 50 MB high-water mark are enforced.
- Privacy can report and delete all V1 learning data.
- Existing dictation, insertion, dictionary, history, privacy, and cleanup tests continue to pass.

## Build Sequence

### Milestone 1: Storage Foundation

- `LearningStore`, schema, migration, retention, and tests.
- `MemorySnapshot` and startup loading.
- Privacy reporting/deletion foundation.

### Milestone 2: Explicit Vocabulary and Formatting

- Extend existing vocabulary UI with language and scope.
- Wire snapshot-based dictionary application.
- Add background usage increments.
- Add the two formatting preferences.

### Milestone 3: Fix This Dictation

- Recent buffer owned by `AppCoordinator`.
- Panel and recent-entry picker.
- Bounded diff extractor.
- Atomic save, explicit mapping confirmation, and Save & Copy.

### Milestone 4: Qualification

- Full automated regression suite.
- Performance benchmark with large snapshots.
- Retention/storage tests.
- Privacy deletion verification.
- Phase 0 spike reports.
- Gate A/B metrics collection enabled locally.

Nothing after Milestone 4 is scheduled until Gate A and Gate B are reviewed with real usage evidence.
