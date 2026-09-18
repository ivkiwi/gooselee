#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CONFIG="${1:-debug}"
INSTALL_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/guesli-packaging-test.XXXXXX")"
APP_BUNDLE_NAME="GuesliPackagingTest.app"
APP_PATH="$INSTALL_ROOT/$APP_BUNDLE_NAME"
APP_BIN="$APP_PATH/Contents/MacOS/Guesli"
CLI_BIN="$APP_PATH/Contents/MacOS/guesli-cli"
GIGAAM_HELPER="$APP_PATH/Contents/MacOS/onnx-gigaam-helper"
FLUIDAUDIO_LICENSE="$APP_PATH/Contents/Resources/FluidAudio-LICENSE-Apache-2.0.txt"
APP_ICON="$APP_PATH/Contents/Resources/gooselee.icns"
MENU_ICON="$APP_PATH/Contents/Resources/menu_goose_color.png"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
SPEC_OUTPUT="$INSTALL_ROOT/guesli-cli-spec.json"
TRANSCRIBE_HELP_OUTPUT="$INSTALL_ROOT/guesli-cli-transcribe-help.txt"

cleanup() {
  rm -rf "$INSTALL_ROOT"
}
trap cleanup EXIT

echo "Building isolated app bundle in $INSTALL_ROOT"
GUESLI_INSTALL_DIR="$INSTALL_ROOT" \
GUESLI_APP_BUNDLE_NAME="$APP_BUNDLE_NAME" \
GUESLI_SKIP_SIGN=1 \
"$ROOT/scripts/build_native_app.sh" "$BUILD_CONFIG"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected packaged app at $APP_PATH" >&2
  exit 1
fi

if [[ ! -x "$APP_BIN" ]]; then
  echo "Missing app executable at $APP_BIN" >&2
  exit 1
fi

if [[ ! -x "$CLI_BIN" ]]; then
  echo "Missing CLI executable at $CLI_BIN" >&2
  exit 1
fi

if [[ ! -x "$GIGAAM_HELPER" ]]; then
  echo "Missing ONNX GigaAM helper at $GIGAAM_HELPER" >&2
  exit 1
fi
find "$APP_PATH/Contents/MacOS" -maxdepth 1 -name 'libonnxruntime*.dylib' -type f | grep -q . || {
  echo "Missing ONNX Runtime dylib" >&2
  exit 1
}
[[ -s "$FLUIDAUDIO_LICENSE" ]] || { echo "Missing bundled FluidAudio Apache license" >&2; exit 1; }
[[ -s "$APP_ICON" ]] || { echo "Missing bundled GooseLee app icon" >&2; exit 1; }
[[ -s "$MENU_ICON" ]] || { echo "Missing bundled GooseLee menu icon" >&2; exit 1; }

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$INFO_PLIST")" == "GooseLee" ]] || {
  echo "Packaged app display name is not GooseLee" >&2
  exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO_PLIST")" == "gooselee.icns" ]] || {
  echo "Packaged app does not reference gooselee.icns" >&2
  exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :GuesliSupportDirectoryName' "$INFO_PLIST")" == "Guesli" ]] || {
  echo "Branding change must preserve the Guesli support directory" >&2
  exit 1
}
case "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")" in
  0.9.*) ;;
  *) echo "Packaged app version is not in the 0.9 release line" >&2; exit 1 ;;
esac

"$CLI_BIN" spec > "$SPEC_OUTPUT"
"$CLI_BIN" transcribe --help > "$TRANSCRIBE_HELP_OUTPUT"

if ! grep -q '"command" : "guesli-cli spec"' "$SPEC_OUTPUT"; then
  echo "Packaged CLI did not return the expected spec payload." >&2
  cat "$SPEC_OUTPUT" >&2
  exit 1
fi

if ! grep -q 'USAGE: guesli-cli transcribe' "$TRANSCRIBE_HELP_OUTPUT"; then
  echo "Packaged CLI did not return transcribe help." >&2
  cat "$TRANSCRIBE_HELP_OUTPUT" >&2
  exit 1
fi

echo "Packaged CLI smoke test passed."
echo "Verified:"
echo "  - $APP_BIN"
echo "  - $CLI_BIN"
echo "  - $GIGAAM_HELPER"
echo "  - bundled third-party license"
echo "  - GooseLee display name, icon, and preserved Guesli data directory"
