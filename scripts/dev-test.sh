#!/usr/bin/env bash
set -euo pipefail

# Builds and launches an isolated dev app for end-to-end testing.
#
# - Separate bundle ID (com.guesli.dev*) — won't interfere with production Guesli
# - Separate data directory (~/Library/Application Support/GuesliDev*/)
# - Preserves existing dev config and database by default
# - Dev builds default to local-only entitlements to preserve existing TCC
#   permissions and avoid requiring Apple Developer profiles
# - CloudKit/APNs dev signing is opt-in with --cloud-entitlements
# - External contributors can set GUESLI_SKIP_SIGN=1 to build without the
#   maintainer signing certificate
# - Uses a shared, worktree-isolated SwiftPM scratch path by default; set
#   GUESLI_DISABLE_SWIFTPM_SCRATCH_PATH=1 to use package-local .build instead
# - Installs to /Applications/GuesliDev*.app
#
# Usage:
#   ./scripts/dev-test.sh                         # Build and launch GuesliDev
#   ./scripts/dev-test.sh --lane A                # Build and launch GuesliDevA
#   ./scripts/dev-test.sh --lane A --local-only   # Omit iCloud/APNs entitlements
#   ./scripts/dev-test.sh --reset                 # Reset onboarding only (keeps data)
#   GUESLI_PROVISIONING_PROFILE=/path/to/profile.provisionprofile \
#   GUESLI_SIGN_IDENTITY="Apple Development: Name (TEAMID)" \
#   GUESLI_CODESIGN_TIMESTAMP=none ./scripts/dev-test.sh --cloud-entitlements

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Build and launch a local Guesli dev app.

Options:
  --lane A|B|C            Build a fixed reusable dev lane: GuesliDevA/B/C.
  --local-only            Sign without iCloud/APNs entitlements.
                          Alias: --without-cloud-entitlements.
  --cloud-entitlements    Sign with the default cloud entitlements file.
                          Alias: --with-cloud-entitlements.
  --reset                 Reset onboarding only for the selected lane.
  --help                  Show this help text.

Default behavior without --lane uses the app identity: GuesliDev,
com.guesli.dev, ~/Library/Application Support/GuesliDev, and
/Applications/GuesliDev.app. Dev builds use local-only entitlements unless
--cloud-entitlements is provided.

Cloud-entitled dev builds require a provisioning profile whose app identifier
matches the selected bundle ID and a signing identity included by that profile.
Pass the profile and signing identity explicitly through
GUESLI_PROVISIONING_PROFILE and GUESLI_SIGN_IDENTITY.
EOF
}

# Parse args
RESET=0
LANE=""
ENTITLEMENTS_MODE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      echo "Error: --clean has been removed because it deletes GuesliDev data." >&2
      echo "To test a fresh profile, create a named backup first and use a separate support directory." >&2
      exit 2
      ;;
    --reset)
      RESET=1
      shift
      ;;
    --lane)
      [[ $# -ge 2 ]] || { echo "Error: --lane requires A, B, or C." >&2; exit 2; }
      LANE="$2"
      shift 2
      ;;
    --lane=*)
      LANE="${1#--lane=}"
      shift
      ;;
    --local-only|--without-cloud-entitlements)
      ENTITLEMENTS_MODE="local-only"
      shift
      ;;
    --cloud-entitlements|--with-cloud-entitlements)
      ENTITLEMENTS_MODE="cloud"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$LANE" in
  "")
    DEV_APP_NAME="GuesliDev"
    DEV_BUNDLE_ID="com.guesli.dev"
    ;;
  A|a|B|b|C|c)
    LANE_UPPER="$(printf '%s' "$LANE" | tr '[:lower:]' '[:upper:]')"
    LANE_LOWER="$(printf '%s' "$LANE" | tr '[:upper:]' '[:lower:]')"
    DEV_APP_NAME="GuesliDev${LANE_UPPER}"
    DEV_BUNDLE_ID="com.guesli.dev.${LANE_LOWER}"
    ;;
  *)
    echo "Error: unsupported lane '$LANE'. Allowed lanes: A, B, C." >&2
    exit 2
    ;;
esac

if [[ -z "$ENTITLEMENTS_MODE" ]]; then
  ENTITLEMENTS_MODE="local-only"
fi

DEV_SUPPORT_DIR="$HOME/Library/Application Support/$DEV_APP_NAME"
DEV_APP="/Applications/$DEV_APP_NAME.app"
ONBOARDING_PROGRESS_FILE="$DEV_SUPPORT_DIR/onboarding-progress.json"
RESOLVED_PROVISIONING_PROFILE="${GUESLI_PROVISIONING_PROFILE:-}"
RESOLVED_SIGN_IDENTITY="${GUESLI_SIGN_IDENTITY:-}"
RESOLVED_CODESIGN_TIMESTAMP="${GUESLI_CODESIGN_TIMESTAMP:-}"
BUILD_ENV=(
  GUESLI_APP_NAME="$DEV_APP_NAME"
  GUESLI_BUNDLE_ID="$DEV_BUNDLE_ID"
  GUESLI_SUPPORT_DIR_NAME="$DEV_APP_NAME"
  GUESLI_DISPLAY_NAME="$DEV_APP_NAME"
  GUESLI_SPARKLE_FEED_URL=""
)
if [[ -n "$LANE" ]]; then
  BUILD_ENV+=(GUESLI_EXECUTABLE_NAME="$DEV_APP_NAME")
