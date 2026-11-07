#!/usr/bin/env node
/**
 * Debug probe of the llama-server A/B (Ticket #372): descriptive, no gate.
 *
 *   node smoke/run-ab.mjs --root <dir> --arms V7D,V9D --runs 0 --seed-base 372800
 *   node smoke/probe-lv4.mjs --root <dir>
 *
 * Reads the -lv 4 server log of every run in <root>/schedule.json and writes
 * <root>/probe.json and <root>/PROBE.md: Flash Attention lines per context
 * (main model, drafter), context checkpoints created and restored, and the
 * draft acceptance of requests with and without a restored checkpoint, plus
 * per request in log order (so the request after a restore is visible too).
 * Debug logging costs time, so the probe reports no speed values.
 */
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";

import { fmtDraft } from "./grade-ab.mjs";
import { llamaDebugSummary } from "./measure.mjs";

const fmtPool = (d) => (d.rate === null ? "–" : `${fmtDraft(d)}, ${d.requests} Requests`);

async function main() {
  const rootIndex = process.argv.indexOf("--root");
  const root = rootIndex >= 0 ? process.argv[rootIndex + 1] : null;
  if (!root) throw new Error("--root <probe-root> fehlt");

  const schedule = JSON.parse(await readFile(path.join(root, "schedule.json"), "utf8"));
  const runs = [];
  for (const entry of schedule) {
    const log = await readFile(path.join(root, entry.dir, "server", "llama-server.log"), "utf8");
    runs.push({ dir: entry.dir, arm: entry.arm, seed: entry.seed, ...llamaDebugSummary(log) });
  }
  await writeFile(path.join(root, "probe.json"), JSON.stringify(runs, null, 2));

  const fa = (run, role) => run.contexts.find((c) => c.role === role)?.fa.join("; ") || "–";
  const lines = [
    "# Debug-Sonde -lv 4 (generiert von probe-lv4.mjs)",
    "",
    "| Lauf | Arm | Seed | FA Hauptmodell | FA Drafter | Checkpoints angelegt | zurückgespielt | acceptance mit Restore | acceptance ohne Restore |",
    "|---|---|---|---|---|---|---|---|---|",
    ...runs.map(
      (r) =>
        `| ${r.dir} | ${r.arm} | ${r.seed} | ${fa(r, "main")} | ${fa(r, "draft")} | ${r.checkpointsCreated} | ${r.checkpointsRestored} | ${fmtPool(r.draft.withRestore)} | ${fmtPool(r.draft.withoutRestore)} |`,
    ),
  ];
  for (const run of runs) {
    lines.push("", `## ${run.dir} (${run.arm})`, "", "| Request | Task | Restore | draft acceptance |", "|---|---|---|---|");
    run.requests.forEach((r, i) => {
      const rate = r.generated ? r.accepted / r.generated : null;
      lines.push(`| ${i + 1} | ${r.task} | ${r.restored ? "ja" : "–"} | ${fmtDraft({ ...r, rate })} |`);
    });
  }
  await writeFile(path.join(root, "PROBE.md"), lines.join("\n") + "\n");
  console.log(`Sonde: ${path.join(root, "PROBE.md")}`);
}

try {
  await main();
} catch (error) {
  console.error(String(error?.message ?? error));
  process.exitCode = 2;
}
