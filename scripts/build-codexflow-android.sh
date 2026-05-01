#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-/home/lin/.local/share/flutter/bin/flutter}"
APP_DIR="$ROOT_DIR/flutter/codexflow"
WEB_DIR="${CODEXFLOW_ANDROID_WEB_DIR:-/home/lin/.local/share/codexflow-web/web}"
VERSION="0.2.0"
BUILD_NUMBER="2"
VERSIONED_APK="codexflow-android-v${VERSION}.apk"
LATEST_APK="codexflow-android-latest.apk"
META_JSON="codexflow-android-latest.json"
KEY_PROPERTIES="$APP_DIR/android/key.properties"

export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.dev}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.googleapis.com}"

if [[ ! -f "$KEY_PROPERTIES" ]]; then
  echo "Missing Android signing config: $KEY_PROPERTIES" >&2
  echo "Create flutter/codexflow/android/key.properties and reuse /home/lin/.local/share/codexflow-keys/release.jks for the release keystore." >&2
  exit 1
fi

cd "$APP_DIR"
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" test
"$FLUTTER_BIN" build apk --release

mkdir -p "$WEB_DIR"
cp "$APP_DIR/build/app/outputs/flutter-apk/app-release.apk" "$WEB_DIR/$VERSIONED_APK"
cp "$WEB_DIR/$VERSIONED_APK" "$WEB_DIR/$LATEST_APK"

SHA256="$(sha256sum "$WEB_DIR/$VERSIONED_APK" | awk '{print $1}')"
BUILT_AT="$(date -Iseconds)"
cat > "$WEB_DIR/$META_JSON" <<JSON
{
  "version": "$VERSION",
  "buildNumber": $BUILD_NUMBER,
  "artifact": "$VERSIONED_APK",
  "latestArtifact": "$LATEST_APK",
  "sha256": "$SHA256",
  "builtAt": "$BUILT_AT"
}
JSON

echo "$WEB_DIR/$VERSIONED_APK"
echo "$SHA256"
