import { execFileSync } from "node:child_process";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { readFile, stat } from "node:fs/promises";

/**
 * Mess-Helfer für den Realmodell-Smoke-Test (Ticket #158).
 *
 * Die llama-server-Instanz wird nicht vom Harness gestartet — sie gehört der
 * komki-Instanz (KOMKI_HOME, default ~/.local/share/komki). Der Harness
 * prüft Health und Key-Pflicht und liest Port/Key/Pid aus der Instanz.
 */

export function komkiBaseDir() {
  return process.env.KOMKI_HOME ?? path.join(os.homedir(), ".local", "share", "komki");
}

async function readTrimmed(file) {
  try {
    return (await readFile(file, "utf8")).trim();
  } catch {
    return null;
  }
}

/** GET ohne Key auf den llama-server; liefert {code} oder {error}. */
export function llamaGet(port, urlPath, timeoutMs = 3000) {
  return new Promise((resolve) => {
    const req = http.get(
      { hostname: "127.0.0.1", port, path: urlPath, timeout: timeoutMs },
      (res) => {
        res.resume();
        res.on("end", () => resolve({ code: String(res.statusCode) }));
      },
    );
    req.on("timeout", () => {
      req.destroy();
      resolve({ error: "timeout" });
    });
    req.on("error", (error) => resolve({ error: String(error.message ?? error) }));
  });
}

/**
 * Löst die laufende llama-server-Instanz auf.
 * Wirft mit klarer Anweisung, wenn der Server nicht erreichbar ist.
 */
export async function resolveLlama() {
  const base = komkiBaseDir();
  const configPath = path.join(base, "config.json");
  const configRaw = await readTrimmed(configPath);
  if (!configRaw) {
    throw new Error(
      `keine komki-Instanz gefunden (${configPath}) — komki init ausführen`,
    );
  }
  const config = JSON.parse(configRaw);
  const port = config.port;
  const apiKey = await readTrimmed(path.join(base, "tmp", "llama.key"));
  if (!port || !apiKey) {
    throw new Error(
      "Instanz unvollständig (Port oder llama.key fehlen) — komki init/up ausführen",
    );
  }
  const health = await llamaGet(port, "/health");
  if (health.code !== "200") {
    throw new Error(
      `llama-server antwortet nicht auf /health (${health.code ?? health.error}) — komki up ausführen`,
    );
  }
  const props = await llamaGet(port, "/props");
  const authRequired = props.code === "401";
  const pid = Number((await readTrimmed(path.join(base, "tmp", "llama-server.pid"))) ?? 0);

  return {
    base,
    port,
    pid,
    apiKey,
    authRequired,
    baseUrl: `http://127.0.0.1:${port}/v1`,
    gguf: config.gguf_path ?? null,
    ctx: config.ctx ?? null,
    logPath: path.join(base, "tmp", "llama-server.log"),
  };
}

/** Resident Set Size des llama-server in MiB (oder null). */
export function llamaRssMiB(pid) {
  if (!pid) return null;
  try {
    const out = execFileSync("ps", ["-o", "rss=", "-p", String(pid)], {
      encoding: "utf8",
    }).trim();
    const rssKiB = Number(out);
    return Number.isFinite(rssKiB) ? Math.round(rssKiB / 1024) : null;
  } catch {
    return null;
  }
}

/** Aktueller Bytestand des llama-server-Logs (als Slicegrenze). */
export async function llamaLogOffset(llama) {
  try {
    return (await stat(llama.logPath)).size;
  } catch {
    return 0;
  }
}

/**
 * Liest das Log-Segment [startOffset, endOffset) und zerlegt es in Requests:
 * je `task N` ein Paar aus prompt-eval und eval-Zeile.
 * [{ task, promptTokens, promptMs, evalTokens, evalMs, tokensPerSecond }]
 */
export async function llamaLogSegment(llama, startOffset, endOffset) {
  let text = "";
  try {
    const handle = await readFile(llama.logPath);
    text = handle.subarray(startOffset, endOffset).toString("utf8");
  } catch {
    return [];
  }
  const byTask = new Map();
  const lineRe = /slot print_timing:.*?task\s+(\d+)\s*\|(.+)$/gm;
  for (const match of text.matchAll(lineRe)) {
    const task = match[1];
    const line = match[2];
    let entry = byTask.get(task);
    if (!entry) {
      entry = { task, promptTokens: null, promptMs: null, evalTokens: null, evalMs: null };
      byTask.set(task, entry);
    }
    const prompt = /prompt eval time =\s*([\d.]+) ms \/(\s*\d+) tokens/.exec(line);
    const evalm = /(?<!prompt )eval time =\s*([\d.]+) ms \/(\s*\d+) tokens/.exec(line);
    if (prompt) {
      entry.promptMs = Number(prompt[1]);
      entry.promptTokens = Number(prompt[2]);
    } else if (evalm) {
      entry.evalMs = Number(evalm[1]);
      entry.evalTokens = Number(evalm[2]);
    }
  }
  return [...byTask.values()].map((entry) => ({
    ...entry,
    tokensPerSecond:
      entry.evalMs && entry.evalTokens
        ? Math.round((entry.evalTokens / entry.evalMs) * 1000 * 100) / 100
        : null,
  }));
}

// ---------------------------------------------------------------- Tool-Validierung

