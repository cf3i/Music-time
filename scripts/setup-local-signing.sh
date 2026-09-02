#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIGNING_DIR="$PROJECT_DIR/.local-signing"
KEYCHAIN_PATH="$SIGNING_DIR/EdgePulseLocal.keychain-db"
PASSWORD_FILE="$SIGNING_DIR/keychain-password"
IDENTITY_NAME="EdgePulse Local Development"

ensure_keychain_searchable() {
    local keychains=()
    local line
    local existing

    while IFS= read -r line; do
        line="${line#*\"}"
        line="${line%\"*}"
        [[ -n "$line" ]] && keychains+=("$line")
    done < <(security list-keychains -d user)

    for existing in "${keychains[@]}"; do
        [[ "$existing" == "$KEYCHAIN_PATH" ]] && return
    done

    security list-keychains -d user -s "${keychains[@]}" "$KEYCHAIN_PATH"
}

validate_identity() {
    security find-identity -v -p codesigning "$KEYCHAIN_PATH" \
        | grep -Fq "\"$IDENTITY_NAME\""
}

trust_identity() {
    echo "macOS may ask for an administrator confirmation to trust this certificate for code signing only."
    security add-trusted-cert \
        -r trustRoot \
        -p codeSign \
        -k "$KEYCHAIN_PATH" \
        "$SIGNING_DIR/certificate.pem"
}

if [[ -f "$KEYCHAIN_PATH" && -f "$PASSWORD_FILE" ]]; then
    KEYCHAIN_PASSWORD="$(<"$PASSWORD_FILE")"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    ensure_keychain_searchable
    if validate_identity; then
        echo "Local signing identity is ready: $IDENTITY_NAME"
        exit 0
    fi

    if [[ -f "$SIGNING_DIR/certificate.pem" ]]; then
        trust_identity
        if validate_identity; then
            echo "Local signing identity is ready: $IDENTITY_NAME"
            exit 0
        fi
    fi

    echo "The existing EdgePulse signing keychain is incomplete." >&2
    echo "Move $SIGNING_DIR aside and run this script again." >&2
    exit 1
fi

mkdir -p "$SIGNING_DIR"
chmod 700 "$SIGNING_DIR"
umask 077

KEYCHAIN_PASSWORD="$(openssl rand -hex 24)"
printf '%s' "$KEYCHAIN_PASSWORD" > "$PASSWORD_FILE"

TEMP_DIR="$(mktemp -d "$SIGNING_DIR/setup.XXXXXX")"
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

openssl req \
    -x509 \
    -newkey rsa:2048 \
    -sha256 \
    -days 3650 \
    -nodes \
    -subj "/CN=$IDENTITY_NAME/O=EdgePulse Local Development" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,digitalSignature,keyCertSign" \
    -addext "extendedKeyUsage=codeSigning" \
    -keyout "$TEMP_DIR/private-key.pem" \
    -out "$TEMP_DIR/certificate.pem"

openssl pkcs12 \
    -export \
    -name "$IDENTITY_NAME" \
    -inkey "$TEMP_DIR/private-key.pem" \
    -in "$TEMP_DIR/certificate.pem" \
    -out "$TEMP_DIR/identity.p12" \
    -passout "pass:$KEYCHAIN_PASSWORD"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$TEMP_DIR/identity.p12" \
    -k "$KEYCHAIN_PATH" \
    -P "$KEYCHAIN_PASSWORD" \
    -T /usr/bin/codesign
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$KEYCHAIN_PASSWORD" \
    "$KEYCHAIN_PATH" >/dev/null

cp "$TEMP_DIR/certificate.pem" "$SIGNING_DIR/certificate.pem"
ensure_keychain_searchable
trust_identity
if ! validate_identity; then
    echo "macOS did not accept the local code-signing identity." >&2
    exit 1
fi

security find-identity -v -p codesigning "$KEYCHAIN_PATH"
echo "Created project-local signing identity: $IDENTITY_NAME"
