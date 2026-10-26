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
클라우드 세션에서 작성했고, 그 환경엔 Flutter·macOS가 없어 아래는 **한 번도 실행되지 않았다**. 여기서부터 이어서 할 일:
1. `flutter analyze`, `flutter test` 통과시키기 (정적 검토만 받은 코드)
2. `tool/package_macos.sh`로 DMG 만들기 — Node 다운로드, `npm ci`, `cargo install minsync`(protoc 필요), 웹·macOS 빌드, ad-hoc 서명
3. DMG 설치본으로 첫 실행 마법사 → 서버 시작 → 첫 수집 → 검색까지 확인
4. launchd 예약 등록 확인: `launchctl print gui/$(id -u)/io.github.zaepark.zaevis.daily`
5. 설정 화면의 whisperX 설치 확인 (uv 설치 스크립트 `UV_UNMANAGED_INSTALL` 동작, imageio-ffmpeg 링크)

## 규칙
- `~/jaepark` 상위 폴더는 회사 저장소 원격에 연결돼 있다. zaevis·worklog는 `.git/info/exclude`로 제외되어 있으니 그 저장소에 커밋하지 말 것.
- 사용자 worklog는 `~/jaepark/worklog`. 실험은 `ZAEVIS_HOME=/tmp/zv-test` 같은 별도 상태 폴더로 할 것 (실제 `~/.zaevis` 오염 금지).
- 커밋 메시지는 한국어.