function normalizeCall(call) {
  if (call.function?.name) {
    return { id: call.id ?? null, name: call.function.name, arguments: call.function.arguments };
  }
  return { id: call.id ?? null, name: call.name, arguments: call.arguments };
}

function typeOf(value) {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  return typeof value;
}

/**
 * Validiert alle Tool-Calls eines Proxy-Logs gegen die JSON-Schemata, die
 * pi im ersten Request übermittelt hat. Ergebnis je Call:
 *   { name, args, valid, class, details }
 * class ∈ ok | invalid-json | unknown-tool | missing-required | wrong-type | extra-keys
 */
export function validateToolCalls(requests) {
  const chatRequests = requests.filter(
    (r) => r.method === "POST" && (r.url ?? "").includes("/chat/completions"),
  );
  if (chatRequests.length === 0) return [];

  const schemas = new Map();
  for (const tool of chatRequests[0].parsed?.tools ?? []) {
    const fn = tool.function ?? tool;
    if (fn?.name) schemas.set(fn.name, fn.parameters ?? null);
  }

  const calls = [];
  for (const request of chatRequests) {
    for (const raw of request.response?.toolCalls ?? []) {
      const call = normalizeCall(raw);
      const entry = {
        at: request.at,
        name: call.name,
        rawArguments: call.arguments,
        valid: true,
        class: "ok",
        details: null,
      };

      if (!schemas.has(call.name)) {
        entry.valid = false;
        entry.class = "unknown-tool";
        calls.push(entry);
        continue;
      }

      let args;
      try {
        args = JSON.parse(call.arguments);
      } catch {
        entry.valid = false;
        entry.class = "invalid-json";
        // Länge-Truncation erkennen: Completion == max_completion_tokens
        // heißt, die Antwort wurde am Output-Limit abgeschnitten — die
        // Argumente sind dann unvollständig, nicht vom Modell verhunzt.
        const completion = request.response?.usage?.completion_tokens ?? null;
        const limit = request.parsed?.max_completion_tokens ?? null;
        entry.details = {
          completionTokens: completion,
          maxCompletionTokens: limit,
          truncatedByOutputLimit: completion !== null && limit !== null && completion >= limit,
        };
        calls.push(entry);
        continue;
      }
      entry.args = args;

      const schema = schemas.get(call.name);
      const properties = schema?.properties ?? {};
      const required = schema?.required ?? [];

      const missing = required.filter((key) => !(key in args));
      if (missing.length > 0) {
        entry.valid = false;
        entry.class = "missing-required";
        entry.details = { missing };
      }
      const wrongType = [];
      for (const [key, value] of Object.entries(args)) {
        const expected = properties[key]?.type;
        if (expected && typeOf(value) !== expected) wrongType.push({ key, expected, got: typeOf(value) });
      }
      if (wrongType.length > 0) {
        entry.valid = false;
        entry.class = "wrong-type";
        entry.details = { wrongType, ...(entry.details ?? {}) };
      }
      const extra = Object.keys(args).filter((key) => !(key in properties));
      if (extra.length > 0) {
        // extra-keys sind kein Validierungsfehler für pi, aber Korpus-Material:
        // pi-tool-repair repariert den dokumentierten Alias file_path → path.
        entry.class = entry.class === "ok" ? "extra-keys" : entry.class;
        entry.details = { extra, ...(entry.details ?? {}) };
        entry.aliasCandidate = extra.includes("file_path") && "path" in properties;
      }
      calls.push(entry);
    }
  }
  return calls;
}

/** Summiert die usage aus den Proxy-Antworten (falls der Server sie liefert). */
export function usageTotals(requests) {
  let prompt = 0;
  let completion = 0;
  let withUsage = 0;
  for (const request of requests) {
    const usage = request.response?.usage;
    if (usage) {
      withUsage += 1;
      prompt += usage.prompt_tokens ?? 0;
      completion += usage.completion_tokens ?? 0;
    }
  }
  return { prompt, completion, requestsWithUsage: withUsage };
}

/** Summiert die usage aus den Assistant-Nachrichten der Session. */
export function sessionUsageTotals(session) {
  let input = 0;
  let output = 0;
  let messages = 0;
  for (const message of session?.messages ?? []) {
    const usage = message?.usage;
    if (message?.role === "assistant" && usage) {
      messages += 1;
      input += usage.input ?? 0;
      output += usage.output ?? 0;
    }
  }
  return { input, output, messages };
}

/** Letzter Assistant-Text der Session (die finale Antwort des Modells). */
export function answerText(session) {
  const texts = (session?.messages ?? [])
    .filter((m) => m.role === "assistant")
    .map((m) => (typeof m.content === "string" ? m.content : contentBlocksText(m.content)));
  return texts.at(-1) ?? null;
}

function contentBlocksText(content) {
  if (!Array.isArray(content)) return "";
  return content
    .filter((block) => block?.type === "text")
    .map((block) => block.text ?? "")
    .join("\n");
}

/** Der pi-Kern-Summary-Request der Compaction (System-Prompt-Signatur). */
export function summaryRequests(requests) {
  return requests.filter((request) => {
    const messages = request.parsed?.messages ?? [];
    const system = messages.find((m) => m.role === "system");
    const systemText =
      typeof system?.content === "string"
        ? system.content
        : JSON.stringify(system?.content ?? "");
    return /^You are a context summarization assistant\./.test(systemText);
  });
}
