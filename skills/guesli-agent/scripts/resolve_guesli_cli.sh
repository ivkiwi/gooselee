#!/usr/bin/env bash
set -euo pipefail

if command -v guesli-cli >/dev/null 2>&1; then
  command -v guesli-cli
  exit 0
fi

if [[ -x "/Applications/Guesli.app/Contents/MacOS/guesli-cli" ]]; then
  echo "/Applications/Guesli.app/Contents/MacOS/guesli-cli"
  exit 0
fi

if [[ -x "native/Guesli/.build/debug/guesli-cli" ]]; then
  echo "$(pwd)/native/Guesli/.build/debug/guesli-cli"
  exit 0
fi

if [[ -x "native/Guesli/.build/release/guesli-cli" ]]; then
  echo "$(pwd)/native/Guesli/.build/release/guesli-cli"
  exit 0
fi

exit 1
