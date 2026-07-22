# Contributing to Flint

Thank you for helping improve Flint. Changes should preserve the product's core
promise: dictation stays local, begins promptly, keeps the app responsive, and
inserts output at most once.

## Before starting

For substantial features or architecture changes, open an issue first so the
scope and privacy implications can be discussed. Small bug fixes, tests, and
documentation improvements can go directly to a pull request.

Please do not add passive keystroke observation, audio retention, telemetry,
cloud transcription, or automatic learning from unrelated user activity without
an explicit design and privacy review.

## Development setup

Follow the native and website setup in the [README](./README.md). The architecture
and safety invariants are documented in [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md).

Create a focused branch and keep generated build output, environment files,
database exports, and signing material out of Git. Only maintainer release work
may update the five-version DMG archive under `landing/public/downloads`.

## Validation

For native app changes:

```sh
cd app
swift test
MACOSX_DEPLOYMENT_TARGET=14.0 swift build -c release
```

For website or service changes:

```sh
npm ci --prefix landing
npm run landing:test
npm run landing:lint
npm run landing:build
```

Tests are not proof that system-wide text insertion works. Changes to targeting,
Accessibility, shortcuts, paste fallback, or onboarding should include a manual
macOS test description in the pull request. Verify that insertion occurs once
and the user's clipboard is restored unchanged.

## Pull requests

- Keep each pull request focused and explain the user-visible outcome.
- Add or update tests for behavior changes.
- Update public documentation when behavior, data storage, permissions, or setup
  changes.
- Do not combine broad formatting changes with logic changes.
- Do not commit `.dmg` files outside a maintainer release change that adds the
  newest beta and removes the oldest retained version.

By contributing, you agree that your contribution may be distributed under the
repository's [MIT License](./LICENSE).
