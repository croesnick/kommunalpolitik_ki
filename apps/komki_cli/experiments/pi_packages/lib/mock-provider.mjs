import http from "node:http";
import { appendFile, mkdir } from "node:fs/promises";
import path from "node:path";

import { MOCK_MODEL } from "./config.mjs";

/**
 * Scriptable OpenAI-compatible provider.
 *
 * A response is one of:
 *   { text: "..." }
 *   { toolCalls: [{ name, arguments: object|string, id? }], text?: "..." }
 *   { raw: object }                    // exact assistant message (non-stream)
 *
 * `arguments` may be an intentionally malformed JSON string. This is required
 * to observe tool-repair behaviour without a real model.
 */

function sse(res, payload) {
  res.write(`data: ${JSON.stringify(payload)}\n\n`);
}

function chunk(delta, finishReason = null) {
  return {
    id: "chatcmpl-mock",
    object: "chat.completion.chunk",
    created: 1,
    model: MOCK_MODEL,
    choices: [{ index: 0, delta, finish_reason: finishReason }],
  };
}

function normalizeToolCalls(response) {
  return (response.toolCalls ?? []).map((call, index) => {
    const args =
      typeof call.arguments === "string"
        ? call.arguments
        : JSON.stringify(call.arguments ?? {});
    return {
      id: call.id ?? `call_mock_${index + 1}`,
      type: "function",
      function: { name: call.name, arguments: args },
    };
  });
}

export async function startMockProvider({ script = [], logPath, contextWindow } = {}) {
  const requests = [];
  let index = 0;

  await mkdir(path.dirname(logPath), { recursive: true });

  const server = http.createServer((req, res) => {
    let body = "";
    req.on("data", (d) => {
      body += d;
    });
    req.on("end", async () => {
      const entry = {
        at: new Date().toISOString(),
        method: req.method,
        url: req.url,
        body,
      };
      requests.push(entry);
      await appendFile(logPath, `${JSON.stringify(entry)}\n`).catch(() => {});

      if (req.method === "GET" && req.url === "/v1/models") {
        res.writeHead(200, { "content-type": "application/json" });
        res.end(
          JSON.stringify({
            object: "list",
            data: [
              {
                id: MOCK_MODEL,
                object: "model",
                owned_by: "mock",
                context_window: contextWindow,
              },
            ],
          }),
        );
        return;
      }

      if (req.method !== "POST" || req.url !== "/v1/chat/completions") {
        res.writeHead(404, { "content-type": "text/plain" });
        res.end("not found");
        return;
      }

      let parsed = {};
      try {
        parsed = JSON.parse(body || "{}");
      } catch {
        res.writeHead(400, { "content-type": "text/plain" });
        res.end("invalid json");
        return;
      }

      const selected =
        index < script.length
          ? script[index]
          : { text: "SCRIPT_EXHAUSTED_FINAL" };
      index += 1;

      if (selected.error) {
        res.writeHead(selected.error.status ?? 500, {
          "content-type": "application/json",
        });
        res.end(
          JSON.stringify({
            error: { message: selected.error.message ?? "mock error", type: "mock" },
          }),
        );
        return;
      }

      const toolCalls = normalizeToolCalls(selected);
      const text = selected.text ?? "";
      const finishReason = toolCalls.length > 0 ? "tool_calls" : "stop";

      if (parsed.stream) {
        res.writeHead(200, {
          "content-type": "text/event-stream",
          "cache-control": "no-cache",
          connection: "keep-alive",
        });
        sse(res, chunk({ role: "assistant", content: text || undefined }));
        if (text) {
          sse(res, chunk({ content: text }));
        }
        if (toolCalls.length > 0) {
          sse(
            res,
            chunk({
              tool_calls: toolCalls.map((call, i) => ({
                index: i,
                id: call.id,
                type: "function",
                function: call.function,
              })),
            }),
          );
        }
        sse(res, chunk({}, finishReason));
        sse(res, {
          id: "chatcmpl-mock",
          object: "chat.completion.chunk",
          created: 1,
          model: MOCK_MODEL,
          choices: [],
          usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 },
        });
        res.write("data: [DONE]\n\n");
        res.end();
        return;
      }

      res.writeHead(200, { "content-type": "application/json" });
      res.end(
        JSON.stringify({
          id: "chatcmpl-mock",
          object: "chat.completion",
          created: 1,
          model: MOCK_MODEL,
          choices: [
            {
              index: 0,
              message: {
                role: "assistant",
                content: text || null,
                ...(toolCalls.length > 0 ? { tool_calls: toolCalls } : {}),
              },
              finish_reason: finishReason,
            },
          ],
          usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 },
        }),
      );
    });
  });

  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });

  const port = server.address().port;
  return {
    baseUrl: `http://127.0.0.1:${port}/v1`,
    port,
    requests,
    close: () =>
      new Promise((resolve) => {
        server.close(() => resolve());
        server.closeAllConnections?.();
      }),
  };
}
