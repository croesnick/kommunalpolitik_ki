#!/usr/bin/env node
/**
 * Model A/B on top of the smoke harness (Ticket #285).
 *
 * Runs run-smoke.mjs per arm against its own staging llama-server (--gguf),
 * interleaved: round 0 = warm-up (not measured), rounds 1..n = measured
 * runs, each round A B C. All arms of a round share the seed (ab-arms.mjs).
 * Every run starts its server fresh and stops it afterwards — same starting
 * point for every run, with load time as a measurement.
 *
 *   node smoke/run-ab.mjs --root <dir> [--runs 3] [--arms A,B,C]
 *                         [--only 1,2,3,4,6] [--timeout-factor 6]
 *   node smoke/run-ab.mjs --root <dir> --preflight   # load check only
 *
 * Re-measuring a close metric (decision rule 4 in the labbook):
 * --first-round 4 --runs 5 --only 2 runs rounds 4–5 only, without warm-up.
 *
 * Follow-up studies use their own seed base (--seed-base) so no run repeats
 * an earlier seed. Arms with `serverArgs` or a `draft` (ab-arms.mjs) pass
 * them to the staging server.
 *
 * Resumable: a run whose directory holds results.json counts as done and
 * is skipped on the next invocation. Provenance (hardware, versions,
 * SHA-256 of binary and GGUFs, git state) and the schedule with the system
 * state per run go to <root>/provenance.json and <root>/schedule.json.
 */
