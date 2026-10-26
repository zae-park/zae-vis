# zaevis

어디서 무슨 작업을 하든 기록을 모아 **개인 작업 기록과 지식 베이스**를 만드는 키트입니다.

- **수집 (매일, 자동)**: git 커밋, Claude Code 세션, 셸 명령, 회의 전사본, 직접 만든 커넥터를 `worklog/sources/`에 모읍니다. 매일 18:30(launchd)에 돌고, 언제든 수동으로도 돌릴 수 있습니다.
- **주입 (실시간)**: 한 줄 기록, 전사본 붙여넣기, 녹음 업로드(whisperX 자동 전사)는 넣는 즉시 worklog에 저장됩니다.
- **색인·검색**: [AutoRAG](https://github.com/Marker-Inc-Korea/AutoRAG) Lite(로컬, 무료). 키워드(BM25)에 더해 **의미 검색**: 앱이 번들된 MinSync로 Qwen3-Embedding-0.6B 모델을 이 맥에서 돌려(`minsync serve`) 뜻이 비슷한 기록도 찾습니다. 외부 서비스·키 없음, 설정에서 끌 수 있음. 처음 켤 때 모델(1.1GB)을 내려받습니다. 색인은 매일 수집 직후 + 수동 + (선택) 주입 즉시.
- **정리**: Claude가 매주 원본을 읽어 로그·프로젝트·월간 요약을 씁니다.
- **front**: Flutter 앱(데스크톱 + 브라우저)과 `zaevis` CLI에서 검색·열람·주입·데이터소스 설정을 모두 합니다. 추가 유료 서비스는 쓰지 않습니다.
- **외부 연결**: 기본값은 없음. 유일한 선택 항목이 설정의 **검색 결과 재정렬(OpenRouter)**이며, 켜고 키를 저장해야만 검색어와 상위 25개 문단이 OpenRouter로 갑니다. 키는 `~/.zaevis/secrets.json`(소유자만 읽기)에만 두고 앱에는 끝 4자리만 보여 줍니다.

```
 데이터소스 (매일 18:30 + 수동)          실시간 주입 (앱 · CLI)
 git · Claude Code · 셸 · 전사본 폴더     한 줄 기록 · 전사본 · 녹음(whisperX)
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
| `bin/zaevis` | CLI. `zaevis run cli` · `run web` · `run app`, `zaevis search`, `zaevis setup` 등 |
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

### DMG 만들기 (배포하는 사람만)

```bash
brew install --cask flutter && brew install protobuf cmake
curl https://sh.rustup.rs -sSf | sh          # MinSync(검색 임베딩 엔진) 빌드용, 처음 한 번
tool/package_macos.sh                         # → dist/zaevis-<버전>-arm64.dmg
```

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
| `claude-code` | `~/.claude/projects` 세션 기록: 요청, 수정한 파일, 실행한 명령, 마지막 응답 | 기록 폴더 |
| `shell-history` | zsh 명령 이력 (`setopt EXTENDED_HISTORY` 필요) | 히스토리 파일 |
| `transcripts` | 전사 서비스 내보내기 폴더에서 가져오기 + `inbox/audio` 녹음을 whisperX로 전사 | 가져올 폴더, 언어, 모델 |
| 사용자 커넥터 | Markdown을 출력하는 아무 명령 (`{from}`, `{to}` 치환) | 명령 |

모든 원본은 기록 전에 토큰·비밀번호·API 키를 가립니다. 설정은 앱의 **수집** 화면이나 `~/.zaevis/sources.json`에서 바꿉니다.
Claude Cowork·claude.ai 대화는 로컬 기록이 없어 자동 수집되지 않습니다. 필요하면 내보낸 대화를 전사본처럼 넣거나 사용자 커넥터를 만드세요.

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
