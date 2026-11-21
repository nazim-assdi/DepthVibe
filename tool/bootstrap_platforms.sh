#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK is not installed or is not on PATH." >&2
  exit 1
fi

if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python)"
else
  echo "Python 3 is required to configure platform permissions and generate app icons." >&2
  exit 1
fi

flutter create \
  --project-name depthvibe \
  --org com.ntech \
  --platforms=android,ios,windows,linux,macos \
  .

"$PYTHON_BIN" tool/test_platform_branding.py
"$PYTHON_BIN" tool/configure_platforms.py
"$PYTHON_BIN" tool/generate_brand_icons.py
flutter pub get
