#!/usr/bin/env bash
# Generates the platform runner folders (web/, macos/, windows/, linux/) that `flutter create`
# owns, without touching lib/ or test/. Run once after cloning, and in CI.
#
#   app/tool/setup_platforms.sh [platforms]     default: web,macos,windows,linux
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
PLATFORMS="${1:-web,macos,windows,linux}"

flutter create --platforms="$PLATFORMS" --project-name worklog_app --org io.github.zaepark .

# The macOS app runs sandboxed; it needs the outgoing-network entitlement to reach
# the local worklog server at http://127.0.0.1:4710.
for f in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
  [[ -f "$f" ]] || continue
  if ! grep -q "com.apple.security.network.client" "$f"; then
    perl -0pi -e 's#</dict>\s*</plist>#\t<key>com.apple.security.network.client</key>\n\t<true/>\n</dict>\n</plist>#' "$f"
    echo "added network.client entitlement to $f"
  fi
done
