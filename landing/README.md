# Flint Landing

Next.js 16 App Router prototype for the Flint marketing site.

## Development

From the repository root:

```sh
npm install
npm run landing:dev
```

The production URL is configured with `NEXT_PUBLIC_SITE_URL`. Set it before deployment so canonical URLs, the sitemap, and robots metadata use the real domain.

Run `npm run landing:lint` and `npm run landing:build` before publishing. The production visual asset requirements are in [ASSETS.md](./ASSETS.md).

## Licensing API

The same Next.js deployment hosts Flint's server-side licensing endpoints. Copy
`.env.example` to `.env`, configure the server-only secrets, and run:

```sh
npm run landing:db:migrate
```

The complete endpoint contract, local-device protocol, and beta license
provisioning command are in [LICENSE_API.md](./LICENSE_API.md).
