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
- `LICENSE_KEY_PEPPER`
- `LICENSE_SIGNING_PRIVATE_KEY`
- `COMMERCE_WEBHOOK_SECRET`
- `LICENSE_APP_BUNDLE_ID`
- `NEXT_PUBLIC_SITE_URL=https://flint.moyezrabbani.dev`

`LICENSE_CERTIFICATE_PUBLIC_KEY` is public and is embedded in the Flint macOS
source. It is not required by the server at runtime.

## Before Production Traffic

1. Point `flint.moyezrabbani.dev` at the deployment host and verify HTTPS.
2. Add and verify the Resend sending domain. The configured sender is
   `licenses@flint.moyezrabbani.dev`; Resend will reject production email until
   the domain is verified.
3. Run `npm run landing:db:migrate` against the production database exactly
   once. It is safe to rerun.
4. Upload the current versioned DMG and checksum to its immutable GitHub release. Confirm `landing/app/lib/beta/latest-release.ts` or the `FLINT_BETA_*` environment variables match that artifact.
5. Run the complete disposable beta signup/download check against the deployed API:

   ```sh
   FLINT_BETA_TEST_URL=https://flint.moyezrabbani.dev \
   npm run landing:beta:verify
   ```

6. Run the complete disposable activation check only when preparing a paid release:

   ```sh
   FLINT_LICENSE_TEST_URL=https://flint.moyezrabbani.dev/api/licenses \
   npm run landing:licenses:verify
   ```

7. Confirm `/robots.txt`, `/sitemap.xml`, `/privacy`, `/beta`, and `/api/releases/latest` on the deployed domain.
8. Keep `FlintLicenseEnforcement` false throughout the free beta. For a later paid build, keep it false until the deployed API has passed an
   activation and renewal test with a real beta key. Then set it true in
   `app/Distribution/Info.plist` for the next paid beta DMG.

## Payment Provider

The commerce webhook intentionally returns `501` until a provider is selected.
For an early paid beta, provision keys with `npm run landing:licenses:create`
after receiving payment. Once checkout is selected, add its verified webhook
adapter in `app/api/webhooks/commerce/route.ts`; that is the only remaining
payment-specific implementation.

Payment work is not part of the free public beta. The placeholder commerce route remains disabled.

## Beta Email Export

The download gate stores beta-access consent separately from optional product-update consent. Export the current list locally without exposing database credentials:

```sh
npm run landing:beta:export > flint-beta-signups.csv
```
