# Flint Deployment

Deploy the `landing` Next.js application to `flint.moyezrabbani.dev`. The
marketing site and licensing API are one deployment; no separate service is
needed.

## Environment Variables

Set these as encrypted production environment variables in the host. Copy their
values from the ignored `landing/.env`; do not generate a second signing key.

- `DATABASE_URL`
- `RESEND_API_KEY`
- `LICENSE_EMAIL_FROM`
- `BETA_EMAIL_FROM`
- `LICENSE_KEY_PEPPER`
- `BETA_ABUSE_PEPPER`
- `BETA_OTP_PEPPER`
- `LICENSE_SIGNING_PRIVATE_KEY`
- `COMMERCE_WEBHOOK_SECRET`
- `LICENSE_APP_BUNDLE_ID`
- `NEXT_PUBLIC_SITE_URL=https://flint.moyezrabbani.dev`

`LICENSE_CERTIFICATE_PUBLIC_KEY` is public and is embedded in the Flint macOS
source. It is not required by the server at runtime.

## Before Production Traffic

1. Point `flint.moyezrabbani.dev` at the deployment host and verify HTTPS.
2. Add and verify the Resend sending domain. Configure `BETA_EMAIL_FROM` for
   six-digit download verification emails and `LICENSE_EMAIL_FROM` for future
   device-transfer emails. Resend will reject production email until the domain
   is verified.
3. Run `npm run landing:db:migrate` against the production database. It is safe
   to rerun. Migration `0004_beta_email_verification.sql` must be present before
   deploying the matching application build.
4. Upload the current versioned DMG and checksum to a durable public artifact host. Beta 3 is temporarily shipped from `public/downloads`; use public object storage for repeated releases. Confirm `landing/app/lib/beta/latest-release.ts` or the `FLINT_BETA_*` environment variables match that artifact.
5. Set `FLINT_BETA_TEST_EMAIL` to an inbox you control that supports plus
   addressing, then run the complete disposable OTP/signup/download check
   against the deployed API:

   ```sh
   FLINT_BETA_TEST_URL=https://flint.moyezrabbani.dev \
   npm run landing:beta:verify
   ```

6. Run the complete disposable activation check only when preparing a paid release:

   ```sh
   FLINT_LICENSE_TEST_URL=https://flint.moyezrabbani.dev/api/licenses \
   npm run landing:licenses:verify
   ```

7. Run the public production-surface verifier:

   ```sh
   FLINT_PRODUCTION_URL=https://flint.moyezrabbani.dev \
   npm run landing:production:verify
   ```

   This confirms the public pages, legal/support routes, security headers, and
   ARM64 release metadata.
8. Keep `FlintLicenseEnforcement` false throughout the free beta. For a later paid build, keep it false until the deployed API has passed an
   activation and renewal test with a real beta key. Then set it true in
   `app/Distribution/Info.plist` for the next paid beta DMG.

## Backups and Recovery

Use the database provider's automatic backups and point-in-time recovery when
available. For the public beta, retain at least 30 days and send backup-failure
alerts to the support email. Before launch, perform one restore into a separate,
disposable database and confirm that migrations and beta-signup export work.

An additional portable PostgreSQL backup can be created with:

```sh
DATABASE_URL="postgresql://production-backup-connection" \
FLINT_BACKUP_DIR="/private/path/to/flint-backups" \
npm run landing:db:backup
```

The command writes a custom-format `pg_dump`, validates its table of contents,
and writes a SHA-256 checksum. Never store backups in `landing/public`, Git, or
another publicly served directory. Restore only into a new database first:

```sh
pg_restore --clean --if-exists --no-owner --no-privileges \
  --dbname="postgresql://disposable-restore-database" flint-postgres-YYYYMMDDTHHMMSSZ.dump
```

## Monitoring and Abuse Controls

- Monitor `/api/releases/latest` over HTTPS every five minutes and alert the
  support email after two consecutive failures.
- Alert on sustained HTTP 5xx responses, migration failures, database storage
  pressure, and failed backups. Review 429 counts for abuse or an overly strict
  limit; never log request bodies, submitted license keys, or download tokens.
- Beta request and verification limits are stored in PostgreSQL as short-lived
  HMAC hashes. Code requests allow 20 attempts per request address and 5 per
  normalized email per 15 minutes. Verification allows at most 5 incorrect
  codes per challenge in addition to request-address and challenge rate limits.
  `BETA_ABUSE_PEPPER` and `BETA_OTP_PEPPER` must be distinct, high entropy, and
  server-only.
- Security headers are set by Next.js. Re-run the production verifier after
  every deployment so a hosting override cannot silently remove them.

## Rollback

Application deployments can roll back to the previous immutable build. Database
migrations are append-only: do not reverse or edit an applied migration during
an incident. Roll back application code only when it remains compatible with
the already-applied schema, then ship a new forward migration for any required
database correction.

## Payment Provider

The commerce webhook intentionally returns `501` until a provider is selected.
For an early paid beta, provision keys with `npm run landing:licenses:create`
after receiving payment. Once checkout is selected, add its verified webhook
adapter in `app/api/webhooks/commerce/route.ts`; that is the only remaining
payment-specific implementation.

Payment work is not part of the free public beta. The placeholder commerce route remains disabled.

## Beta Email Export

The download gate stores optional first and last names, verified email status, and beta-access consent separately from optional product-update consent. Export the current list locally without exposing database credentials:

```sh
npm run landing:beta:export > flint-beta-signups.csv
```
