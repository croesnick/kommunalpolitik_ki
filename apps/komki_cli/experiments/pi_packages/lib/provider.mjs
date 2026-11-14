import http from "node:http";
import { appendFile, mkdir } from "node:fs/promises";
import path from "node:path";
import { StringDecoder } from "node:string_decoder";

/**
 * Logging forward proxy in front of the real llama-server.
 *
 * pi's models.json points at this proxy instead of the llama-server. The
 * proxy forwards every request verbatim (method, path, headers including the
 * Authorization header pi sends, body) to the upstream llama-server and
 * pipes the response — including SSE streams — back to pi unmodified.
 *
 * While passing through, it appends one JSONL record per request to logPath:
 *
 *   { at, method, url, status, durationMs, body, response }
 *
 * `response` is reconstructed for both streaming and non-streaming replies:
 * `{ text, reasoning, toolCalls, finishReason, usage, sse }`. Streaming
 * replies also carry timings relative to the request start (Ticket #285):
 * `firstByteMs`, `firstTokenMs` (first delta of any kind, thinking
 * included) and `firstAnswerMs` (first content or tool-call delta). The Authorization header
 * is never logged. The record shape extends the mock provider's request log
 * ({ at, method, url, body }) so shared consumers keep working.
 *
 * Bodies are accumulated as Buffers and decoded once at the end — chunk
 * boundaries must never split multi-byte UTF-8 (German fixtures). Every
 * completion path (upstream error, mid-stream abort, client abort) logs a
 * record, so diagnostic runs keep their measurements. Pending log appends
 * are awaited by close().
 */

const HOP_BY_HOP = new Set([
  "connection",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "te",
  "trailer",
  "transfer-encoding",
  "upgrade",
  "host",
  "content-length",
]);

const pendingAppends = new Set();

function parseDataLines(buffer) {
  const events = [];
  for (const line of buffer.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed.startsWith("data:")) continue;
    const payload = trimmed.slice(5).trim();
    if (!payload || payload === "[DONE]") continue;
    try {
      events.push(JSON.parse(payload));
    } catch {
      // tolerate malformed keep-alive comments
    }
  }
  return events;
}

function rebuildCalls(events) {
  const calls = new Map();
  let fallback = 0;
  for (const event of events) {
    for (const choice of event.choices ?? []) {
      for (const call of choice.delta?.tool_calls ?? []) {
        const index = call.index ?? fallback++;
        let slot = calls.get(index);
        if (!slot) {
          slot = { index, id: null, name: null, arguments: "" };
          calls.set(index, slot);
        }
        if (call.id) slot.id = call.id;
        if (call.function?.name) slot.name = call.function.name;
        slot.arguments += call.function?.arguments ?? "";
      }
    }
  }
  return [...calls.values()];
}

function reconstructSse(events) {
  let text = "";
  let reasoning = "";
  let finishReason = null;
  let usage = null;
  for (const event of events) {
    for (const choice of event.choices ?? []) {
      const delta = choice.delta ?? {};
      if (typeof delta.content === "string") text += delta.content;
      if (typeof delta.reasoning_content === "string") reasoning += delta.reasoning_content;
      if (choice.finish_reason) finishReason = choice.finish_reason;
    }
    if (event.usage && (event.choices?.length ?? 0) === 0) usage = event.usage;
  }
  return {
    text,
    reasoning,
    toolCalls: rebuildCalls(events),
    finishReason,
    usage,
    sse: true,
    chunks: events.length,
  };
}

function reconstructJson(body) {
  try {
    const parsed = JSON.parse(body);
    const choice = parsed.choices?.[0] ?? {};
    const message = choice.message ?? {};
    return {
      text: message.content ?? "",
      toolCalls: message.tool_calls ?? [],
      finishReason: choice.finish_reason ?? null,
      usage: parsed.usage ?? null,
      sse: false,
    };
  } catch {
    return {
      text: null,
      toolCalls: [],
      finishReason: null,
      usage: null,
      sse: false,
      parseError: true,
    };
  }
}

/**
 * Timestamps of the first deltas of an SSE stream (Ticket #285). Parses the
 * chunks incrementally, for timing only; StringDecoder keeps multi-byte
 * UTF-8 sequences intact across chunk boundaries. The reconstruction still
 * works on the complete buffer.
 */
function sseTimer(started) {
  const decoder = new StringDecoder("utf8");
  let pending = "";
  const timings = { firstByteMs: null, firstTokenMs: null, firstAnswerMs: null };
  return {
    timings,
    push(chunk) {
      const now = Date.now() - started;
      timings.firstByteMs ??= now;
      if (timings.firstAnswerMs !== null) return;
      pending += decoder.write(chunk);
      const lines = pending.split("\n");
      pending = lines.pop();
      for (const event of parseDataLines(lines.join("\n"))) {
        for (const choice of event.choices ?? []) {
          const delta = choice.delta ?? {};
          const answer = Boolean(delta.content) || (delta.tool_calls?.length ?? 0) > 0;
          if (answer || delta.reasoning_content) timings.firstTokenMs ??= now;
          if (answer) timings.firstAnswerMs ??= now;
        }
      }
    },
  };
}

