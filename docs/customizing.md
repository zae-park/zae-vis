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
| GET | `/api/search?q=&topK=` | `{ ok, query, hits[] }` (AutoRAG Lite) |
| GET / POST | `/api/index` | 색인 상태 · 색인 갱신 시작 (`{ force?: true }`) |

설정은 `~/.worklog-kit/config.json`이고, 환경변수 `WORKLOG_DIR`, `AUTORAG_CONFIG`, `WORKLOG_PORT`, `WORKLOG_WEB_DIR`로 덮어쓸 수 있습니다.

AutoRAG Lite 검색 응답 형태는 공개 계약이 아니라서 `normalizeSearch()`가 흔한 필드 이름을 모두 받아 정규화합니다. AutoRAG를 올린 뒤 결과가 비어 보이면 이 함수부터 확인하세요.

## 앱 화면 추가

1. `app/lib/api.dart`에 API 메서드 추가
2. `app/lib/screens/`에 화면 추가
3. `app/lib/main.dart`의 `_dests`와 `_screen()`에 등록

외부 패키지는 `http` 하나만 씁니다. Markdown은 `widgets/markdown_view.dart`의 작은 렌더러가 worklog에서 쓰는 문법(제목, 목록, 체크박스, 코드, `[[링크]]`, `#태그`)만 처리합니다.

## 다른 사람에게 줄 때

- 저장소에는 개인 데이터가 없습니다. 받는 사람은 `kit/setup.sh`만 실행하면 자기 경로·이메일로 채워진 worklog가 생깁니다.
- 회사 저장소를 담은 폴더 안에 worklog를 만들면 `setup.sh`가 그 저장소의 `.git/info/exclude`에 등록해 커밋을 막습니다.
- 색인 범위는 worklog 폴더 하나입니다. 회사 코드나 메일을 색인하려면 각자 회사 정책을 먼저 확인하세요.
