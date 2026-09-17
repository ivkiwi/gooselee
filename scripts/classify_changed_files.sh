#!/usr/bin/env bash
set -euo pipefail

native_or_packaging=false
browser_extension=false
release_update=false

while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  case "$path" in
    native/*|assets/*|LICENSE)
      native_or_packaging=true
      ;;
    .github/workflows/ci.yml|.github/workflows/release-macos-app.yml|docs/appcast-guesli.xml|scripts/classify_changed_files.sh|scripts/merge_appcast_item.py|scripts/release_version.sh|scripts/require_successful_ci_gate.sh|scripts/test_classify_changed_files.sh|scripts/test_merge_appcast_item.py|scripts/test_release_workflow_security.sh|scripts/update_appcast_release_notes.py|scripts/verify_update_flow.sh)
      release_update=true
      ;;
    scripts/*.sh|scripts/*.py)
      native_or_packaging=true
      ;;
  esac
  case "$path" in
    browser-extension/*)
      browser_extension=true
      ;;
  esac
  case "$path" in
    .github/workflows/release-macos-app.yml|docs/appcast-guesli.xml|scripts/build_native_app.sh|scripts/build_localvqe.sh|scripts/build_onnx_gigaam_helper.sh|scripts/localvqe_runtime.sh|scripts/merge_appcast_item.py|scripts/test_merge_appcast_item.py|scripts/test_localvqe_runtime_validation.sh|scripts/test_packaged_cli.sh|scripts/verify_update_flow.sh|LICENSE|native/Guesli/ThirdPartyLicenses/FluidAudio-Apache-2.0.txt)
      release_update=true
      ;;
  esac
done

echo "native_or_packaging=$native_or_packaging"
echo "browser_extension=$browser_extension"
echo "release_update=$release_update"
