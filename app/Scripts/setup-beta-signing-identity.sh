#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPOSITORY_DIR="$(cd "$ROOT_DIR/.." && pwd)"
SIGNING_DIR="${FLINT_BETA_SIGNING_DIR:-$HOME/Library/Application Support/Flint Beta Signing}"
IDENTITY_NAME="${FLINT_BETA_SIGNING_IDENTITY:-Flint Beta Signing}"
KEYCHAIN_PATH="$SIGNING_DIR/FlintBeta.keychain-db"
PASSWORD_PATH="$SIGNING_DIR/keychain-password"
BACKUP_PATH="$SIGNING_DIR/FlintBetaSigningIdentity.p12"
CERTIFICATE_PATH="$SIGNING_DIR/FlintBetaSigningCertificate.pem"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/flint-beta-signing.XXXXXX")"

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

ensure_keychain_is_searchable() {
    local existing_path
    local found=false
    local keychains=()

    while IFS= read -r existing_path; do
        existing_path="$(printf '%s' "$existing_path" | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//')"
        [[ -n "$existing_path" ]] || continue
        keychains+=("$existing_path")
        if [[ "$existing_path" == "$KEYCHAIN_PATH" ]]; then
            found=true
        fi
    done < <(security list-keychains -d user)

    if [[ "$found" == false ]]; then
        security list-keychains -d user -s "$KEYCHAIN_PATH" "${keychains[@]}"
    fi
}

for command in openssl security; do
    if ! command -v "$command" >/dev/null; then
        echo "Required command is unavailable: $command" >&2
        exit 1
    fi
done

mkdir -p "$SIGNING_DIR"
SIGNING_DIR="$(cd "$SIGNING_DIR" && pwd -P)"
chmod 700 "$SIGNING_DIR"
KEYCHAIN_PATH="$SIGNING_DIR/FlintBeta.keychain-db"
PASSWORD_PATH="$SIGNING_DIR/keychain-password"
BACKUP_PATH="$SIGNING_DIR/FlintBetaSigningIdentity.p12"
CERTIFICATE_PATH="$SIGNING_DIR/FlintBetaSigningCertificate.pem"

case "$SIGNING_DIR/" in
    "$REPOSITORY_DIR/"*)
        echo "Refusing to store beta signing material inside the Flint repository: $SIGNING_DIR" >&2
        exit 1
        ;;
esac

if [[ -f "$KEYCHAIN_PATH" || -f "$PASSWORD_PATH" || -f "$BACKUP_PATH" ]]; then
    if [[ ! -f "$KEYCHAIN_PATH" || ! -f "$PASSWORD_PATH" || ! -f "$BACKUP_PATH" ]]; then
        echo "Incomplete beta signing material exists at $SIGNING_DIR." >&2
        echo "Move that directory aside and rerun this script, or restore all three files from backup." >&2
        exit 1
    fi

    KEYCHAIN_PASSWORD="$(tr -d '\r\n' < "$PASSWORD_PATH")"
    ensure_keychain_is_searchable
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    if [[ ! -f "$CERTIFICATE_PATH" ]]; then
        security find-certificate -c "$IDENTITY_NAME" -p "$KEYCHAIN_PATH" \
            | openssl x509 -out "$CERTIFICATE_PATH"
        chmod 600 "$CERTIFICATE_PATH"
    fi
    if ! security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -Fq "\"$IDENTITY_NAME\""; then
        security add-trusted-cert \
            -r trustRoot \
            -p codeSign \
            -k "$KEYCHAIN_PATH" \
            "$CERTIFICATE_PATH"
    fi
    if security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -Fq "\"$IDENTITY_NAME\""; then
        security lock-keychain "$KEYCHAIN_PATH"
        echo "Existing Flint beta signing identity is ready in $KEYCHAIN_PATH"
        exit 0
    fi

    echo "The beta signing keychain exists but does not contain '$IDENTITY_NAME'." >&2
    exit 1
fi

umask 077
openssl rand -hex -out "$PASSWORD_PATH" 32
KEYCHAIN_PASSWORD="$(tr -d '\r\n' < "$PASSWORD_PATH")"

openssl req \
    -x509 \
    -newkey rsa:3072 \
    -sha256 \
    -days 3650 \
    -nodes \
    -subj "/CN=$IDENTITY_NAME/O=Flint Beta Release" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -keyout "$TEMP_DIR/private-key.pem" \
    -out "$TEMP_DIR/certificate.pem" >/dev/null 2>&1

openssl pkcs12 \
    -export \
    -legacy \
    -name "$IDENTITY_NAME" \
    -inkey "$TEMP_DIR/private-key.pem" \
    -in "$TEMP_DIR/certificate.pem" \
    -passout "file:$PASSWORD_PATH" \
    -out "$BACKUP_PATH"
openssl x509 -in "$TEMP_DIR/certificate.pem" -out "$CERTIFICATE_PATH"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
ensure_keychain_is_searchable
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$BACKUP_PATH" \
    -k "$KEYCHAIN_PATH" \
    -P "$KEYCHAIN_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security >/dev/null
security set-key-partition-list \
    -S apple-tool:,apple: \
    -s \
    -k "$KEYCHAIN_PASSWORD" \
    "$KEYCHAIN_PATH" >/dev/null
security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$KEYCHAIN_PATH" \
    "$CERTIFICATE_PATH"

chmod 600 "$PASSWORD_PATH" "$BACKUP_PATH" "$CERTIFICATE_PATH" "$KEYCHAIN_PATH"

if ! security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -Fq "\"$IDENTITY_NAME\""; then
    echo "The beta signing identity was created but macOS does not recognize it for code signing." >&2
    exit 1
fi
security lock-keychain "$KEYCHAIN_PATH"

echo "Created persistent Flint beta signing identity: $IDENTITY_NAME"
echo "Private material and its encrypted backup are stored outside Git at: $SIGNING_DIR"
echo "Back up that directory securely. Losing it will change Flint's macOS privacy identity."
