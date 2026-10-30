#!/usr/bin/env node
/**
 * Aufgabe 5 des Realmodell-Smoke-Tests (Ticket #158): ask_user_question im
 * interaktiven TUI, aber ohne Skripttrick des Modells — der echte Lauf.
 *
 * Das Modell bekommt eine Drucksache mit unklarem Prüfumfang. Es soll selbst
 * entscheiden, das rpiv-ask-user-question-Tool zu rufen. Der Harness erkennt
 * den Dialog an der rpiv-Signatur ("Type something." + "❯"), wählt mit der
 * dokumentierten Taste 1 die erste Option und verifiziert die Antwort in
 * Session und Folge-Request. Erscheint kein Dialog, ist das der dokumentierte
 * Fehlerfall (Modell fragt im Klartext oder ruft das Tool nicht).
 *
 * Aufruf:
 *   node smoke/run-tui.mjs [--root <run-root>]
 *
 * Ohne --root entsteht ein eigener Lauf unter $KOMKI_PI_EXPERIMENTS_DIR/runs.
 */
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  statSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";

import { PACKAGES, PI_CLI, packageDir, runRoot, timestamp } from "../lib/config.mjs";
import { contentText, parseSessionFile } from "../lib/session.mjs";
import { startForwardProvider } from "../lib/provider.mjs";
import {
  answerText,
  llamaRssMiB,
  resolveLlama,
  sessionUsageTotals,
  usageTotals,
  validateToolCalls,
} from "./measure.mjs";
import { DRUCKSACHE_BAHNHOFSTR } from "./fixtures.mjs";
import {
  capturePane,
  killServer,
  killSession,
  sendKey,
  sendLiteral,
  startSession,
  trimCapture,
  waitForPane,
  waitForSessionExit,
} from "../lib/tmux.mjs";

const PACKAGE = PACKAGES.askUser;
const EXTENSION = path.join(packageDir(PACKAGE), "index.ts");
const SOCKET = `komki-smoke-tui-${process.pid}`;
const SESSION = `komki-smoke-ask-${process.pid}`;

const PROMPT =
  "Ich will die Drucksache drucksache-bahnhofstr.md für die nächste Ausschusssitzung vorbereiten, weiß aber noch nicht, wie tief ich sie prüfen soll. Lies die Drucksache und stelle mir dazu genau eine strukturierte Rückfrage mit sinnvollen Optionen.";

const READY_TIMEOUT_MS = 20_000;
const DIALOG_TIMEOUT_MS = 180_000;
const ANSWER_TIMEOUT_MS = 120_000;

function parseArgs(argv) {
  const args = { root: null };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--root") args.root = argv[i + 1];
  }
  return args;
}

function stamp(date = new Date()) {
  return date.toISOString().replace(/[:.]/g, "-");
}

function shQuote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

function findNewestJsonl(root) {
  const found = [];
  const walk = (dir) => {
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.isFile() && entry.name.endsWith(".jsonl")) {
        found.push({ file: full, mtime: statSync(full).mtimeMs });
      }
    }
  };
  walk(root);
  found.sort((a, b) => b.mtime - a.mtime);
  return found[0]?.file ?? null;
}

function readRequests(logPath) {
  try {
    return readFileSync(logPath, "utf8")
      .split("\n")
      .filter(Boolean)
      .map((line) => {
        const record = JSON.parse(line);
        let parsed = null;
        try {
          parsed = JSON.parse(record.body);
        } catch {}
        return { ...record, parsed };
      });
  } catch {
    return [];
  }
}

function requirement(id, text, status, observed, gating = true) {
  return { id, requirement: text, status, observed, gating };
}

