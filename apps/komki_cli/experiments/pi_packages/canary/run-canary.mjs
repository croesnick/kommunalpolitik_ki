#!/usr/bin/env node
/**
 * Seatbelt canary for the real komki pi profile.
 *
 * Standalone runner (not wired into run-all.mjs): generates a temporary copy
 * of KomkiCli.Profile.generate/2 with the mock-provider port in place of the
 * llama port, runs pi under sandbox-exec, and checks the extension's JSON
 * result. The base instance profile under ~/.local/share/komki/profile is
 * never touched.
 */

import { spawn, spawnSync } from "node:child_process";
import {
  cp,
  mkdir,
  readFile,
  stat,
  unlink,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { MOCK_MODEL, MOCK_PROVIDER } from "../lib/config.mjs";
import { startMockProvider } from "../lib/mock-provider.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const EXTENSION_SOURCE = path.join(HERE, "canary-extension.ts");
const KOMKI_APP_DIR = path.resolve(HERE, "../../..");
const KOMKI_BASE =
  process.env.KOMKI_HOME ?? path.join(os.homedir(), ".local", "share", "komki");
const CONFIG_PATH = path.join(KOMKI_BASE, "config.json");
const ESCAPE_FILE = "/tmp/komki-canary-escape.txt";
const CANARY_TOKEN = "canary-token-not-a-real-credential";
const STAMP = new Date().toISOString().replace(/[:.]/g, "-");

function log(message) {
  process.stdout.write(`${message}\n`);
}

async function exists(file) {
  try {
    await stat(file);
    return true;
  } catch {
    return false;
  }
}

function runMixProfileGenerator({ port, scratch, profilePath }) {
  const expression = [
    "cfg = KomkiCli.Config.load!(System.fetch_env!(\"KOMKI_CANARY_CONFIG\"))",
    "cfg = Map.put(cfg, :port, String.to_integer(System.fetch_env!(\"KOMKI_CANARY_PORT\")))",
    "scratch = KomkiCli.Config.canonical(System.fetch_env!(\"KOMKI_CANARY_SCRATCH\"))",
    "out = KomkiCli.Config.canonical(System.fetch_env!(\"KOMKI_CANARY_PROFILE\"))",
    "KomkiCli.Profile.write!(out, KomkiCli.Profile.generate(cfg, scratch))",
    "IO.puts(out)",
  ].join("\n");

  const result = spawnSync("mix", ["run", "-e", expression], {
    cwd: KOMKI_APP_DIR,
    env: {
      ...process.env,
      KOMKI_CANARY_CONFIG: CONFIG_PATH,
      KOMKI_CANARY_PORT: String(port),
      KOMKI_CANARY_SCRATCH: scratch,
      KOMKI_CANARY_PROFILE: profilePath,
    },
    encoding: "utf8",
  });

  return {
    status: result.status,
    signal: result.signal,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
    error: result.error ? String(result.error) : null,
  };
}

function statusOf(ok) {
  return ok ? "pass" : "fail";
}

async function main() {
  const config = JSON.parse(await readFile(CONFIG_PATH, "utf8"));
  const scratch = path.join(KOMKI_BASE, "tmp", `canary-${STAMP}`);
  const profilePath = path.join(scratch, "komki-canary.sb");
  const extensionPath = path.join(scratch, "canary-extension.ts");
  const resultPath = path.join(scratch, "canary-result.json");
  const home = path.join(scratch, "home");
  const agentDir = path.join(home, ".pi", "agent");
  const workDir = path.join(scratch, "work");
  const sessionsDir = path.join(scratch, "sessions");
  const mockLog = path.join(scratch, "mock-requests.jsonl");

  await mkdir(scratch, { recursive: true });
  await mkdir(agentDir, { recursive: true });
  await mkdir(workDir, { recursive: true });
  await mkdir(sessionsDir, { recursive: true });
  await mkdir(path.join(scratch, "tmp"), { recursive: true });
  await unlink(ESCAPE_FILE).catch(() => {});

  const mock = await startMockProvider({
    script: [{ text: "CANARY_CONTROL_OK" }],
    logPath: mockLog,
    contextWindow: 8192,
  });

  log(`mock provider: 127.0.0.1:${mock.port}`);

  const generation = runMixProfileGenerator({
    port: mock.port,
    scratch,
    profilePath,
  });

  if (generation.status !== 0 || !(await exists(profilePath))) {
    await mock.close();
    const report = {
      date: new Date().toISOString(),
      verdict: "blocked",
      blocker: "KomkiCli.Profile.generate/2 via mix run failed",
      configPath: CONFIG_PATH,
      mockPort: mock.port,
      scratch,
      profilePath,
      generation,
    };
    const blockedPath = path.join(HERE, `blocked-${STAMP}.json`);
    await writeFile(blockedPath, `${JSON.stringify(report, null, 2)}\n`);
    log(JSON.stringify(report, null, 2));
    log(`blocked report: ${blockedPath}`);
    process.exitCode = 2;
    return;
  }

  await cp(EXTENSION_SOURCE, extensionPath);

  const models = {
    providers: {
      [MOCK_PROVIDER]: {
        api: "openai-completions",
        apiKey: "mock-key",
        baseUrl: mock.baseUrl,
        models: [
          {
            id: MOCK_MODEL,
            name: "Mock Model",
            contextWindow: 8192,
            maxTokens: 512,
            reasoning: false,
          },
        ],
      },
    },
  };

  await writeFile(path.join(agentDir, "models.json"), JSON.stringify(models, null, 2));
  await writeFile(path.join(agentDir, "settings.json"), "{}\n");
  await writeFile(path.join(agentDir, "trust.json"), "{}\n");

  const args = [
    config.sandbox_exec,
    "-f",
    profilePath,
    "--",
    config.node_bin,
    config.cli_js,
    "--print",
    "--mode",
    "json",
    "--offline",
    "--no-extensions",
    "--no-skills",
    "--no-context-files",
    "--no-prompt-templates",
    "--no-themes",
    "--no-approve",
    "--session-dir",
    sessionsDir,
    "--provider",
    MOCK_PROVIDER,
    "--model",
    MOCK_MODEL,
    "--tools",
    "read",
    "-e",
    extensionPath,
    "Sag OK",
  ];

  const env = {
    HOME: home,
    PI_CODING_AGENT_DIR: agentDir,
    TMPDIR: path.join(scratch, "tmp"),
    XDG_CONFIG_HOME: path.join(home, ".config"),
    XDG_DATA_HOME: path.join(home, ".local", "share"),
    XDG_CACHE_HOME: path.join(home, ".cache"),
    PATH: "/usr/bin:/bin",
    LANG: "C",
    LC_ALL: "C",
    PI_OFFLINE: "1",
    KOMKI_CANARY_SANDBOX_EXEC: "1",
    KOMKI_CANARY_RESULT: resultPath,
    KOMKI_CANARY_MOCK_URL: `http://127.0.0.1:${mock.port}/v1/models`,
    KOMKI_CANARY_LLAMA_KEY: path.join(KOMKI_BASE, "tmp", "llama.key"),
    // Deliberately fake: the residual is that the extension sees whatever
    // token the harness passes, not that a real mediator token leaks.
    KOMKI_MEDIATOR_TOKEN: CANARY_TOKEN,
  };

  const started = Date.now();
  const child = spawn(args[0], args.slice(1), {
    cwd: workDir,
    env,
    stdio: ["ignore", "pipe", "pipe"],
    detached: true,
  });

  let stdout = "";
  let stderr = "";
  let timedOut = false;
  child.stdout.on("data", (chunk) => {
    stdout += chunk;
  });
  child.stderr.on("data", (chunk) => {
    stderr += chunk;
  });

  const timer = setTimeout(() => {
    timedOut = true;
    try {
      process.kill(-child.pid, "SIGKILL");
    } catch {
      try {
        child.kill("SIGKILL");
      } catch {}
    }
  }, 60000);

  const exit = await new Promise((resolve) => {
    child.on("error", (error) => resolve({ code: null, signal: null, error: String(error) }));
    child.on("exit", (code, signal) => resolve({ code, signal }));
  });

  clearTimeout(timer);
  await mock.close();
  const durationMs = Date.now() - started;

  let canaryResult = null;
  let canaryResultError = null;
  try {
    canaryResult = JSON.parse(await readFile(resultPath, "utf8"));
  } catch (error) {
    canaryResultError = String(error?.message ?? error);
  }

  const escapeFileExists = await exists(ESCAPE_FILE);
  const providerRequests = mock.requests.filter(
    (request) => request.method === "POST" && request.url === "/v1/chat/completions",
  );

  const checks = canaryResult?.checks ?? {};
  const requirements = [
    {
      id: "external-fetch-denied",
      requirement: "fetch('https://example.com') fails under Seatbelt",
      status: statusOf(checks.externalFetch && checks.externalFetch.ok === false),
      observed: checks.externalFetch ?? null,
      gating: true,
    },
    {
      id: "exec-denied",
      requirement: "child_process.execFile('/bin/echo') fails (not in exec allowlist)",
      status: statusOf(checks.execFileEcho && checks.execFileEcho.ok === false),
      observed: checks.execFileEcho ?? null,
      gating: true,
    },
    {
      id: "tmp-write-denied",
      requirement: "/tmp/komki-canary-escape.txt is not created",
      status: statusOf(
        checks.tmpWrite && checks.tmpWrite.ok === false && !escapeFileExists,
      ),
      observed: {
        writeAttempt: checks.tmpWrite ?? null,
        hostSeesFile: escapeFileExists,
      },
      gating: true,
    },
    {
      id: "mock-provider-allowed",
      requirement: "Mock provider on the allowed loopback port answers",
      status: statusOf(
        checks.mockFetch?.ok === true && providerRequests.length > 0,
      ),
      observed: {
        extensionFetch: checks.mockFetch ?? null,
        providerRequests: providerRequests.length,
      },
      gating: true,
    },
    {
      id: "result-written-in-scope",
      requirement: "Extension can write canary-result.json inside the scratch scope",
      status: statusOf(canaryResult !== null),
      observed: {
        resultPath,
        parseError: canaryResultError,
      },
      gating: true,
    },
    {
      id: "mediator-token-visible",
      requirement: "Residual: KOMKI_MEDIATOR_TOKEN is visible in process.env",
      status: checks.mediatorTokenInEnv === true ? "pass" : "fail",
      observed: { visible: checks.mediatorTokenInEnv ?? "not recorded" },
      gating: false,
    },
    {
      id: "llama-key-readable",
      requirement: "Residual: llama.key is readable by the in-process extension",
      status: checks.llamaKeyReadable === true ? "pass" : "fail",
      observed: { readable: checks.llamaKeyReadable ?? "not recorded" },
      gating: false,
    },
  ];

  const gatingFailures = requirements.filter(
    (requirement) => requirement.gating && requirement.status !== "pass",
  );

  const report = {
    date: new Date().toISOString(),
    verdict: gatingFailures.length === 0 ? "pass" : "fail",
    piVersion: "1.1.0",
    nodeVersion: process.version,
    configPath: CONFIG_PATH,
    mockPort: mock.port,
    scratch,
    profilePath,
    profileUsedMockPort: (await readFile(profilePath, "utf8")).includes(
      `localhost:${mock.port}`,
    ),
    extensionSource: EXTENSION_SOURCE,
    extensionPath,
    commandShape:
      "<sandbox-exec> -f <generated-profile> -- <node> <pi cli.js> --print --mode json --offline --no-extensions --no-skills --no-context-files --no-prompt-templates --no-themes --no-approve --session-dir <scratch>/sessions --provider mock --model mock-model --tools read -e <scratch>/canary-extension.ts 'Sag OK'",
    exit: {
      code: exit.code,
      signal: exit.signal ?? null,
      spawnError: exit.error ?? null,
      timedOut,
      durationMs,
    },
    providerRequests: providerRequests.length,
    canaryResult,
    canaryResultError,
    hostSeesEscapeFile: escapeFileExists,
    requirements,
    residual:
      "The extension runs in-process with pi, so every credential the harness passes in the environment (KOMKI_MEDIATOR_TOKEN) is visible to extension code. llama.key under <base>/tmp was not readable because the pi profile grants read only to pi-home and the scratch scope. The Seatbelt profile bounds syscalls, not in-process data flow.",
    stderrTail: stderr.slice(-4000),
    stdoutTail: stdout.slice(-4000),
  };

  const reportPath = path.join(HERE, `report-${STAMP}.json`);
  await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`);

  log("");
  for (const requirement of requirements) {
    log(
      `${requirement.id.padEnd(28)} ${requirement.status.toUpperCase().padEnd(6)} ${
        requirement.gating ? "" : "(residual, non-gating)"
      }`,
    );
  }
  log("");
  log(`verdict: ${report.verdict.toUpperCase()}`);
  log(`profile: ${profilePath}`);
  log(`scratch: ${scratch}`);
  log(`report:  ${reportPath}`);
  if (gatingFailures.length > 0) {
    log(`failed:  ${gatingFailures.map((r) => r.id).join(", ")}`);
    process.exitCode = 1;
  }
}

await main();
