# zaevis

어디서 무슨 작업을 하든 기록을 모아 **개인 작업 기록과 지식 베이스**를 만드는 키트입니다.

- **수집 (매일, 자동)**: git 커밋, Claude Code 세션, 셸 명령, 회의 전사본, 직접 만든 커넥터를 `worklog/sources/`에 모읍니다. 매일 18:30(launchd)에 돌고, 언제든 수동으로도 돌릴 수 있습니다.
- **주입 (실시간)**: 한 줄 기록, 전사본 붙여넣기, 앱 안에서 바로 녹음하거나 녹음 파일 업로드(whisperX 자동 전사)는 넣는 즉시 worklog에 저장됩니다. 로그 탭에서 줄마다 ⋯ 메뉴로 고치거나 지울 수 있습니다(정리가 쓴 줄은 출처 표시가 남습니다).
- **색인·검색**: [AutoRAG](https://github.com/Marker-Inc-Korea/AutoRAG) Lite(로컬, 무료). 키워드(BM25)에 더해 **의미 검색**: 앱이 번들된 MinSync로 Qwen3-Embedding-0.6B 모델을 이 맥에서 돌려(`minsync serve`) 뜻이 비슷한 기록도 찾습니다. 외부 서비스·키 없음, 설정에서 끌 수 있음. 처음 켤 때 모델(1.1GB)을 내려받습니다. 색인은 매일 수집 직후 + 수동 + (선택) 주입 즉시.
- **정리 (지식화, 매주 월요일 자동)**: 수집 원본과 inbox(전사본·세션 노트)를 읽어 로그 줄·프로젝트 상태·월간 요약을 씁니다. 이 맥에 **이미 있는 것**으로 돌립니다: 설치된 에이전트 CLI(Claude Code · Codex · Gemini, 본인 구독)가 있으면 그것으로, 없으면 저장된 OpenRouter 키로. 설정 → 정리에서 어떤 것이 감지됐는지 보고 고르거나 "지금 정리하기"로 바로 돌립니다. 새 계정은 필요 없습니다.
- **front**: Flutter 앱(데스크톱 + 브라우저)과 `zaevis` CLI에서 검색·열람·주입·데이터소스 설정을 모두 합니다. 추가 유료 서비스는 쓰지 않습니다.
- **단축키**: ⌘K 검색 · ⌘N 한 줄 기록 · ⌘⇧R 녹음 · ⌘1~5 탭 · ⌘, 설정. 데스크톱에서는 어느 앱을 쓰고 있든 **⌘⇧Space**로 zaevis 창을 띄워 바로 한 줄 기록을 남깁니다(macOS 메뉴에도 같은 항목이 있습니다).
- **외부 연결**: 기본값은 없음. 유일한 선택 항목이 설정의 **검색 결과 재정렬(OpenRouter)**이며, 켜고 키를 저장해야만 검색어와 상위 25개 문단이 OpenRouter로 갑니다. 키는 `~/.zaevis/secrets.json`(소유자만 읽기)에만 두고 앱에는 끝 4자리만 보여 줍니다.

```
 데이터소스 (매일 18:30 + 수동)          실시간 주입 (앱 · CLI)
 git · Claude Code · 셸 · 전사본 폴더     한 줄 기록 · 전사본 · 앱 내 녹음·업로드(whisperX)
 · 사용자 커넥터(명령어)                          │
            │ zaevis collect                        │
            ▼                                       ▼
 worklog/sources/<이름>/날짜.md          worklog/log · inbox/
            └───────────────┬───────────────────────┘
                            ▼
              AutoRAG Lite 색인 (매일 · 수동 · 선택: 주입 즉시)
                            ▼
        server (127.0.0.1:4710) ── Flutter 앱 · 웹 · zaevis CLI
                            ▲
        Claude 주간 정리 → log/ · projects/ · summaries/
```

- **내 데이터는 이 저장소에 들어오지 않습니다.** `worklog/` 폴더는 `setup.sh`가 원하는 위치에 만들고, 저장소 안에 두더라도 `.gitignore`로 막혀 있습니다.
- AutoRAG는 포크하지 않고 npm 의존성(`@autorag/librarian`, Apache-2.0)으로 씁니다. AutoRAG 데스크톱 앱(FSL 라이선스)은 쓰지 않고, 이 저장소의 Flutter 앱이 그 역할을 대신합니다.

## 구성

| 경로 | 내용 |
|---|---|
| `bin/zaevis` | CLI. `zaevis run cli` · `run web` · `run app`, `zaevis search`, `zaevis ask`, `zaevis setup` 등 |
| `kit/setup.sh` | worklog 폴더 생성, Claude 지침·예약 작업 프롬프트 생성, AutoRAG 색인 초기화 |
| `kit/templates/worklog/` | worklog 규칙(README)과 프로젝트 템플릿 |
| `kit/claude/` | 세션 노트 지침(`CLAUDE.md`), 주간·월간 정리 예약 작업 프롬프트 |
| `server/` | 로컬 API 서버 (Node 24, TypeScript). worklog 파일 + AutoRAG MCP를 HTTP로 제공하고, 웹 앱도 서빙 |
| `app/` | Flutter 앱. 검색 · 로그 · 프로젝트 · 월간 정리 · 색인 상태 |

## 설치 (macOS)

1. `zaevis-<버전>-arm64.dmg`를 열고 **zaevis**를 Applications로 끌어다 놓습니다.
2. Applications에서 zaevis를 엽니다. 서명되지 않은 앱이라 처음 한 번은 경고가 뜹니다:
   **시스템 설정 → 개인정보 보호 및 보안 → "그래도 열기"** (또는 터미널에서 `xattr -dr com.apple.quarantine /Applications/zaevis.app`).
3. 첫 화면 마법사에서 기록 폴더, 코드 폴더, 데이터소스, 매일 수집 시각을 고르고 **시작**을 누르면 끝입니다.

Node, Python, Homebrew 같은 것은 설치할 필요가 없습니다. 서버·검색 엔진은 앱 안에 들어 있고, 녹음 전사(whisperX)는 앱 설정에서 버튼 한 번으로 설치합니다.
터미널 명령이 필요하면 앱 설정 → **터미널에서 zaevis 명령 쓰기**를 누르세요.

### 플랫폼

| | 설치 | 비고 |
|---|---|---|
| macOS (Apple Silicon·Intel) | `dist/zaevis-<버전>-arm64.dmg` / `-x86_64.dmg` | 매일 수집은 launchd, 전역 단축키 ⌘⇧Space, 메뉴 막대 |
| Windows 10/11 (x64) | `dist/zaevis-<버전>-win-x64.zip` — 풀어서 `zaevis.exe` 실행 | 매일 수집은 작업 스케줄러, 전역 단축키 Ctrl+Shift+Space. SmartScreen 경고는 "추가 정보 → 실행" |
| 브라우저 (web) | 설치한 앱의 설정 → "브라우저로 열기" 또는 `zaevis run web` | 같은 서버(`127.0.0.1:4710`)가 웹 앱을 함께 서빙. 녹음·검색·설정 모두 동작, 전역 단축키만 없음 |
| Linux | 소스에서 `zaevis run app` | 패키지는 아직 없음. 매일 수집은 `zaevis schedule`이 알려 주는 crontab 한 줄 |

세 플랫폼 모두 같은 서버·CLI(`server/src/zaevis.ts`)를 쓰고, 앱은 번들된 Node로 그 파일을 실행합니다. 셸 스크립트는 없습니다.

### DMG 만들기 (배포하는 사람만)

```bash
brew install --cask flutter && brew install protobuf cmake
curl https://sh.rustup.rs -sSf | sh          # MinSync(검색 임베딩 엔진) 빌드용, 처음 한 번
tool/package_macos.sh                         # → dist/zaevis-<버전>-arm64.dmg
```

Windows에서는 Flutter(Visual Studio C++ 워크로드 포함)·Rust·protobuf·cmake를 설치한 뒤:

```powershell
powershell -ExecutionPolicy Bypass -File tool\package_windows.ps1   # → dist\zaevis-<버전>-win-x64.zip
```

GitHub Actions(`ci.yml`)가 세 OS에서 서버 테스트와 macOS·Windows 앱 빌드를 돌리고, 태그를 올리거나 수동 실행하면 두 설치본을 아티팩트로 만듭니다.

Node 24 공식 배포본(체크섬 확인), 서버 의존성, MinSync, 웹·macOS 빌드를 앱 하나로 묶고 ad-hoc 서명까지 합니다. 빌드한 맥과 같은 CPU(Apple Silicon / Intel)용 DMG가 나옵니다.

### 개발용으로 소스에서 바로 쓰기

```bash
brew install node@24 flutter protobuf cmake
curl https://sh.rustup.rs -sSf | sh
git clone https://github.com/zae-park/zaevis.git && cd zaevis
bin/zaevis install && zaevis setup && zaevis doctor
```

## 사용

앱의 탭: **검색 · 로그 · 프로젝트 · 월간 정리 · 수집**. 터미널에서는:

```bash
zaevis run cli          # 터미널: 입력하면 검색, :log  :projects  :summary  :index
zaevis run web          # 브라우저: 웹 앱이 없거나 바뀌었으면 빌드 후 열기 (--rebuild로 강제)
zaevis run app          # 데스크톱 앱: flutter 개발 모드 (핫 리로드)
zaevis run app --release   # 릴리스 빌드 후 앱 실행
```

API 서버(`127.0.0.1:4710`)는 필요할 때 백그라운드로 자동 실행됩니다. 직접 관리하려면 `zaevis start | stop | status | logs`, 이 터미널에서 띄우려면 `zaevis run server`.

바로 쓰는 명령 (전체 목록은 `zaevis help`):

```bash
zaevis search GA4 캠페인 매핑
zaevis ask "GA4 매핑은 왜 미뤘지?"   # 검색 상위 문단을 근거로 답 + 출처 [n] (아래 "질문" 참고)
zaevis log                # 이번 달 로그 (zaevis log 2026-09)
zaevis projects
zaevis summary            # 최근 월간 정리
zaevis index --refresh    # 검색 색인 갱신 (처음 한 번은 꼭)

zaevis add "#decision [[roas]] 매핑 테이블을 수동으로 채우기로"   # 한 줄 기록
zaevis ingest 회의.txt 녹음.m4a      # 전사본은 inbox로, 녹음은 whisperX로 바로 전사
zaevis collect                      # 지금 수집 + 색인 (zaevis collect git: 하나만)
zaevis sources                      # 데이터소스 상태 (zaevis sources off shell-history)
zaevis schedule install 18:30       # 매일 실행 시각 바꾸기
zaevis ext install whisperx         # 녹음 전사 확장 (Python·ffmpeg까지 자동 설치)
```

## 데이터소스

| 이름 | 수집 내용 | 설정 |
|---|---|---|
| `git` | 저장소 상위 폴더 아래 모든 저장소의 모든 커밋, 줄마다 작성자 표시 | 폴더, 탐색 깊이 |
| `agent-sessions` | 에이전트 세션: Claude Code(`~/.claude/projects`) · Codex CLI(`~/.codex/sessions`) · Gemini CLI(`~/.gemini/tmp`)의 로컬 기록과 ChatGPT 데이터 내보내기. 세션마다 요청→응답 쌍, 수정한 파일, 실행한 명령 | 도구별 켜기/끄기, ChatGPT 내보내기 폴더 |
| `shell-history` | 터미널에서 친 명령(zsh 이력)을 시간순으로 — 어느 저장소에서 무엇을 빌드·배포했는지의 흔적. `setopt EXTENDED_HISTORY`가 켜져 있어야 시각이 남음 | 히스토리 파일 |
| `transcripts` | 전사 서비스 내보내기 폴더에서 가져오기 + `inbox/audio` 녹음을 whisperX로 전사 | 가져올 폴더, 언어, 모델 |
| 사용자 커넥터 | Markdown을 출력하는 아무 명령. `{from}` `{to}`는 ISO 시각, `{fromDate}` `{toDate}`는 YYYY-MM-DD로 치환. 앱의 "커넥터 추가"에 폴더의 노트·macOS 캘린더 프리셋이 있고, 추가하면 바로 한 번 수집해 결과를 보여 줌 | 명령 |

모든 원본은 기록 전에 토큰·비밀번호·API 키를 가립니다. 설정은 앱의 **수집** 화면이나 `~/.zaevis/sources.json`에서 바꿉니다.
Claude Cowork·claude.ai 대화는 로컬 기록이 없어 자동 수집되지 않습니다. 필요하면 내보낸 대화를 전사본처럼 넣거나 사용자 커넥터를 만드세요.

### 외부 소스 (AutoRAG 데이터소스)

위 데이터소스는 worklog 폴더에 Markdown으로 쌓이는 것들입니다. 그와 별도로 AutoRAG가 **직접 색인하는 외부 소스**를 붙일 수 있습니다. worklog에는 들어가지 않고, 검색할 때 AutoRAG가 worklog 히트와 함께 섞어 돌려줍니다(결과 카드의 출처가 "Obsidian 볼트"·"Slack"처럼 표시되고, 출처 칩으로 거를 수 있음). 앱 **수집** 화면 맨 아래 "외부 소스 (AutoRAG)"에서 연결합니다.

| 소스 | 필요한 것 | 연결할 때 적는 것 |
|---|---|---|
| Obsidian 볼트 | 없음 (AutoRAG가 노트를 직접 색인, 키워드+의미 검색) | 볼트 폴더 |
| 메일 내보내기 (.mbox/.eml) | 없음 | 파일·폴더 |
| RSS · 뉴스 | 없음 | 피드 주소 |
| macOS Spotlight | 없음 (macOS만) | Spotlight 질의, 폴더 |
| GitHub 이슈·PR / Gist | 환경 변수 `GITHUB_TOKEN` (값은 저장하지 않고 변수 **이름**만) | 저장소 `owner/repo`, 토큰 변수 이름 |
| Slack · Notion · Discord · 카카오톡 · WhatsApp · Telegram | 각 CLI(`slacrawl` `notcrawl` `discrawl` `lazykatok` `wacrawl` `telecrawl`)를 설치하고 거기서 로그인·수집을 한 번 해 둔 아카이브 | Slack은 워크스페이스 ID, 나머지는 아카이브 위치(비우면 기본값) |
| 메일 (mailcrawl) | `mailcrawl` CLI와 그 안의 계정 | 계정 이름, 메일함 |
| 클라우드 드라이브 | `rclone`과 `rclone config`로 만든 리모트 | 리모트 이름 |
| 사진·스크린샷 / 브라우저 기록 | `clawgallery` / `hister` | 폴더 / 주소 |

절차: 카드를 펼치면 **미설치**(설치 명령 복사 버튼) → **연결 안 됨**(필요한 칸만 있는 폼, "연결") → **연결됨**(켜기/끄기 스위치, 저장, 지금 동기화, 연결 삭제) 순으로 바뀝니다. 연결하거나 저장하면 서버가 AutoRAG의 `datasources` 설정을 고쳐 쓰고 검색 자식을 재시작한 뒤 외부 소스만 동기화합니다(`autorag.refresh`의 `datasources` 단계). 매일 수집 뒤 색인에서도 같이 동기화됩니다. 동기화는 연결 전체를 한 번에 돕니다(AutoRAG에 연결별 갱신이 없음). 토큰·비밀번호 값은 어디에도 저장되지 않으며, `token` 같은 이름의 값을 넣으면 서버가 거절합니다. 카드의 "밖으로 나가는 것"이 각 소스가 어디에 접속하는지 알려 줍니다(Obsidian·메일 내보내기·Spotlight는 없음).

### 질문 (기록을 근거로 답하기)

검색 탭 위의 **검색 / 질문** 전환을 질문으로 두고 물어보면, 같은 검색으로 고른 상위 문단(기본 10개)만 근거로 한국어 답을 써 줍니다.
질문과 답은 대화로 쌓입니다. "그건 왜?"처럼 짧게 이어 물으면 앞 대화를 기억하고(앞 질문과 함께 검색), 대화는 `~/.zaevis/ask/`에 남아 오른쪽 위 시계 아이콘으로 다시 열거나 지울 수 있습니다.
답의 각 문장 끝에 [번호]가 붙습니다. 번호나 답 아래 근거 칩에 마우스를 올리면 출처와 발췌 앞부분이 툴팁으로 보이고, 누르면 오른쪽 패널(좁은 창은 아래 시트)에 전체 발췌·경로·이전/다음 근거·원문 열기가 나옵니다.
근거가 없으면 "기록에서 근거를 찾지 못했습니다"라고 답합니다.
답을 쓰는 것은 주간 정리와 같은 에이전트입니다: 이 컴퓨터에 설치된 **Claude Code · Codex · Gemini CLI**(내 구독으로, 파일을 읽기만 하는 모드) 또는 저장된 **OpenRouter 키**.
설정 → 정리 (지식화)의 에이전트·모델 선택을 그대로 따르고, 쓸 수 있는 것이 없으면 설정으로 안내합니다. 터미널에서는 `zaevis ask "질문"`.

### 정리 결과 검토

설정 → 정리 (지식화)의 **적용 전에 검토**(기본 켬)를 켜 두면 에이전트가 쓴 로그 줄·프로젝트 페이지·월간 정리를 바로 worklog에 넣지 않고
제안으로 보관합니다. 로그 탭 위의 배너나 설정의 "검토 대기"에서 **검토하기**를 누르면 줄마다 체크해서 남길 것만 **적용**하거나 전부 **버리기**할 수 있습니다.
에이전트가 지우려던 기존 줄은 적용해도 지워지지 않습니다. 끄면 예전처럼 바로 씁니다.

### 알림 · 전역 단축키 · 검색 필터

- **알림**: 정리 제안이 준비됐을 때, 수집이 실패했을 때, 녹음 전사가 끝났을 때 시스템 알림(macOS 알림 센터·Windows 토스트)이 옵니다. 서버가 보내므로 앱 창이 닫혀 있어도 옵니다. 설정 → 알림에서 끕니다.
- **전역 단축키**: 기본 ⌘⇧Space(Windows: Ctrl+Shift+Space). 설정 → 단축키 → 바꾸기에서 원하는 조합을 눌러 바꿉니다. 수정키 없는 단일 키는 받지 않습니다.
- **검색 필터**: 결과 위의 칩으로 출처(git 커밋·에이전트 세션·한 줄 기록·전사본 …)와 기간(7일·30일·이번 달)을 거릅니다. 한 번에 40건을 받아 와 앱 안에서 거릅니다.
- **색인 진행**: 색인 창에서 "본문 읽는 중 12/40 파일 → 임베딩·색인 → 마무리"를 진행 막대로 보여 줍니다.

### 주간·월간 정리 예약

`~/.zaevis/weekly-task-prompt.md`에 내 경로로 채워진 프롬프트가 생깁니다.
Claude 앱에서 이 내용으로 **매주 월요일 오전** 예약 작업을 만들고, 내 컴퓨터에서 실행되도록 설정하세요.
월간 요약은 매월 첫 월요일에 같은 작업이 이어서 씁니다.

## 매일 쓰는 법

- 회의 전사본 → `worklog/inbox/transcripts/YYYY-MM-DD_제목.txt`
- 코드 작업 → Claude가 `CLAUDE.md` 지침대로 `inbox/claude-sessions/`에 노트를 남김
- 그 밖의 일 → `worklog/log/YYYY-MM.md`에 한 줄: `- 10-21 [[프로젝트]] #decision 무엇을, 왜`

형식 규칙은 `kit/templates/worklog/README.md`(설치 후에는 내 worklog 폴더의 `README.md`)에 있습니다.

## 커스터마이징

[docs/customizing.md](docs/customizing.md)를 보세요. 태그 추가, 로그 형식 변경, 서버 API, 앱 화면 추가 방법을 정리해 두었습니다.

## 개발

```bash
cd server && npm install && npm test
cd app && flutter test && flutter analyze
```

GitHub Actions는 push마다 서버 테스트와 Flutter analyze·test만 돌립니다. 앱 빌드(웹·데스크톱)는 로컬에서 합니다.

## 라이선스

MIT. 의존하는 AutoRAG 엔진은 Apache-2.0입니다.
