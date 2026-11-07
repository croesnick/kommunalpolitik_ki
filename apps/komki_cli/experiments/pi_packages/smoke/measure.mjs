import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
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

/** SHA-256 of a file (pins of GGUF and binary). */
export function sha256File(file) {
  return new Promise((resolve, reject) => {
    const hash = createHash("sha256");
    createReadStream(file)
      .on("data", (chunk) => hash.update(chunk))
      .on("end", () => resolve(hash.digest("hex")))
      .on("error", reject);
  });
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
        res.on("error", (error) => resolve({ error: String(error.message ?? error) }));
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
  let config;
  try {
    config = JSON.parse(configRaw);
  } catch (error) {
    throw new Error(`config.json unlesbar (${configPath}): ${error.message}`);
  }
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

/**
 * Counts the tokens of a text via /tokenize of the running server (its own
 * tokenizer, so exact per arm). null if the server does not answer.
 */
export function llamaTokenCount(llama, text, timeoutMs = 30_000) {
  const body = JSON.stringify({ content: text, add_special: false });
  return new Promise((resolve) => {
    const req = http.request(
      {
        hostname: "127.0.0.1",
        port: llama.port,
        path: "/tokenize",
        method: "POST",
        timeout: timeoutMs,
        headers: {
          "content-type": "application/json",
          "content-length": Buffer.byteLength(body),
          authorization: `Bearer ${llama.apiKey}`,
        },
      },
      (res) => {
        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => {
          try {
            resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")).tokens?.length ?? null);
          } catch {
            resolve(null);
          }
        });
      },
    );
    req.on("timeout", () => req.destroy());
    req.on("error", () => resolve(null));
    req.end(body);
  });
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

/**
 * phys_footprint of the llama-server in MiB via /usr/bin/footprint (or
 * null). Unlike RSS it counts compressed and swapped-out pages and the
 * malloc buffers in which llama.cpp keeps weights and KV cache under Metal.
 */
export function llamaFootprintMiB(pid) {
  if (!pid) return null;
  try {
    const out = execFileSync("/usr/bin/footprint", ["-j", "/dev/stdout", String(pid)], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    const bytes = JSON.parse(out.slice(out.indexOf("{"))).processes?.[0]?.footprint;
    return Number.isFinite(bytes) ? Math.round(bytes / 1024 / 1024) : null;
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

// #372: speculative decoding (MTP drafter) logs its acceptance per task.
const DRAFT_ACCEPTANCE = /task\s+(\d+)\s*\|\s*draft acceptance = [\d.]+ \(\s*(\d+) accepted \/\s*(\d+) generated\)/;

/** Pools draft acceptance over [{ accepted, generated }]; missing values count as 0. */
export function poolDraft(list) {
  const accepted = list.reduce((s, d) => s + (d?.accepted ?? 0), 0);
  const generated = list.reduce((s, d) => s + (d?.generated ?? 0), 0);
  return { accepted, generated, rate: generated ? accepted / generated : null };
}

/**
 * Reads the log segment [startOffset, endOffset) and splits it into
 * requests: per `task N` a prompt-eval and an eval line, with an MTP
 * drafter also the draft acceptance.
 * [{ task, promptTokens, promptMs, evalTokens, evalMs, draftAccepted,
 *    draftGenerated, tokensPerSecond }]
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
      entry = {
        task,
        promptTokens: null,
        promptMs: null,
        evalTokens: null,
        evalMs: null,
        draftAccepted: null,
        draftGenerated: null,
      };
      byTask.set(task, entry);
    }
    const prompt = /prompt eval time =\s*([\d.]+) ms \/(\s*\d+) tokens/.exec(line);
    const evalm = /(?<!prompt )eval time =\s*([\d.]+) ms \/(\s*\d+) tokens/.exec(line);
    const draft = DRAFT_ACCEPTANCE.exec(match[0]);
    if (draft) {
      entry.draftAccepted = Number(draft[2]);
      entry.draftGenerated = Number(draft[3]);
    } else if (prompt) {
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

/**
 * Summary of a llama-server log written with -lv 4 (#372 debug probe).
 * Contexts in load order (main model, then MTP drafter) with their Flash
 * Attention lines (labelled main/draft only if exactly two contexts load);
 * context checkpoints created and restored; draft acceptance per request in
 * log order and pooled over requests with and without a restored checkpoint.
 */
export function llamaDebugSummary(text) {
  const contexts = [];
  const requests = [];
  const restoredTasks = new Set();
  let created = 0;
  let restored = 0;
  for (const line of text.split("\n")) {
    if (line.includes("llama_context: constructing llama_context")) contexts.push([]);
    const fa = /resolve_fused_ops: (Flash Attention.*)$/.exec(line);
    if (fa && contexts.length > 0) contexts.at(-1).push(fa[1].trim());
    if (line.includes("created context checkpoint")) created += 1;
    const restore = /task (\d+) \| restored context checkpoint/.exec(line);
    if (restore) {
      restored += 1;
      restoredTasks.add(restore[1]);
    }
    const draft = DRAFT_ACCEPTANCE.exec(line);
    if (draft) requests.push({ task: draft[1], accepted: Number(draft[2]), generated: Number(draft[3]) });
  }
  for (const request of requests) request.restored = restoredTasks.has(request.task);
  const pool = (withRestore) => {
    const list = requests.filter((r) => r.restored === withRestore);
    return { requests: list.length, ...poolDraft(list) };
  };
  const roles = contexts.length === 2 ? ["main", "draft"] : [];
  return {
    contexts: contexts.map((fa, i) => ({ role: roles[i] ?? `context ${i}`, fa })),
    checkpointsCreated: created,
    checkpointsRestored: restored,
    requests,
    draft: { withRestore: pool(true), withoutRestore: pool(false) },
  };
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

  // Schemata über alle Chat-Requests mergen (last wins): Ein unparsebarer
  // erster Datensatz darf die Map nicht leeren und damit jeden Call des
  // Laufs als unknown-tool fehlklassifizieren.
  const schemas = new Map();
  for (const request of chatRequests) {
    for (const tool of request.parsed?.tools ?? []) {
      const fn = tool.function ?? tool;
      if (fn?.name) schemas.set(fn.name, fn.parameters ?? null);
    }
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

      // Valides JSON, aber kein Objekt (null, 42, "x", [...]) ist ein
      // Malformed-Call — klassifizieren statt zu werfen oder als ok zu werten.
      if (typeof args !== "object" || args === null || Array.isArray(args)) {
        entry.valid = false;
        entry.class = "wrong-type";
        entry.details = { got: Array.isArray(args) ? "array" : typeof args, expected: "object" };
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

/**
 * From this many identical tool calls in a row on, a run counts as a
 * tool-call loop (#383). Calibrated on the #372 proxy logs: clean runs
 * never repeat a call, benign retries reach 3 (`read` of one note), the
 * loops that ended on their own reached 7 and 10, the ones that ran into
 * the timeout 600 and 647.
 */
export const TOOL_LOOP_REPEATS = 5;

/** Compaction requests of pi: a side request, not a turn of the agent. */
export function isSummaryRequest(record) {
  try {
    const system = JSON.parse(record.body).messages?.find((m) => m.role === "system");
    const text = typeof system?.content === "string" ? system.content : JSON.stringify(system?.content ?? "");
    return text.startsWith("You are a context summarization assistant.");
  } catch {
    return false;
  }
}

function callSignature(raw) {
  const call = normalizeCall(raw);
  try {
    const parsed = JSON.parse(call.arguments);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      const sorted = Object.fromEntries(Object.entries(parsed).sort(([a], [b]) => a.localeCompare(b)));
      return { name: call.name, arguments: JSON.stringify(sorted) };
    }
  } catch {
    // unparsable arguments compare as raw text
  }
  return { name: call.name, arguments: call.arguments };
}

/**
 * Tool-call loops in a proxy log (#383): runs of at least `minRepeats`
 * consecutive model turns with identical tool calls (same names, same
 * arguments up to key order). A turn without tool calls ends a run;
 * compaction summaries are skipped. Result per loop:
 *   { name, arguments, repeats, firstAt }
 */
export function toolCallLoops(records, minRepeats = TOOL_LOOP_REPEATS) {
  const loops = [];
  let run = null;
  const close = () => {
    if (run?.repeats >= minRepeats) {
      const single = run.calls.length === 1;
      loops.push({
        name: run.calls.map((c) => c.name).join("+"),
        arguments: single ? run.calls[0].arguments : JSON.stringify(run.calls.map((c) => c.arguments)),
        repeats: run.repeats,
        firstAt: run.firstAt,
      });
    }
    run = null;
  };
  for (const record of records) {
    if (isSummaryRequest(record)) continue;
    const calls = (record.response?.toolCalls ?? []).map(callSignature);
    const key = JSON.stringify(calls);
    if (calls.length === 0 || key !== run?.key) close();
    if (calls.length === 0) continue;
    if (run) run.repeats += 1;
    else run = { key, calls, repeats: 1, firstAt: record.at };
  }
  close();
  return loops;
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
