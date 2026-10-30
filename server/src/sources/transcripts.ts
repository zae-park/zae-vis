// Meeting transcripts: pulls exports from other tools (importDirs) into the inbox and
// transcribes any audio waiting in inbox/audio with whisperX.

import { existsSync } from "node:fs";
import { copyFile, mkdir, readdir, stat } from "node:fs/promises";
import { basename, extname, join } from "node:path";
import { expandHome } from "../config.ts";
import { hfStatus } from "../hf.ts";
import { AUDIO_EXT, TEXT_EXT, datedStem, transcribeFile, whisperxBin } from "../transcribe.ts";
import { addTo, dayKey, type Source } from "./types.ts";

async function files(dir: string): Promise<string[]> {
  try {
    return (await readdir(dir, { withFileTypes: true })).filter((e) => e.isFile() && !e.name.startsWith(".")).map((e) => join(dir, e.name));
  } catch {
    return [];
  }
}

export const transcriptsSource: Source = {
  name: "transcripts",
  append: true,
  title: "회의 전사본",
  description: "다른 전사 서비스의 내보내기 폴더에서 전사본을 가져오고, inbox/audio 의 녹음을 whisperX로 전사합니다.",
  options: [
    { key: "importDirs", label: "가져올 폴더 (전사 서비스 내보내기 경로)", kind: "paths" },
    { key: "audioDir", label: "전사할 녹음 폴더", kind: "path" },
    { key: "language", label: "전사 언어", kind: "text" },
    { key: "model", label: "whisperX 모델", kind: "text" },
  ],
  async collect({ from, to, settings, config, log, tick }) {
    const inbox = join(config.worklogDir, "inbox", "transcripts");
    const audioDir = expandHome(String(settings.audioDir ?? join(config.worklogDir, "inbox", "audio")));
    await mkdir(inbox, { recursive: true });
    await mkdir(audioDir, { recursive: true });
    const byDay: Record<string, string[]> = {};
    let imported = 0;
    let transcribed = 0;

    // 1) exports from other tools
    const importDirs = Array.isArray(settings.importDirs) ? (settings.importDirs as string[]) : [];
    for (const dir of importDirs.map(expandHome)) {
      if (!existsSync(dir)) {
        log(`transcripts: 가져올 폴더 없음 ${dir}`);
        continue;
      }
      for (const f of await files(dir)) {
        const ext = extname(f).toLowerCase();
        const st = await stat(f);
        if (st.mtime < from || st.mtime > to) continue;
        if (TEXT_EXT.has(ext)) {
          const stem = await datedStem(f);
          if (existsSync(join(inbox, stem + ext)) || existsSync(join(config.worklogDir, "processed", "transcripts", stem + ext))) continue;
          await copyFile(f, join(inbox, stem + ext));
          addTo(byDay, dayKey(st.mtime), `- 가져옴: \`${stem}${ext}\` ← ${dir}`);
          imported++;
        } else if (AUDIO_EXT.has(ext)) {
          const stem = await datedStem(f);
          const target = join(audioDir, stem + ext);
          if (!existsSync(target) && !existsSync(join(config.worklogDir, "processed", "audio", stem + ext))) await copyFile(f, target);
        }
      }
    }

    // 2) audio waiting for transcription (any age)
    const audio = (await files(audioDir)).filter((f) => AUDIO_EXT.has(extname(f).toLowerCase()));
    if (audio.length && !whisperxBin(settings.whisperxBin as string | undefined)) {
      log(`transcripts: 녹음 ${audio.length}개가 있지만 whisperX가 없습니다 ('zaevis ext install whisperx').`);
    } else {
      const hf = hfStatus();
      if (audio.length && !hf.loggedIn) log("화자 구분은 설정에서 Hugging Face에 로그인한 뒤 됩니다. 전사 자체는 그대로 진행합니다.");
      else if (audio.length && hf.accept.length) log(`화자 구분은 ${hf.accept.join(", ")} 사용에 동의한 뒤 됩니다. 설정에서 동의 페이지를 여세요.`);
      for (let i = 0; i < audio.length; i++) {
        const a = audio[i]!;
        const day = dayKey((await stat(a)).mtime);
        const file = basename(a);
        try {
          const where = `전사 ${i + 1}/${audio.length} · ${file}`;
          log(where, null);
          const out = await transcribeFile(a, config.worklogDir, {
            language: String(settings.language ?? "ko"),
            model: String(settings.model ?? "large-v3-turbo"),
            whisperxBin: settings.whisperxBin as string | undefined,
            onTick: tick,
            onProgress: (p) => log(`${where} · ${p.line}`, p.fraction),
          });
          addTo(byDay, day, `- 전사: \`${out.split("/").pop()}\``);
          transcribed++;
        } catch (err) {
          log(`transcripts: ${file} 전사 실패 — ${(err as Error).message}`);
        }
      }
    }
    const days: Record<string, string> = {};
    for (const [d, lines] of Object.entries(byDay)) days[d] = lines.join("\n");
    return { days, note: `가져옴 ${imported}개 · 전사 ${transcribed}개${audio.length > transcribed ? ` · 대기 ${audio.length - transcribed}개` : ""}` };
  },
};
