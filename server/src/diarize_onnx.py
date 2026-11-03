# Speaker labels for a whisperX JSON result with sherpa-onnx (no Hugging Face account needed).
# argv: audio, whisperX JSON, models folder (segmentation.onnx, embedding.onnx).
# Prints "[S<k>]: text" lines on stdout, one per sentence; diarize.ts turns them into "[A] …" turns.

import json
import os
import re
import sys

import sherpa_onnx
from whisperx.audio import load_audio  # ffmpeg → 16 kHz mono float32, any input format

audio_path, src, models = sys.argv[1], sys.argv[2], sys.argv[3]
threshold = float(os.environ.get("ZAEVIS_DIARIZE_THRESHOLD", "0.7"))
threads = int(os.environ.get("ZAEVIS_DIARIZE_THREADS", "4"))

config = sherpa_onnx.OfflineSpeakerDiarizationConfig(
    segmentation=sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
        pyannote=sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(model=os.path.join(models, "segmentation.onnx")),
        num_threads=threads,
    ),
    embedding=sherpa_onnx.SpeakerEmbeddingExtractorConfig(model=os.path.join(models, "embedding.onnx"), num_threads=threads),
    clustering=sherpa_onnx.FastClusteringConfig(num_clusters=-1, threshold=threshold),
    min_duration_on=0.3,
    min_duration_off=0.5,
)
if not config.validate():
    sys.exit("화자 구분 설정이 올바르지 않습니다")
diarizer = sherpa_onnx.OfflineSpeakerDiarization(config)
audio = load_audio(audio_path, sr=diarizer.sample_rate)
turns = [(t.start, t.end, t.speaker) for t in diarizer.process(audio).sort_by_start_time()]

with open(src, encoding="utf-8") as f:
    result = json.load(f)
segments = [s for s in (result.get("segments") or []) if str(s.get("text") or "").strip()]


def sentences(seg):
    """A ~30 s recognition chunk split at sentence ends, its time shared out by length."""
    text = str(seg.get("text") or "").strip()
    parts = [p.strip() for p in re.split(r"(?<=[.?!。？！])\s+", text) if p.strip()]
    a, b = float(seg.get("start") or 0), float(seg.get("end") or 0)
    total = sum(len(p) for p in parts) or 1
    out, t = [], a
    for p in parts:
        d = (b - a) * len(p) / total
        out.append({"text": p, "start": t, "end": t + d})
        t += d
    return out


# The fast pass skipped alignment, so chunks are long. Word timing (whisperX alignment) lets a speaker
# change inside a chunk show; without the model, sentences with proportional times are the fallback.
aligned = None
if segments and os.environ.get("ZAEVIS_DIARIZE_ALIGN", "1") != "0":
    try:
        import torch
        import whisperx

        torch.set_num_threads(threads)
        model, meta = whisperx.load_align_model(language_code=result.get("language") or "ko", device="cpu")
        aligned = whisperx.align(segments, model, meta, audio, "cpu", return_char_alignments=False).get("segments")
        aligned = [s for s in aligned or [] if str(s.get("text") or "").strip() and s.get("start") is not None]
    except Exception as err:  # no model for the language, offline, …
        print(f"정렬 없이 문장 단위로 나눕니다: {err}", file=sys.stderr)
        aligned = None
pieces = aligned if aligned else [p for s in segments for p in sentences(s)]

# A "speaker" with almost no speech is usually one voice split off (a cough, a laugh, a mic bump):
# its turns count for whoever spoke around them.
spoken = {}
for s, e, k in turns:
    spoken[k] = spoken.get(k, 0.0) + e - s
total = sum(spoken.values()) or 1.0
minor = {k for k, d in spoken.items() if d < 30 and d / total < 0.02}
turns = [t for t in turns if t[2] not in minor]

# One line per sentence: "[S<k>]: text". server/src/diarize.ts merges runs, letters speakers and wraps.
last = None
out = []
for seg in pieces:
    text = str(seg.get("text") or "").strip()
    if not text:
        continue
    a, b = float(seg.get("start") or 0), float(seg.get("end") or 0)
    overlap = {}
    for s, e, k in turns:
        if e <= a:
            continue
        if s >= b:
            break
        overlap[k] = overlap.get(k, 0.0) + min(b, e) - max(a, s)
    speaker = max(overlap, key=overlap.get) if overlap else last
    out.append(f"[S{speaker}]: {text}" if speaker is not None else text)
    last = speaker

sys.stdout.write("\n".join(out))
if out:
    sys.stdout.write("\n")
