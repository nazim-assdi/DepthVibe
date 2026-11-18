#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK is not installed or is not on PATH." >&2
  exit 1
fi

flutter create \
  --project-name depthvibe \
  --org com.ntech \
  --platforms=android,ios,windows,linux,macos \
  .

if command -v python3 >/dev/null 2>&1; then
  python3 tool/configure_platforms.py
elif command -v python >/dev/null 2>&1; then
  python tool/configure_platforms.py
else
  echo "Python 3 is required to configure platform permissions." >&2
  exit 1
fi
flutter pub get
