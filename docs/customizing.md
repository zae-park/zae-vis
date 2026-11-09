# 커스터마이징

## 로그 형식과 태그

규칙의 원본은 `kit/templates/worklog/README.md`입니다. Claude 예약 작업은 매번 **내 worklog 폴더의 README.md**를 읽고 그대로 따르므로, 규칙을 바꾸려면 그 파일만 고치면 됩니다.

태그를 추가할 때 함께 바꿀 곳:

| 위치 | 내용 |
|---|---|
| 내 `worklog/README.md` | 태그 목록과 설명 (Claude가 읽음) |
| `app/lib/screens/log_screen.dart` | `_tags` 목록 (필터 칩). 메모리 탭(`memory_screen.dart`)이 이 화면을 '기록' 층으로 품고, '원본'(`_OriginsView`)·'상태'(`_ProjectsPanel`)를 더한다 |
| `app/lib/widgets/common.dart` | `tagColor`, `tagLabel` |

서버는 `#태그`를 형식에 상관없이 읽으므로 고칠 필요가 없습니다.

## 서버 API

`server/src/app.ts`. 127.0.0.1에만 바인딩하고, CORS는 localhost 출처만 허용합니다.

| 메서드 | 경로 | 응답 |
|---|---|---|
| GET | `/api/health` | `{ ok, worklog }` |
| GET | `/api/logs` · `/api/logs/:YYYY-MM` | 월 목록 · `{ month, entries[] }` |
| GET | `/api/projects` · `/api/projects/:slug` | 프로젝트 요약 목록 · 프로젝트 본문 |
| GET | `/api/summaries` · `/api/summaries/:YYYY-MM` | 월 목록 · `{ month, markdown }` (리포트가 쓴 front matter는 뺀 본문) |
| GET | `/api/reports` | 리포트: 설정 `setting{daily{enabled,days[mon…sun]},weekly{enabled,day},monthly{enabled,day 1~28}}`, 진행 중 `running{kind,period,startedAt,agent}`, 종류별 마지막 실행 `lastRun{daily?,weekly?,monthly?: {period,at,ok,agent,ms,path?,error?}}`, 종류별 목록 `reports{daily[],weekly[],monthly[]: {kind,period,path,createdAt,agent}}`(월간은 정리가 쓴 `summaries/`도 포함, agent null), 지금 기본 기간 `defaults{daily,weekly,monthly}` (`server/src/reports.ts`) |
| GET | `/api/reports/:kind/:period` | 리포트 하나 `{ kind, period, path, createdAt, agent, range{from,to,label}, markdown }`. kind는 daily·weekly·monthly, period는 `YYYY-MM-DD` · `YYYY-Www`(ISO 주, 월~일) · `YYYY-MM`. 파일은 `reports/daily/`, `reports/weekly/`, `summaries/` |
| PUT | `/api/reports/settings` | `{ daily?: { enabled?, days? }, weekly?: { enabled?, day? }, monthly?: { enabled?, day? } }` 부분 갱신 → GET과 같은 응답. 요일이 아니거나 날짜가 1~28 밖이면 400. `daily.ts`가 수집 뒤 due인 것(일간: 보고할 날의 요일이 days에 있을 때, 아침 실행은 전날 · 주간: day 요일에 전날이 든 주 · 월간: day 날에 지난달; 파일이 있거나 같은 기간을 이미 돌렸으면 건너뜀)을 차례로 만들고 알림 |
| POST | `/api/reports/run` | `{ kind, period? }` 지금 만들기 (202 `{ started, kind, period, agent }`; period 생략 = defaults). 실행 중·에이전트 없음 409 `{ error: busy|no_agent, reason }`, 종류·기간 형식 오류 400. 입력(그 기간의 log 줄, `sources/*/<날짜>.md`, inbox·processed의 전사본·세션 노트, 주간·월간은 하위 리포트)을 12만 자 상한에 최근 것부터 모아 "이 기록만 근거로 한 일·결정·막힌 것·다음 할 일, 항목 끝에 (근거: 날짜 파일)" 프롬프트를 질문 모드와 같은 읽기 전용 경로(`ask.ts generateText`)로 돌리고, 결과를 front matter(kind·period·range·createdAt·agent·inputs)와 함께 씀. 마지막 전체 수집(`state.daily.lastRun`)이 기간의 마지막 날이 끝나기 전이면(`reports.ts collectBefore`) 먼저 수집하고 색인을 뒤에서 갱신(`ReportRunner.run(…, { prepare })`). 제목 아래에 zaevis가 직접 쓰는 참조 범위 두 줄(`scopeNote`: `> 참조한 기록: 기간 · 정리된 로그 N줄 · 수집 원본 N개 파일 · …` / `> 마지막 수집 MM-DD HH:MM · 마지막 정리 …`). 기록이 없는 기간은 에이전트 없이 "새 기록이 없습니다" 리포트를 쓰고 `ok: true, empty: true`(front matter `agent: none`) |
| GET | `/api/search?q=&topK=` | `{ ok, query, hits[] }` (AutoRAG Lite). hit마다 `context`(출처·날짜·섹션·작성자·매치 단어)와 가장 잘 맞는 문단 `snippet`, 상위 대비 점수가 낮으면 `weak` |
| GET / POST | `/api/ask` | 질문(RAG): GET은 쓸 수 있는 에이전트(`agents[]`, 정리와 같은 감지), 답할 에이전트 `chosen`, 진행 중 `running{q,startedAt,agent}`, 마지막 답 `last`, 대화 목록 `conversations[{id,title,updatedAt,turns}]`. POST `{ q, topK? (기본 10, 최대 20), conversationId? }` → `{ q, answer, sources[{ n, path, label, passage }], agent, ms, at, conversationId, turn }`. `conversationId`가 있으면 그 대화의 앞 턴(최근 4개, 답 600자)을 프롬프트에 넣고, 16자 이하 짧은 질문은 앞 질문과 함께 검색한다. 모르는 id면 새 대화. 대화는 `$ZAEVIS_HOME/ask/<id>.json`(최근 50개). `GET /api/ask/:id` 대화 전체, `DELETE /api/ask/:id` 삭제. 검색 상위 문단(약한 일치 제외, 발췌 1000자)을 `[n]`으로 번호 매겨 "발췌만 근거로 한국어로, 문장마다 [n]" 프롬프트로 에이전트에 넘긴다(`server/src/ask.ts`). CLI는 worklog를 cwd로 읽기 전용(claude `--tools ""`, codex `--sandbox read-only`, gemini `--yolo` 없이)으로 실행. 에이전트 없음·실행 중 409, 질문 없음 400, 검색 결과 없음 404, 검색·에이전트 실패 502. 질문이 모호하면(발췌의 대상이 둘 이상이고 답이 갈릴 때) 에이전트가 `되묻기: 질문` + `- 선택지 [n]` 꼴로 답하고, 응답에 `clarify{ question, options[] }`가 붙는다. 되물은 바로 다음 턴은 되묻지 않고 답한다. 줄마다 라우팅: POST에 `shown?[{ n, path }]`(앞 화면 번호)·`force?: "answer"`(라우터 건너뜀: "답 받기", 되묻기에 대한 답, 다시 묻기, CLI `zaevis ask`). 응답 `route{ by: jev|agent, intent: search|answer|files }`, `files?[{ path, name, bytes, date, kind }]`. OpenRouter 키가 있으면 `server/src/route.ts`가 Jev(`typesafe/jev-1.13`, OpenRouter decisions 엔드포인트, 5초 한 번)에 줄·앞 대화 2턴·후보 파일(`files.ts candidateFiles`: 앞 화면 → 검색 상위 6 → 폴더마다 최근 4개, 최대 40)을 주고 의도와 파일 하나를 고르게 한다. search면 에이전트 없이 빈 답(대화에 저장 안 함, GET `router: jev|agent`), files면 그 파일, answer면 고른 파일 전체를 `[1]`로. Jev가 보류(escalate)·실패하면 에이전트 경로. 에이전트 경로는 프롬프트 끝에 같은 후보 목록을 붙이고, 답 대신 `파일:` + `- 경로`(목록에 있는 것만 인정)로 넘기거나 `읽기:` + `- 경로`로 파일 전체를 요청하면(합쳐 4만 자, Windows 1.2만 자) 그것을 `[1]`부터 붙여 한 번 더 묻는다 |
| PUT | `/api/transcripts/speakers` | 전사본 화자 이름 `{ path, names: { "A": "재박" } }` → `{ path, speakers[], markdown }`. 차례 머리의 `[A] `만 바꾼다 |
| POST | `/api/transcripts/relabel` | 화자 없이 저장된 전사본에 화자 붙이기 `{ path }` → 202 `{ file }`. `processed/audio/`에 남은 원본 녹음(같은 이름, 또는 날짜를 붙이기 전 이름)을 whisperX로 다시 인식해 시간 정보를 얻고 화자 단계를 돌려 머리(제목·whisperX 줄) 아래 본문을 `[A] …` 차례로 바꾼다. 실패하면 파일은 그대로. 진행은 `GET /api/inbox`의 `jobs[]`에서 `kind: "speakers"`, `file`이 전사본 이름. 원본 녹음이 없으면 404 `no_audio` |
| GET | `/api/knowledge` | 지식화 현황 `{ collect{ lastRun, ok, days, latestDay }, waiting{ transcripts, sessions, sourceDays, lastDigest }, review[ProposalSummary], knowledge{ logLines, latestLogDay, projects, summaries }, reports{ daily|weekly|monthly{ enabled, count } }, digest{ running, agent, weekly, daily, nextWeekly, review } }` (`server/src/knowledge.ts`). sourceDays는 마지막 정리(`.state.md`의 last_weekly·last_daily 중 늦은 날) 뒤의 원본 날짜 수 |
| POST | `/api/voice?name=voice.wav` | 대화 입력창의 음성: 본문이 녹음(WAV 등, 최대 10MB) → `{ text, ms }`. whisperX venv에서 faster-whisper를 띄워 두고(`voice.ts`, 첫 요청 때 시작, 10분 쉬면 내림) 전사 언어 설정대로 읽는다. 녹음은 임시 파일로만 받고 답하기 전에 지운다. 소리가 거의 없으면 400 |
| POST | `/api/asr` | 스트리밍 ASR 세션 시작 `{ mode: "live"\|"meeting", language?, name? }` → `{ id, mode }` (201). 설계는 `docs/asr.md`. `name`은 meeting 초안 파일 stem(`…_녹음.wav` → `inbox/transcripts/…_녹음.md`). whisperX 없으면 409 `no_asr`. 디코드 우선순위는 서버 `DecodeQueue`(final high > partial low; meeting은 final만) |
| POST | `/api/asr/:id/audio` | 본문 = 16kHz mono PCM16 → `{ events[{type,text,at,t0?,t1?}], partial, text }`. live는 partial(~350ms)·final, meeting은 final만 |
| POST | `/api/asr/:id/stop` | 남은 말을 flush → `{ events, partial, text, draft? }`. meeting이고 글이 있으면 `draft` = worklog 상대 경로의 초안 md(whisperX가 같은 stem을 덮어씀). 세션 제거 |
| DELETE | `/api/asr/:id` | 세션 취소 `{ ok }`. 진행 중·대기 중 decode는 abort(다른 세션의 긴 decode를 기다리지 않음) |
| POST | `/api/ask/cancel` | 진행 중인 질문을 멈춘다 `{ cancelled }`. 에이전트 CLI를 끝내고(Windows는 `taskkill /T`), OpenRouter 요청은 abort. 기다리던 `POST /api/ask`는 409 `{ error: "cancelled" }`, 대화에 저장하지 않음 |
| GET | `/api/file?path=` | worklog 안의 markdown·txt 원문 `{ path, markdown }` (검색 결과·기록 줄의 원문 보기) |
| GET | `/api/download?path=` | 원문 파일 자체를 첨부로 (`content-disposition`에 UTF-8 파일 이름). `/api/file`과 같은 경로 규칙: worklog 안의 .md·.txt, 추가 색인 폴더, 외부 소스 원문 |
| GET | `/api/origins?limit=` | 수집된 원본 목록 `{ files[{ path, source, kind: source\|inbox\|processed, date, name, bytes }] }` 최신순 — `sources/<이름>/<날짜>.md`, inbox·processed의 전사본·세션 노트 (메모리 탭 "원본") |
| GET | `/api/origin?src=` | 기록 줄의 `(src: …)` 텍스트 → `{ paths[] }`. `git <저장소> <해시>`는 git 날짜 파일에서 해시를 찾고, `<소스> YYYY-MM-DD`는 그 날짜 파일(`claude-code`는 agent-sessions로 폴백), `YYYY-MM-DD_제목`은 processed/inbox의 전사본·세션 노트 (`Worklog.resolveSource`) |
| GET / POST | `/api/index` | 색인 상태(+ `embedding`: 로컬 임베딩 데몬 상태 off/starting/ready/failed, + `tokenizer`: `{ active: multilingual\|whitespace\|unknown, needsReindex, kiwi{ installed, library, model, source: zaevis\|user\|system\|env, version, dir, asset, downloadMb } }` — 키워드(BM25) 색인이 Kiwi 형태소로 됐는지, Kiwi는 있는데 색인이 공백 기준이라 처음부터 다시 만들어야 하는지) · 색인 갱신 시작 (`{ force?: true }`). GET·POST 때 Kiwi가 새로 생겼으면 검색 자식을 재시작해 `KIWI_LIBRARY_PATH`·`KIWI_MODEL_PATH`를 넘긴다(`server/src/kiwi.ts` TokenizerGate; 색인 중에는 안 함). `needsReindex`는 force 갱신이 성공해야 풀린다(state.json `kiwiReindexPending`) |
| POST | `/api/logs` | 한 줄 기록 `{ text, tags[], projects[], date? }` |
| PUT / DELETE | `/api/logs/:YYYY-MM` | 한 줄 편집 `{ raw, text?, tags?, projects?, date? }` · 삭제 `{ raw }`. `raw`는 파일에 있는 현재 줄 그대로이며, 못 찾으면 409(다른 곳에서 바뀜). 정리가 쓴 줄의 `(src: …)`는 보존 |
| GET | `/api/inbox` | inbox 파일과 전사 작업 |
| POST | `/api/inbox/transcripts` · `/api/inbox/audio?name=` | 전사본 저장 · 녹음 업로드(본문 그대로, 최대 1GB) |
| GET / POST / PUT / DELETE | `/api/sources[/:name]` | 데이터소스 목록 · 사용자 커넥터 추가 · 설정 변경 · 삭제 |
| POST | `/api/sources/shell-history/enable-timestamps` | zsh 시각 기록 켜기: `~/.zshrc`(`$ZDOTDIR`가 있으면 그곳) 끝에 `setopt EXTENDED_HISTORY  # zaevis` 한 줄을 붙임 → `{ ok, file, changed }` (`changed: false` = 이미 켜져 있어 손대지 않음; 주석·`extendedhistory` 같은 다른 표기도 인식). 앱은 확인 대화상자 뒤에 부른다 (`server/src/sources/shellHistory.ts enableExtendedHistory`) |
| GET / POST | `/api/collect` | 수집 상태 · 수집 시작 (`{ sources?: [], index?: false }`) |
| GET | `/api/datasources` | 외부 AutoRAG 데이터소스: 템플릿마다 `{ name, template, title, description, fields[], cli{bin,install}, external, probe{installed, binPath, archive, env[{name,set}], unavailable}, configured, enabled, note, connector, channels, autorag(autorag.datasources.list의 항목), sync{lastSync, ok, error?, chunks?} }` + `syncing`, `lastRefresh`. 템플릿 목록·probe는 `server/src/datasources.ts` |
| PUT | `/api/datasources/:name` | 연결 만들기·고치기 `{ enabled?, description?, connector?, channels?, type?(별칭일 때 템플릿), sync?: false, secrets?: { ENV_NAME: 값 } }`. `secrets`는 secrets.json에 `env:ENV_NAME`으로 저장(""는 삭제)되고 `secretsEnv()`가 검색 자식 환경에 넣는다(probe의 `env[].stored`가 저장 여부). AutoRAG `config.json`의 `datasources.<name>`만 바꾸고(다른 키 보존) 검색 자식을 재시작한 뒤 켜져 있으면 `datasources` 단계만 refresh. 토큰·비밀번호처럼 보이는 키나 환경 변수 이름이 아닌 `tokenEnv`는 400 |
| DELETE | `/api/datasources/:name` | 연결 삭제 (설정 항목 제거 + 재시작) |
| CLI | `zaevis ext install kiwi [--force]` | 한국어 형태소 분석기(Kiwi) 설치 (API 아님; 설정 → 검색·색인 창·마법사의 버튼이 번들 실행기로 돌림). `server/src/kiwi.ts`: 고정 버전(`KIWI_VERSION`)의 GitHub 릴리스 자산(mac arm64/x86_64, Linux x64/arm64, Windows x64 + 공용 모델)을 sha256 표와 대조해 받아 `~/.zaevis/ext/kiwi/{lib/libkiwi.dylib, models/cong/base, VERSION}`에 품(정적 라이브러리·헤더는 버림). 찾기 순서는 kiwi-rs·AutoRAG와 같음: `KIWI_*` 환경 변수(있으면 절대적) → ext/kiwi → `~/.local/kiwi` → 시스템 폴더. 서버(`main.ts`)와 일일 작업(`daily.ts`)이 autorag-mcp 자식 env에 경로를 넣는다. 질의 때도 Kiwi를 쓰므로 지우면 처음부터 다시 색인 |
| CLI | `zaevis ext install <cli>` | 외부 소스 도구 설치 (API 아님; 앱 카드의 설치 버튼이 번들 실행기로 돌리고 로그를 보여 줌). 템플릿의 `cli.brew`(tap 포함) · `cli.release`(GitHub 최신 릴리스 자산 → `~/.zaevis/ext/bin`) · `cli.npm`(`~/.zaevis/ext/npm` prefix) 순. 검색 자식의 PATH는 `cliPath()`가 ext·brew·npm 폴더를 포함 |
| POST | `/api/datasources/:name/sync` | 외부 소스 동기화 시작 (202; AutoRAG는 연결별 갱신이 없어 전체를 돈다). 색인 중이면 409 |
| GET / PUT | `/api/settings` | 매일 실행 시각(launchd 재등록), 주입 즉시 색인, `localEmbedding`(의미 검색 켜기/끄기 — 켜면 데몬을 띄우고 처음부터 재색인), `notifications`(시스템 알림, 기본 켬), `hotkey`(전역 단축키 스펙 `"meta+shift+space"` 꼴, `""`=플랫폼 기본), `appearance{ theme: system|light|dark, textScale: 0.9|1|1.1|1.2|1.3, locale: system|ko|en }`(앱 화면·언어, 모르는 값은 기본으로), `language`(사용자 언어 코드 `ko`, 첫 실행 `setup --language`), `transcribeLanguage`(`user` = language를 따름 · `auto` = whisper 감지 · 언어 코드). GET에는 `rerank` 상태(`enabled, hasKey, keyHint, model, external`)와 `tokenizer`(`/api/index`와 같은 꼴) 포함 |
| PUT | `/api/settings/rerank` | OpenRouter 재정렬 `{ enabled?, model?, apiKey? }` — `apiKey: ""`는 키 삭제. 키는 `secrets.json`(0600)에 저장되고 응답엔 끝 4자리만. AutoRAG 설정의 `rerank`를 다시 쓰고 검색 자식 프로세스를 재시작 |
| POST | `/api/settings/rerank/test` | `{ apiKey? }` 키를 OpenRouter에 확인 (`{ ok, message }`), 저장하지 않음 |
| GET / PUT | `/api/digest` | 주간 정리(지식화): 감지된 에이전트(`agents[]`: claude/codex/gemini CLI, openrouter 키 — 항목마다 `available`, `detail`(버전), `loggedIn: true|false|null`, `loginHint`. claude는 `claude auth status`의 JSON(없는 옛 버전은 `claude -p ok --max-turns 1`의 "Not logged in"), codex는 `~/.codex/auth.json`·`OPENAI_API_KEY`, gemini는 `~/.gemini/oauth_creds.json`·`GEMINI_API_KEY`; 바이너리별 10분 캐시. `pickAgent`는 `loggedIn: false`인 CLI를 건너뛰고, 에이전트 없음 메시지(`noAgentReason`)가 로그인만 필요한 CLI를 이름으로 알려 준다. `/api/ask`·`/api/reports`의 `agents`·`chosen`도 같은 감지), 설정(`agent: auto|…`, `model`, `weekly`, `daily`, `review`), 실제로 돌 에이전트 `chosen`, 실행 중 여부와 `scope`(daily|weekly), 마지막 실행 `last`(`scope`, `days`, `changed`; 검토로 넘긴 것이 있으면 `proposalId`). `review`는 프로젝트 페이지·월간 정리만 제안으로 잡는다 — 끝까지 성공한 실행의 로그 줄과 처리한 inbox 파일은 바로 적용한다(실패한 실행은 전부 제안으로) |
| GET | `/api/launch` | `{ running, launch: { startedAt, finishedAt?, steps: [{ name: collect\|index\|digest, state: pending\|running\|done\|skipped\|failed, note?, startedAt?, finishedAt? }] } \| null }` — 앱 시작 화면이 1초마다 읽는다 |
| POST | `/api/launch` | 앱을 새로 띄울 때 한 번: 전체 수집(+색인, `POST /api/collect`와 같은 실행이며 진행 중이면 합류) → 하루 정리(수집이 건드린 날로, `startDigest("daily", { launch: true, touched })`). 정리는 "매일 정리"가 꺼져 있거나 마지막으로 잘 끝난 정리가 `LAUNCH_RECENT_MINUTES`(60분) 안이면 `skipped`와 이유. 202 |
| POST | `/api/digest/run` | `{ scope?: "daily" (기본) \| "weekly" }` 지금 정리 시작 (202). daily는 먼저 전체 수집 → `digestDays`(수집이 건드린 날 + 마지막 정리 뒤의 원본 날, 최근 14일) → `kit/claude/daily-task-prompt.md`(로그 줄·inbox만, projects/·summaries/·.state.md는 안 고침) → 끝나면 `.state.md`에 `last_daily: <마지막 날>`과 색인 갱신. 읽을 것이 없으면 에이전트를 부르지 않는다. weekly는 월요일과 같은 주간 정리. 쓸 수 있는 에이전트가 없거나 이미 실행 중이면 409 `{ started: false, reason }`. 질문(`/api/ask`)에서 에이전트가 첫 줄에 `정리:`를 쓰면 같은 daily 실행을 시작하고 `route.intent: "digest"`로 답한다 |
| GET | `/api/digest/proposals[/:id]` | 검토 대기 제안 목록(`id, createdAt, agent, status, lines, projects, summaries, processed`) · 하나의 내용(`logLines[{month,line,entry}]`, `removedLines`, `projects[{slug,before,after}]`, `summaries[{path,before,after}]`, `processed[{from,to}]`, `report`). 서버는 정리 전 스냅샷과 후를 비교해 제안을 만들고 worklog는 원상 복구한다(`server/src/review.ts`) |
| POST | `/api/digest/proposals/:id` | `{ action: "apply", lines?: [idx], projects?: [slug], summaries?: bool, processed?: bool }` 고른 부분만 worklog에 씀 (생략=전부) · `{ action: "dismiss" }`. pending이 아니면 409 |

