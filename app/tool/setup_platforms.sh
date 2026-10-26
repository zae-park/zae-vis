#!/usr/bin/env bash
# Generates the platform runner folders (web/, macos/, windows/, linux/) that `flutter create`
# owns, without touching lib/ or test/. Run once after cloning, and in CI.
#
#   app/tool/setup_platforms.sh [platforms]     default: web,macos,windows,linux
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
PLATFORMS="${1:-web,macos,windows,linux}"

# `flutter create` rewrites the runner templates (entitlements included) every time it runs, so only
# ask it for platforms that are missing; existing folders keep their mtimes and local edits.
MISSING=()
for p in ${PLATFORMS//,/ }; do [[ -d "$p" ]] || MISSING+=("$p"); done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  flutter create --platforms="$(IFS=,; echo "${MISSING[*]}")" --project-name zaevis --org io.github.zaepark .
fi

# zaevis is a local tool distributed outside the App Store: it starts its own server (bundled
# Node), reads ~/.claude, git repositories and shell history, and installs a LaunchAgent.
# None of that works inside the App Sandbox, so the sandbox is turned off.
for f in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
  [[ -f "$f" ]] || continue
  # Only write when something changes: Xcode refuses to build if the entitlements file's
  # mtime moves between builds ("modified during the build").
  changed=0
  if perl -0ne 'exit 1 unless /<key>com\.apple\.security\.app-sandbox<\/key>\s*<true\/>/' "$f"; then
    perl -0pi -e 's#(<key>com\.apple\.security\.app-sandbox</key>\s*)<true/>#$1<false/>#' "$f"; changed=1
  fi
  for key in com.apple.security.network.client com.apple.security.files.user-selected.read-only com.apple.security.device.audio-input; do
    if ! grep -q "$key" "$f"; then
      KEY="$key" perl -0pi -e 's#</dict>\s*</plist>#\t<key>$ENV{KEY}</key>\n\t<true/>\n</dict>\n</plist>#' "$f"; changed=1
    fi
  done
  [[ $changed -eq 1 ]] && echo "entitlements updated: $f" || echo "entitlements ok: $f"
done

# In-app recording: macOS refuses microphone access (and kills the app) without a usage description.
PLIST=macos/Runner/Info.plist
if [[ -f "$PLIST" ]] && ! grep -q NSMicrophoneUsageDescription "$PLIST"; then
  perl -0pi -e 's#</dict>\s*</plist>#\t<key>NSMicrophoneUsageDescription</key>\n\t<string>회의나 메모를 녹음해 바로 전사(whisperX)하려면 마이크가 필요합니다.</string>\n</dict>\n</plist>#' "$PLIST"
  echo "Info.plist updated: NSMicrophoneUsageDescription"
fi