fi

use_local_only_entitlements() {
  RESOLVED_PROVISIONING_PROFILE=""
  RESOLVED_SIGN_IDENTITY=""
  RESOLVED_CODESIGN_TIMESTAMP=""
  BUILD_ENV+=(
    GUESLI_ENTITLEMENTS="$ROOT/scripts/GuesliLocalOnly.entitlements"
    GUESLI_PROVISIONING_PROFILE=""
    GUESLI_APS_ENVIRONMENT=""
  )
}

case "$ENTITLEMENTS_MODE" in
  local-only)
    use_local_only_entitlements
    ;;
  cloud)
    if [[ -z "$RESOLVED_PROVISIONING_PROFILE" ]]; then
      echo "Error: cloud-entitled dev builds require GUESLI_PROVISIONING_PROFILE." >&2
      echo "The profile must match bundle ID '$DEV_BUNDLE_ID' and include the signing identity." >&2
      echo "Use --local-only for a dev build that does not need iCloud/APNs entitlements." >&2
      exit 2
    else
      if [[ -z "$RESOLVED_SIGN_IDENTITY" ]]; then
        echo "Error: cloud-entitled dev builds require GUESLI_SIGN_IDENTITY." >&2
        echo "Use the Apple Development identity included by the selected provisioning profile." >&2
        exit 2
      fi
      BUILD_ENV+=(
        GUESLI_PROVISIONING_PROFILE="$RESOLVED_PROVISIONING_PROFILE"
        GUESLI_SIGN_IDENTITY="$RESOLVED_SIGN_IDENTITY"
      )
      if [[ -n "$RESOLVED_CODESIGN_TIMESTAMP" ]]; then
        BUILD_ENV+=(GUESLI_CODESIGN_TIMESTAMP="$RESOLVED_CODESIGN_TIMESTAMP")
      fi
    fi
    ;;
  *)
    echo "Error: internal unsupported entitlements mode '$ENTITLEMENTS_MODE'." >&2
    exit 2
    ;;
esac

# Kill any running dev instance
pkill -f "$DEV_APP" 2>/dev/null || true
sleep 0.5

# Reset onboarding only if requested
if [[ "$RESET" -eq 1 ]] && [[ -f "$DEV_SUPPORT_DIR/config.json" ]]; then
  echo "Resetting onboarding flag for $DEV_APP_NAME..."
  python3 -c "
import json, os, pathlib
p = pathlib.Path('$DEV_SUPPORT_DIR/config.json')
c = json.loads(p.read_text())
c['has_completed_onboarding'] = False
mode = p.stat().st_mode & 0o777
p.write_text(json.dumps(c, indent=2) + '\n')
os.chmod(p, mode)
progress = pathlib.Path('$ONBOARDING_PROGRESS_FILE')
if progress.exists():
    progress.unlink()
    print('  Cleared transient onboarding progress')
print('  Onboarding reset (data preserved)')
"
fi

# Build with isolated identity
echo "Building $DEV_APP_NAME (debug, signed)..."
echo "  Bundle ID:    $DEV_BUNDLE_ID"
echo "  Data:         $DEV_SUPPORT_DIR"
echo "  Entitlements: $ENTITLEMENTS_MODE"
if [[ -n "$RESOLVED_PROVISIONING_PROFILE" ]]; then
  echo "  Profile:      $RESOLVED_PROVISIONING_PROFILE"
fi
if [[ -n "$RESOLVED_SIGN_IDENTITY" ]]; then
  echo "  Sign identity: $RESOLVED_SIGN_IDENTITY"
fi
env "${BUILD_ENV[@]}" "$ROOT/scripts/build_native_app.sh" debug

echo ""
echo "Launching $DEV_APP_NAME..."
open "$DEV_APP"

echo ""
echo "=== Dev Test Ready ==="
echo "  App: $DEV_APP"
echo "  Data: $DEV_SUPPORT_DIR"
echo "  DB: $DEV_SUPPORT_DIR/guesli.db"
echo ""
echo "Tips:"
if [[ -n "$LANE" ]]; then
  echo "  ./scripts/dev-test.sh --lane $LANE --reset    # Re-run onboarding for this lane (keep data)"
else
  echo "  ./scripts/dev-test.sh --reset                 # Re-run onboarding (keep data)"
fi
echo "  pkill -f \"$DEV_APP\"                         # Kill this dev app"
