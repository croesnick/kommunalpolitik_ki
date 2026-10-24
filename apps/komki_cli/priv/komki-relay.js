// komki-relay.js — stdio-MCP ↔ Vermittler über den Unix-Socket (Ticket #143,
// CONTRACT §8). Geschrieben von komki_cli nach <base>/pi-home/.pi/agent/;
// pi startet es als stdio-MCP-Server. Nur Node-Standardbibliothek.
//
// Umgebung: KOMKI_MEDIATOR_SOCKET (Socket-Pfad), KOMKI_MEDIATOR_TOKEN
// (Bearer-Token), KOMKI_SESSION_ID (Zuordnung im PDR). Token und Inhalte
// erscheinen nie auf stderr.
"use strict";
const http = require("node:http");
const readline = require("node:readline");

const SOCKET = process.env.KOMKI_MEDIATOR_SOCKET;
const TOKEN = process.env.KOMKI_MEDIATOR_TOKEN;
const SESSION = process.env.KOMKI_SESSION_ID;

for (const [name, value] of [["KOMKI_MEDIATOR_SOCKET", SOCKET], ["KOMKI_MEDIATOR_TOKEN", TOKEN], ["KOMKI_SESSION_ID", SESSION]]) {
  if (!value) {
    process.stderr.write(`komki-relay: ${name} fehlt\n`);
    process.exit(1);
  }
}

let mcpSession = null;
let queue = Promise.resolve();

function emit(message) {
  process.stdout.write(JSON.stringify(message) + "\n");
}

function emitError(id, code, message) {
  emit({ jsonrpc: "2.0", id: id === undefined ? null : id, error: { code, message } });
}

function post(body) {
  return new Promise((resolve, reject) => {
    const headers = {
      Host: "localhost",
      "Content-Type": "application/json",
      Accept: "application/json, text/event-stream",
      Authorization: `Bearer ${TOKEN}`,
      "X-Komki-Session": SESSION,
      "Content-Length": Buffer.byteLength(body),
    };
    if (mcpSession) headers["Mcp-Session-Id"] = mcpSession;

    const req = http.request({ socketPath: SOCKET, path: "/mcp", method: "POST", headers, agent: false }, (res) => {
      const chunks = [];
      res.on("data", (chunk) => chunks.push(chunk));
      res.on("end", () => resolve({ res, text: Buffer.concat(chunks).toString("utf8") }));
      res.on("error", reject);
    });
    req.on("error", reject);
    req.end(body);
  });
}

// SSE: Ereignisse durch Leerzeilen getrennt, mehrere data:-Zeilen je Ereignis.
function sseMessages(text) {
  const out = [];
  for (const event of text.split(/\r?\n\r?\n/)) {
    const data = event
      .split(/\r?\n/)
      .filter((line) => line.startsWith("data:"))
      .map((line) => line.slice(5).replace(/^ /, ""))
      .join("\n");
    if (data) out.push(JSON.parse(data));
  }
  return out;
}

function jsonMessages(text) {
  if (!text.trim()) return [];
  const parsed = JSON.parse(text);
  return Array.isArray(parsed) ? parsed : [parsed];
}

async function relay(line) {
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    emitError(null, -32700, "komki-relay: ungültiges JSON auf stdin");
    return;
  }
  const isRequest = message.id !== undefined && message.method !== undefined;

  try {
    const { res, text } = await post(line);
    const session = res.headers["mcp-session-id"];
    if (session) mcpSession = session;

    if (res.statusCode === 202) return;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      if (isRequest) emitError(message.id, -32000, `komki-relay: Vermittler antwortet HTTP ${res.statusCode}`);
      else process.stderr.write(`komki-relay: Nachricht abgelehnt (HTTP ${res.statusCode})\n`);
      return;
    }

    const type = String(res.headers["content-type"] || "");
    const messages = type.includes("text/event-stream") ? sseMessages(text) : jsonMessages(text);
    // anubis quittiert manches mit "{}" — nur echte JSON-RPC-Nachrichten weiter.
    messages.filter((m) => m && m.jsonrpc === "2.0").forEach(emit);
  } catch (error) {
    if (isRequest) emitError(message.id, -32000, `komki-relay: Vermittler nicht erreichbar (${error.code || "Fehler"})`);
    else process.stderr.write(`komki-relay: Vermittler nicht erreichbar (${error.code || "Fehler"})\n`);
  }
}

// Strikt nacheinander: initialize setzt die Mcp-Session-Id, bevor die
// nächste Nachricht hinausgeht.
const input = readline.createInterface({ input: process.stdin, terminal: false });
input.on("line", (line) => {
  if (!line.trim()) return;
  queue = queue.then(() => relay(line));
});
// stdin zu: keine offenen Handles mehr (agent: false, kein Keep-Alive) —
// Node endet von selbst, sobald die letzte Antwort geschrieben ist.
