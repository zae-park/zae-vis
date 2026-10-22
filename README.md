# worklog-kit

코드 작업과 회의 전사본으로 **개인 작업 기록과 지식 베이스**를 만드는 키트입니다.
정리는 Claude가 하고, 검색은 [AutoRAG](https://github.com/Marker-Inc-Korea/AutoRAG) Lite(로컬, 무료, 한국어 형태소 검색)가 하고,
열람은 이 저장소의 Flutter 앱(데스크톱 + 브라우저)으로 합니다. 추가 유료 서비스는 쓰지 않습니다.

```
 입력                         정리 (Claude, 매주)              열람·검색
 ─────────────────────        ────────────────────────        ──────────────────────────
 회의 전사본  ─┐                                               Flutter 앱 (macOS/Win/Linux/웹)
 Claude 세션 노트 ─┼──▶ worklog/ ──▶ log/  projects/  summaries/ ──▶       │  HTTP (127.0.0.1)
 git 커밋     ─┘        (내 폴더)                                       server/ (Node)
 내 한 줄 로그 ─┘                                                       ├─ worklog 파일 읽기
                                                                        └─ AutoRAG Lite (MCP)
```

- **내 데이터는 이 저장소에 들어오지 않습니다.** `worklog/` 폴더는 `setup.sh`가 원하는 위치에 만들고, 저장소 안에 두더라도 `.gitignore`로 막혀 있습니다.
- AutoRAG는 포크하지 않고 npm 의존성(`@autorag/librarian`, Apache-2.0)으로 씁니다. AutoRAG 데스크톱 앱(FSL 라이선스)은 쓰지 않고, 이 저장소의 Flutter 앱이 그 역할을 대신합니다.

## 구성

| 경로 | 내용 |
|---|---|
| `kit/setup.sh` | worklog 폴더 생성, Claude 지침·예약 작업 프롬프트 생성, AutoRAG 색인 초기화 |
| `kit/templates/worklog/` | worklog 규칙(README)과 프로젝트 템플릿 |
| `kit/claude/` | 세션 노트 지침(`CLAUDE.md`), 주간·월간 정리 예약 작업 프롬프트 |
| `server/` | 로컬 API 서버 (Node 24, TypeScript). worklog 파일 + AutoRAG MCP를 HTTP로 제공하고, 웹 앱도 서빙 |
| `app/` | Flutter 앱. 검색 · 로그 · 프로젝트 · 월간 정리 · 색인 상태 |

## 설치 (macOS 기준)

필요한 것: Node.js 24+, Rust(cargo)와 protobuf(AutoRAG 임베딩 엔진 빌드용, 처음 한 번), Flutter 3.27+

```bash
brew install node@24 flutter protobuf
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

git clone https://github.com/zae-park/worklog-kit.git
cd worklog-kit
kit/setup.sh                       # worklog 위치, 저장소 위치, git 이메일을 묻습니다
```

`setup.sh`는 다시 실행해도 기존 파일을 덮어쓰지 않습니다. 검색 없이 기록만 쓰려면 `--no-autorag`.

### 실행

```bash
# 1) 서버
cd server && npm start             # http://127.0.0.1:4710

# 2-a) 브라우저: 웹 앱을 빌드하면 서버가 같은 주소로 제공합니다
cd app && tool/setup_platforms.sh && flutter build web
open http://127.0.0.1:4710

# 2-b) 데스크톱 앱
cd app && flutter run -d macos      # 또는 windows / linux
```

처음 한 번 앱 화면의 **색인 아이콘 → 색인 갱신**을 누르거나 `autorag lite refresh`를 실행하세요.

### 주간·월간 정리 예약

`~/.worklog-kit/weekly-task-prompt.md`에 내 경로로 채워진 프롬프트가 생깁니다.
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
cd app && tool/setup_platforms.sh && flutter test && flutter analyze
```

GitHub Actions가 push마다 서버 테스트, Flutter analyze·test·웹 빌드, macOS 빌드를 돌립니다.

## 라이선스

MIT. 의존하는 AutoRAG 엔진은 Apache-2.0입니다.
