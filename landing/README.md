# Flint Landing

Next.js 16 App Router prototype for the Flint marketing site.

## Development

From the repository root:

```sh
npm --prefix landing install
npm run landing:dev
```

The production URL is configured with `NEXT_PUBLIC_SITE_URL`. Set it before deployment so canonical URLs, the sitemap, and robots metadata use the real domain.

Run `npm run landing:lint` and `npm run landing:build` before publishing. The production visual asset requirements are in [ASSETS.md](./ASSETS.md).

## Public beta downloads

The home-page download form accepts optional first and last names, verifies the submitted email with a six-digit one-time code, and stores the verified signup plus versioned terms acceptance in PostgreSQL. Only a successful verification returns the short-lived one-time handoff to the current versioned DMG. Apply migrations, configure Resend, verify the flow, and export signups with:

```sh
npm run landing:db:migrate
FLINT_BETA_TEST_EMAIL=you+flint-test@example.com \
FLINT_BETA_TEST_URL=http://127.0.0.1:3000 npm run landing:beta:verify
npm run landing:beta:export > flint-beta-signups.csv
```

After deploying, verify the public pages, security headers, and ARM64 release metadata with:

```sh
FLINT_PRODUCTION_URL=https://flint.moyezrabbani.dev npm run landing:production:verify
```

Current release metadata lives in `app/lib/beta/latest-release.ts` and is exposed to packaged Flint builds at `/api/releases/latest`.

### Landing palette

The landing page uses Tailwind CSS v4 and semantic color tokens. Set
`NEXT_PUBLIC_FLINT_BASE_THEME` to `warm` (the default) or `slate` in `.env`
before building to compare the two base palettes. Components use the same
semantic tokens, so changing the setting does not require component edits.

## Licensing API

The same Next.js deployment hosts Flint's server-side licensing endpoints. Copy
`.env.example` to `.env`, configure the server-only secrets, and run:

```sh
npm run landing:db:migrate
```

The complete endpoint contract, local-device protocol, and beta license
provisioning command are in [LICENSE_API.md](./LICENSE_API.md).

Deployment requirements for `flint.moyezrabbani.dev` are in
[DEPLOYMENT.md](./DEPLOYMENT.md).
