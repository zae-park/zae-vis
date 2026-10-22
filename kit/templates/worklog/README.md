# worklog — 개인 작업 기록과 지식 관리

혼자 쓰는 작업 기록이다. 팀과 공유하지 않는다.
입력(전사본, Claude 세션 노트, git 커밋, 내 한 줄 로그)을 모아 Claude가 매주 로그로 정리하고, 매월 요약을 쓴다.
worklog-kit 앱으로 검색·열람하거나, Obsidian으로 이 폴더를 볼트로 열어도 된다.

- 작성자: {{AUTHOR_EMAIL}}
- 코드 저장소 위치: {{REPOS_ROOT}}

## 폴더

```
worklog/
  README.md                 ← 이 규칙 파일. 예약 작업은 항상 이 파일부터 읽는다
  inbox/
    transcripts/            ← 회의·음성 메모 전사본 (YYYY-MM-DD_제목.txt)
    claude-sessions/        ← Claude 코드 작업 세션 노트 (YYYY-MM-DD_저장소.md)
  processed/                ← 주간 정리가 끝난 inbox 파일을 같은 하위 폴더로 옮겨 둔다
  log/YYYY-MM.md            ← 월별 한 줄 로그 (나와 Claude가 함께 씀)
  projects/<slug>.md        ← 프로젝트별 현재 상태, 결정, 링크
  summaries/YYYY-MM.md      ← 월간 정리 결과물
  .state.md                 ← 마지막 주간 정리 날짜
  .autorag/                 ← 검색 색인 (AutoRAG가 관리, 손대지 않음)
```

## 로그 형식

한 줄 = 날짜 · 프로젝트 링크 · 유형 태그 · 설명. 무엇을 했는지보다 **왜** 했는지를 적는다.

```
- 10-06 [[databricks-poc]] #done Claude MCP 연결 완료 — 원인은 토큰 스코프
- 10-07 [[hiring]] #decision DS JD에 실험설계 역량을 필수로 추가
- 10-08 [[roas-multihorizon]] #done 광고·결제 분리 채점 — 어느 쪽이 문제인지 가르기 위해 (src: git roas-multihorizon a1b2c3d)
```

- 유형 태그는 `#done`, `#decision`, `#blocked`, `#learned` 네 가지만 쓴다.
- 프로젝트는 `[[slug]]` 링크로 적는다. slug는 `projects/` 파일명과 같다.
- Claude가 쓴 줄은 끝에 `(src: …)`로 출처를 붙인다. 출처 없는 줄은 내가 쓴 줄이다.
  - 전사본: `(src: 2026-10-06_회의명)` · 세션 노트: `(src: session 2026-10-06_crea)` · 커밋: `(src: git <저장소> <해시 7자리>)`
- 날짜순으로 쌓는다. 내가 쓴 줄은 Claude가 고치거나 지우지 않는다.

## 프로젝트 파일 형식 (`projects/<slug>.md`)

`projects/_template.md`를 복사해 쓴다. `repos`는 이 프로젝트에 속한 git 저장소 이름 목록이다.
어느 프로젝트에도 없는 저장소의 커밋은 저장소 이름을 slug로 새 프로젝트 파일을 만든다.

## 주간 정리 (매주 월요일 오전, Claude 예약 작업)

1. `.state.md`에서 마지막 정리 날짜를 읽는다. 없으면 7일 전부터.
2. 입력을 읽는다.
   - `inbox/transcripts/`, `inbox/claude-sessions/`의 모든 파일
   - `{{REPOS_ROOT}}` 아래 git 저장소에서 작성자 `{{AUTHOR_EMAIL}}`의 커밋 (마지막 정리 날짜 이후, `git log --all`)
3. 완료·결정·블로커·배운 점을 뽑아 해당 월의 `log/YYYY-MM.md`에 한 줄씩 추가한다.
   - 커밋은 하나하나 적지 않는다. 같은 날 같은 저장소의 커밋은 의미 단위로 묶어 한 줄로 쓴다.
   - 이미 같은 내용의 줄(내가 쓴 줄 포함)이 있으면 추가하지 않는다.
4. 관련 `projects/*.md`의 현재 상태·주요 결정·열린 문제를 갱신한다.
5. 처리한 inbox 파일을 `processed/`의 같은 하위 폴더로 옮긴다. 삭제하지 않는다.
6. `.state.md`에 오늘 날짜를 적는다.

## 월간 정리 (그 달의 첫 월요일, 주간 정리 직후)

지난달 `log/YYYY-MM.md`와 `projects/*.md`로 `summaries/YYYY-MM.md` 초안을 쓴다.

```
# YYYY-MM 작업 정리
## 한 줄 요약
## 프로젝트별      ← 프로젝트마다 결과 2~4줄, 주요 결정과 이유
## 막힌 것 / 다음 달로 넘어간 것
## 배운 것
```

- 숫자·날짜는 로그와 커밋에 있는 것만 쓴다. 추측하지 않는다.

## 내가 할 일

- **매일**: 회의가 아닌 일 중 남길 만한 것을 `log/YYYY-MM.md`에 한 줄. 또는 30초 음성 메모를 전사해 `inbox/transcripts/`로.
- **회의 후**: 전사 서비스 결과를 `inbox/transcripts/YYYY-MM-DD_제목.txt`로 저장 (자동 내보내기가 되면 그 경로로 설정).
- **매월 첫 월요일**: `summaries/` 초안을 읽고 빠지거나 틀린 부분만 고친다.
