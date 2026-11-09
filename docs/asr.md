# 실시간·회의 전사 (ASR) 설계

녹음이 **끝난 뒤**에만 돌리던 whisper 경로를, **한 세션 엔진**으로 바꿔
대화 마이크(live)와 회의 녹음(meeting)을 같이 푼다. Whisper 자체는 스트림 API가 없으므로
VAD·창 자르기·재디코드는 zaevis가 한다.

## 목표

| 모드 | UX | 저장 |
|------|----|------|
| `live` | 말하는 동안 입력창에 partial, 멈추면 final로 질문 전송 | 오디오·전사 저장 안 함 |
| `meeting` | 녹음 중·직후 초안 글. 끝나면 whisperX가 고품질·화자로 교체 | WAV → inbox, 초안 md → `inbox/transcripts/<stem>.md` (whisperX가 덮어씀) |

## 계층

```
AsrCapture (앱)  ──PCM──►  AsrSession (서버)
                              ├─ Chunker (에너지 VAD + 프레임 배열)
                              ├─ DecodeQueue (final=high > partial=low)
                              ├─ WhisperDaemon (voice_daemon, warm)
                              └─ Policy(live|meeting) → events
```

## HTTP API

| 메서드 | 경로 | 본문 | 응답 |
|--------|------|------|------|
| POST | `/api/asr` | `{ mode, language?, name? }` | `{ id, mode }` (201). whisperX 없으면 409 `no_asr` |
| POST | `/api/asr/:id/audio` | raw PCM16 (16 kHz mono) | `{ events[], partial, text }` |
| POST | `/api/asr/:id/stop` | | `{ events, partial, text, draft? }` |
| DELETE | `/api/asr/:id` | | `{ ok }` |

`name`은 meeting에서 초안 파일 stem에 쓴다 (`2026-11-09_1200_녹음.wav` → `inbox/transcripts/2026-11-09_1200_녹음.md`).
`draft`는 meeting이고 최종 글이 있을 때만 worklog 상대 경로. live는 오디오·전사를 저장하지 않는다.
cancel/stop 중 decode는 `aborted`를 보고, 대기 큐에 남은 작업은 바로 건너뛴다(다른 세션의 긴 final을 붙잡지 않음).

## Policy

| | live | meeting |
|--|------|---------|
| partial | 350ms, beam 1 | 끔 |
| final | 침묵 500ms / 20s 창 / stop, beam 5 | 침묵 600ms / 20s / stop, beam 5 |
| 우선순위 | final high > partial low (DecodeQueue) | final only (high) |

## Chunker

- 16 kHz mono PCM16, 30ms 프레임
- speech: RMS ≥ 0.012
- 발화 버퍼는 **프레임 배열**(프레임마다 `Buffer.concat` 하지 않음)
- final: 침묵 임계 또는 maxSpeechMs(20s, overlap 2s)

## 앱

- `AsrCapture`: 세션 생성 실패(409) 시 로컬 버퍼만 유지 → live는 `/api/voice`, meeting은 WAV 업로드
- stop 시 in-flight push를 기다린 뒤 남은 PCM을 flush
- AskView / RecordDialog가 같은 Capture를 씀

## 폴백

- whisperX 없음 → 세션 409 → 기존 한 방 경로 (`/api/voice` 또는 WAV 업로드)
- decode/cancel 경합 → `aborted` + 대기 큐 `flushSkipped`(다른 세션 decode를 붙잡지 않음) → inflight 대기 → tmp 삭제
- 이미 돌고 있는 decode는 끝날 때까지 기다린 뒤 결과를 버리고 tmp를 지움