GET이 아닌 요청은 `x-zaevis: 1` 헤더가 있어야 하고, 다른 사이트(Origin)나 다른 호스트 이름에서 온 요청은 거절합니다. 사용자 커넥터가 명령을 실행하기 때문에 넣은 보호 장치입니다.

설정은 `~/.zaevis/config.json`이고, 환경변수 `WORKLOG_DIR`, `AUTORAG_CONFIG`, `ZAEVIS_PORT`, `ZAEVIS_WEB_DIR`로 덮어쓸 수 있습니다.

AutoRAG Lite 검색 응답 형태는 공개 계약이 아니라서 `normalizeSearch()`가 흔한 필드 이름을 모두 받아 정규화합니다. AutoRAG를 올린 뒤 결과가 비어 보이면 이 함수부터 확인하세요.

외부 데이터소스 히트는 `source`가 `/obsidian/default/노트.md`처럼 불투명 경로이고 `metadata.datasourceId`가 붙습니다. `normalizeSearch()`는 그 경로를 그대로 두고, `context.ts`의 `classifyPath`가 `kind: "external"`, `datasource`, `sourceLabel`(템플릿의 한국어 제목)을 붙입니다. 원문이 로컬 파일인 소스(Obsidian)는 `metadata.path`를 `context.file`로 넘기고 `GET /api/file?path=/obsidian/…`가 볼트에서 읽어 줍니다. `autorag.search`는 `datasourceIds`를 주지 않으면 설정된 외부 소스를 모두 포함하므로 zaevis는 선택 없이 호출합니다.

