#!/usr/bin/env bash
# Materialize the Android release keystore from a base64 secret and write
# android/keystore.properties for Gradle. If secrets are absent, no-op so the
# build falls back to debug signing (APK/AAB still produced for QA/sideload).
#
# Expected secrets (see README.md):
#   ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD
set -euo pipefail

ANDROID_DIR="${ANDROID_PROJECT_DIR:-android}"

# When Fastlane runs from repo root (monorepo), honor MOBILE_PATH.
if [[ -n "${MOBILE_PATH:-}" ]] && [[ ! -d "$ANDROID_DIR" ]] && [[ -d "${MOBILE_PATH}/${ANDROID_DIR}" ]]; then
  ANDROID_DIR="${MOBILE_PATH}/${ANDROID_DIR}"
fi

# When invoked from fastlane/ via absolute script path, prefer app root relative android/.
if [[ ! -d "$ANDROID_DIR" ]] && [[ -d "$(dirname "$0")/../${ANDROID_PROJECT_DIR:-android}" ]]; then
  ANDROID_DIR="$(cd "$(dirname "$0")/../${ANDROID_PROJECT_DIR:-android}" && pwd)"
fi
if [[ -z "${ANDROID_KEYSTORE_BASE64:-}" ]]; then
  echo "ANDROID_KEYSTORE_BASE64 not set — using debug signing fallback (APK/AAB will not be Play-ready)."
  exit 0
fi

mkdir -p "$ANDROID_DIR/app"
keystore_path="$ANDROID_DIR/app/release.keystore"

echo "$ANDROID_KEYSTORE_BASE64" | base64 --decode > "$keystore_path"

cat > "$ANDROID_DIR/keystore.properties" <<EOF
storeFile=app/release.keystore
storePassword=${ANDROID_KEYSTORE_PASSWORD:-}
keyAlias=${ANDROID_KEY_ALIAS:-}
keyPassword=${ANDROID_KEY_PASSWORD:-}
EOF

echo "Wrote $ANDROID_DIR/keystore.properties and release.keystore."
echo "NOTE: your android/app/build.gradle must read keystore.properties for the release signingConfig."
