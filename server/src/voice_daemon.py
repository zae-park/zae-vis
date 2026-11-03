# Voice commands for the chat: one faster-whisper model kept in memory, so a few seconds of speech come back as text
# in about as long (a fresh whisperX process spends most of its time loading the model).
# argv: model name, CPU threads. stdin: one JSON request per line {"id", "path", "language"|null};
# stdout: one JSON reply per line {"id", "text"} or {"id", "error"}. Exits when stdin closes (voice.ts idles it out).

import json
import sys

from faster_whisper import WhisperModel
from whisperx.audio import load_audio  # ffmpeg → 16 kHz mono float32; the venv's own `av` cannot open files here

model_name, threads = sys.argv[1], int(sys.argv[2])
model = WhisperModel(model_name, device="cpu", compute_type="int8", cpu_threads=threads)
print(json.dumps({"ready": True}), flush=True)

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    req = {}
    try:
        req = json.loads(line)
        segments, _ = model.transcribe(
            load_audio(req["path"]),
            language=req.get("language") or None,
            # beam 1 dropped words on short clips; 5 costs little at this length
            beam_size=5,
            vad_filter=True,
            condition_on_previous_text=False,
        )
        text = " ".join(s.text.strip() for s in segments).strip()
        print(json.dumps({"id": req.get("id"), "text": text}, ensure_ascii=False), flush=True)
    except Exception as err:  # a bad file must not take the daemon down
        print(json.dumps({"id": req.get("id"), "error": str(err)}, ensure_ascii=False), flush=True)
