#!/usr/bin/env bash
# Builds dist/zaevis-<version>-<arch>.dmg — an app people install by dragging to Applications.
# Everything the app needs at runtime is inside zaevis.app; users install nothing else.
#
#   tool/package_macos.sh [--skip-minsync]
#
# Needs on THIS (build) Mac only: Flutter, Rust (cargo) + protobuf (for MinSync), curl.
#   brew install --cask flutter && brew install protobuf && curl https://sh.rustup.rs -sSf | sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/package"
DIST="$ROOT/dist"
NODE_MAJOR=24
SKIP_MINSYNC=0
[[ "${1:-}" == "--skip-minsync" ]] && SKIP_MINSYNC=1

say() { printf '\033[1m›\033[0m %s\n' "$*"; }
die() { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "macOS에서 실행하세요."
command -v flutter >/dev/null || die "Flutter가 필요합니다: brew install --cask flutter"
if [[ $SKIP_MINSYNC -eq 0 ]]; then
  command -v cargo >/dev/null || die "Rust가 필요합니다: curl https://sh.rustup.rs -sSf | sh  (검색 없이 만들려면 --skip-minsync)"
  command -v protoc >/dev/null || die "protobuf가 필요합니다: brew install protobuf"
fi

ARCH="$(uname -m)"                       # arm64 | x86_64
NODE_ARCH=$([[ "$ARCH" == "arm64" ]] && echo arm64 || echo x64)
VERSION="$(grep -E '^version:' "$ROOT/app/pubspec.yaml" | sed -E 's/version: *([0-9.]+).*/\1/')"
PAYLOAD="$BUILD/payload"
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD"/{bin,node/bin} "$BUILD/cache" "$DIST"

# ── 1) Node runtime (official build, checksum-verified, cached) ─────────────────
say "Node $NODE_MAJOR ($NODE_ARCH)"
SUMS="$BUILD/cache/SHASUMS256-v$NODE_MAJOR.txt"
curl -fsSL "https://nodejs.org/dist/latest-v$NODE_MAJOR.x/SHASUMS256.txt" -o "$SUMS"
TARBALL="$(grep -oE "node-v[0-9.]+-darwin-$NODE_ARCH\.tar\.gz" "$SUMS" | head -1)"
[[ -n "$TARBALL" ]] || die "Node 배포 파일을 찾지 못했습니다."
if [[ ! -f "$BUILD/cache/$TARBALL" ]]; then
  curl -fL "https://nodejs.org/dist/latest-v$NODE_MAJOR.x/$TARBALL" -o "$BUILD/cache/$TARBALL.part"
  mv "$BUILD/cache/$TARBALL.part" "$BUILD/cache/$TARBALL"
fi
(cd "$BUILD/cache" && grep " $TARBALL\$" "$SUMS" | shasum -a 256 -c -) || die "Node 체크섬이 맞지 않습니다."
NODE_DIR="$BUILD/cache/${TARBALL%.tar.gz}"
[[ -d "$NODE_DIR" ]] || tar -xzf "$BUILD/cache/$TARBALL" -C "$BUILD/cache"
cp "$NODE_DIR/bin/node" "$PAYLOAD/node/bin/node"
cp "$NODE_DIR/LICENSE" "$PAYLOAD/node/LICENSE"
NPM="$NODE_DIR/bin/npm"

# ── 2) server with production dependencies ─────────────────────────────────────
say "서버"
mkdir -p "$PAYLOAD/server"
cp -R "$ROOT/server/src" "$ROOT/server/package.json" "$ROOT/server/package-lock.json" "$PAYLOAD/server/"
(cd "$PAYLOAD/server" && PATH="$NODE_DIR/bin:$PATH" "$NPM" ci --omit=dev --no-fund --no-audit --silent)
# Drop files never loaded at runtime (source maps, type declarations, docs). Keep everything else:
# some packages ship runtime modules with names like changelog.js.
find "$PAYLOAD/server/node_modules" -type f \( -name "*.map" -o -name "*.d.ts" -o -name "*.d.mts" -o -name "*.d.cts" \
  -o -iname "README.md" -o -iname "CHANGELOG.md" -o -iname "HISTORY.md" \) -delete

# ── 3) MinSync (AutoRAG embedding engine; Rust build, cached) ──────────────────
if [[ $SKIP_MINSYNC -eq 0 ]]; then
  say "MinSync (처음 한 번은 수 분)"
  if [[ ! -x "$BUILD/cache/minsync/bin/minsync" ]]; then
    cargo install minsync --locked --root "$BUILD/cache/minsync"
  fi
  cp "$BUILD/cache/minsync/bin/minsync" "$PAYLOAD/bin/minsync"
fi

# ── 4) CLI, kit ────────────────────────────────────────────────────────────────
cp "$ROOT/bin/zaevis" "$PAYLOAD/bin/zaevis"
cp -R "$ROOT/kit" "$PAYLOAD/kit"
echo "$VERSION" > "$PAYLOAD/VERSION"

# ── 5) Flutter: web (served by the bundled server) + macOS app ───────────────────
say "Flutter 빌드"
cd "$ROOT/app"
[[ -d web && -d macos ]] || tool/setup_platforms.sh web,macos
tool/setup_platforms.sh macos >/dev/null   # re-applies entitlements if the folder already existed
flutter pub get
flutter build web --release
cp -R build/web "$PAYLOAD/web"
flutter build macos --release
APP_SRC="$ROOT/app/build/macos/Build/Products/Release/zaevis.app"
[[ -d "$APP_SRC" ]] || die "macOS 빌드 결과가 없습니다: $APP_SRC"

# ── 6) assemble + sign (ad-hoc: required for Apple Silicon, no developer ID needed) ─
say "앱 번들 합치기"
STAGE="$BUILD/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_SRC" "$STAGE/zaevis.app"
cp -R "$PAYLOAD" "$STAGE/zaevis.app/Contents/Resources/zaevis"
codesign --force --deep --sign - "$STAGE/zaevis.app"
codesign --verify --deep "$STAGE/zaevis.app"

ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/처음 열 때 읽어주세요.txt" <<'TXT'
zaevis 설치

1. zaevis.app 을 Applications 폴더로 끌어다 놓으세요.
2. Applications 에서 zaevis 를 여세요.
   "확인되지 않은 개발자" 경고가 뜨면:
   - 시스템 설정 → 개인정보 보호 및 보안 → 아래쪽 "그래도 열기"를 누르거나
   - 터미널에서 한 번: xattr -dr com.apple.quarantine /Applications/zaevis.app
3. 첫 화면의 설정 마법사를 따라가면 끝입니다. 다른 설치는 필요 없습니다.
TXT

DMG="$DIST/zaevis-$VERSION-$ARCH.dmg"
rm -f "$DMG"
hdiutil create -volname "zaevis $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
say "완료: $DMG ($(du -h "$DMG" | cut -f1))"
