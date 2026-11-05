#!/usr/bin/env bash
# Builds the app the way every shipped build must be built.
#
#   tool/build_release.sh          an APK for testing on phones (arm64)
#   tool/build_release.sh store    an App Bundle (.aab) to upload to Play
#
# Each build is numbered with the count of commits on this branch, so every
# upload has a higher number than the last, as the stores require; the
# version name (1.0.0) comes from pubspec.yaml. BUILD_NUMBER=... overrides.
#
# The API origin is compiled in from config/development.json (git-ignored;
# see config/development.example.json). The Firebase project (push and crash
# reports) is set in the server's .env and fetched by the app at start-up, so
# no build carries it necessarily; Firebase values in the config file are
# only a fallback for a phone that has never reached the server.
# android/key.properties signs with the shared release key;
# android/maps.properties turns Google Maps on.
set -euo pipefail
cd "$(dirname "$0")/.."

config=config/development.json
if [[ ! -f $config ]]; then
  echo "Missing $config: copy config/development.example.json and set API_BASE_URL." >&2
  exit 1
fi
if ! python3 -c "import json,sys; sys.exit(0 if str(json.load(open('$config')).get('API_BASE_URL','')).strip() else 1)"; then
  echo "$config has no API_BASE_URL: the app would not know its server. Not building." >&2
  exit 1
fi
target=apk
if [[ ${1:-} == store ]]; then
  target=store
  shift
fi
if [[ ! -f android/key.properties ]]; then
  if [[ $target == store ]]; then
    echo "No android/key.properties: a store build must be signed with the release key. Not building." >&2
    exit 1
  fi
  echo "Note: no android/key.properties; signing with this machine's debug key." >&2
fi
build_number=${BUILD_NUMBER:-$(git rev-list --count HEAD)}

defines=(--dart-define-from-file="$config")
if [[ -f android/maps.properties ]]; then
  defines+=(--dart-define=GOOGLE_MAPS=true)
fi

if [[ $target == store ]]; then
  flutter build appbundle --release --build-number="$build_number" "${defines[@]}" "$@"
else
  flutter build apk --release --target-platform android-arm64 --build-number="$build_number" "${defines[@]}" "$@"
fi
