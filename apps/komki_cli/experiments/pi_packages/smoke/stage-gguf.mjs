#!/usr/bin/env node
/**
 * Staging eines Kandidaten-GGUF mit Pin-Disziplin (Ticket #285), nach dem
 * Muster von KomkiCli.Model.download/1:
 *
 *   1. feste Revision statt main; die vom Server gemeldete Prüfsumme
 *      (X-Linked-ETag = SHA-256 der LFS-Datei) muss vor dem Download zum Pin
 *      passen,
 *   2. Download als <datei>.part mit /usr/bin/curl -C - (fortsetzbar),
 *   3. SHA-256 der fertigen Datei gegen den Pin; erst dann Umbenennung auf
 *      den endgültigen Namen. Eine abweichende Datei bleibt als .part liegen
 *      und wird nicht verwendet.
 *
 * Ablage: <KOMKI_HOME>/models-staging (nie models/ der Instanz).
 *
 *   node smoke/stage-gguf.mjs --repo unsloth/gemma-4-26B-A4B-it-qat-GGUF \
 *     --revision <commit> --file <name.gguf> --sha256 <hex>
 */
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, rename } from "node:fs/promises";
import path from "node:path";

import { komkiBaseDir, sha256File } from "./measure.mjs";

const CURL = "/usr/bin/curl";

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i]?.replace(/^--/, "");
    args[key] = argv[i + 1];
  }
  for (const key of ["repo", "revision", "file", "sha256"]) {
    if (!args[key]) throw new Error(`--${key} fehlt`);
  }
  if (!/^[0-9a-f]{40}$/.test(args.revision)) throw new Error("--revision muss ein Commit-Hash sein");
  if (!/^[0-9a-f]{64}$/.test(args.sha256)) throw new Error("--sha256 muss 64 Hex-Zeichen haben");
  return args;
}

function remoteSha256(url) {
  const out = spawnSync(CURL, ["-sI", "--max-time", "20", url], { encoding: "utf8" });
  if (out.status !== 0) throw new Error(`Quelle nicht erreichbar (curl exit ${out.status})`);
  return /^x-linked-etag:\s*"?([0-9a-f]{64})"?/im.exec(out.stdout)?.[1] ?? null;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const url = `https://huggingface.co/${args.repo}/resolve/${args.revision}/${args.file}`;
  const dir = path.join(komkiBaseDir(), "models-staging");
  const target = path.join(dir, args.file);
  const part = `${target}.part`;
  await mkdir(dir, { recursive: true });

  if (existsSync(target)) {
    const actual = await sha256File(target);
    if (actual !== args.sha256) throw new Error(`${target} liegt schon da, aber SHA-256 ${actual} ≠ Pin`);
    console.log(`bereits gestaged und verifiziert: ${target}`);
    return;
  }

  const remote = remoteSha256(url);
  if (remote === null) console.log("Quelle meldet keine Prüfsumme; entscheidet die Prüfung danach");
  else if (remote !== args.sha256) throw new Error(`Quelle meldet ${remote}, Pin ist ${args.sha256}`);
  else console.log(`Quelle bestätigt Pin vor dem Download: ${remote}`);

  const curl = spawnSync(CURL, ["-L", "--fail", "-C", "-", "--progress-bar", "-o", part, url], {
    stdio: "inherit",
  });
  if (curl.status !== 0) throw new Error(`Download abgebrochen (curl exit ${curl.status}); erneut starten setzt fort`);

  const actual = await sha256File(part);
  if (actual !== args.sha256) throw new Error(`SHA-256 nach dem Download ${actual} ≠ Pin; ${part} bleibt liegen`);
  await rename(part, target);
  console.log(`gestaged und verifiziert: ${target}\nsha256 ${actual}`);
}

try {
  await main();
} catch (error) {
  console.error(String(error?.message ?? error));
  process.exitCode = 2;
}
