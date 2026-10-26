#!/usr/bin/env bash
# zaevis setup — creates your personal worklog folder and wires Claude + AutoRAG to it.
# Safe to re-run: existing files are never overwritten.
#
#   kit/setup.sh [--worklog DIR] [--repos DIR] [--email ADDR] [--daily-at HH:MM] [--disable SOURCE]...
#                [--claude-md] [--no-autorag] [--skip-refresh] [--no-schedule] [--yes]
#
# The zaevis app runs this from its first-run wizard with --yes and explicit values.
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$KIT_DIR/.." && pwd)"
STATE_DIR="${ZAEVIS_HOME:-$HOME/.zaevis}"

WORKLOG_DIR=""
REPOS_ROOT=""
AUTHOR_EMAIL=""
WITH_AUTORAG=1
ASSUME_YES=0
SKIP_REFRESH=0
WITH_SCHEDULE=1
WITH_CLAUDE_MD=0
DAILY_AT="18:30"
DISABLED=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worklog) WORKLOG_DIR="$2"; shift 2 ;;
    --repos) REPOS_ROOT="$2"; shift 2 ;;
    --email) AUTHOR_EMAIL="$2"; shift 2 ;;
    --no-autorag) WITH_AUTORAG=0; shift ;;
    --skip-refresh) SKIP_REFRESH=1; shift ;;
    --no-schedule) WITH_SCHEDULE=0; shift ;;
    --claude-md) WITH_CLAUDE_MD=1; shift ;;
    --daily-at) DAILY_AT="$2"; shift 2 ;;
    --disable) DISABLED+=("$2"); shift 2 ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

ask() { # ask VAR "prompt" default
  local __var=$1 __prompt=$2 __default=$3 __reply
  if [[ -n "${!__var}" ]]; then return; fi
  if [[ $ASSUME_YES -eq 1 ]]; then printf -v "$__var" '%s' "$__default"; return; fi
  read -r -p "$__prompt [$__default]: " __reply
  printf -v "$__var" '%s' "${__reply:-$__default}"
}

expand() { local p="$1"; [[ "$p" == "~/"* ]] && p="$HOME/${p:2}"; printf '%s' "$p"; }

ask WORKLOG_DIR "worklog 폴더 위치" "$HOME/worklog"
ask REPOS_ROOT "코드 저장소들이 있는 상위 폴더" "$HOME"
ask AUTHOR_EMAIL "git 작성자 이메일" "$(git config --global user.email 2>/dev/null || echo you@example.com)"
WORKLOG_DIR="$(expand "$WORKLOG_DIR")"
REPOS_ROOT="$(expand "$REPOS_ROOT")"

render() { # render SRC DEST — replaces {{PLACEHOLDERS}}; skips existing DEST
  local src=$1 dest=$2
  if [[ -e "$dest" ]]; then echo "  = $dest (있음, 건너뜀)"; return; fi
  mkdir -p "$(dirname "$dest")"
  WL="$WORKLOG_DIR" RR="$REPOS_ROOT" AE="$AUTHOR_EMAIL" perl -pe \
    's/\{\{WORKLOG_DIR\}\}/$ENV{WL}/g; s/\{\{REPOS_ROOT\}\}/$ENV{RR}/g; s/\{\{AUTHOR_EMAIL\}\}/$ENV{AE}/g' \
    "$src" > "$dest"
  echo "  + $dest"
}

echo "1) worklog 폴더: $WORKLOG_DIR"
mkdir -p "$WORKLOG_DIR"/{inbox/transcripts,inbox/claude-sessions,inbox/audio,processed/transcripts,processed/claude-sessions,processed/audio,log,projects,summaries,sources}
render "$KIT_DIR/templates/worklog/README.md" "$WORKLOG_DIR/README.md"
render "$KIT_DIR/templates/worklog/projects/_template.md" "$WORKLOG_DIR/projects/_template.md"
MONTH="$(date +%Y-%m)"
[[ -e "$WORKLOG_DIR/log/$MONTH.md" ]] || { printf '# %s 로그\n\n' "$MONTH" > "$WORKLOG_DIR/log/$MONTH.md"; echo "  + log/$MONTH.md"; }
[[ -e "$WORKLOG_DIR/.state.md" ]] || printf 'last_weekly: %s\n' "$(date -v-7d +%F 2>/dev/null || date -d '7 days ago' +%F)" > "$WORKLOG_DIR/.state.md"

if [[ $WITH_CLAUDE_MD -eq 1 ]]; then
  echo "2) Claude 세션 노트 지침: $REPOS_ROOT/CLAUDE.md"
  if [[ -e "$REPOS_ROOT/CLAUDE.md" ]] && ! grep -q "zaevis" "$REPOS_ROOT/CLAUDE.md"; then
    echo "  ! 기존 CLAUDE.md가 있어 덮어쓰지 않습니다. 아래 파일 내용을 직접 붙여 넣으세요:"
    render "$KIT_DIR/claude/CLAUDE.md" "$STATE_DIR/CLAUDE.snippet.md"
  else
    render "$KIT_DIR/claude/CLAUDE.md" "$REPOS_ROOT/CLAUDE.md"
  fi
else
  echo "2) Claude Code 작업은 claude-code 데이터소스가 세션 기록에서 직접 모읍니다 (CLAUDE.md 불필요)"
fi