export async function startForwardProvider({ upstreamBaseUrl, logPath } = {}) {
  if (!upstreamBaseUrl) {
    throw new Error("startForwardProvider requires upstreamBaseUrl");
  }
  const upstream = new URL(upstreamBaseUrl);
  await mkdir(path.dirname(logPath), { recursive: true });

  const server = http.createServer((req, res) => {
    const started = Date.now();
    const requestChunks = [];
    let upstreamReq = null;
    let upstreamResponded = false;
    let logged = false;

    const abortLog = () => {
      if (logged || upstreamResponded) return;
      logged = true;
      appendLog(
        logPath,
        req,
        started,
        null,
        Buffer.concat(requestChunks).toString("utf8"),
        {
          text: null,
          toolCalls: [],
          finishReason: null,
          usage: null,
          clientAborted: true,
        },
      );
    };

    req.on("data", (chunk) => {
      requestChunks.push(chunk);
    });
    req.on("aborted", () => {
      upstreamReq?.destroy();
      abortLog();
    });

    req.on("end", () => {
      const bodyBuffer = Buffer.concat(requestChunks);
      const requestBody = bodyBuffer.toString("utf8");

      const headers = { ...req.headers };
      for (const name of HOP_BY_HOP) delete headers[name];
      headers.host = `${upstream.hostname}:${upstream.port}`;

      upstreamReq = http.request(
        {
          hostname: upstream.hostname,
          port: Number(upstream.port),
          method: req.method,
          path: req.url,
          headers,
        },
        (upstreamRes) => {
          upstreamResponded = true;
          const status = upstreamRes.statusCode;
          const isSse = /text\/event-stream/i.test(
            upstreamRes.headers["content-type"] ?? "",
          );
          const responseChunks = [];
          const timer = sseTimer(started);

          // Jeder Abschlusspfad loggt genau einmal: normales Ende,
          // Upstream-Fehler mitten im Stream, Abbruch auf einer Seite.
          const finishLog = (extra) => {
            if (logged) return;
            logged = true;
            const payload = Buffer.concat(responseChunks).toString("utf8");
            const response = isSse
              ? { ...reconstructSse(parseDataLines(payload)), ...timer.timings }
              : reconstructJson(payload);
            appendLog(logPath, req, started, status, requestBody, extra
              ? { ...response, ...extra }
              : response);
          };

          res.writeHead(status, upstreamRes.headers);

          upstreamRes.on("data", (chunk) => {
            responseChunks.push(chunk);
            if (isSse) timer.push(chunk);
            res.write(chunk);
          });
          upstreamRes.on("end", () => {
            res.end();
            finishLog();
          });
          upstreamRes.on("aborted", () => {
            finishLog({ upstreamAborted: true });
            try {
              res.end();
            } catch {}
          });
          upstreamRes.on("error", (error) => {
            finishLog({ upstreamError: String(error?.message ?? error) });
            try {
              res.end();
            } catch {}
          });
        },
      );

      upstreamReq.on("error", (error) => {
        if (!res.headersSent) res.writeHead(502, { "content-type": "text/plain" });
        res.end(`forward error: ${error.message}`);
        // Nach einem geloggten Response-Ende (finishLog) keinen zweiten
        // Datensatz anhängen — Midstream-Tod darf einen Request nicht doppelt
        // loggen, sonst verrutschen die Zählungen.
        if (logged) return;
        logged = true;
        appendLog(logPath, req, started, 502, requestBody, {
          text: null,
          toolCalls: [],
          finishReason: null,
          usage: null,
          forwardError: String(error?.message ?? error),
        });
      });

      res.on("close", () => {
        // Normalfall: close kommt nach res.end() und finishLog war schon da.
        // Abbruchfall: Teil-Rekord statt Datenverlust.
        upstreamReq?.destroy();
      });

      upstreamReq.end(bodyBuffer);
    });
  });

  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });

  return {
    baseUrl: `http://127.0.0.1:${server.address().port}/v1`,
    port: server.address().port,
    close: async () => {
      await Promise.allSettled([...pendingAppends]);
      await new Promise((resolve) => {
        server.close(() => resolve());
        server.closeAllConnections?.();
      });
    },
  };
}

function appendLog(logPath, req, started, status, body, response) {
  const record = {
    at: new Date().toISOString(),
    method: req.method,
    url: req.url,
    status,
    durationMs: Date.now() - started,
    body,
    response,
  };
  const append = appendFile(logPath, `${JSON.stringify(record)}\n`).catch(() => {});
  pendingAppends.add(append);
  append.finally(() => pendingAppends.delete(append));
}
