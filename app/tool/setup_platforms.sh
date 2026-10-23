#!/usr/bin/env bash
# Generates the platform runner folders (web/, macos/, windows/, linux/) that `flutter create`
# owns, without touching lib/ or test/. Run once after cloning, and in CI.
#
#   app/tool/setup_platforms.sh [platforms]     default: web,macos,windows,linux
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
PLATFORMS="${1:-web,macos,windows,linux}"

flutter create --platforms="$PLATFORMS" --project-name zaevis --org io.github.zaepark .

# The macOS app runs sandboxed: it needs the outgoing-network entitlement to reach the local
# zaevis server (http://127.0.0.1:4710) and read access to files the user picks (recordings).
for f in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
  [[ -f "$f" ]] || continue
  for key in com.apple.security.network.client com.apple.security.files.user-selected.read-only; do
    if ! grep -q "$key" "$f"; then
      KEY="$key" perl -0pi -e 's#</dict>\s*</plist>#\t<key>$ENV{KEY}</key>\n\t<true/>\n</dict>\n</plist>#' "$f"
      echo "added $key entitlement to $f"
    fi
  done
done
