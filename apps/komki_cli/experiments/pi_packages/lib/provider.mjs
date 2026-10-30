import http from "node:http";
import { appendFile, mkdir } from "node:fs/promises";
import path from "node:path";

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
 * `{ text, toolCalls, finishReason, usage, sse }`. The Authorization header
 * is never logged. The record shape extends the mock provider's request log
 * ({ at, method, url, body }) so shared consumers keep working.
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
  let finishReason = null;
  let usage = null;
  for (const event of events) {
    for (const choice of event.choices ?? []) {
      const delta = choice.delta ?? {};
      if (typeof delta.content === "string") text += delta.content;
      if (choice.finish_reason) finishReason = choice.finish_reason;
    }
    if (event.usage && (event.choices?.length ?? 0) === 0) usage = event.usage;
  }
  return {
    text,
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

export async function startForwardProvider({ upstreamBaseUrl, logPath } = {}) {
  if (!upstreamBaseUrl) {
    throw new Error("startForwardProvider requires upstreamBaseUrl");
  }
  const upstream = new URL(upstreamBaseUrl);
  await mkdir(path.dirname(logPath), { recursive: true });

  const server = http.createServer((req, res) => {
    const started = Date.now();
    let requestBody = "";
    req.on("data", (chunk) => {
      requestBody += chunk;
    });
    req.on("end", () => {
      const headers = { ...req.headers };
      for (const name of HOP_BY_HOP) delete headers[name];
      headers.host = `${upstream.hostname}:${upstream.port}`;

      const upstreamReq = http.request(
        {
          hostname: upstream.hostname,
          port: Number(upstream.port),
          method: req.method,
          path: req.url,
          headers,
        },
        (upstreamRes) => {
          const status = upstreamRes.statusCode;
          const isSse = /text\/event-stream/i.test(
            upstreamRes.headers["content-type"] ?? "",
          );
          let payloadBuffer = "";

          res.writeHead(status, upstreamRes.headers);

          upstreamRes.on("data", (chunk) => {
            payloadBuffer += chunk;
            res.write(chunk);
          });
          upstreamRes.on("end", () => {
            res.end();
            const response = isSse
              ? reconstructSse(parseDataLines(payloadBuffer))
              : reconstructJson(payloadBuffer);
            appendLog(logPath, req, started, status, requestBody, response);
          });
        },
      );

      upstreamReq.on("error", (error) => {
        if (!res.headersSent) res.writeHead(502, { "content-type": "text/plain" });
        res.end(`forward error: ${error.message}`);
        appendLog(logPath, req, started, 502, requestBody, {
          text: null,
          toolCalls: [],
          finishReason: null,
          usage: null,
          forwardError: String(error?.message ?? error),
        });
      });

      req.on("aborted", () => {
        upstreamReq.destroy();
      });
      res.on("close", () => {
        upstreamReq.destroy();
      });

      upstreamReq.end(requestBody);
    });
  });

  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });

  return {
    baseUrl: `http://127.0.0.1:${server.address().port}/v1`,
    port: server.address().port,
    close: () =>
      new Promise((resolve) => {
        server.close(() => resolve());
        server.closeAllConnections?.();
      }),
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
  appendFile(logPath, `${JSON.stringify(record)}\n`).catch(() => {});
}
