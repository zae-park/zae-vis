# zaevis TODO

우선순위 순. 끝난 항목은 지우고 CLAUDE.md "현재 상태"에 한 줄로 남긴다.

1. **스트리밍 ASR 실측** — `e83d7e7`의 live·meeting 세션(`server/src/asr.ts`, 앱 `recording/asr_capture.dart`)을 실제 Mac에서 재 본다: partial 지연, final 정확도, whisperX 교체 전 초안 품질. VAD는 고정 RMS 0.012라 마이크·소음이 바뀌면 끊김 판정이 흔들릴 수 있다(소음 바닥 적응 또는 Silero VAD 검토). 끝나면 CLAUDE.md '현재 상태'에 항목 추가.
2. **서버 문구 다국어화** — 오류 `message`·알림·`hint`·진행 문구(`server/src` 약 530곳)가 한국어뿐. 응답에 `code`+인자를 붙여 앱이 ARB로 바꾸고, 알림은 `config.appearance.locale`로 서버가 고른다(docs/customizing.md '언어').
3. **Windows 상주 실행** — 시작 프로그램 등록과 창 없이 백그라운드로 도는 서버.
4. **클라우드·브라우저 접속** — 서버를 원격에 두고 브라우저로 쓰기. 인증(지금은 127.0.0.1 전용·무인증), 수집기(사용자 컴퓨터)와 서버(클라우드) 분리, 저장 데이터 암호화, 에이전트 CLI 대신 API 모델.
5. **정리 안내** — 전사본이 없을 때 녹음을 먼저 전사하도록 안내.
6. **외부 소스 더 깊게** — 외부 데이터소스는 Obsidian만 실제로 확인했다. CLI가 있는 Mac에서 Slack·Notion 아카이브를 연결해 보고, 채널 allowlist(`channels`)·별칭(한 템플릿에 연결 여러 개) 편집 UI, 외부 히트의 원문 열기(지금은 Obsidian만, Slack 등은 404), 매일 색인 때 외부 동기화 결과 알림을 붙인다.
7. **로마자 질문을 한글로 다시 검색** — 빈 검색은 한글로 물어보라고 안내한다. 질문의 로마자를 한글 표기로 바꿔 한 번 더 찾는 것은 아직 없다 (로제타 / rosetta).
8. **검토 대기 단계** — 녹음 줄은 inbox에 있으면 정리 대기까지다. 대기 중인 정리 제안이 그 전사를 인용하면 '검토 대기'로 바꿀 것. 제안 목록 API는 파일 이름을 주지 않는다.
9. **출처 개수** — 파일 화면의 처리된 전사는 '출처 연결'이라고만 한다. 그 파일을 인용한 기록 줄이 몇 개인지는 메모리 원본에만 있다.

끝난 것: 비밀 마스킹 보강(2026-11-26, `server/src/redact.ts`: 새 토큰 모양, 전사본·회의 초안·한 줄 기록, 외부로 나가는 프롬프트, `zaevis redact [--apply]`) · 리포트 일간·주간·월간(2026-10-27, `server/src/reports.ts`, `/api/reports`, 앱 `reports_screen.dart`, `zaevis report`) · 외부 데이터소스 연결(2026-10-27, `server/src/datasources.ts`, `/api/datasources`, 수집 화면 "외부 소스 (AutoRAG)") · 질문에 답하기(RAG, 2026-10-27, `server/src/ask.ts`, 앱 검색 화면 검색/질문 전환, `zaevis ask`) · 정리 결과 검토(2026-10-27, `server/src/review.ts`, 앱 `review_screen.dart`) · 알림(`notify.ts`) · 전역 단축키 변경 · 검색 필터 · 색인 진행 표시 · 커넥터 프리셋 · 에이전트 세션 소스(`sources/agents.ts`, 요청→응답 쌍) · 로컬 임베딩 검색 (2026-10-26, `server/src/embedding.ts`) · 검색 결과 맥락 (2026-10-26, `server/src/context.ts`, 앱 `file_screen.dart`) · OpenRouter 재정렬 설정 (2026-10-26, `server/src/rerank.ts`; Lite가 쓰는 외부 모델은 이것뿐이라 Jev·질의 분해 설정은 만들지 않음) · 앱 내 녹음 (2026-10-26, `app/lib/recording/`, `widgets/record_dialog.dart`) · 주간 정리 자동화 (2026-10-26, `server/src/digest.ts`: 설치된 에이전트 CLI나 OpenRouter 키로 README 절차를 실행) · 한국어 형태소 검색(Kiwi, `server/src/kiwi.ts`) · 에이전트 로그인 감지(`digest.ts` `loggedIn`) · 앱 안 자동 업데이트(2026-10-29, `app/lib/update.dart`, `update_apply.dart`) · 설치본에서 다른 기종 ONNX·비-LSTM tesseract 코어 제거(`tool/prune_modules.mjs`) · 시각 없는 셸 이력 수집(2026-10-29, `shellHistory.ts`: 시각이 없는 명령은 수집한 날에 묶고, 다음 날에는 같은 명령을 다시 넣지 않음).
