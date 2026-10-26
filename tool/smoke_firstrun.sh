#!/usr/bin/env bash
# Replays the app's first-run wizard (setup → server → first collect → index → search) headlessly
# against a packaged bundle, inside throw-away HOME and ZAEVIS_HOME folders. Nothing under the real
# ~ or ~/.zaevis is touched; the LaunchAgent it registers is removed again at the end.
#
#   tool/smoke_firstrun.sh [zaevis.app]        default: build/package/dmg/zaevis.app
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/build/package/dmg/zaevis.app}"
P="$APP/Contents/Resources/zaevis"
[[ -x "$P/node/bin/node" ]] || { echo "번들이 아닙니다: $APP" >&2; exit 1; }

FAKE_HOME="$(mktemp -d /tmp/zv-smoke-home.XXXX)"
STATE="$(mktemp -d /tmp/zv-smoke-state.XXXX)"
PORT=4711   # not 4710, so a real server keeps running
EMAIL="$(git config --global user.email 2>/dev/null || echo you@example.com)"

zv() { env -i HOME="$FAKE_HOME" USER="$USER" ZAEVIS_HOME="$STATE" ZAEVIS_PORT=$PORT NO_COLOR=1 LANG=ko_KR.UTF-8 \
  PATH="$P/node/bin:$P/bin:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$P/bin/zaevis" "$@"; }
api() { curl -sf -H 'x-zaevis: 1' "$@" "http://127.0.0.1:$PORT/api${API_PATH}"; }
cleanup() {
  zv stop >/dev/null 2>&1 || true
  zv schedule remove >/dev/null 2>&1 || true
  echo "남긴 폴더: $FAKE_HOME · $STATE  (지워도 됩니다)"
}
trap cleanup EXIT

# a small fake home: this checkout as the only repository, Claude sessions read-only
printf '[user]\n\temail = %s\n' "$EMAIL" > "$FAKE_HOME/.gitconfig"
git clone -q "$ROOT" "$FAKE_HOME/zaevis"
[[ -d "$HOME/.claude" ]] && ln -s "$HOME/.claude" "$FAKE_HOME/.claude"
[[ -f "$HOME/.zsh_history" ]] && cp "$HOME/.zsh_history" "$FAKE_HOME/.zsh_history"

echo "1) setup (마법사가 보내는 인자 그대로)"
(cd "$FAKE_HOME" && zv setup --yes --skip-refresh --worklog "$FAKE_HOME/worklog" --repos "$FAKE_HOME" --email "$EMAIL" --daily-at 18:30 | grep -E '^[0-9]\)|●')
grep -q '"index": "첫 수집은 앱이 진행"' "$STATE/state.json" || { echo "✗ state.json 선표시 없음"; exit 1; }
sleep 3
grep -q '건너뜀' "$STATE/daily.log" 2>/dev/null || { echo "✗ launchd 즉시 실행이 건너뛰지 않았습니다"; cat "$STATE/daily.log" 2>/dev/null; exit 1; }
echo "   ✓ launchd 즉시 실행 건너뜀"

echo "2) 서버 시작"; zv start | tail -1

echo "3) 첫 수집"
API_PATH=/collect api -X POST -H 'content-type: application/json' -d '{}' >/dev/null
for _ in $(seq 1 150); do API_PATH=/collect api | grep -q '"collecting":false' && break; sleep 2; done
API_PATH=/collect api | grep -q '"lastCollect":{' || { echo "✗ 수집이 끝나지 않았습니다"; exit 1; }
API_PATH=/collect api | python3 -c 'import json,sys
for r in json.load(sys.stdin)["lastCollect"]["report"]: print("  ", "✓" if r["ok"] else "✗", r["name"], r.get("note") or r.get("error"))'

echo "4) 색인"
for _ in $(seq 1 300); do x="$(API_PATH=/index api)"; grep -q '"refreshing":false' <<<"$x" && grep -q '"lastRefresh":{' <<<"$x" && break; sleep 2; done
python3 -c 'import json,sys
d=json.load(sys.stdin); a=d["autorag"]
print("   lastRefresh ok:", d["lastRefresh"]["ok"], "| state:", a.get("state"), a.get("counts"))
bad=[g for g in a.get("diagnostics",[]) if g["severity"]=="error"]
for g in bad: print("   ✗", g["code"], g["message"])
sys.exit(1 if bad or not d["lastRefresh"]["ok"] else 0)' <<<"$x"
sleep 1; grep -q '"index": "완료"' "$STATE/state.json" || { echo "✗ state.daily 미기록"; exit 1; }
echo "   ✓ state.daily 기록"

echo "5) 검색"
API_PATH="/search?q=zaevis&topK=3" api | python3 -c 'import json,sys
h=json.load(sys.stdin)["hits"]; [print("  ", x["path"]) for x in h]; sys.exit(0 if h else 1)'
echo "✓ 첫 실행 흐름 통과"
