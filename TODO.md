# zaevis TODO

우선순위 순. 끝난 항목은 지우고 CLAUDE.md "현재 상태"에 한 줄로 남긴다.

1. **정리 안내** — 전사본이 없을 때 녹음을 먼저 전사하도록 안내.
2. **외부 소스 더 깊게** — 외부 데이터소스는 Obsidian만 실제로 확인했다. CLI가 있는 Mac에서 Slack·Notion 아카이브를 연결해 보고, 채널 allowlist(`channels`)·별칭(한 템플릿에 연결 여러 개) 편집 UI, 외부 히트의 원문 열기(지금은 Obsidian만, Slack 등은 404), 매일 색인 때 외부 동기화 결과 알림을 붙인다.

끝난 것: 리포트 일간·주간·월간(2026-10-27, `server/src/reports.ts`, `/api/reports`, 앱 `reports_screen.dart`, `zaevis report`) · 외부 데이터소스 연결(2026-10-27, `server/src/datasources.ts`, `/api/datasources`, 수집 화면 "외부 소스 (AutoRAG)") · 질문에 답하기(RAG, 2026-10-27, `server/src/ask.ts`, 앱 검색 화면 검색/질문 전환, `zaevis ask`) · 정리 결과 검토(2026-10-27, `server/src/review.ts`, 앱 `review_screen.dart`) · 알림(`notify.ts`) · 전역 단축키 변경 · 검색 필터 · 색인 진행 표시 · 커넥터 프리셋 · 에이전트 세션 소스(`sources/agents.ts`, 요청→응답 쌍) · 로컬 임베딩 검색 (2026-10-26, `server/src/embedding.ts`) · 검색 결과 맥락 (2026-10-26, `server/src/context.ts`, 앱 `file_screen.dart`) · OpenRouter 재정렬 설정 (2026-10-26, `server/src/rerank.ts`; Lite가 쓰는 외부 모델은 이것뿐이라 Jev·질의 분해 설정은 만들지 않음) · 앱 내 녹음 (2026-10-26, `app/lib/recording/`, `widgets/record_dialog.dart`) · 주간 정리 자동화 (2026-10-26, `server/src/digest.ts`: 설치된 에이전트 CLI나 OpenRouter 키로 README 절차를 실행) · 한국어 형태소 검색(Kiwi, `server/src/kiwi.ts`) · 에이전트 로그인 감지(`digest.ts` `loggedIn`) · 앱 안 자동 업데이트(2026-10-29, `app/lib/update.dart`, `update_apply.dart`) · 설치본에서 다른 기종 ONNX·비-LSTM tesseract 코어 제거(`tool/prune_modules.mjs`) · 시각 없는 셸 이력 수집(2026-10-29, `shellHistory.ts`: 시각이 없는 명령은 수집한 날에 묶고, 다음 날에는 같은 명령을 다시 넣지 않음).
