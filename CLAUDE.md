# zaevis — Claude Code 작업 안내

개인 작업 기록·지식 관리 도구. 데이터소스를 매일 수집(git, Claude Code 세션, zsh 이력, 전사본, 사용자 커넥터)하고,
실시간 주입(한 줄 기록·전사본·녹음→whisperX)을 받고, AutoRAG Lite로 색인·검색하고, Flutter 앱(macOS·웹)과 `zaevis` CLI로 쓴다.
사용자 문서는 README.md, 구조·API는 docs/customizing.md.

## 구조
- `server/` Node 24 TypeScript(빌드 없이 `node src/*.ts`). `main.ts` API 서버(127.0.0.1:4710), `daily.ts` 수집+색인,
  `cli.ts` 터미널 클라이언트, `sources/` 커넥터, `schedule.ts` launchd, `transcribe.ts` whisperX
- `app/` Flutter. `lib/backend/` 앱 번들 안의 서버 관리(`backend_io.dart`), `screens/onboarding_screen.dart` 첫 실행 마법사
- `zaevis` 명령의 실제 구현은 `server/src/zaevis.ts`(시작/중지/상태, run, setup, doctor, install, ext whisperx, 나머지는 cli.ts·daily.ts 위임)와 `server/src/setup.ts`(옛 kit/setup.sh). `bin/zaevis`(sh)·`bin/zaevis.cmd`는 Node를 찾아 그 파일을 실행하는 래퍼일 뿐. 셸 스크립트에 로직을 넣지 말 것
- 플랫폼: macOS(launchd, DMG `tool/package_macos.sh`), Windows(작업 스케줄러 `schtasks`, `tool/package_windows.ps1` → zip), web(서버가 `web/`를 서빙), Linux(cron 힌트). `schedule.ts`가 OS별 분기. CI(`.github/workflows/ci.yml`)가 세 OS에서 서버 테스트, mac·Windows 앱 빌드, 태그/수동 실행 시 설치본 패키징
- 앱 번들 레이아웃: macOS `zaevis.app/Contents/Resources/zaevis/`, Windows `zaevis.exe` 옆 `zaevis\` — 안에 `{node/(bin/node | node.exe), bin/{zaevis,zaevis.cmd,minsync}, server/, kit/, web/, VERSION}`. 앱(`backend_io.dart`)은 번들 node로 `server/src/zaevis.ts`를 직접 실행

## 검증 명령
- 서버: `cd server && npm install && npm test` (35개 통과 상태)
- 앱: `cd app && tool/setup_platforms.sh && flutter pub get && flutter analyze && flutter test`
- DMG: `tool/package_macos.sh` → `dist/zaevis-<ver>-<arch>.dmg`

## 현재 상태 (2026-10-27)
이 Mac(Apple Silicon)에서 아래를 모두 실행·확인했다.
- `flutter analyze` 0건, `flutter test` 28개, 서버 테스트 73개 통과
- `tool/package_macos.sh` → `dist/zaevis-0.1.0-arm64.dmg` (약 490MB: MinSync 274MB, server/node_modules 707MB 중 onnxruntime-node 287MB)
  - 빌드 Mac에 **cmake**가 추가로 필요하다 (minsync 의존성 protobuf-src가 protobuf를 소스 빌드). Rust는 `~/.cargo/bin`에 있으니 PATH에 넣을 것
- 첫 실행 흐름은 `tool/smoke_firstrun.sh [zaevis.app]`로 재현한다: 임시 HOME·ZAEVIS_HOME에서 마법사가 보내는 인자 그대로
  setup → 서버 → 첫 수집 → 색인 → 검색까지 돌리고, 등록한 launchd 예약은 끝에 해제한다
- 별도 `ZAEVIS_HOME`은 launchd 라벨도 `io.github.zaepark.zaevis.daily.<폴더명>-<해시>`로 분리된다 (테스트가 실제 예약을 내리지 않도록)
- GUI 자체는 `ZAEVIS_HOME`을 바꿔 띄워 확인: 설정이 있으면 `zaevis start` 후 API를 호출하고, 없으면 마법사 화면(서버 호출 없음)
- 의미 검색: 서버가 `minsync serve`(Qwen3-Embedding-0.6B, Metal)를 자식으로 띄운다(`server/src/embedding.ts`). AutoRAG는 `~/.cache/minsync/serve/*/port`와 `/health`로 데몬을 찾아 채택한다.
  설정 `localEmbedding`(기본 켬), 켜면 force 재색인. 일일 작업은 idle 300초짜리 데몬을 detached로 띄운다. 모델은 `~/.cache/minsync/models`(1.1GB)
- 검색 결과 맥락: `server/src/context.ts`가 경로로 출처·날짜, 청크 안에서 질의에 가장 잘 맞는 문단(한국어 2글자 조각 매칭), 위쪽 `## 제목`(섹션), git 줄의 작성자를 뽑는다. 상위 대비 0.2 미만은 `weak`. 원문은 `GET /api/file?path=` → 앱 `file_screen.dart`
- 외부 provider: AutoRAG Lite 검색이 쓰는 외부 모델은 **OpenRouter 재정렬(rerank)** 하나뿐이다(Jev·질의 분해는 Lite 경로에서 쓰이지 않음). `server/src/rerank.ts`가 키(`secrets.json` 0600)·설정(`config.rerank`)·AutoRAG `config.json`의 `rerank` 항목·검색 자식의 `OPENROUTER_API_KEY`를 관리한다. setup.sh는 lite init 뒤 `rerank: false`로 두고 jev/queryDecomposition을 지운다
- 앱 내 녹음: `record` 플러그인으로 16kHz 모노 PCM 스트림을 받아 메모리에서 WAV로 만들어 `/api/inbox/audio`에 올린다(`app/lib/recording/recorder.dart`, `widgets/record_dialog.dart`; 앱바 마이크 버튼·수집 탭 "녹음하기"). macOS는 `setup_platforms.sh`가 Info.plist `NSMicrophoneUsageDescription`과 `audio-input` entitlement를 넣는다(없으면 마이크 접근 시 앱이 죽음). 테스트는 `Recorder` 인터페이스의 가짜 구현으로
- 주간 정리(지식화): `server/src/digest.ts`. `detectAgents()`가 PATH+흔한 설치 경로에서 claude/codex/gemini CLI를, 저장된 키로 openrouter를 감지. `auto`는 CLI 우선. CLI는 worklog를 cwd로 `kit/claude/weekly-task-prompt.md`를 비대화형 실행(claude: `-p --permission-mode acceptEdits --allowedTools …`, codex: `exec --full-auto`, gemini: `-p --yolo`). openrouter는 서버가 직접 입력(마지막 정리 이후 sources + inbox)을 모아 JSON 계획을 받고 `applyPlan`으로 로그·프로젝트·processed·.state.md를 쓴다. 매주 월요일 `daily.ts`가 수집 뒤 `weeklyDue`면 실행. API `/api/digest`, CLI `zaevis digest [--run]`, 앱 설정 "정리 (지식화)". 격리 테스트 때 HOME을 가짜로 두면 Claude Code가 "Not logged in"이 되니 실제 HOME으로 돌릴 것
- UI: `app/lib/theme.dart`(ZaevisTheme: Pretendard 번들 폰트, 종이색 바탕, 잉크 블루 강조, 평면 카드+헤어라인), 넓은 창은 `main.dart`의 `_Sidebar`+`_PageHeader`, 공통 `EmptyPane`(첫 줄 제목)·`SectionHeader`·`Panel`. **화면 확인은 웹 빌드로**: `flutter build web` → `ZAEVIS_WEB_DIR=app/build/web ZAEVIS_PORT=4712 bin/zaevis start` → 내장 브라우저(`preview_start`)로 스크린샷. macOS 화면은 권한이 없어 못 본다. SelectableText엔 `minLines`를 줄 것(maxLines만 주면 그 높이를 통째로 차지)
- 단축키: `app/lib/shortcuts.dart`가 정의·메뉴·설정 목록의 단일 출처. `ShortcutScope`(CallbackShortcuts)가 홈 셸을 감싸고, 전역 ⌘⇧Space는 hotkey_manager(시스템 범위)+window_manager(창 앞으로). macOS 메뉴는 `PlatformMenuBar`. 테스트·웹은 `ZaevisApp(desktopIntegration: false)`로 끈다. 위젯 테스트에서 ⌘는 `sendKeyDownEvent(metaLeft)`로
- whisperX: `zaevis ext install whisperx`로 uv(`UV_UNMANAGED_INSTALL` → `$ZAEVIS_HOME/ext/uv`)·whisperx 3.8.6·imageio-ffmpeg 링크 확인, 설정 API `whisperx: true`
- 정리 검토 흐름(2026-10-27): `server/src/review.ts`. `DigestRunner`가 `review` 모드면 실행 전 `takeSnapshot`(log/·projects/·summaries/·.state.md·inbox 목록) → 실행 → `diffSnapshot` → `restoreSnapshot`으로 worklog를 되돌리고 `$ZAEVIS_HOME/digest/proposals/<id>.json`에 제안 저장. `applyProposal(root, p, {lines?, projects?, summaries?, processed?})`가 고른 것만 씀(지운 줄은 복구하지 않음). 앱 `screens/review_screen.dart`, 로그 탭 배너, 설정 "검토 대기"
- 알림: `server/src/notify.ts` — macOS `osascript display notification`, Windows PowerShell WinRT 토스트, Linux notify-send. `config.notifications`로 끔. 호출처: 정리 끝(제안 준비/완료/실패), `daily.ts` 수집 실패, 제안 적용, 전사 완료/실패
- 에이전트 세션 소스(`server/src/sources/agents.ts`, 이름 `agent-sessions`)가 claude-code 소스를 대체: Claude Code·Codex CLI(`~/.codex/sessions` rollout JSONL)·Gemini CLI(`~/.gemini/tmp/**/chats`)·ChatGPT 내보내기(`conversations.json`)를 하루 파일에 `## <도구> · HH:MM–HH:MM 제목`으로 합친다. 세션 요약은 요청→응답 쌍(`replies[i]`는 `prompts[i]`에 대한 마지막 텍스트 답, `replyGist`로 400자), 수정 파일, 명령. 옵션 `kind: "bool"` + `help`
- 전역 단축키 변경: 서버 `settings.hotkey`에 `"meta+shift+space"` 꼴로 저장(정규식 `^[a-z0-9+]{0,60}$`). 앱 `shortcuts.dart`의 `HotkeySpec`(parse/label/fromEvent, 수정키 없는 키 거부)·`GlobalHotkey.register(cb, spec)`/`update(spec)`. 홈 셸이 시작 때 설정을 읽어 등록. 설정의 녹화 대화상자는 hotkey_manager의 HotKeyRecorder 대신 `Focus.onKeyEvent`로 직접 받는다(수정키 단독 입력을 걸러야 해서)
- 검색 필터: 앱이 `topK=40`으로 받아 `context.kind`(출처)와 `context.date`(기간: 7일·30일·이번 달, 월 파일은 말일 기준, 날짜 없는 히트는 '전체'에서만)로 거른다. `SearchPeriod`·`SearchScreen.clock`(테스트용 시계)
- 색인 진행: AutoRAG `status.progress`(`phase: parsed|minsync|datasources|jikji|everything|fsearch|finalizing`, `sourceFiles.total`, `parsedCounts.scanned`, `minsync.synced`)를 `IndexProgress.fraction`(읽기 60%·임베딩 30%·나머지 10%)으로 합쳐 막대 하나로. 색인 중엔 2초 폴링
- 커넥터 추가 대화상자: `ConnectorPreset.all`(폴더의 노트 `find -newermt {fromDate}`, macOS 캘린더 icalBuddy, 직접 입력). 추가하면 그 소스만 바로 수집하고 카드를 펼쳐 결과를 보여 준다. 명령 치환에 `{fromDate}`/`{toDate}` 추가
- 위젯 테스트 요령: 설정처럼 lazy하지 않은 ListView는 `scrollUntilVisible`이 바로 끝나므로 `dragUntilVisible(finder.hitTestable(), <ListView 안의 Scrollable>, Offset(0,-250))`로. `find.byType(Scrollable).first`는 TextField의 것일 수 있다. 버튼 안 스피너가 도는 동안은 `pumpAndSettle` 대신 `pump(duration)`

남은 일
- Claude Code 세션엔 손쉬운 사용·화면 녹화 권한이 없어 GUI 클릭·스크린샷은 자동화하지 못했다. 마법사 버튼 클릭은 사람이 한 번 눌러 확인할 것
- shell-history는 `setopt EXTENDED_HISTORY`가 없는 zsh 이력에서 시각이 없어 실패한다 (안내 메시지는 나온다)
- 검색은 BM25+로컬 임베딩의 하이브리드 **랭킹**까지다. 질문에 답을 쓰는 RAG(검색한 문단을 로컬 에이전트 CLI/OpenRouter에 넣어 답+출처)는 아직 없다 — 다음 작업 후보

## 규칙
- `~/jaepark` 상위 폴더는 회사 저장소 원격에 연결돼 있다. zaevis·worklog는 `.git/info/exclude`로 제외되어 있으니 그 저장소에 커밋하지 말 것.
- 사용자 worklog는 `~/jaepark/worklog`. 실험은 `ZAEVIS_HOME=/tmp/zv-test` 같은 별도 상태 폴더로 할 것 (실제 `~/.zaevis` 오염 금지).
- 커밋 메시지는 한국어.
