#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/native/ONNXGigaAMHelper/main.cpp"
OUTPUT_DIR="${1:?usage: build_onnx_gigaam_helper.sh OUTPUT_DIR}"

ORT_VERSION="1.29.0"
# microsoft/onnxruntime GitHub releases were removed in 2026-11; NuGet ships the official signed macOS dylib.
ORT_ARCHIVE="microsoft.ml.onnxruntime.$ORT_VERSION.nupkg"
ORT_URL="https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/$ORT_VERSION/$ORT_ARCHIVE"
ORT_SHA256="4557021fec4da3924e2e12ff44b1cc50b176de0d2c5c7daa89ab11c208b3a454"
ORT_CACHE="${GUESLI_ONNX_RUNTIME_CACHE_DIR:-$HOME/Library/Caches/guesli-onnxruntime}"
ORT_ROOT="${GUESLI_ONNX_RUNTIME_ROOT:-$ORT_CACHE/onnxruntime-osx-arm64-$ORT_VERSION}"
ARCHIVE_PATH="$ORT_CACHE/$ORT_ARCHIVE"

if [[ ! -f "$ORT_ROOT/include/onnxruntime_cxx_api.h" || ! -f "$ORT_ROOT/lib/libonnxruntime.$ORT_VERSION.dylib" ]]; then
  if [[ -n "${GUESLI_ONNX_RUNTIME_ROOT:-}" ]]; then
    echo "Invalid GUESLI_ONNX_RUNTIME_ROOT: $ORT_ROOT" >&2
    exit 1
  fi
  mkdir -p "$ORT_CACHE"
  if [[ ! -f "$ARCHIVE_PATH" ]]; then
    curl -fsSL "$ORT_URL" -o "$ARCHIVE_PATH.tmp"
    mv "$ARCHIVE_PATH.tmp" "$ARCHIVE_PATH"
  fi
  printf '%s  %s\n' "$ORT_SHA256" "$ARCHIVE_PATH" | shasum -a 256 -c -
  rm -rf "$ORT_ROOT" "$ORT_ROOT.tmp"
  unzip -q "$ARCHIVE_PATH" 'build/native/include/*' 'runtimes/osx-arm64/native/libonnxruntime.dylib' -d "$ORT_ROOT.tmp"
  mkdir -p "$ORT_ROOT/lib"
  mv "$ORT_ROOT.tmp/build/native/include" "$ORT_ROOT/include"
  mv "$ORT_ROOT.tmp/runtimes/osx-arm64/native/libonnxruntime.dylib" "$ORT_ROOT/lib/libonnxruntime.$ORT_VERSION.dylib"
  ln -s "libonnxruntime.$ORT_VERSION.dylib" "$ORT_ROOT/lib/libonnxruntime.dylib"
  rm -rf "$ORT_ROOT.tmp"
fi

mkdir -p "$OUTPUT_DIR"
xcrun clang++ \
  -std=c++17 \
  -O3 \
  -DNDEBUG \
  -arch arm64 \
  -mmacosx-version-min=14.2 \
  -I "$ORT_ROOT/include" \
  "$SOURCE" \
  -L "$ORT_ROOT/lib" \
  -lonnxruntime \
  -Wl,-rpath,@loader_path \
  -o "$OUTPUT_DIR/onnx-gigaam-helper"

cp "$ORT_ROOT/lib/libonnxruntime.$ORT_VERSION.dylib" \
  "$OUTPUT_DIR/libonnxruntime.$ORT_VERSION.dylib"
xcrun install_name_tool \
  -change @rpath/libonnxruntime.1.dylib \
  @loader_path/libonnxruntime.$ORT_VERSION.dylib \
  "$OUTPUT_DIR/onnx-gigaam-helper"
chmod +x "$OUTPUT_DIR/onnx-gigaam-helper"

otool -L "$OUTPUT_DIR/onnx-gigaam-helper" | grep -Fq \
  "@loader_path/libonnxruntime.$ORT_VERSION.dylib"