## 앱 화면 추가

1. `app/lib/api.dart`에 API 메서드 추가
2. `app/lib/screens/`에 화면 추가
3. `app/lib/main.dart`의 `_dests`와 `_screen()`에 등록
4. 화면에 보이는 글은 `app/lib/l10n/app_ko.arb`(원본)와 `app_en.arb`에 같은 키로 넣고 `flutter gen-l10n`(또는 `flutter pub get`) 뒤 `context.l10n.키`로 씁니다. BuildContext가 없는 곳(모델·컨트롤러·`api.dart`)은 `l10nNow.키`

### 언어 (l10n)

앱은 한국어(기본)와 영어를 지원합니다. 설정 → 일반 → 언어 → 화면 언어(시스템·한국어·English)이고(같은 묶음의 '주로 쓰는 언어'는 전사 기본 언어 `language`로 별개), 값은 서버 `config.appearance.locale`에 저장돼 macOS 앱과 웹이 같은 언어를 씁니다. 시스템은 OS 언어가 한국어면 한국어, 그 밖에는 영어입니다(`l10n.dart resolveAppLocale`).

- 구조: `app/l10n.yaml` + `flutter_localizations`/gen_l10n. 생성 파일 `app/lib/l10n/app_localizations*.dart`도 커밋합니다.
- 테스트는 `test/flutter_test_config.dart`가 시스템 언어를 한국어로 두므로 한국어 문구로 찾습니다.
- **아직 한국어로만 나오는 것**: 서버가 만들어 앱이 그대로 보여 주는 글 — API 오류의 `message`, 시스템 알림, 상태 문구(`hint`, `loginHint`, 색인·전사 진행 메시지, 데이터소스 템플릿 제목 등, `server/src` 약 530곳). 다음 단계는 서버가 사람이 읽는 문장 대신 코드(`code` + 인자)를 함께 보내고 앱이 그 코드를 ARB 문자열로 바꾸는 것, 또는 요청 헤더 `Accept-Language`(앱 locale)를 보고 서버가 문장을 고르는 것입니다. 알림은 앱 밖에서 뜨므로 서버가 `config.appearance.locale`을 읽어 고르면 됩니다.
- 질문·리포트·정리 프롬프트와 그 결과(에이전트가 쓰는 글)는 언어 설정과 상관없이 한국어입니다.

