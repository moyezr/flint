# Flint Blockers

These are the remaining items that require credentials, external systems,
physical testing, provider configuration, or a product decision. The native
dictation loop, explicit personalization, release-manifest updater, licensing
client, and Next.js licensing API are implemented.

## Free Public Beta

### Developer ID and Notarization

- Current state: direct beta packaging produces an ad-hoc-signed ARM64 DMG with
  honest Gatekeeper instructions.
- External blocker: no Apple Developer Program membership, Developer ID
  Application certificate, or notarytool profile is available.
- Beta decision: ship transparently without notarization. Revisit Developer ID
  before a paid or lower-friction release.

### Production Operations

- Current state: the landing app has append-only migrations, beta terms
  acceptance, a required first name, an optional last name, email OTP
  verification, database-backed abuse limits, security headers, backup tooling,
  and production smoke verifiers.
- External blocker: the deployment provider must be configured with PostgreSQL,
  encrypted secrets, HTTPS/DNS, automatic backups, alerting, and an uptime
  monitor. A restore drill and post-deployment beta download verification must
  be performed against the real services.

### Release Qualification

- Current state: ordinary browser use and sleep/wake have developer smoke
  coverage. The beta is explicitly Apple-Silicon-only because the current DMG
  contains an ARM64 executable.
- Remaining manual work: clean-user onboarding, Gatekeeper and permissions,
  interrupted/corrupt/low-disk model recovery, a 10–15 minute dictation, silent
  dictation, repeated shortcuts, and a recorded cross-app insertion matrix.
- Product decision: `showOverlay` remains persisted but intentionally has no UI
  because hiding the overlay would also hide listening/error feedback and the
  post-dictation Fix/Teach actions. Remove it or define a safe reduced-feedback
  experience before exposing it.

### Launch Media

- External owner: final real-product screenshots, workflow capture, and social
  share card remain with the developer. Browser and application icons are
  configured from the approved `F/` mark.

## Later Paid Release

- Select a payment provider and implement verified commerce fulfillment.
- Deploy and qualify activation, renewal, offline lease, deactivation, and
  replacement-device transfer with real keys before enabling
  `FlintLicenseEnforcement`.
- Add jurisdiction-reviewed paid terms and refund terms before accepting money.
- Replace the manifest download prompt with a signed in-place updater only
  after Developer ID signing is available.
