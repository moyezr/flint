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
