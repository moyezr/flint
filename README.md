# Flint

Flint is an offline macOS dictation application and its accompanying marketing site.

## Repository layout

- [`app/`](./app) - native macOS application, release tooling, and its tests.
- [`landing/`](./landing) - Next.js 16 landing page prototype.

## Local development

Run the macOS application from `app/`:

```sh
cd app
swift run Flint
```

Run the landing page from the repository root:

```sh
npm install
npm run landing:dev
```
