# zaevis — Claude Code 작업 안내

개인 작업 기록·지식 관리 도구. 데이터소스를 매일 수집(git, Claude Code 세션, zsh 이력, 전사본, 사용자 커넥터)하고,
실시간 주입(한 줄 기록·전사본·녹음→whisperX)을 받고, AutoRAG Lite로 색인·검색하고, Flutter 앱(macOS·웹)과 `zaevis` CLI로 쓴다.
사용자 문서는 README.md, 구조·API는 docs/customizing.md.

## 구조
- `server/` Node 24 TypeScript(빌드 없이 `node src/*.ts`). `main.ts` API 서버(127.0.0.1:4710), `daily.ts` 수집+색인,
  `cli.ts` 터미널 클라이언트, `sources/` 커넥터, `schedule.ts` launchd, `transcribe.ts` whisperX
- `app/` Flutter. `lib/backend/` 앱 번들 안의 서버 관리(`backend_io.dart`), `screens/onboarding_screen.dart` 첫 실행 마법사
- `bin/zaevis` CLI(bash), `kit/setup.sh` 초기 설정, `tool/package_macos.sh` DMG 패키징
- 앱 번들 레이아웃: `zaevis.app/Contents/Resources/zaevis/{node/bin/node, bin/{zaevis,minsync}, server/, kit/, web/}`

## 검증 명령
- 서버: `cd server && npm install && npm test` (35개 통과 상태)
- 앱: `cd app && tool/setup_platforms.sh && flutter pub get && flutter analyze && flutter test`
- DMG: `tool/package_macos.sh` → `dist/zaevis-<ver>-<arch>.dmg`

## 현재 상태 (2026-10-26)
이 Mac(Apple Silicon)에서 아래를 모두 실행·확인했다.
- `flutter analyze` 0건, `flutter test` 10개, 서버 테스트 35개 통과
- `tool/package_macos.sh` → `dist/zaevis-0.1.0-arm64.dmg` (약 490MB: MinSync 274MB, server/node_modules 707MB 중 onnxruntime-node 287MB)
  - 빌드 Mac에 **cmake**가 추가로 필요하다 (minsync 의존성 protobuf-src가 protobuf를 소스 빌드). Rust는 `~/.cargo/bin`에 있으니 PATH에 넣을 것
- 첫 실행 흐름은 `tool/smoke_firstrun.sh [zaevis.app]`로 재현한다: 임시 HOME·ZAEVIS_HOME에서 마법사가 보내는 인자 그대로
  setup → 서버 → 첫 수집 → 색인 → 검색까지 돌리고, 등록한 launchd 예약은 끝에 해제한다
- 별도 `ZAEVIS_HOME`은 launchd 라벨도 `io.github.zaepark.zaevis.daily.<폴더명>-<해시>`로 분리된다 (테스트가 실제 예약을 내리지 않도록)
- GUI 자체는 `ZAEVIS_HOME`을 바꿔 띄워 확인: 설정이 있으면 `zaevis start` 후 API를 호출하고, 없으면 마법사 화면(서버 호출 없음)
- 의미 검색: 서버가 `minsync serve`(Qwen3-Embedding-0.6B, Metal)를 자식으로 띄운다(`server/src/embedding.ts`). AutoRAG는 `~/.cache/minsync/serve/*/port`와 `/health`로 데몬을 찾아 채택한다.
  설정 `localEmbedding`(기본 켬), 켜면 force 재색인. 일일 작업은 idle 300초짜리 데몬을 detached로 띄운다. 모델은 `~/.cache/minsync/models`(1.1GB)
- 검색 결과 맥락: `server/src/context.ts`가 경로로 출처·날짜, 청크 안에서 질의에 가장 잘 맞는 문단(한국어 2글자 조각 매칭), 위쪽 `## 제목`(섹션), git 줄의 작성자를 뽑는다. 상위 대비 0.2 미만은 `weak`. 원문은 `GET /api/file?path=` → 앱 `file_screen.dart`
- whisperX: `zaevis ext install whisperx`로 uv(`UV_UNMANAGED_INSTALL` → `$ZAEVIS_HOME/ext/uv`)·whisperx 3.8.6·imageio-ffmpeg 링크 확인, 설정 API `whisperx: true`

남은 일
- Claude Code 세션엔 손쉬운 사용·화면 녹화 권한이 없어 GUI 클릭·스크린샷은 자동화하지 못했다. 마법사 버튼 클릭은 사람이 한 번 눌러 확인할 것
- shell-history는 `setopt EXTENDED_HISTORY`가 없는 zsh 이력에서 시각이 없어 실패한다 (안내 메시지는 나온다)

## 규칙
- `~/jaepark` 상위 폴더는 회사 저장소 원격에 연결돼 있다. zaevis·worklog는 `.git/info/exclude`로 제외되어 있으니 그 저장소에 커밋하지 말 것.
- 사용자 worklog는 `~/jaepark/worklog`. 실험은 `ZAEVIS_HOME=/tmp/zv-test` 같은 별도 상태 폴더로 할 것 (실제 `~/.zaevis` 오염 금지).
- 커밋 메시지는 한국어.
