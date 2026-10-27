# worklog — 개인 작업 기록과 지식 관리

혼자 쓰는 작업 기록이다. 팀과 공유하지 않는다.
zaevis가 매일 데이터소스(git 커밋, Claude Code 세션, 셸 명령, 회의 전사본, 직접 추가한 커넥터)를 `sources/`에 모으고 검색 색인을 갱신한다.
Claude가 매주 그 원본과 inbox를 읽어 로그·프로젝트를 정리하고, 매월 요약을 쓴다.
zaevis 앱으로 검색·열람하거나, Obsidian으로 이 폴더를 볼트로 열어도 된다.

- 코드 저장소 위치: {{REPOS_ROOT}}

## 폴더

```
worklog/
  README.md                 ← 이 규칙 파일. 예약 작업은 항상 이 파일부터 읽는다
  sources/<이름>/YYYY-MM-DD.md ← zaevis가 매일 자동 수집한 원본 (직접 고치지 않음)
  inbox/
    transcripts/            ← 회의·음성 메모 전사본 (YYYY-MM-DD_제목.txt), 앱·CLI로 바로 넣은 것 포함
    audio/                  ← 전사 대기 녹음 (whisperX가 전사 후 processed/audio로 옮김)
    claude-sessions/        ← Claude가 남긴 세션 노트 (YYYY-MM-DD_저장소.md)
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
  - 전사본: `(src: 2026-10-06_회의명)` · 세션: `(src: agent-sessions 2026-10-06)` · 커밋: `(src: git <저장소> <해시 7자리>)` · 셸: `(src: shell 2026-10-06)` · 그 밖의 커넥터: `(src: <이름> 2026-10-06)`
- 날짜순으로 쌓는다. 내가 쓴 줄은 Claude가 고치거나 지우지 않는다.

## 프로젝트 파일 형식 (`projects/<slug>.md`)

`projects/_template.md`를 복사해 쓴다. `repos`는 이 프로젝트에 속한 git 저장소 이름 목록이다.
어느 프로젝트에도 없는 저장소의 커밋은 저장소 이름을 slug로 새 프로젝트 파일을 만든다.

## 주간 정리 (매주 월요일 오전, Claude 예약 작업)

1. `.state.md`에서 마지막 정리 날짜를 읽는다. 없으면 7일 전부터.
2. 입력을 읽는다.
   - `sources/*/YYYY-MM-DD.md` 중 마지막 정리 날짜 이후 파일 전부 (git, agent-sessions, shell-history, transcripts, 사용자 커넥터)
   - `inbox/transcripts/`, `inbox/claude-sessions/`의 모든 파일
   - `sources/git/`이 비어 있으면(zaevis 수집 전) `{{REPOS_ROOT}}` 아래 git 저장소의 모든 커밋을 작성자와 함께 직접 읽는다 (`git log --all --format='%h %an %s'`)
3. 완료·결정·블로커·배운 점을 뽑아 해당 월의 `log/YYYY-MM.md`에 한 줄씩 추가한다.
   - 원본을 그대로 옮기지 않는다. 같은 날 같은 일(커밋, 세션, 명령)은 의미 단위로 묶어 한 줄로 쓰고, 왜 했는지가 보이게 쓴다.
   - 셸 명령 이력은 단독으로 줄을 만들지 않고, 다른 기록의 맥락을 보충할 때만 쓴다.
   - 이미 같은 내용의 줄(내가 쓴 줄 포함)이 있으면 추가하지 않는다.
4. 관련 `projects/*.md`의 현재 상태·주요 결정·열린 문제를 갱신한다.
5. 처리한 inbox 파일을 `processed/`의 같은 하위 폴더로 옮긴다. 삭제하지 않는다. `sources/`는 건드리지 않는다.
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

- **매일**: 자동 수집에 안 잡히는 일(결정, 대화, 생각)을 한 줄: 앱의 "한 줄 기록" 또는 `zaevis add "#decision [[프로젝트]] 무엇을, 왜"`.
- **회의 후**: 전사본을 앱에서 붙여넣거나 `zaevis ingest 파일`. 녹음 파일이면 whisperX가 바로 전사한다. 전사 서비스 내보내기 폴더를 데이터소스(transcripts → 가져올 폴더)에 등록해 두면 매일 자동으로 가져온다.
- **매월 첫 월요일**: `summaries/` 초안을 읽고 빠지거나 틀린 부분만 고친다.
