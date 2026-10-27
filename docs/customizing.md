# 커스터마이징

## 로그 형식과 태그

규칙의 원본은 `kit/templates/worklog/README.md`입니다. Claude 예약 작업은 매번 **내 worklog 폴더의 README.md**를 읽고 그대로 따르므로, 규칙을 바꾸려면 그 파일만 고치면 됩니다.

태그를 추가할 때 함께 바꿀 곳:

| 위치 | 내용 |
|---|---|
| 내 `worklog/README.md` | 태그 목록과 설명 (Claude가 읽음) |
| `app/lib/screens/log_screen.dart` | `_tags` 목록 (필터 칩) |
| `app/lib/widgets/common.dart` | `tagColor`, `tagLabel` |

서버는 `#태그`를 형식에 상관없이 읽으므로 고칠 필요가 없습니다.

## 서버 API

`server/src/app.ts`. 127.0.0.1에만 바인딩하고, CORS는 localhost 출처만 허용합니다.

| 메서드 | 경로 | 응답 |
|---|---|---|
| GET | `/api/health` | `{ ok, worklog }` |
| GET | `/api/logs` · `/api/logs/:YYYY-MM` | 월 목록 · `{ month, entries[] }` |
| GET | `/api/projects` · `/api/projects/:slug` | 프로젝트 요약 목록 · 프로젝트 본문 |
| GET | `/api/summaries` · `/api/summaries/:YYYY-MM` | 월 목록 · `{ month, markdown }` |
| GET | `/api/search?q=&topK=` | `{ ok, query, hits[] }` (AutoRAG Lite). hit마다 `context`(출처·날짜·섹션·작성자·매치 단어)와 가장 잘 맞는 문단 `snippet`, 상위 대비 점수가 낮으면 `weak` |
| GET | `/api/file?path=` | worklog 안의 markdown 원문 `{ path, markdown }` (검색 결과 원문 보기) |
| GET / POST | `/api/index` | 색인 상태(+ `embedding`: 로컬 임베딩 데몬 상태 off/starting/ready/failed) · 색인 갱신 시작 (`{ force?: true }`) |
| POST | `/api/logs` | 한 줄 기록 `{ text, tags[], projects[], date? }` |
| PUT / DELETE | `/api/logs/:YYYY-MM` | 한 줄 편집 `{ raw, text?, tags?, projects?, date? }` · 삭제 `{ raw }`. `raw`는 파일에 있는 현재 줄 그대로이며, 못 찾으면 409(다른 곳에서 바뀜). 정리가 쓴 줄의 `(src: …)`는 보존 |
| GET | `/api/inbox` | inbox 파일과 전사 작업 |
| POST | `/api/inbox/transcripts` · `/api/inbox/audio?name=` | 전사본 저장 · 녹음 업로드(본문 그대로, 최대 1GB) |
| GET / POST / PUT / DELETE | `/api/sources[/:name]` | 데이터소스 목록 · 사용자 커넥터 추가 · 설정 변경 · 삭제 |
| GET / POST | `/api/collect` | 수집 상태 · 수집 시작 (`{ sources?: [], index?: false }`) |
| GET / PUT | `/api/settings` | 매일 실행 시각(launchd 재등록), 주입 즉시 색인, `localEmbedding`(의미 검색 켜기/끄기 — 켜면 데몬을 띄우고 처음부터 재색인). GET에는 `rerank` 상태(`enabled, hasKey, keyHint, model, external`) 포함 |
| PUT | `/api/settings/rerank` | OpenRouter 재정렬 `{ enabled?, model?, apiKey? }` — `apiKey: ""`는 키 삭제. 키는 `secrets.json`(0600)에 저장되고 응답엔 끝 4자리만. AutoRAG 설정의 `rerank`를 다시 쓰고 검색 자식 프로세스를 재시작 |
| POST | `/api/settings/rerank/test` | `{ apiKey? }` 키를 OpenRouter에 확인 (`{ ok, message }`), 저장하지 않음 |
| GET / PUT | `/api/digest` | 주간 정리(지식화): 감지된 에이전트(`agents[]`: claude/codex/gemini CLI, openrouter 키), 설정(`agent: auto|…`, `model`, `weekly`), 실제로 돌 에이전트 `chosen`, 실행 중 여부, 마지막 실행 `last` |
| POST | `/api/digest/run` | 지금 정리 시작 (202). 쓸 수 있는 에이전트가 없거나 이미 실행 중이면 409 `{ started: false, reason }` |

GET이 아닌 요청은 `x-zaevis: 1` 헤더가 있어야 하고, 다른 사이트(Origin)나 다른 호스트 이름에서 온 요청은 거절합니다. 사용자 커넥터가 명령을 실행하기 때문에 넣은 보호 장치입니다.

설정은 `~/.zaevis/config.json`이고, 환경변수 `WORKLOG_DIR`, `AUTORAG_CONFIG`, `ZAEVIS_PORT`, `ZAEVIS_WEB_DIR`로 덮어쓸 수 있습니다.

AutoRAG Lite 검색 응답 형태는 공개 계약이 아니라서 `normalizeSearch()`가 흔한 필드 이름을 모두 받아 정규화합니다. AutoRAG를 올린 뒤 결과가 비어 보이면 이 함수부터 확인하세요.

## 앱 화면 추가

1. `app/lib/api.dart`에 API 메서드 추가
2. `app/lib/screens/`에 화면 추가
3. `app/lib/main.dart`의 `_dests`와 `_screen()`에 등록

외부 패키지는 `http` 하나만 씁니다. Markdown은 `widgets/markdown_view.dart`의 작은 렌더러가 worklog에서 쓰는 문법(제목, 목록, 체크박스, 코드, `[[링크]]`, `#태그`)만 처리합니다.

## 다른 사람에게 줄 때

- 저장소에는 개인 데이터가 없습니다. 받는 사람은 `kit/setup.sh`만 실행하면 자기 경로로 채워진 worklog가 생깁니다.
- 회사 저장소를 담은 폴더 안에 worklog를 만들면 `setup.sh`가 그 저장소의 `.git/info/exclude`에 등록해 커밋을 막습니다.
- 색인 범위는 worklog 폴더 하나입니다. 회사 코드나 메일을 색인하려면 각자 회사 정책을 먼저 확인하세요.

## CLI 명령 추가

`bin/zaevis`(bash)가 명령을 나누고, 서버 API를 쓰는 명령은 `server/src/cli.ts`의 `run()`으로 넘깁니다.
새 조회 명령은 `run()`에 case를 추가하고, `bin/zaevis`의 `search|s|log|…` 목록에 이름을 더하면 됩니다.

## 데이터소스 커넥터 추가

**명령어로 (코드 수정 없이)**: 앱의 수집 화면 → 커넥터 추가, 또는 `~/.zaevis/sources.json`의 `custom`에 추가합니다.

```json
{ "custom": [ { "name": "calendar", "command": "python3 ~/bin/cal_export.py --since {from} --until {to}" } ] }
```

명령은 Markdown을 출력하면 됩니다. 날짜별로 나누려면 `<!-- zaevis:date 2026-10-23 -->` 줄을 넣습니다.

**내장 커넥터로**: `server/src/sources/`에 `Source`(`types.ts`)를 구현하고 `sources/index.ts`의 `BUILTIN`에 추가합니다.
`collect()`는 수집 구간의 날짜별 Markdown을 돌려주고, 수집기가 `sources/<이름>/<날짜>.md`에 씁니다.
매번 하루 전체를 다시 만들어 덮어쓰는 방식이라 같은 날 여러 번 돌려도 중복이 생기지 않습니다(이벤트형은 `append: true`).
