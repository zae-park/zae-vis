# zaevis TODO

우선순위 순. 끝난 항목은 지우고 CLAUDE.md "현재 상태"에 한 줄로 남긴다.

1. **자동 업데이트** — 앱이 새 DMG를 확인·내려받아 교체. 지금은 DMG를 열어 끌어다 놓는 수동 절차.
2. **번들 용량** — 약 500MB 중 onnxruntime-node 287MB 등 AutoRAG 의존성 정리.
3. **셸 이력** — `setopt EXTENDED_HISTORY`가 없는 zsh 이력(시각 없음)도 수집할지 결정.
4. **Intel Mac DMG** — Intel Mac에서 한 번 빌드.
5. **한국어 형태소 키워드 검색** — AutoRAG가 `lexical-tokenizer-unavailable`(Kiwi 네이티브 라이브러리·모델 없음)을 경고한다. 번들에 Kiwi를 넣으면 `연구목표`·`인증서를` 같은 활용형도 키워드로 매치된다.
6. **정리 품질** — 에이전트 CLI 로그인 여부 감지(지금은 실행해 봐야 "Not logged in"을 안다), 정리 결과 미리 보기·되돌리기, 전사본이 없을 때 녹음을 먼저 전사하도록 안내.

끝난 것: 로컬 임베딩 검색 (2026-10-26, `server/src/embedding.ts`) · 검색 결과 맥락 (2026-10-26, `server/src/context.ts`, 앱 `file_screen.dart`) · OpenRouter 재정렬 설정 (2026-10-26, `server/src/rerank.ts`; Lite가 쓰는 외부 모델은 이것뿐이라 Jev·질의 분해 설정은 만들지 않음) · 앱 내 녹음 (2026-10-26, `app/lib/recording/`, `widgets/record_dialog.dart`) · 주간 정리 자동화 (2026-10-26, `server/src/digest.ts`: 설치된 에이전트 CLI나 OpenRouter 키로 README 절차를 실행).
