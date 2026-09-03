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

# A release keystore is only USED if android/app/build.gradle wires a release signingConfig
# that reads keystore.properties. Expo/RN prebuild generates a release buildType that signs
# with `signingConfigs.debug` and never reads keystore.properties — so without the wiring the
# "release" AAB/APK is silently DEBUG-signed and the Play Store rejects it. Detect and warn loudly.
app_gradle="$ANDROID_DIR/app/build.gradle"
app_gradle_kts="$ANDROID_DIR/app/build.gradle.kts"
if { [[ -f "$app_gradle" ]] && grep -q "keystore.properties" "$app_gradle"; } || \
   { [[ -f "$app_gradle_kts" ]] && grep -q "keystore.properties" "$app_gradle_kts"; }; then
  echo "Detected keystore.properties wiring in the Gradle config — release signing looks configured."
else
  echo "::warning::Release keystore materialized, but android/app/build.gradle does not read keystore.properties. The release build will be DEBUG-signed and Play will reject it. Wire the release signingConfig (see README.md → 'Android release signing'), or commit a pre-configured android/ and set SKIP_PREBUILD=true."
fi