# Never let the personal log leak into a repository that happens to contain it.
for dir in "$WORKLOG_DIR" "$REPOS_ROOT"; do
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$top" && -d "$top/.git" ]]; then
    ex="$top/.git/info/exclude"
    for p in "$WORKLOG_DIR" "$REPOS_ROOT/CLAUDE.md"; do
      case "$p" in "$top"/*) rel="${p#"$top"/}"
        grep -qxF "/$rel" "$ex" 2>/dev/null || { echo "/$rel" >> "$ex"; echo "  + $ex 에 /$rel 추가 (커밋 방지)"; } ;;
      esac
    done
  fi
done

echo "3) 예약 작업 프롬프트: $STATE_DIR/weekly-task-prompt.md"
render "$KIT_DIR/claude/weekly-task-prompt.md" "$STATE_DIR/weekly-task-prompt.md"

AUTORAG_CONFIG="$STATE_DIR/autorag/config.json"
mkdir -p "$STATE_DIR"
if [[ -e "$STATE_DIR/config.json" ]]; then
  echo "  = $STATE_DIR/config.json (있음, 건너뜀 — 바꾸려면 앱 설정 화면이나 파일을 직접 수정)"
else
  cat > "$STATE_DIR/config.json" <<JSON
{
  "worklogDir": "$WORKLOG_DIR",
  "reposRoot": "$REPOS_ROOT",
  "authorEmail": "$AUTHOR_EMAIL",
  "autoragConfig": "$AUTORAG_CONFIG",
  "port": 4710,
  "dailyAt": "$DAILY_AT",
  "indexOnInject": false
}
JSON
  echo "  + $STATE_DIR/config.json"
fi
if [[ ! -e "$STATE_DIR/sources.json" ]]; then
  {
    printf '{\n'
    for src in ${DISABLED[@]+"${DISABLED[@]}"}; do printf '  "%s": { "enabled": false },\n' "$src"; done
    printf '  "custom": []\n}\n'
  } > "$STATE_DIR/sources.json"
  echo "  + $STATE_DIR/sources.json"
fi

if [[ $WITH_AUTORAG -eq 1 ]]; then
  echo "4) AutoRAG Lite (검색 색인, 모델·API 키 불필요)"
  node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  if [[ "$node_major" -lt 24 ]]; then
    echo "  ! Node.js 24 이상이 필요합니다 (현재: ${node_major}). 설치 후 다시 실행하세요: brew install node@24"
    exit 1
  fi
  if ! command -v minsync >/dev/null; then
    if ! command -v cargo >/dev/null || ! command -v protoc >/dev/null || ! command -v cmake >/dev/null; then
      echo "  ! 임베딩 엔진 MinSync를 빌드하려면 Rust(cargo), protoc, cmake가 필요합니다:"
      echo "      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
      echo "      brew install protobuf cmake"
      echo "    설치 후 다시 실행하세요. (검색 없이 쓰려면 --no-autorag)"
      exit 1
    fi
  fi
  [[ -d "$ROOT_DIR/server/node_modules" ]] || (cd "$ROOT_DIR/server" && npm install --no-fund --no-audit)
  if [[ ! -e "$AUTORAG_CONFIG" ]]; then
    mkdir -p "$(dirname "$AUTORAG_CONFIG")"
    AUTORAG_CONFIG="$AUTORAG_CONFIG" "$ROOT_DIR/server/node_modules/.bin/autorag" lite init \
      --search-paths "$WORKLOG_DIR" --languages ko,en
  fi
  if ! command -v minsync >/dev/null; then
    echo "  MinSync 빌드 중 (처음 한 번, 수 분 걸림)…"
    cargo install minsync --locked
  fi
  if [[ $SKIP_REFRESH -eq 0 ]]; then
    echo "  색인 생성 중…"
    AUTORAG_CONFIG="$AUTORAG_CONFIG" "$ROOT_DIR/server/node_modules/.bin/autorag" lite refresh
  fi
fi

# The app's wizard passes --skip-refresh and runs the first collect itself right after this script.
# The LaunchAgent below starts `daily --if-stale` as soon as it is loaded; mark today as done so it
# does not run a second collect + index at the same time (MinSync holds a lock).
if [[ $SKIP_REFRESH -eq 1 && ! -e "$STATE_DIR/state.json" ]]; then
  printf '{\n  "sources": {},\n  "daily": { "lastRun": "%s", "ok": true, "index": "첫 수집은 앱이 진행" }\n}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE_DIR/state.json"
fi

if [[ $WITH_SCHEDULE -eq 1 && "$(uname -s)" == "Darwin" ]] && command -v node >/dev/null && [[ "$(node -p 'process.versions.node.split(".")[0]')" -ge 24 ]]; then
  echo "5) 매일 수집·색인 예약 (launchd)"
  [[ -d "$ROOT_DIR/server/node_modules" ]] || (cd "$ROOT_DIR/server" && npm install --no-fund --no-audit --silent)
  ZAEVIS_HOME="$STATE_DIR" node "$ROOT_DIR/server/src/cli.ts" schedule install "$DAILY_AT" || echo "  ! 예약 등록 실패 — 나중에 'zaevis schedule install'"
fi

cat <<DONE

완료.
- 명령 등록:   $ROOT_DIR/bin/zaevis install   (이미 했다면 생략)
- 터미널:      zaevis run cli
- 브라우저:    zaevis run web
- 데스크톱 앱: zaevis run app
- 지금 수집:   zaevis collect          (매일 자동: zaevis schedule)
- 녹음 전사:   zaevis ext install whisperx
- 주간 정리 예약: Claude에서 "$STATE_DIR/weekly-task-prompt.md" 내용으로 매주 월요일 예약 작업을 만드세요.
DONE
