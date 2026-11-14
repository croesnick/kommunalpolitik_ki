import { spawn, spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { openSync, closeSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

import { llamaGet } from "./measure.mjs";

/**
 * Staging llama-server for the model A/B (Ticket #285).
 *
 * Same flags as the production start in KomkiCli.Llama (`--jinja
 * --offline --no-webui --no-slots -c <ctx> --alias local-model`, API key
 * from a file), but without a Seatbelt profile, on its own port, with its
 * own key and log under the run directory — never via the komki instance.
 * Only the GGUF, its sampling flags, the seed, per-arm extra server
 * arguments (thinking switch, MTP drafter) and — #320 — the binary
 * itself vary.
 *
 * Returns the same shape as resolveLlama() (port, pid, apiKey, baseUrl,
 * gguf, ctx, logPath), so run-smoke.mjs measures both paths alike, plus
 * loadMs (spawn until /health 200) and stop().
 */

export const DEFAULT_LLAMA_SERVER = "/opt/homebrew/bin/llama-server";
const HEALTH_TIMEOUT_MS = 15 * 60_000;

/** Sampling object → llama-server flags. Key = flag without "--". */
export function samplingFlags(sampling = {}) {
  return Object.entries(sampling).flatMap(([flag, value]) => [`--${flag}`, String(value)]);
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function startStagingServer({
  gguf,
  port,
  sampling = {},
  seed = null,
  ctx = 131072,
  extraArgs = [],
  dir,
  bin = process.env.KOMKI_LLAMA_SERVER ?? DEFAULT_LLAMA_SERVER,
}) {
  await mkdir(dir, { recursive: true });
  const keyPath = path.join(dir, "llama.key");
  const logPath = path.join(dir, "llama-server.log");
  const apiKey = randomBytes(24).toString("hex");
  await writeFile(keyPath, apiKey, { mode: 0o600 });

  const busy = await llamaGet(port, "/health", 1000);
  if (busy.code) throw new Error(`Port ${port} ist belegt (/health ${busy.code}) — anderen Port wählen`);

  const args = [
    "-m", gguf,
    "--host", "127.0.0.1",
    "--port", String(port),
    "--alias", "local-model",
    "--jinja",
    "--offline",
    "--no-webui",
    "--no-slots",
    ...samplingFlags(sampling),
    ...(seed === null ? [] : ["--seed", String(seed)]),
    ...extraArgs,
    "-c", String(ctx),
    "--api-key-file", keyPath,
  ];

  const logFd = openSync(logPath, "a");
  const started = Date.now();
  const child = spawn(bin, args, { stdio: ["ignore", logFd, logFd] });
  closeSync(logFd);
  let exited = null;
  child.on("exit", (code, signal) => {
    exited = { code, signal };
  });

  let loadMs = null;
  while (Date.now() - started < HEALTH_TIMEOUT_MS) {
    if (exited) break;
    const health = await llamaGet(port, "/health", 2000);
    if (health.code === "200") {
      loadMs = Date.now() - started;
      break;
    }
    await delay(250);
  }
  if (loadMs === null) {
    child.kill("SIGTERM");
    const tail = (await readFile(logPath, "utf8").catch(() => "")).slice(-2000);
    throw new Error(`Staging-Server kam nicht hoch (${JSON.stringify(exited)}):\n${tail}`);
  }

  const props = await llamaGet(port, "/props");

  return {
    base: dir,
    port,
    pid: child.pid,
    apiKey,
    authRequired: props.code === "401",
    baseUrl: `http://127.0.0.1:${port}/v1`,
    gguf,
    ctx,
    logPath,
    staging: { bin, args, sampling, seed, extraArgs, loadMs },
    async stop() {
      if (exited) return;
      child.kill("SIGTERM");
      for (let i = 0; i < 120 && !exited; i += 1) await delay(250);
      if (!exited) child.kill("SIGKILL");
    },
  };
}

/** `llama-server --version` (build number and commit) for the provenance record. */
export function llamaVersion(bin = process.env.KOMKI_LLAMA_SERVER ?? DEFAULT_LLAMA_SERVER) {
  // depending on the build, llama-server prints the version to stdout or stderr
  const out = spawnSync(bin, ["--version"], { encoding: "utf8" });
  return `${out.stdout ?? ""}${out.stderr ?? ""}`.trim() || null;
}
