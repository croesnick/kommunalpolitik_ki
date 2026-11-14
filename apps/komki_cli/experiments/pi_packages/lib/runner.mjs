import { spawn } from "node:child_process";
import {
  mkdir,
  readdir,
  readFile,
  stat,
  writeFile,
} from "node:fs/promises";
import path from "node:path";

import {
  DEFAULT_CONTEXT_WINDOW,
  MOCK_MODEL,
  MOCK_PROVIDER,
  NODE_BIN,
  PI_CLI,
} from "./config.mjs";
import { startMockProvider } from "./mock-provider.mjs";
import { startForwardProvider } from "./provider.mjs";
import { parseSessionFile } from "./session.mjs";

function safeId(id) {
  return String(id).replace(/[^a-zA-Z0-9_.-]/g, "-");
}

async function listFiles(root, base = root, out = []) {
  let entries;
  try {
    entries = await readdir(root, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const entry of entries) {
    const full = path.join(root, entry.name);
    if (entry.isDirectory()) {
      await listFiles(full, base, out);
    } else if (entry.isFile()) {
      let size = -1;
      try {
        size = (await stat(full)).size;
      } catch {}
      out.push(path.relative(base, full));
    } else if (entry.isSymbolicLink()) {
      out.push(`${path.relative(base, full)} (symlink)`);
    }
  }
  return out.sort();
}

function parseJsonl(text) {
  const events = [];
  const parseErrors = [];
  for (const [i, line] of text.split("\n").entries()) {
    if (!line.trim()) continue;
    try {
      events.push(JSON.parse(line));
    } catch (error) {
      parseErrors.push({ line: i + 1, error: String(error), text: line.slice(0, 300) });
    }
  }
  return { events, parseErrors };
}

async function newestSessionFile(dir) {
  const files = [];
  async function walk(current) {
    let entries;
    try {
      entries = await readdir(current, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) await walk(full);
      else if (entry.isFile() && entry.name.endsWith(".jsonl")) {
        files.push({ full, mtime: (await stat(full)).mtimeMs });
      }
    }
  }
  await walk(dir);
  files.sort((a, b) => b.mtime - a.mtime);
  return files[0]?.full ?? null;
}

/**
 * Run one pi invocation against the mock provider.
 *
 * options:
 *   id, runRoot, runDir           - isolated directory (runDir reuses a prior run)
 *   prompt, responses            - mock script
 *   tools                        - --tools value (comma separated)
 *   extensions                   - array of -e paths
 *   continue                     - add --continue
 *   settings                     - settings.json content (merged shallowly)
 *   agentFiles                   - [{ path, content }] relative to agentDir
 *   contextWindow                - models.json contextWindow
 *   timeoutMs                    - default 30000
 *   extraArgs                    - appended before prompt
 *   sessionDir                   - override session directory
 *   provider                     - real provider instead of the mock:
 *                                 { upstreamBaseUrl, apiKey, name, model, maxTokens }
 *                                 pi points at a logging forward proxy
 *                                 (lib/provider.mjs); `responses` is ignored.
 */
export async function runPi(options = {}) {
  const runRoot = options.runRoot;
  if (!runRoot) throw new Error("runPi requires runRoot");

  const runDir =
    options.runDir ??
    path.join(runRoot, safeId(options.id ?? `run-${Date.now()}`));
  const agentRoot = path.join(runDir, "agent");
  const agentDir = path.join(agentRoot, ".pi", "agent");
  const workDir = path.join(runDir, "work");
  const sessionDir = options.sessionDir ?? path.join(runDir, "sessions");
  const harnessDir = path.join(runDir, "harness");
  const requestsPath = path.join(
    harnessDir,
    `${safeId(options.id ?? "run")}-${Date.now()}`,
    "requests.jsonl",
  );

  await mkdir(agentDir, { recursive: true });
  await mkdir(workDir, { recursive: true });
  await mkdir(sessionDir, { recursive: true });
  await mkdir(harnessDir, { recursive: true });

  const contextWindow = options.contextWindow ?? DEFAULT_CONTEXT_WINDOW;

  let mock = null;
  let forwarder = null;
  let providerName = MOCK_PROVIDER;
  let modelName = MOCK_MODEL;
  let providerLabel = "Mock Model";
  let apiKey = "mock-key";
  let baseUrl;
  let maxTokens = 512;

  if (options.provider) {
    forwarder = await startForwardProvider({
      upstreamBaseUrl: options.provider.upstreamBaseUrl,
      logPath: requestsPath,
    });
    providerName = options.provider.name ?? "pi-local";
    modelName = options.provider.model ?? "local-model";
    providerLabel = modelName;
    apiKey = options.provider.apiKey;
    baseUrl = forwarder.baseUrl;
    maxTokens = options.provider.maxTokens ?? 4096;
  } else {
    mock = await startMockProvider({
      script: options.responses ?? [],
      logPath: requestsPath,
      contextWindow,
    });
    baseUrl = mock.baseUrl;
  }

  // try/finally um den ganzen Provider-Lebenszyklus: Jeder Fehler zwischen
  // Server-Start und Abschluss leakt sonst einen lauschenden Server, der den
  // Node-Prozess am Leben hält.
  let exit;
  let stdout = "";
  let stderr = "";
  let timedOut = false;
  let requestParseErrors = 0;
  let before = new Set();
  let args = [];
  let started = Date.now();

  try {
    const models = {
      providers: {
        [providerName]: {
          api: "openai-completions",
          apiKey,
          baseUrl,
          models: [
            {
              id: modelName,
              name: providerLabel,
              contextWindow,
              maxTokens,
              reasoning: false,
            },
          ],
        },
      },
    };

    const settings = {
      ...(options.settings ?? {}),
    };
    await writeFile(path.join(agentDir, "models.json"), JSON.stringify(models, null, 2));
    await writeFile(path.join(agentDir, "settings.json"), JSON.stringify(settings, null, 2));
    await writeFile(path.join(agentDir, "trust.json"), JSON.stringify({}));

    for (const file of options.agentFiles ?? []) {
      const target = path.isAbsolute(file.path)
        ? file.path
        : path.join(agentDir, file.path);
      await mkdir(path.dirname(target), { recursive: true });
      await writeFile(target, file.content ?? "");
    }

    before = new Set(await listFiles(runDir));

    args = [
      PI_CLI,
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
      sessionDir,
      "--provider",
      providerName,
      "--model",
      modelName,
      "--tools",
      options.tools ?? "read",
    ];
    if (options.continue) args.push("--continue");
    for (const extension of options.extensions ?? []) {
      args.push("-e", extension);
    }
    args.push(...(options.extraArgs ?? []));
    for (const fileArg of options.fileArgs ?? []) args.push(fileArg);
    args.push(options.prompt ?? "Sag OK");

    const env = {
      HOME: agentRoot,
      PI_CODING_AGENT_DIR: agentDir,
      PI_OFFLINE: "1",
      PATH: "/usr/bin:/bin",
      LANG: "C",
      LC_ALL: "C",
    };

    started = Date.now();
    const child = spawn(NODE_BIN, args, {
      cwd: workDir,
      env,
      stdio: ["ignore", "pipe", "pipe"],
      detached: true,
    });

    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });

    const timeoutMs = options.timeoutMs ?? 30000;
    const timer = setTimeout(() => {
      timedOut = true;
      try {
        process.kill(-child.pid, "SIGKILL");
      } catch {
        try {
          child.kill("SIGKILL");
        } catch {}
      }
    }, timeoutMs);

    exit = await new Promise((resolve) => {
      child.on("error", (error) => resolve({ code: null, signal: null, error: String(error) }));
      child.on("exit", (code, signal) => resolve({ code, signal }));
    });

    clearTimeout(timer);
  } finally {
    await mock?.close();
    await forwarder?.close();
  }

  const { events, parseErrors } = parseJsonl(stdout);
  const sessionFile = await newestSessionFile(sessionDir);
  const session = sessionFile ? await parseSessionFile(sessionFile) : null;

  const after = new Set(await listFiles(runDir));
  const created = [...after].filter((file) => !before.has(file));
  const removed = [...before].filter((file) => !after.has(file));

  const parsedRequests = [];
  try {
    const raw = await readFile(requestsPath, "utf8");
    for (const line of raw.split("\n")) {
      if (!line.trim()) continue;
      try {
        const record = JSON.parse(line);
        let body = null;
        try {
          body = JSON.parse(record.body);
        } catch {}
        parsedRequests.push({ ...record, parsed: body });
      } catch {
        requestParseErrors += 1;
      }
    }
  } catch {}

  return {
    code: exit.code,
    signal: exit.signal,
    spawnError: exit.error ?? null,
    timedOut,
    durationMs: Date.now() - started,
    stdout,
    stderr,
    events,
    parseErrors,
    requestParseErrors,
    session,
    sessionFile,
    requests: parsedRequests,
    workDir,
    agentDir,
    agentRoot,
    runDir,
    sessionDir,
    files: { created, removed },
    args,
  };
}

