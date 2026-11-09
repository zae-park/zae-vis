# Voice / ASR daemon: one faster-whisper model kept in memory.
# argv: model name, CPU threads. stdin: one JSON request per line
#   {"id", "path", "language"|null, "beam_size"?, "vad_filter"?, "condition_on_previous_text"?}
# stdout: one JSON reply per line {"id", "text"} or {"id", "error"}.
# Exits when stdin closes (voice.ts idles it out).

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
        beam = int(req["beam_size"]) if req.get("beam_size") is not None else 5
        # beam 1 dropped words on short clips; live partials still pass 1 deliberately
        vad = True if req.get("vad_filter") is None else bool(req.get("vad_filter"))
        cond = bool(req.get("condition_on_previous_text")) if req.get("condition_on_previous_text") is not None else False
        segments, _ = model.transcribe(
            load_audio(req["path"]),
            language=req.get("language") or None,
            beam_size=max(1, beam),
            vad_filter=vad,
            condition_on_previous_text=cond,
        )
        text = " ".join(s.text.strip() for s in segments).strip()
        print(json.dumps({"id": req.get("id"), "text": text}, ensure_ascii=False), flush=True)
    except Exception as err:  # a bad file must not take the daemon down
        print(json.dumps({"id": req.get("id"), "error": str(err)}, ensure_ascii=False), flush=True)