import { execFileSync, spawn } from "node:child_process";
import { createWriteStream, existsSync, realpathSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { EXPERIMENTS_ROOT, PI_CLI, timestamp } from "../lib/config.mjs";
import { ARMS, seedFor } from "./ab-arms.mjs";
import { komkiBaseDir, sha256File } from "./measure.mjs";
import { DEFAULT_LLAMA_SERVER, llamaVersion, startStagingServer } from "./staging-server.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));

function parseArgs(argv) {
  const args = {
    root: null,
    runs: 3,
    arms: ["A", "B", "C"],
    only: "1,2,3,4,6",
    timeoutFactor: 6,
    firstRound: 0,
    seedBase: 285_000,
    preflight: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--root") args.root = argv[i + 1];
    if (argv[i] === "--runs") args.runs = Number(argv[i + 1]);
    if (argv[i] === "--arms") args.arms = argv[i + 1].split(",");
    if (argv[i] === "--only") args.only = argv[i + 1];
    if (argv[i] === "--timeout-factor") args.timeoutFactor = Number(argv[i + 1]);
    if (argv[i] === "--first-round") args.firstRound = Number(argv[i + 1]);
    if (argv[i] === "--seed-base") args.seedBase = Number(argv[i + 1]);
    if (argv[i] === "--preflight") args.preflight = true;
  }
  for (const arm of args.arms) if (!ARMS[arm]) throw new Error(`unbekannter Arm ${arm}`);
  return args;
}

function sh(cmd, cmdArgs) {
  try {
    return execFileSync(cmd, cmdArgs, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
  } catch {
    return null;
  }
}

function stagedPath(name) {
  return path.join(komkiBaseDir(), "models-staging", name);
}

function ggufPath(arm) {
  return stagedPath(path.basename(ARMS[arm].file));
}

/** Extra llama-server arguments of an arm, the MTP drafter path included. */
function serverArgsOf(arm) {
  const { serverArgs = [], draft } = ARMS[arm];
  return draft ? [...serverArgs, "--model-draft", stagedPath(draft.as)] : serverArgs;
}

/** System state before/after a run: swap, load, thermals, power source. */
function systemState() {
  return {
    at: new Date().toISOString(),
    swap: sh("/usr/sbin/sysctl", ["-n", "vm.swapusage"]),
    loadavg: os.loadavg().map((x) => Math.round(x * 100) / 100),
    freeMemMiB: Math.round(os.freemem() / 1024 / 1024),
    thermal: sh("/usr/bin/pmset", ["-g", "therm"])?.split("\n").filter((l) => /limit|level/i.test(l)).join("; ") ?? null,
    power: sh("/usr/bin/pmset", ["-g", "batt"])?.split("\n")[0] ?? null,
  };
}

async function provenance(args) {
  const llamaBin = realpathSync(process.env.KOMKI_LLAMA_SERVER ?? DEFAULT_LLAMA_SERVER);
  const piPackage = JSON.parse(
    await readFile(path.join(path.dirname(PI_CLI), "..", "..", "package.json"), "utf8"),
  );
  const ggufs = {};
  for (const arm of args.arms) {
    const file = ggufPath(arm);
    const actual = existsSync(file) ? await sha256File(file) : null;
    if (actual !== ARMS[arm].sha256) {
      throw new Error(`Arm ${arm}: ${file} fehlt oder SHA-256 ${actual} ≠ Pin — erst stage-gguf.mjs`);
    }
    ggufs[arm] = { ...ARMS[arm], path: file, sha256Verified: actual };
    const draft = ARMS[arm].draft;
    if (draft) {
      const draftFile = stagedPath(draft.as);
      const draftSha = existsSync(draftFile) ? await sha256File(draftFile) : null;
      if (draftSha !== draft.sha256) {
        throw new Error(`Arm ${arm}: Drafter ${draftFile} fehlt oder SHA-256 ${draftSha} ≠ Pin`);
      }
      ggufs[arm].draft = { ...draft, path: draftFile, sha256Verified: draftSha };
    }
  }
  return {
    at: new Date().toISOString(),
    args,
    host: {
      cpu: sh("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"]),
      model: sh("/usr/sbin/sysctl", ["-n", "hw.model"]),
      memBytes: Number(sh("/usr/sbin/sysctl", ["-n", "hw.memsize"])),
      os: sh("/usr/bin/sw_vers", ["-productVersion"]),
      osBuild: sh("/usr/bin/sw_vers", ["-buildVersion"]),
    },
    node: process.version,
    pi: { version: piPackage.version, cli: PI_CLI },
    llamaServer: { path: llamaBin, version: llamaVersion(llamaBin), sha256: await sha256File(llamaBin) },
    git: {
      head: sh("git", ["-C", HERE, "rev-parse", "HEAD"]),
      dirty: (sh("git", ["-C", HERE, "status", "--porcelain", "--", "."]) ?? "").length > 0,
    },
    ggufs,
    system: systemState(),
  };
}

function scheduleOf(args) {
  const entries = [];
  for (let round = args.firstRound; round <= args.runs; round += 1) {
    for (const arm of args.arms) {
      entries.push({
        seq: entries.length + 1,
        round,
        arm,
        kind: round === 0 ? "warmup" : "measured",
        seed: seedFor(round, args.seedBase),
        dir: path.join("runs", `${String(entries.length + 1).padStart(2, "0")}-r${round}-${arm}`),
      });
    }
  }
  return entries;
}

function runSmoke(entry, args, root) {
  const arm = ARMS[entry.arm];
  const runDir = path.join(root, entry.dir);
  const smokeArgs = [
    path.join(HERE, "run-smoke.mjs"),
    "--gguf", ggufPath(entry.arm),
    "--port", String(arm.port),
    "--sampling", JSON.stringify(arm.sampling),
    "--seed", String(entry.seed),
    "--server-args", JSON.stringify(serverArgsOf(entry.arm)),
    "--timeout-factor", String(args.timeoutFactor),
    "--only", args.only,
    "--root", runDir,
  ];
  return new Promise((resolve) => {
    const log = createWriteStream(path.join(runDir, "run.log"));
    const child = spawn(process.execPath, smokeArgs, { stdio: ["ignore", "pipe", "pipe"] });
    child.stdout.pipe(log, { end: false });
    child.stderr.pipe(log, { end: false });
    child.stdout.on("data", (chunk) => process.stdout.write(chunk));
    child.on("exit", (code) => {
      log.end();
      resolve(code);
    });
  });
}

async function preflight(args, root) {
  const results = {};
  for (const arm of args.arms) {
    const started = Date.now();
    try {
      const llama = await startStagingServer({
        gguf: ggufPath(arm),
        port: ARMS[arm].port,
        sampling: ARMS[arm].sampling,
        extraArgs: serverArgsOf(arm),
        dir: path.join(root, "preflight", arm),
      });
      results[arm] = { ok: true, loadMs: llama.staging.loadMs };
      await llama.stop();
    } catch (error) {
      results[arm] = { ok: false, error: String(error?.message ?? error), ms: Date.now() - started };
    }
    console.log(`Preflight ${arm}: ${JSON.stringify(results[arm])}`);
  }
  await writeFile(path.join(root, "preflight.json"), JSON.stringify(results, null, 2));
  return results;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = args.root ?? path.join(EXPERIMENTS_ROOT, "ab-285", timestamp());
  await mkdir(root, { recursive: true });
  console.log(`A/B-Root: ${root}`);

  const prov = await provenance(args);
  await writeFile(path.join(root, `provenance-${timestamp()}.json`), JSON.stringify(prov, null, 2));
  await writeFile(path.join(root, "provenance.json"), JSON.stringify(prov, null, 2));

  if (args.preflight) {
    const results = await preflight(args, root);
    process.exitCode = Object.values(results).every((r) => r.ok) ? 0 : 1;
    return;
  }

  const schedulePath = path.join(root, "schedule.json");
  const previous = existsSync(schedulePath) ? JSON.parse(await readFile(schedulePath, "utf8")) : [];
  const done = new Map(previous.filter((e) => e.exitCode !== undefined).map((e) => [e.dir, e]));
  const schedule = [];

  for (const entry of scheduleOf(args)) {
    const runDir = path.join(root, entry.dir);
    if (done.has(entry.dir) && existsSync(path.join(runDir, "results.json"))) {
      schedule.push(done.get(entry.dir));
      continue;
    }
    await mkdir(runDir, { recursive: true });
    console.log(`\n##### ${entry.seq} Runde ${entry.round} (${entry.kind}) Arm ${entry.arm} seed ${entry.seed}`);
    const before = systemState();
    const exitCode = await runSmoke(entry, args, root);
    schedule.push({ ...entry, before, after: systemState(), exitCode });
    await writeFile(schedulePath, JSON.stringify(schedule, null, 2));
  }
  await writeFile(schedulePath, JSON.stringify(schedule, null, 2));
  console.log(`\nAblauf: ${schedulePath}`);
}

try {
  await main();
} catch (error) {
  console.error(String(error?.message ?? error));
  process.exitCode = 2;
}
