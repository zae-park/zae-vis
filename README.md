# zaevis

어디서 무슨 작업을 하든 기록을 모아 **개인 작업 기록과 지식 베이스**를 만드는 키트입니다.

## 화면

검색 · 메모리 · 리포트 · 연결. 넓은 창은 왼쪽 사이드바입니다.

<img src="docs/images/search.png" alt="검색: 색인으로 찾은 기록" width="880">

<img src="docs/images/memory.png" alt="메모리: 한 줄 기록과 프로젝트 상태" width="880">

<img src="docs/images/reports.png" alt="리포트: 하루 기록으로 만든 일간 리포트" width="880">

<img src="docs/images/collect.png" alt="연결: 바로 넣기와 데이터소스" width="880">

- **수집 (매일, 자동)**: git 커밋, 에이전트 세션(Claude Code · Codex · Gemini CLI · ChatGPT 내보내기), 셸 명령, 회의 전사본, 직접 만든 커넥터를 `worklog/sources/`에 모읍니다. 매일 18:30(launchd)에 돌고, 언제든 수동으로도 돌릴 수 있습니다. **연결** 탭에서 켜고 끄며, Slack·Notion·Obsidian 같은 **외부 소스**는 AutoRAG가 직접 색인해 검색에 섞습니다.
- **주입 (실시간)**: 한 줄 기록, 전사본 붙여넣기, 앱 안에서 바로 녹음하거나 녹음 파일 업로드(whisperX 자동 전사)는 넣는 즉시 worklog에 저장됩니다. 메모리 탭에서 줄마다 ⋯ 메뉴로 고치거나 지울 수 있습니다(정리가 쓴 줄은 출처 표시가 남습니다).
- **색인·검색**: [AutoRAG](https://github.com/Marker-Inc-Korea/AutoRAG) Lite(로컬, 무료). 키워드(BM25)에 더해 **의미 검색**: 앱이 번들된 MinSync로 Qwen3-Embedding-0.6B 모델을 이 맥에서 돌려(`minsync serve`) 뜻이 비슷한 기록도 찾습니다. 외부 서비스·키 없음, 설정에서 끌 수 있음. 처음 켤 때 모델(1.1GB)을 내려받습니다. 키워드 쪽은 한국어 형태소 분석기 [Kiwi](https://github.com/bab2min/Kiwi)를 설치하면(첫 실행 마법사가 기본으로 설치, 설정 → 검색에서도 버튼 하나, 약 130MB) `인증서를`·`갱신했다` 같은 활용형도 `인증서`·`갱신`으로 찾습니다. 색인은 매일 수집 직후 + 수동 + (선택) 주입 즉시.
- **질문 (RAG)**: 검색 탭의 **질문** 모드에 물으면 검색 상위 문단만 근거로 출처 [번호]가 달린 답을 씁니다. 이어 물으면 앞 대화를 기억합니다.
- **리포트 (일간 · 주간 · 월간)**: **리포트** 탭에서 그 기간의 기록만 근거로 한 일·결정·막힌 것·다음 할 일을 정리합니다. "지금 만들기" 또는 매일 수집 뒤 자동.
- **정리 (지식화, 매주 월요일 자동)**: 수집 원본과 inbox(전사본·세션 노트)를 읽어 로그 줄·프로젝트 상태·월간 요약을 씁니다. 질문·리포트·정리는 모두 이 맥에 **이미 있는 것**으로 돌립니다: 설치된 에이전트 CLI(Claude Code · Codex · Gemini, 본인 구독)가 있으면 그것으로, 없으면 저장된 OpenRouter 키로. 설정 → 정리에서 어떤 것이 감지됐는지(설치·로그인 여부)를 보고 고르거나 "지금 정리하기"로 바로 돌립니다. 로그인이 안 된 CLI는 건너뛰고 "로그인 필요: 터미널에서 claude login"처럼 알려 줍니다. 설정이 자동이면 할당량으로 막힌 CLI는 다음 서비스(마지막은 OpenRouter)로 넘기고, 질문·리포트·설정에 그 순서를 레일로 보여 줍니다. 주간 정리는 파일을 쓰기 시작한 뒤에는 넘기지 않고, 에이전트를 하나 고정하면 그 하나만 씁니다. 새 계정은 필요 없습니다.
- **front**: Flutter 앱(데스크톱 + 브라우저)의 네 탭 **검색(질문) · 메모리 · 리포트 · 연결**과 `zaevis` CLI에서 검색·열람·주입·데이터소스 설정을 모두 합니다. 추가 유료 서비스는 쓰지 않습니다.
- **단축키**: ⌘K 검색 · ⌘N 한 줄 기록 · ⌘⇧R 녹음 · ⌘1~4 탭 · ⌘, 설정. 데스크톱에서는 어느 앱을 쓰고 있든 **⌘⇧Space**로 zaevis 창을 띄워 바로 한 줄 기록을 남깁니다(macOS 메뉴에도 같은 항목이 있습니다).
- **외부 연결**: 기본값은 없음. 유일한 선택 항목이 설정의 **검색 결과 재정렬(OpenRouter)**이며, 켜고 키를 저장해야만 검색어와 상위 25개 문단이 OpenRouter로 갑니다. 키는 `~/.zaevis/secrets.json`(소유자만 읽기)에만 두고 앱에는 끝 4자리만 보여 줍니다.

```
 데이터소스 (매일 18:30 + 수동)          실시간 주입 (앱 · CLI)
 git · 에이전트 세션 · 셸 · 전사본 폴더   한 줄 기록 · 전사본 · 앱 내 녹음·업로드(whisperX)
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
        리포트(일간·주간·월간) → reports/ · summaries/
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
| `app/` | Flutter 앱. 검색·질문 · 메모리(기록·하루·원본·상태) · 리포트 · 연결(데이터소스·외부 소스) · 설정 |

## 설치

앱을 받아서 쓰는 방법과, 저장소를 클론해서 개발하는 방법이 있습니다.

### macOS 앱

1. [Releases](https://github.com/zae-park/zae-vis/releases)에서 `zaevis-<버전>-arm64.dmg`(Apple Silicon) 또는 `-x86_64.dmg`(Intel)를 받습니다. 릴리스가 아직 없으면 아래 **소스에서 실행**으로 띄웁니다.
2. DMG를 열고 **zaevis**를 Applications로 끌어다 놓습니다.
3. Applications에서 zaevis를 엽니다. 서명되지 않은 앱이라 처음 한 번은 경고가 뜹니다:
   **시스템 설정 → 개인정보 보호 및 보안 → "그래도 열기"** (또는 터미널에서 `xattr -dr com.apple.quarantine /Applications/zaevis.app`).
4. 첫 화면 마법사에서 기록 폴더, 코드 폴더, 데이터소스, 매일 수집 시각을 고르고 **시작**을 누르면 끝입니다. 마지막 화면이 다음에 할 세 가지를 알려 줍니다: **연결** 탭에서 소스 확인 → **메모리** 탭에서 한 줄 기록 → **리포트** 켜기.

### Windows 앱

1. 같은 Releases에서 `zaevis-<버전>-win-x64.zip`을 받아 풀고 `zaevis.exe`를 실행합니다.
2. SmartScreen 경고가 뜨면 **추가 정보 → 실행**을 누릅니다.
3. 첫 화면 마법사는 macOS와 같습니다. 매일 수집은 작업 스케줄러에 등록되고, 전역 단축키는 Ctrl+Shift+Space입니다.

Node, Python, Homebrew 같은 것은 설치할 필요가 없습니다. 서버·검색 엔진은 앱 안에 들어 있고, 녹음 전사(whisperX)와 한국어 형태소 분석(Kiwi)은 앱 설정에서 버튼 한 번으로 설치합니다(Kiwi는 첫 실행 마법사가 기본으로 넣습니다).
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

Kiwi(한국어 형태소 분석기, 라이브러리 28MB + 모델 104MB)는 DMG에 넣지 않습니다. 임베딩 모델(1.1GB)처럼 첫 실행 때 내려받는 편이 설치본(약 490MB)을 키우지 않고, 마법사가 기본으로 설치해 주며, 직접 둔 Kiwi가 있는 Mac은 그것을 쓰기 때문입니다. 동봉하려면 `tool/package_macos.sh`가 `ext/kiwi` 레이아웃(`lib/libkiwi.dylib`, `models/cong/base`)을 payload에 넣고 `server/src/kiwi.ts`의 후보 목록에 번들 경로를 더하면 됩니다.

### 소스에서 실행

```bash
brew install node@24 flutter protobuf cmake
curl https://sh.rustup.rs -sSf | sh
git clone https://github.com/zae-park/zaevis.git && cd zaevis
bin/zaevis install && zaevis setup && zaevis doctor
```

## 사용

앱의 탭: **검색 · 메모리 · 리포트 · 연결**. 터미널에서는:

```bash
zaevis run cli          # 터미널: 입력하면 검색, :log  :projects  :summary  :index
zaevis run web          # 브라우저: 웹 앱이 없거나 바뀌었으면 빌드 후 열기 (--rebuild로 강제)
zaevis run app          # 데스크톱 앱: flutter 개발 모드 (핫 리로드)
zaevis run app --release   # 릴리스 빌드 후 앱 실행
```

API 서버(`127.0.0.1:4710`)는 필요할 때 백그라운드로 자동 실행됩니다. 직접 관리하려면 `zaevis start | stop | status | logs`, 이 터미널에서 띄우려면 `zaevis run server`.

바로 쓰는 명령 (전체 목록은 `zaevis help`):

```bash
zaevis search 검색 색인
zaevis ask "색인은 왜 미뤘지?"   # 검색 상위 문단을 근거로 답 + 출처 [n] (아래 "질문" 참고)
zaevis log                # 이번 달 로그 (zaevis log 2026-09)
zaevis projects
zaevis summary            # 최근 월간 정리 (= 월간 리포트)
zaevis report daily       # 일간 리포트 보기 — 없으면 지금 만들어서 보여 줌 (weekly·monthly, 기간 지정 가능)
zaevis index --refresh    # 검색 색인 갱신 (처음 한 번은 꼭)

zaevis add "#decision [[notes]] 색인을 처음부터 다시 만들기로"   # 한 줄 기록
zaevis ingest 회의.txt 녹음.m4a      # 전사본은 inbox로, 녹음은 whisperX로 바로 전사
zaevis collect                      # 지금 수집 + 색인 (zaevis collect git: 하나만)
zaevis sources                      # 데이터소스 상태 (zaevis sources off shell-history)
zaevis schedule install 18:30       # 매일 실행 시각 바꾸기
zaevis ext install whisperx         # 녹음 전사 확장 (Python·ffmpeg까지 자동 설치)
zaevis ext install kiwi             # 한국어 형태소 분석기 — 키워드 검색이 활용형도 찾음 (설치 뒤 zaevis index --force)
```

### 메모리 (이 앱이 아는 것 전부)

메모리 탭은 네 층으로 되어 있습니다.
- **기록**: 날짜순 한 줄 기록. 줄마다 **내 기록**(자물쇠 — 정리 에이전트는 이 줄을 고치지 못하고 검토를 거쳐 제안만 합니다) 또는 **정리**(에이전트가 원본에서 뽑은 줄) 표시가 붙고, 정리가 쓴 줄의 **출처**를 누르면 그 줄이 나온 원본 파일이 열립니다.
- **하루**: 날짜마다 한 카드. 내가 쓴 줄, 그 날 수집된 원본, 정리가 그 원본에서 남긴 줄을 같이 보여 줍니다. 같은 카드에 있으면 한 로그·한 검색으로 관리되고 있다는 뜻이고, 원본에서 줄이 이어진 날은 **이어짐**, 한 줄과 수집이 둘 다 있는 날은 **함께**로 표시합니다.
- **원본**: 매일 수집된 날짜별 파일(git·에이전트 세션·셸·커넥터)과 전사본·세션 노트. 날짜마다 "기록 N줄의 근거"로 그 원본이 몇 줄의 기록을 만들었는지, "아직 정리 안 됨"으로 정리가 아직 읽지 않은 날을 보여 줍니다. 출처 칩으로 거르고, 칩을 누르면 원문이 열립니다.
- **상태**: 정리 에이전트가 프로젝트마다 갱신하는 현재 상태·결정·열린 문제 페이지. 넓은 창에서는 오른쪽 패널에, 좁은 창에서는 네 번째 칸에 있습니다.

위의 안내 띠(ⓘ)가 내가 쓴 것 → 정리가 더한 것 → 검색·질문·리포트가 쓰는 것의 흐름을 층마다 설명합니다.

## 데이터소스

| 이름 | 수집 내용 | 설정 |
|---|---|---|
| `git` | 저장소 상위 폴더 아래 모든 저장소의 모든 커밋, 줄마다 작성자 표시 | 폴더, 탐색 깊이 |
| `agent-sessions` | 에이전트 세션: Claude Code(`~/.claude/projects`) · Codex CLI(`~/.codex/sessions`) · Gemini CLI(`~/.gemini/tmp`)의 로컬 기록과 ChatGPT 데이터 내보내기. 세션마다 요청→응답 쌍, 수정한 파일, 실행한 명령 | 도구별 켜기/끄기, ChatGPT 내보내기 폴더 |
| `shell-history` | 터미널에서 친 명령(zsh 이력)을 시간순으로 — 어느 저장소에서 무엇을 빌드·배포했는지의 흔적. `setopt EXTENDED_HISTORY`가 켜져 있어야 시각이 남음: 카드의 **시각 기록 켜기**가 확인 뒤 `~/.zshrc`(또는 `$ZDOTDIR/.zshrc`) 끝에 `setopt EXTENDED_HISTORY  # zaevis` 한 줄을 붙이고(이미 있으면 그대로), 새 터미널부터 모입니다 | 히스토리 파일 |
| `transcripts` | 전사 서비스 내보내기 폴더에서 가져오기 + `inbox/audio` 녹음을 whisperX로 전사 | 가져올 폴더, 언어, 모델 |
| 사용자 커넥터 | Markdown을 출력하는 아무 명령. `{from}` `{to}`는 ISO 시각, `{fromDate}` `{toDate}`는 YYYY-MM-DD로 치환. 앱의 "커넥터 추가"에 폴더의 노트·macOS 캘린더 프리셋이 있고, 추가하면 바로 한 번 수집해 결과를 보여 줌 | 명령 |

모든 원본은 기록 전에 토큰·비밀번호·API 키를 가립니다. 설정은 앱의 **연결** 탭이나 `~/.zaevis/sources.json`에서 바꿉니다.
Claude Cowork·claude.ai 대화는 로컬 기록이 없어 자동 수집되지 않습니다. 필요하면 내보낸 대화를 전사본처럼 넣거나 사용자 커넥터를 만드세요.

### 외부 소스 (AutoRAG 데이터소스)
각 카드에 서비스 아이콘과 상태(미설치 · 연결 안 됨 · 연결됨)가 보입니다. 도구가 필요한 소스는 카드의 **설치** 버튼 하나로 들어갑니다(앱 설치본에서만; 웹에서는 명령 복사).
설치 경로: Slack·Notion·Discord·WhatsApp·Telegram은 `brew install openclaw/tap/<도구>`, rclone·Hister는 brew, 카카오톡(lazykatok)은 GitHub 릴리스 tar.gz를 `~/.zaevis/ext/bin`에 풉니다. mailcrawl·clawgallery는 아직 손으로 설치합니다(카드의 안내 링크).
토큰이 필요한 소스(GitHub·Gist·Hister)는 카드의 **토큰 값** 칸에 넣으면 `~/.zaevis/secrets.json`(소유자만 읽기)에 환경 변수 이름으로 저장되고 검색 프로세스에만 전달됩니다. 앱은 셸 환경 변수를 물려받지 않으므로 이 칸이 유일한 경로입니다.
그 밖의 로그인(Slack·Notion·메일·클라우드 드라이브)은 각 도구 안에서 합니다 — 카드의 "로그인·토큰" 줄에 무엇을 해야 하는지 적혀 있습니다.

위 데이터소스는 worklog 폴더에 Markdown으로 쌓이는 것들입니다. 그와 별도로 AutoRAG가 **직접 색인하는 외부 소스**를 붙일 수 있습니다. worklog에는 들어가지 않고, 검색할 때 AutoRAG가 worklog 히트와 함께 섞어 돌려줍니다(결과 카드의 출처가 "Obsidian 볼트"·"Slack"처럼 표시되고, 출처 칩으로 거를 수 있음). 앱 **연결** 탭 맨 아래 "외부 소스 (AutoRAG)"에서 연결합니다.

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

카드마다 서비스 아이콘과 상태가 보이고, 도구가 필요한 소스는 **설치** 버튼 하나로 들어갑니다(앱 설치본에서; 웹은 명령 복사). Slack·Notion·Discord·WhatsApp·Telegram은 `brew install openclaw/tap/<도구>`, rclone·Hister는 brew, 카카오톡(lazykatok)은 GitHub 릴리스 tar.gz를 `~/.zaevis/ext/bin`에 풉니다. mailcrawl·clawgallery는 아직 손으로 설치합니다(카드의 안내 링크). 그 밖의 로그인(Slack·Notion·메일·클라우드 드라이브)은 각 도구 안에서 하며, 카드의 "로그인·토큰" 줄에 무엇을 해야 하는지 적혀 있습니다.

절차: 카드를 펼치면 **미설치**(설치 버튼 — 아래 참고) → **연결 안 됨**(필요한 칸만 있는 폼, "연결") → **연결됨**(켜기/끄기 스위치, 저장, 지금 동기화, 연결 삭제) 순으로 바뀝니다. 연결하거나 저장하면 서버가 AutoRAG의 `datasources` 설정을 고쳐 쓰고 검색 자식을 재시작한 뒤 외부 소스만 동기화합니다(`autorag.refresh`의 `datasources` 단계). 매일 수집 뒤 색인에서도 같이 동기화됩니다. 동기화는 연결 전체를 한 번에 돕니다(AutoRAG에 연결별 갱신이 없음). 토큰은 카드의 **토큰 값** 칸으로만 받습니다: `~/.zaevis/secrets.json`(소유자만 읽기)에 환경 변수 이름으로 저장되고 검색 프로세스에만 전달되며 다시 표시되지 않습니다(앱은 셸 환경 변수를 물려받지 않으므로 이 칸이 유일한 경로). connector 설정 안에 `token` 같은 이름으로 값을 넣으면 서버가 거절합니다. 카드의 "밖으로 나가는 것"이 각 소스가 어디에 접속하는지 알려 줍니다(Obsidian·메일 내보내기·Spotlight는 없음).

### 질문 (기록을 근거로 답하기)

검색 탭 위의 **검색 / 질문** 전환을 질문으로 두고 물어보면, 같은 검색으로 고른 상위 문단(기본 10개)만 근거로 한국어 답을 써 줍니다.
질문과 답은 대화로 쌓입니다. "그건 왜?"처럼 짧게 이어 물으면 앞 대화를 기억하고(앞 질문과 함께 검색), 대화는 `~/.zaevis/ask/`에 남아 오른쪽 위 시계 아이콘으로 다시 열거나 지울 수 있습니다.
답의 각 문장 끝에 [번호]가 붙습니다. 번호나 답 아래 근거 칩에 마우스를 올리면 출처와 발췌 앞부분이 툴팁으로 보이고, 누르면 오른쪽 패널(좁은 창은 아래 시트)에 전체 발췌·경로·이전/다음 근거·원문 열기가 나옵니다.
근거가 없으면 "기록에서 근거를 찾지 못했습니다"라고 답합니다.
답을 쓰는 것은 주간 정리와 같은 에이전트입니다: 이 컴퓨터에 설치된 **Claude Code · Codex · Gemini CLI**(내 구독으로, 파일을 읽기만 하는 모드) 또는 저장된 **OpenRouter 키**.
설정 → 정리 (지식화)의 에이전트·모델 선택을 그대로 따르고, 쓸 수 있는 것이 없으면 설정으로 안내합니다. 설치는 됐지만 로그인이 안 된 CLI(Claude Code는 `claude auth status`, Codex는 `~/.codex/auth.json`, Gemini는 `~/.gemini/oauth_creds.json` 또는 `GEMINI_API_KEY`로 확인, 10분 캐시)는 건너뛰고 질문·리포트·설정 화면에 "로그인 필요: 터미널에서 claude login"처럼 표시합니다. 터미널에서는 `zaevis ask "질문"`.

### 리포트 (일간 · 주간 · 월간)

**리포트** 탭은 그 기간의 기록만 근거로 에이전트가 쓴 정리입니다: **한 일 · 결정 · 막힌 것 · 다음 할 일**, 항목마다 `(근거: 날짜 파일)`.
입력은 그 기간의 로그 줄, `sources/*/<날짜>.md` 원본, inbox·processed의 전사본과 세션 노트이고(주간은 그 주의 일간 리포트, 월간은 주간·일간 리포트도 함께),
분량 상한을 넘으면 최근 것부터 담습니다. 답을 쓰는 것은 질문 모드와 같은 에이전트(설치된 Claude Code · Codex · Gemini CLI를 읽기 전용으로, 또는 OpenRouter 키)입니다.

- 파일: `worklog/reports/daily/YYYY-MM-DD.md`, `reports/weekly/YYYY-Www.md`, 월간은 기존 월간 정리 자리인 `summaries/YYYY-MM.md`. 첫머리에 생성 시각·에이전트가 front matter로 남습니다.
- **지금 만들기**: 오늘 · 어제 · 이번 주 · 지난주 · 이번 달 · 지난달 중 골라 바로 만듭니다(진행 막대, 끝나면 알림). 터미널에서는 `zaevis report daily 2026-10-26`처럼 기간을 적고, 없으면 만들어 보여 줍니다(`--run`은 다시 만들기).
- **자동**: 탭의 ⚙︎(리포트 설정)에서 일간은 요일 칩(주중 · 주말 · 매일 프리셋), 주간은 요일 하나, 월간은 날짜(1~28일)를 정합니다. 매일 수집이 끝나면 그날 해당하는 리포트를 차례로 만듭니다.
  일간은 아침에 돌면 전날을, 주간은 고른 요일의 전날이 든 주(월~일)를, 월간은 지난달을 씁니다. 기본값은 월간만 켬(매월 1일). 쓸 수 있는 에이전트가 없으면 건너뛰고 로그에 남깁니다.

### 정리 결과 검토

설정 → 정리 (지식화)의 **적용 전에 검토**(기본 켬)를 켜 두면 에이전트가 쓴 로그 줄·프로젝트 페이지·월간 정리를 바로 worklog에 넣지 않고
제안으로 보관합니다. 메모리 탭 위의 배너나 설정의 "검토 대기"에서 **검토하기**를 누르면 줄마다 체크해서 남길 것만 **적용**하거나 전부 **버리기**할 수 있습니다.
에이전트가 지우려던 기존 줄은 적용해도 지워지지 않습니다. 끄면 예전처럼 바로 씁니다.

### 알림 · 전역 단축키 · 검색 필터

- **알림**: 정리 제안이 준비됐을 때, 수집이 실패했을 때, 녹음 전사가 끝났을 때 시스템 알림(macOS 알림 센터·Windows 토스트)이 옵니다. 서버가 보내므로 앱 창이 닫혀 있어도 옵니다. 설정 → 알림에서 끕니다.
- **전역 단축키**: 기본 ⌘⇧Space(Windows: Ctrl+Shift+Space). 설정 → 단축키 → 바꾸기에서 원하는 조합을 눌러 바꿉니다. 수정키 없는 단일 키는 받지 않습니다.
- **검색 필터**: 결과 위의 칩으로 출처(git 커밋·에이전트 세션·한 줄 기록·전사본 …)와 기간(7일·30일·이번 달)을 거릅니다. 한 번에 40건을 받아 와 앱 안에서 거릅니다.
- **색인 진행**: 색인 창에서 "본문 읽는 중 12/40 파일 → 임베딩·색인 → 마무리"를 진행 막대로 보여 줍니다.
- **한국어 형태소 검색 (Kiwi)**: 키워드(BM25) 검색은 기본으로 공백 단위라 `인증서를`은 `인증서`와 맞지 않습니다. Kiwi를 설치하면 MinSync가 각 단어에 형태소를 더해 색인해(`multilingual`) 활용형도 찾고 `연구목표` 같은 합성어도 그대로 맞습니다. 색인 창의 "키워드 분석" 줄과 설정 → 검색에서 상태를 보고 설치합니다(앱 설치본은 버튼, 웹은 `zaevis ext install kiwi`). 라이브러리(28MB)와 모델(104MB)은 Kiwi GitHub 릴리스(고정 버전, 체크섬 확인)에서 `~/.zaevis/ext/kiwi`로 받고, 서버가 검색 엔진에 경로를 넘깁니다. **이미 있는 색인은 공백 기준으로 만든 것이라 설치 뒤 "처음부터 다시" 색인해야** 합니다(설치 버튼이 바로 물어봅니다). 직접 둔 Kiwi(`~/.local/kiwi`, `KIWI_LIBRARY_PATH`·`KIWI_MODEL_PATH`)도 그대로 씁니다. 검색할 때도 Kiwi가 필요하니 설치 뒤에는 지우지 말고, 지웠다면 처음부터 다시 색인하세요.

### 주간·월간 정리 예약

`~/.zaevis/weekly-task-prompt.md`에 내 경로로 채워진 프롬프트가 생깁니다.
Claude 앱에서 이 내용으로 **매주 월요일 오전** 예약 작업을 만들고, 내 컴퓨터에서 실행되도록 설정하세요.
월간 요약은 매월 첫 월요일에 같은 작업이 이어서 씁니다. 리포트 설정의 월간 리포트가 켜져 있으면(기본 매월 1일) 그쪽이 먼저 `summaries/YYYY-MM.md`를 쓰고, 정리는 이미 있는 달은 건너뜁니다.

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
