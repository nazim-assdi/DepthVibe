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

python3 tool/configure_platforms.py
flutter pub get