외부 패키지는 `http` 하나만 씁니다. Markdown은 `widgets/markdown_view.dart`의 작은 렌더러가 worklog에서 쓰는 문법(제목, 목록, 체크박스, 코드, `[[링크]]`, `#태그`)만 처리합니다.

## 다른 사람에게 줄 때

- 저장소에는 개인 데이터가 없습니다. 받는 사람은 `kit/setup.sh`만 실행하면 자기 경로로 채워진 worklog가 생깁니다.
- 회사 저장소를 담은 폴더 안에 worklog를 만들면 `setup.sh`가 그 저장소의 `.git/info/exclude`에 등록해 커밋을 막습니다.
- 색인 범위는 worklog 폴더 하나입니다. 회사 코드나 메일을 색인하려면 각자 회사 정책을 먼저 확인하세요.

## CLI 명령 추가

`bin/zaevis`(bash)가 명령을 나누고, 서버 API를 쓰는 명령은 `server/src/cli.ts`의 `run()`으로 넘깁니다.
새 조회 명령은 `run()`에 case를 추가하고, `server/src/zaevis.ts`의 `search|s|ask|log|…` 목록에 이름을 더하면 됩니다.

## 데이터소스 커넥터 추가

**명령어로 (코드 수정 없이)**: 앱의 연결 탭 → 커넥터 추가, 또는 `~/.zaevis/sources.json`의 `custom`에 추가합니다.

