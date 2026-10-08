#!/usr/bin/env bash
# scripts/release_apk.sh: release APKs for testers, one per phone ABI.
#
#   RISITI_API_URL=https://risiti.example.com scripts/release_apk.sh
#
# Builds with `mix mob.release --android`, trims the OTP runtime it packs,
# and runs Gradle for the APKs.
set -euo pipefail

: "${RISITI_API_URL:?Set RISITI_API_URL to your server, e.g. https://risiti.example.com}"

mix mob.release --android

ZIP=android/app/src/release/assets/otp.zip

# The cached runtime carries its own, older exqlite next to ours. Keep only
# the version in mix.lock.
ours="$(grep -o '"exqlite": {:hex, :exqlite, "[^"]*"' mix.lock | cut -d'"' -f4)"
[ -n "$ours" ] || { echo "No exqlite version in mix.lock" >&2; exit 1; }
for dir in $(unzip -Z1 "$ZIP" | grep -oE '^lib/exqlite-[^/]+' | sort -u); do
  if [ "$dir" != "lib/exqlite-$ours" ]; then
    echo "Removing $dir (ours is $ours)"
    zip -dq "$ZIP" "$dir/*"
  fi
done

# OTP apps Risiti never loads, headers, and macOS "._" files.
zip -dq "$ZIP" 'lib/common_test-*' 'lib/ssh-*' 'lib/mnesia-*' 'lib/jinterface-*' \
  'lib/eldap-*' 'lib/odbc-*' 'erts-*/include/*' 'lib/erts-*/include/*' \
  '*/._*' '._*' || true

(cd android && ./gradlew assembleRelease)

ls -lh android/app/build/outputs/apk/release/*.apk
