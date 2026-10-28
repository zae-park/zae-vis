# zaevis TODO

우선순위 순. 끝난 항목은 지우고 CLAUDE.md "현재 상태"에 한 줄로 남긴다.

1. **자동 업데이트** — 앱이 새 DMG를 확인·내려받아 교체. 지금은 DMG를 열어 끌어다 놓는 수동 절차. **빌드를 Cloud Build에 연결한 뒤** 그 아티팩트 저장소를 갱신 원천으로 삼아 진행하기로 (2026-10-27, 사용자 결정). 권한 설정이 번거로워 지금은 보류.
2. **번들 용량** — 약 520MB 중 onnxruntime-node 287MB 등 AutoRAG 의존성 정리. 1번과 함께 Cloud Build 파이프라인에서 다룬다.
3. **셸 이력** — `setopt EXTENDED_HISTORY`가 없는 zsh 이력(시각 없음)도 수집할지 결정.
4. **한국어 형태소 키워드 검색** — AutoRAG가 `lexical-tokenizer-unavailable`(Kiwi 네이티브 라이브러리·모델 없음)을 경고한다. 번들에 Kiwi를 넣으면 `연구목표`·`인증서를` 같은 활용형도 키워드로 매치된다.
5. **정리 품질** — 에이전트 CLI 로그인 여부 감지(지금은 실행해 봐야 "Not logged in"을 안다), 전사본이 없을 때 녹음을 먼저 전사하도록 안내.
6. **외부 소스 더 깊게** — 외부 데이터소스는 Obsidian만 실제로 확인했다. CLI가 있는 Mac에서 Slack·Notion 아카이브를 연결해 보고, 채널 allowlist(`channels`)·별칭(한 템플릿에 연결 여러 개) 편집 UI, 외부 히트의 원문 열기(지금은 Obsidian만, Slack 등은 404), 매일 색인 때 외부 동기화 결과 알림을 붙인다.

끝난 것: 리포트 일간·주간·월간(2026-10-27, `server/src/reports.ts`, `/api/reports`, 앱 `reports_screen.dart`, `zaevis report`) · 외부 데이터소스 연결(2026-10-27, `server/src/datasources.ts`, `/api/datasources`, 수집 화면 "외부 소스 (AutoRAG)") · 질문에 답하기(RAG, 2026-10-27, `server/src/ask.ts`, 앱 검색 화면 검색/질문 전환, `zaevis ask`) · 정리 결과 검토(2026-10-27, `server/src/review.ts`, 앱 `review_screen.dart`) · 알림(`notify.ts`) · 전역 단축키 변경 · 검색 필터 · 색인 진행 표시 · 커넥터 프리셋 · 에이전트 세션 소스(`sources/agents.ts`, 요청→응답 쌍) · 로컬 임베딩 검색 (2026-10-26, `server/src/embedding.ts`) · 검색 결과 맥락 (2026-10-26, `server/src/context.ts`, 앱 `file_screen.dart`) · OpenRouter 재정렬 설정 (2026-10-26, `server/src/rerank.ts`; Lite가 쓰는 외부 모델은 이것뿐이라 Jev·질의 분해 설정은 만들지 않음) · 앱 내 녹음 (2026-10-26, `app/lib/recording/`, `widgets/record_dialog.dart`) · 주간 정리 자동화 (2026-10-26, `server/src/digest.ts`: 설치된 에이전트 CLI나 OpenRouter 키로 README 절차를 실행).
