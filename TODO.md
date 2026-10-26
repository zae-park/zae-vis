# zaevis TODO

우선순위 순. 끝난 항목은 지우고 CLAUDE.md "현재 상태"에 한 줄로 남긴다.

1. **외부 provider 설정 화면** — rerank·Jev·질의 분해용 키(OpenRouter/TypeSafe/Vercel) 연결. 키는 `secrets.json`(0600)에, 응답엔 마지막 4자리만.
2. **앱 내 녹음** — 마이크로 녹음해 바로 whisperX 전사 대기열로. macOS 마이크 권한 처리.
3. **자동 업데이트** — 앱이 새 DMG를 확인·내려받아 교체. 지금은 DMG를 열어 끌어다 놓는 수동 절차.
4. **월간 정리 자동화** — 지금은 Claude 예약 작업 프롬프트만 제공. 앱이 로컬 모델이나 연결된 provider로 초안을 쓸지 결정.
5. **번들 용량** — 약 500MB 중 onnxruntime-node 287MB 등 AutoRAG 의존성 정리.
6. **셸 이력** — `setopt EXTENDED_HISTORY`가 없는 zsh 이력(시각 없음)도 수집할지 결정.
7. **Intel Mac DMG** — Intel Mac에서 한 번 빌드.
8. **한국어 형태소 키워드 검색** — AutoRAG가 `lexical-tokenizer-unavailable`(Kiwi 네이티브 라이브러리·모델 없음)을 경고한다. 번들에 Kiwi를 넣으면 `연구목표`·`인증서를` 같은 활용형도 키워드로 매치된다.

끝난 것: 로컬 임베딩 검색 (2026-10-26, `server/src/embedding.ts`) · 검색 결과 맥락 (2026-10-26, `server/src/context.ts`, 앱 `file_screen.dart`).