/**
 * Run pi in RPC mode (--mode rpc) and drive the extension UI sub-protocol.
 *
 * The client answers dialog requests, records every protocol record, and closes
 * stdin after agent_settled so pi exits cleanly. Dialog responses are returned
 * verbatim in `uiResponses`.
 */
export async function runPiRpc(options = {}) {
  const runRoot = options.runRoot;
  if (!runRoot) throw new Error("runPiRpc requires runRoot");

  const runDir =
    options.runDir ??
    path.join(runRoot, safeId(options.id ?? `rpc-${Date.now()}`));
  const agentRoot = path.join(runDir, "agent");
  const agentDir = path.join(agentRoot, ".pi", "agent");
  const workDir = path.join(runDir, "work");
  const sessionDir = options.sessionDir ?? path.join(runDir, "sessions");
  const harnessDir = path.join(runDir, "harness");
  const requestsPath = path.join(
    harnessDir,
    `${safeId(options.id ?? "rpc")}-${Date.now()}`,
    "requests.jsonl",
  );

  await mkdir(agentDir, { recursive: true });
  await mkdir(workDir, { recursive: true });
  await mkdir(sessionDir, { recursive: true });
  await mkdir(harnessDir, { recursive: true });

  const contextWindow = options.contextWindow ?? DEFAULT_CONTEXT_WINDOW;
  const mock = await startMockProvider({
    script: options.responses ?? [],
    logPath: requestsPath,
    contextWindow,
  });

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
            contextWindow,
            maxTokens: 512,
            reasoning: false,
          },
        ],
      },
    },
  };
  await writeFile(path.join(agentDir, "models.json"), JSON.stringify(models, null, 2));
  await writeFile(
    path.join(agentDir, "settings.json"),
    JSON.stringify(options.settings ?? {}, null, 2),
  );
  await writeFile(path.join(agentDir, "trust.json"), JSON.stringify({}));

  for (const file of options.agentFiles ?? []) {
    const target = path.isAbsolute(file.path)
      ? file.path
      : path.join(agentDir, file.path);
    await mkdir(path.dirname(target), { recursive: true });
    await writeFile(target, file.content ?? "");
  }

  const before = new Set(await listFiles(runDir));

  const args = [
    PI_CLI,
    "--mode",
    "rpc",
    "--offline",
    "--no-extensions",
    "--no-skills",
    "--no-context-files",
    "--no-prompt-templates",
    "--no-themes",
    "--no-approve",
    "--session-dir",
    sessionDir,
    "--provider",
    MOCK_PROVIDER,
    "--model",
    MOCK_MODEL,
    "--tools",
    options.tools ?? "read",
  ];
  for (const extension of options.extensions ?? []) {
    args.push("-e", extension);
  }
  args.push(...(options.extraArgs ?? []));

  const env = {
    HOME: agentRoot,
    PI_CODING_AGENT_DIR: agentDir,
    PI_OFFLINE: "1",
    PATH: "/usr/bin:/bin",
    LANG: "C",
    LC_ALL: "C",
  };

  const started = Date.now();
  const child = spawn(NODE_BIN, args, {
    cwd: workDir,
    env,
    stdio: ["pipe", "pipe", "pipe"],
    detached: true,
  });

  let stderr = "";
  let stdoutBuffer = "";
  let timedOut = false;
  let stdinClosed = false;
  const records = [];
  const uiRequests = [];
  const uiResponses = [];

  const writeRecord = (record) => {
    if (child.stdin.destroyed || stdinClosed) return;
    child.stdin.write(`${JSON.stringify(record)}\n`);
  };

  const closeStdin = () => {
    if (stdinClosed) return;
    stdinClosed = true;
    try {
      child.stdin.end();
    } catch {}
  };

  const handleUiRequest = (record) => {
    uiRequests.push(record);
    if (!["select", "confirm", "input", "editor"].includes(record.method)) return;
    let response;
    if (record.method === "confirm") {
      response = { type: "extension_ui_response", id: record.id, confirmed: true };
    } else if (record.method === "select") {
      response = {
        type: "extension_ui_response",
        id: record.id,
        value: record.options?.[0],
      };
    } else if (record.method === "input") {
      response = {
        type: "extension_ui_response",
        id: record.id,
        value: options.inputResponse ?? record.placeholder ?? "Antwort",
      };
    } else {
      response = {
        type: "extension_ui_response",
        id: record.id,
        value: record.prefill ?? "",
      };
    }
    uiResponses.push(response);
    writeRecord(response);
  };

  const consumeLine = (line) => {
    if (!line.trim()) return;
    let record;
    try {
      record = JSON.parse(line);
    } catch (error) {
      records.push({ type: "harness_parse_error", error: String(error), line: line.slice(0, 300) });
      return;
    }
    records.push(record);
    if (record.type === "extension_ui_request") handleUiRequest(record);
    if (record.type === "agent_settled") {
      setTimeout(closeStdin, 20);
    }
  };

  child.stdout.on("data", (chunk) => {
    stdoutBuffer += chunk;
    for (;;) {
      const newline = stdoutBuffer.indexOf("\n");
      if (newline < 0) break;
      const line = stdoutBuffer.slice(0, newline).replace(/\r$/, "");
      stdoutBuffer = stdoutBuffer.slice(newline + 1);
      consumeLine(line);
    }
  });
  child.stderr.on("data", (chunk) => {
    stderr += chunk;
  });

  writeRecord({
    id: "prompt-1",
    type: "prompt",
    message: options.prompt ?? "Sag OK",
  });

  const timeoutMs = options.timeoutMs ?? 30000;
  const timer = setTimeout(() => {
    timedOut = true;
    try {
      process.kill(-child.pid, "SIGKILL");
    } catch {
      try {
        child.kill("SIGKILL");
      } catch {}
    }
  }, timeoutMs);

  const exit = await new Promise((resolve) => {
    child.on("error", (error) => resolve({ code: null, signal: null, error: String(error) }));
    child.on("exit", (code, signal) => resolve({ code, signal }));
  });
  clearTimeout(timer);
  await mock.close();

  if (stdoutBuffer.trim()) consumeLine(stdoutBuffer.trim());

  const sessionFile = await newestSessionFile(sessionDir);
  const session = sessionFile ? await parseSessionFile(sessionFile) : null;

  const after = new Set(await listFiles(runDir));
  const created = [...after].filter((file) => !before.has(file));
  const removed = [...before].filter((file) => !after.has(file));

  const parsedRequests = [];
  let requestParseErrors = 0;
  try {
    const raw = await readFile(requestsPath, "utf8");
    for (const line of raw.split("\n")) {
      if (!line.trim()) continue;
      try {
        const record = JSON.parse(line);
        let body = null;
        try {
          body = JSON.parse(record.body);
        } catch {}
        parsedRequests.push({ ...record, parsed: body });
      } catch {
        requestParseErrors += 1;
      }
    }
  } catch {}

  return {
    code: exit.code,
    signal: exit.signal,
    spawnError: exit.error ?? null,
    timedOut,
    durationMs: Date.now() - started,
    stdout: records.map((r) => JSON.stringify(r)).join("\n"),
    stderr,
    events: records,
    records,
    uiRequests,
    uiResponses,
    parseErrors: records.filter((r) => r.type === "harness_parse_error"),
    requestParseErrors,
    session,
    sessionFile,
    requests: parsedRequests,
    workDir,
    agentDir,
    agentRoot,
    runDir,
    sessionDir,
    files: { created, removed },
    args,
  };
}

export { listFiles };
