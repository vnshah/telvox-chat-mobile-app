#!/usr/bin/env bash
# Builds the release APK the way every shipped build must be built.
#
# Firebase (push notifications) and the API origin are compiled in from
# config/development.json (git-ignored; see config/development.example.json).
# A build without them installs and runs, but never receives a notification,
# so this script refuses to build without them. android/key.properties signs
# with the shared release key; android/maps.properties turns Google Maps on.
set -euo pipefail
cd "$(dirname "$0")/.."

config=config/development.json
if [[ ! -f $config ]]; then
  echo "Missing $config: copy config/development.example.json and fill in the Firebase values." >&2
  exit 1
fi
for key in API_BASE_URL FIREBASE_API_KEY FIREBASE_APP_ID FIREBASE_MESSAGING_SENDER_ID FIREBASE_PROJECT_ID; do
  if ! python3 -c "import json,sys; sys.exit(0 if str(json.load(open('$config')).get('$key','')).strip() else 1)"; then
    echo "$config has no $key: push notifications would not work. Not building." >&2
    exit 1
  fi
done
[[ -f android/key.properties ]] || echo "Note: no android/key.properties; signing with this machine's debug key." >&2

defines=(--dart-define-from-file="$config")
if [[ -f android/maps.properties ]]; then
  defines+=(--dart-define=GOOGLE_MAPS=true)
fi

flutter build apk --release --target-platform android-arm64 "${defines[@]}" "$@"
