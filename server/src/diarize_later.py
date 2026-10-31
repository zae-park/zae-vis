# Add speaker labels to a whisperX JSON result. Recognition has already finished.
# Prints the labeled transcript on stdout. The token stays in the environment.

import json
import os
import sys

from whisperx.diarize import DiarizationPipeline, assign_word_speakers

audio, src = sys.argv[1], sys.argv[2]
token = os.environ.get("HF_TOKEN") or ""
with open(src, encoding="utf-8") as f:
    result = json.load(f)
pipeline = DiarizationPipeline(model_name="pyannote/speaker-diarization-3.1", token=token, device="cpu")
labeled = assign_word_speakers(pipeline(audio), result)
lines = []
for seg in labeled.get("segments") or []:
    text = str(seg.get("text") or "").strip()
    if not text:
        continue
    speaker = seg.get("speaker")
    lines.append(f"[{speaker}]: {text}" if speaker else text)
sys.stdout.write("\n".join(lines))
if lines:
    sys.stdout.write("\n")
