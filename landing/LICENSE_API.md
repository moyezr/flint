# Flint Licensing API

The licensing service runs as Next.js Route Handlers under `app/api`. It is
server-only: the database URL, Resend key, license-key pepper, and certificate
private key must never use `NEXT_PUBLIC_` names.

## Configuration

Copy `.env.example` to `.env` and set the required values. Generate secrets on
a secure machine:

```sh
openssl rand -hex 32
openssl genpkey -algorithm Ed25519 -out flint-license-private.pem
base64 < flint-license-private.pem | tr -d '\n'
```

Store the raw private-key PEM only in a secret manager. The base64 value is the
one-line `LICENSE_SIGNING_PRIVATE_KEY` environment value. The corresponding
public key is embedded in the macOS app later so it can verify certificates
offline.

## Database

Run migrations after setting `DATABASE_URL`:

```sh
npm --workspace flint-landing run db:migrate
```

Migrations are append-only SQL files in `db/migrations`. The migration runner
records applied filenames in `flint_schema_migrations`.

Until a payment provider is chosen, create a paid beta license manually after
receiving payment through the chosen sales process. Never put the raw key in a
shell history that you do not control or commit it to a file:

```sh
FLINT_LICENSE_KEY="FLINT-..." \
FLINT_CUSTOMER_EMAIL="customer@example.com" \
npm --workspace flint-landing run licenses:create
```

The command stores only an HMAC of the license key. It prints the new license
ID and customer email, never the key itself.

## Device Protocol

The macOS app generates an Ed25519 device signing key in a `ThisDeviceOnly`
Keychain item. It sends only the raw 32-byte public key, base64url-encoded.

1. `POST /api/licenses/challenges` with `devicePublicKey` and a purpose.
2. Sign the exact `message` returned by the server with the device private key.
3. Call `activate`, `validate`, or `deactivate` with the challenge ID and
   base64url signature.
4. On success, persist the returned signed certificate in Keychain.

Certificates bind one license activation to one device public-key hash and are
valid offline for 90 days by default. They also bind the release to the
configured `LICENSE_APP_BUNDLE_ID`. Revalidate opportunistically after 30 days.
An existing active device is never silently replaced: activation sends a
confirmation email to the purchaser, and a confirmation atomically revokes the
old activation before issuing the new one.

## Native UX Policy

License verification must not run in the push-to-talk hot path. Flint verifies
the locally stored certificate at launch and at most once every 24 hours after
that. Server validation is opportunistic after 30 days and runs in the
background. A valid certificate permits dictation without a network request;
an expired certificate presents the License window before the next recording.

## Endpoints

| Endpoint | Purpose |
| --- | --- |
| `POST /api/licenses/challenges` | Issue a 10-minute, single-use device challenge. |
| `POST /api/licenses/activate` | Activate an unused license or request a transfer. |
| `POST /api/licenses/validate` | Renew an active device's offline certificate. |
| `POST /api/licenses/deactivate` | Deactivate the current device. |
| `POST /api/licenses/transfers/confirm` | Complete a purchaser-confirmed transfer. |
| `POST /api/webhooks/commerce` | Provider adapter seam for verified purchase events. |

The commerce webhook is intentionally not enabled until a payment provider is
selected. It rejects requests with `501` rather than accepting unverified
purchase data.