```json
{ "custom": [ { "name": "calendar", "command": "python3 ~/bin/cal_export.py --since {from} --until {to}" } ] }
```

명령은 Markdown을 출력하면 됩니다. `{from}` `{to}`는 ISO 시각, `{fromDate}` `{toDate}`는 `YYYY-MM-DD`로 바뀝니다(`find -newermt {fromDate}`처럼 긴 형식을 못 읽는 도구용).
날짜별로 나누려면 `<!-- zaevis:date 2026-10-23 -->` 줄을 넣습니다. 앱의 프리셋 목록은 `app/lib/screens/collect_screen.dart`의 `ConnectorPreset.all`에 있습니다.

내장 소스의 옵션(`options[]`)에 `help`를 주면 앱이 입력란 아래 한 줄 설명으로 보여 줍니다. `kind: "bool"`은 스위치로 그려집니다.

**내장 커넥터로**: `server/src/sources/`에 `Source`(`types.ts`)를 구현하고 `sources/index.ts`의 `BUILTIN`에 추가합니다.
`collect()`는 수집 구간의 날짜별 Markdown을 돌려주고, 수집기가 `sources/<이름>/<날짜>.md`에 씁니다.
매번 하루 전체를 다시 만들어 덮어쓰는 방식이라 같은 날 여러 번 돌려도 중복이 생기지 않습니다(이벤트형은 `append: true`).