function verdict(requirements, blocker) {
  if (blocker) return "fail";
  if (requirements.some((r) => r.gating && r.status === "fail")) return "fail";
  if (requirements.some((r) => r.gating && (r.status === "partial" || r.status === "not-tested"))) {
    return "partial";
  }
  return "pass";
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = args.root ?? runRoot(timestamp());
  const runDir = path.join(root, "task-5-tui");
  const agentRoot = path.join(runDir, "agent");
  const agentDir = path.join(agentRoot, ".pi", "agent");
  const workDir = path.join(runDir, "work");
  const sessionDir = path.join(runDir, "sessions");
  const harnessDir = path.join(runDir, "harness");
  const requestsLog = path.join(harnessDir, "requests.jsonl");
  const wrapperPath = path.join(runDir, "run-pi.sh");

  for (const dir of [agentDir, workDir, sessionDir, harnessDir]) {
    mkdirSync(dir, { recursive: true });
  }
  writeFileSync(path.join(workDir, "drucksache-bahnhofstr.md"), DRUCKSACHE_BAHNHOFSTR);

  const llama = await resolveLlama();
  const rssBefore = llamaRssMiB(llama.pid);
  const forwarder = await startForwardProvider({
    upstreamBaseUrl: llama.baseUrl,
    logPath: requestsLog,
  });

  writeFileSync(
    path.join(agentDir, "models.json"),
    JSON.stringify(
      {
        providers: {
          "pi-local": {
            api: "openai-completions",
            apiKey: llama.apiKey,
            baseUrl: forwarder.baseUrl,
            models: [
              {
                id: "local-model",
                name: "local-model",
                contextWindow: 131072,
                // Produktiv-Default von pi, wenn models.json kein maxTokens
                // setzt (provider-composer.js) — gleiche Basis wie run-smoke.
                maxTokens: 16384,
                reasoning: false,
              },
            ],
          },
        },
      },
      null,
      2,
    ),
  );
  writeFileSync(path.join(agentDir, "settings.json"), "{}\n");
  writeFileSync(path.join(agentDir, "trust.json"), "{}\n");

  writeFileSync(
    wrapperPath,
    [
      "#!/bin/sh",
      `export HOME=${shQuote(agentRoot)}`,
      `export PI_CODING_AGENT_DIR=${shQuote(agentDir)}`,
      "export PI_OFFLINE=1",
      "export PATH='/usr/bin:/bin'",
      "export LANG=C",
      "export LC_ALL=C",
      `cd ${shQuote(workDir)}`,
      `exec ${shQuote(process.execPath)} ${shQuote(PI_CLI)} --offline --no-extensions --no-skills --no-context-files --no-prompt-templates --no-themes --no-approve --session-dir ${shQuote(sessionDir)} --provider pi-local --model local-model --tools read,ask_user_question -e ${shQuote(EXTENSION)}`,
      "",
    ].join("\n"),
    { mode: 0o755 },
  );

  const requirements = [];
  const captures = {};
  let blocker = null;
  let dialogVisible = false;
  let answeredOk = false;
  let exitedAfterCtrlD = false;
  let dialogWaitMs = null;
  let sessionFile = null;
  let session = null;

  try {
    startSession({
      socket: SOCKET,
      session: SESSION,
      cwd: workDir,
      command: `exec /bin/sh ${shQuote(wrapperPath)}`,
      width: 120,
      height: 40,
    });

    const ready = await waitForPane({
      socket: SOCKET,
      session: SESSION,
      predicate: (pane) => /local-model|Ask anything|pi v1|We are offline|Type your message/i.test(pane),
      timeoutMs: READY_TIMEOUT_MS,
    });
    captures.initial = trimCapture(ready.pane);
    requirements.push(
      requirement(
        "tui-started",
        "pi interactive TUI startet unter der tmux-PTY",
        ready.ok ? "pass" : "fail",
        { pane: captures.initial },
      ),
    );
    if (!ready.ok) blocker = `TUI startete nicht innerhalb ${READY_TIMEOUT_MS / 1000} s.`;

    if (ready.ok) {
      sendLiteral(SOCKET, SESSION, PROMPT);
      sendKey(SOCKET, SESSION, "Enter");

      const dialogStarted = Date.now();
      const dialog = await waitForPane({
        socket: SOCKET,
        session: SESSION,
        // rpiv-Dialog-Signatur: die Freitext-Zeile steht in jedem Dialog,
        // die Frage selbst formuliert das Modell frei.
        predicate: (pane) => pane.includes("Type something."),
        timeoutMs: DIALOG_TIMEOUT_MS,
      });
      dialogWaitMs = Date.now() - dialogStarted;
      dialogVisible = dialog.ok;
      captures.dialog = trimCapture(dialog.pane);
      requirements.push(
        requirement(
          "dialog-visible",
          "Der rpiv-Dialog erscheint (Modell ruft ask_user_question)",
          dialogVisible ? "pass" : "fail",
          { dialogWaitMs, pane: captures.dialog },
        ),
      );
      if (!dialogVisible) {
        blocker =
          `Kein ask_user_question-Dialog innerhalb ${DIALOG_TIMEOUT_MS / 1000} s — ` +
          "das Modell hat entweder im Klartext gefragt oder das Tool nicht aufgerufen. Pane im Ergebnis.";
      }

      if (dialogVisible) {
        // Dokumentierte Taste: Ziffer wählt die nummerierte Zeile; 1 = erste Option.
        sendKey(SOCKET, SESSION, "1");

        const answerDeadline = Date.now() + ANSWER_TIMEOUT_MS;
        while (Date.now() < answerDeadline) {
          sessionFile = findNewestJsonl(sessionDir);
          if (sessionFile) {
            session = await parseSessionFile(sessionFile);
            const answered = session.toolResults.find(
              (result) => result.toolName === "ask_user_question" && !result.isError,
            );
            if (answered) {
              // Fortsetzung: Assistant-Text NACH dem Antwort-Tool-Result.
              const idx = (session.messages ?? []).findIndex(
                (message) =>
                  message.role === "toolResult" && message.toolCallId === answered.toolCallId,
              );
              const continued = (session.messages ?? [])
                .slice(idx + 1)
                .some(
                  (message) =>
                    message.role === "assistant" && contentText(message.content).trim().length > 0,
                );
              if (continued) {
                answeredOk = true;
                break;
              }
            }
          }
          await new Promise((resolve) => setTimeout(resolve, 500));
        }
        captures.afterAnswer = trimCapture(capturePane(SOCKET, SESSION));
        requirements.push(
          requirement(
            "answer-recorded",
            "Taste 1 wählt die erste Option; Antwort und Modell-Fortsetzung landen in der Session",
            answeredOk ? "pass" : "fail",
            { answerWaitMs: ANSWER_TIMEOUT_MS, pane: captures.afterAnswer },
          ),
        );

        sendKey(SOCKET, SESSION, "C-d");
        exitedAfterCtrlD = await waitForSessionExit({
          socket: SOCKET,
          session: SESSION,
          timeoutMs: 5000,
        });
      }
    }
  } catch (error) {
    blocker = `Harness error: ${String(error?.stack ?? error)}`;
    requirements.push(requirement("harness", "Experiment läuft durch", "fail", blocker));
  } finally {
    killSession(SOCKET, SESSION);
    killServer(SOCKET);
    await forwarder.close();
  }

  // ---------------------------------------------------------------- Auswertung
  const requests = readRequests(requestsLog);
  sessionFile = sessionFile ?? findNewestJsonl(sessionDir);
  session = sessionFile ? await parseSessionFile(sessionFile) : null;
  const toolCalls = validateToolCalls(requests);
  const askCall = session?.toolCalls.find((call) => call.name === "ask_user_question") ?? null;
  const askResult = askCall
    ? session.toolResults.find((result) => result.toolCallId === askCall.id) ?? null
    : null;

  let askArguments = {};
  if (askCall) {
    try {
      askArguments =
        typeof askCall.arguments === "string"
          ? JSON.parse(askCall.arguments)
          : askCall.arguments ?? {};
    } catch {
      askArguments = {};
    }
  }
  const firstOptionLabel = (() => {
    const questions = askArguments.questions;
    if (Array.isArray(questions) && questions[0]?.options?.[0]) {
      const option = questions[0].options[0];
      return typeof option === "string" ? option : option?.label ?? null;
    }
    return null;
  })();
  const answerInSession = Boolean(
    firstOptionLabel && askResult?.text && askResult.text.includes(firstOptionLabel),
  );
  const answerInModelContext = Boolean(
    firstOptionLabel &&
      requests.some((request) =>
        JSON.stringify(request.parsed?.messages ?? "").includes(firstOptionLabel),
      ),
  );

  requirements.push(
    requirement(
      "session-tool-call",
      "Session enthält den ask_user_question-Call",
      askCall ? "pass" : "fail",
      { sessionFile, toolCalls: session?.toolCalls?.map((call) => call.name) ?? [] },
    ),
  );
  requirements.push(
    requirement(
      "model-received-answer",
      "Die gewählte Option erreicht das Modell (Folge-Request enthält das Label)",
      answerInModelContext ? "pass" : "fail",
      { firstOptionLabel, requestCount: requests.length },
    ),
  );
  if (dialogVisible) {
    requirements.push(
      requirement(
        "clean-exit",
        "Ctrl+D beendet die TUI ohne Kill",
        exitedAfterCtrlD ? "pass" : "fail",
        { exited: exitedAfterCtrlD },
      ),
    );
  }

  const finalVerdict = blocker && !dialogVisible ? "fail" : verdict(requirements, blocker);

  const result = {
    id: "task-5-tui",
    title: "ask_user_question im interaktiven TUI (rpiv-ask-user-question)",
    hypothesis:
      "Gemma 4 26B erkennt den klärungsbedürftigen Prüfumfang selbst, ruft ask_user_question mit einer deutschen Frage und Optionen auf; die Auswahl per Taste 1 erreicht das Modell.",
    measurements: {
      dialogWaitMs,
      proxyRequests: requests.map((request) => ({
        url: request.url,
        status: request.status,
        durationMs: request.durationMs,
        finishReason: request.response?.finishReason ?? null,
        usage: request.response?.usage ?? null,
      })),
      usageProxy: usageTotals(requests),
      usageSession: sessionUsageTotals(session),
      toolCalls,
      toolCallErrorCount: toolCalls.filter((call) => !call.valid).length,
      sessionToolResults: (session?.toolResults ?? []).map((result) => ({
        toolName: result.toolName,
        isError: result.isError,
        text: result.text.slice(0, 300),
      })),
      answerText: answerText(session),
      firstOptionLabel,
      answerInSession,
      answerInModelContext,
      rssLlamaMiB: { before: rssBefore, after: llamaRssMiB(llama.pid) },
      sessionFile,
    },
    environment: {
      node: process.version,
      piCli: PI_CLI,
      package: PACKAGE,
      packageVersion: JSON.parse(readFileSync(path.join(packageDir(PACKAGE), "package.json"), "utf8")).version,
      tmuxSocket: SOCKET,
      tmuxSession: SESSION,
      terminal: "120x40",
    },
    prompt: PROMPT,
    captures,
    requirements,
    verdict: finalVerdict,
    blocker,
    limitations: [
      "Nur der Einzelfrage-Pfad mit einer Auswahl per Taste 1 wird geprüft.",
      "Das TUI wird per tmux send-keys gesteuert, nicht per Mensch; 120x40 fix.",
      "Der rpiv:ask-user:answer-Eventbus bleibt wie in Experiment 02 ungetestet.",
    ],
  };

  const outDir = path.join(root, "results");
  mkdirSync(outDir, { recursive: true });
  const outputPath = path.join(outDir, "task-5-tui.json");
  writeFileSync(outputPath, JSON.stringify(result, null, 2));

  console.log(`Result: ${outputPath}`);
  console.log(`Verdict: ${finalVerdict.toUpperCase()}`);
  for (const req of requirements) {
    console.log(`${req.status.toUpperCase().padEnd(10)} ${req.id}`);
  }
  if (blocker) console.log(`Blocker: ${blocker}`);
  process.exitCode = finalVerdict === "pass" ? 0 : finalVerdict === "partial" ? 0 : 1;
}

try {
  await main();
} catch (error) {
  console.error(String(error?.message ?? error));
  process.exitCode = 2;
}
