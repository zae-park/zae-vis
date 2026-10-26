# zaevis TODO

우선순위 순. 끝난 항목은 지우고 CLAUDE.md "현재 상태"에 한 줄로 남긴다.

1. **로컬 임베딩 검색** — 번들 MinSync로 `minsync serve`를 서버가 띄워 키워드+의미 하이브리드 검색. 외부 키 불필요.
   진행 중 (2026-10-26).
2. **검색 결과 맥락** — 결과마다 날짜·출처(git/Claude/전사본/한 줄 기록)·프로젝트·작성자를 보여 주고 원문으로 이동.
3. **외부 provider 설정 화면** — rerank·Jev·질의 분해용 키(OpenRouter/TypeSafe/Vercel) 연결. 키는 `secrets.json`(0600)에, 응답엔 마지막 4자리만. 1번 뒤에.
4. **앱 내 녹음** — 마이크로 녹음해 바로 whisperX 전사 대기열로. macOS 마이크 권한 처리.
5. **자동 업데이트** — 앱이 새 DMG를 확인·내려받아 교체. 지금은 DMG를 열어 끌어다 놓는 수동 절차.
6. **월간 정리 자동화** — 지금은 Claude 예약 작업 프롬프트만 제공. 앱이 로컬 모델이나 연결된 provider로 초안을 쓸지 결정.
7. **번들 용량** — 약 500MB 중 onnxruntime-node 287MB 등 AutoRAG 의존성 정리.
8. **셸 이력** — `setopt EXTENDED_HISTORY`가 없는 zsh 이력(시각 없음)도 수집할지 결정.
9. **Intel Mac DMG** — Intel Mac에서 한 번 빌드.
