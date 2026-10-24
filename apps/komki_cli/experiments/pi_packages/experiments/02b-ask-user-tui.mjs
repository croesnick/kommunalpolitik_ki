#!/usr/bin/env node
/**
 * Standalone TUI experiment for @juicesharp/rpiv-ask-user-question.
 *
 * Runs pi interactively inside a dedicated tmux PTY, points it at the local
 * mock provider, asks one question, answers with the documented digit key, and
 * verifies the answer in the session JSONL and in the next model request.
 *
 * This file is intentionally not wired into run-all.mjs.
 */
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  statSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";

import { PACKAGES, PI_CLI } from "../lib/config.mjs";
import { startMockProvider } from "../lib/mock-provider.mjs";
import { parseSessionFile } from "../lib/session.mjs";
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

function resolveExperimentsRoot() {
  const candidates = [
    process.env.KOMKI_PI_EXPERIMENTS_DIR,
    path.join(os.tmpdir(), "komki-pi-experiments"),
    "/var/folders/zb/b95sfwxs10g1wrqvcqy1xjf40000gp/T/opencode/komki-pi-experiments",
  ].filter(Boolean);
  for (const candidate of candidates) {
    const vendorPackage = path.join(
      candidate,
      "vendor",
      "node_modules",
      PACKAGE,
      "package.json",
    );
    if (existsSync(vendorPackage)) return candidate;
  }
  throw new Error(
    `Vendored ${PACKAGE} not found. Set KOMKI_PI_EXPERIMENTS_DIR. Tried: ${candidates.join(", ")}`,
  );
}

const EXPERIMENTS_ROOT = resolveExperimentsRoot();
const EXTENSION_DIR = path.join(
  EXPERIMENTS_ROOT,
  "vendor",
  "node_modules",
  PACKAGE,
);
const EXTENSION = path.join(EXTENSION_DIR, "index.ts");
const SOCKET = `komki-tui-exp-${process.pid}`;
const SESSION = `komki-ask-tui-${process.pid}`;

const QUESTION = "Welche Option soll geprüft werden?";
const OPTION_A = "Option A";
const OPTION_B = "Option B";
const FINAL_TEXT = "Danke, Option A.";
const KEY_SEQUENCE = ["Stelle eine Rückfrage.", "Enter", "1", "C-d"];

function stamp(date = new Date()) {
  return date.toISOString().replace(/[:.]/g, "-");
}

function shQuote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

function resolvePiCli() {
  const candidates = [
    process.env.KOMKI_PI_CLI,
    path.resolve(
      path.dirname(process.execPath),
      "..",
      "lib",
      "node_modules",
      "@earendil-works",
      "pi-coding-agent",
      "dist",
      "bundle",
      "cli.js",
    ),
    PI_CLI,
  ].filter(Boolean);
  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }
  throw new Error(`pi CLI not found; tried: ${candidates.join(", ")}`);
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

function requestMessagesContain(requests, needle) {
  const last = requests.at(-1);
  if (!last) return false;
  return JSON.stringify(last.parsed?.messages ?? []).includes(needle);
}

function readRequests(logPath) {
  try {
    return readFileSync(logPath, "utf8")
      .split("\n")
      .filter(Boolean)
      .map((line) => {
        const record = JSON.parse(line);
        let body = null;
        try {
          body = JSON.parse(record.body);
        } catch {}
        return { ...record, parsed: body };
      });
  } catch {
    return [];
  }
}

function requirement(id, text, status, observed, gating = true) {
  return { id, requirement: text, status, observed, gating };
}

function verdict(requirements, blocker) {
  if (blocker) return "not-tested";
  if (requirements.some((r) => r.gating && r.status === "fail")) return "fail";
  if (requirements.some((r) => r.gating && r.status === "not-tested")) return "partial";
  return "pass";
}

async function main() {
  const timestamp = stamp();
  const base = path.join(EXPERIMENTS_ROOT, "runs", timestamp);
  const runDir = path.join(base, "work", "02b-ask-user-tui");
  const agentRoot = path.join(runDir, "agent");
  const agentDir = path.join(agentRoot, ".pi", "agent");
  const workDir = path.join(runDir, "work");
  const sessionDir = path.join(runDir, "sessions");
  const harnessDir = path.join(runDir, "harness");
  const requestsLog = path.join(harnessDir, "requests.jsonl");
  const chromeDir = path.join(runDir, "chrome");
  const wrapperPath = path.join(runDir, "run-pi.sh");

  for (const dir of [agentDir, workDir, sessionDir, harnessDir, chromeDir]) {
    mkdirSync(dir, { recursive: true });
  }

  const piCli = resolvePiCli();
  const nodeBin = process.execPath;

  const mock = await startMockProvider({
    logPath: requestsLog,
    contextWindow: 8192,
    script: [
      {
        toolCalls: [
          {
            name: "ask_user_question",
            arguments: {
              questions: [
                {
                  question: QUESTION,
                  header: "Auswahl",
                  options: [
                    { label: OPTION_A, description: "Erste Option" },
                    { label: OPTION_B, description: "Zweite Option" },
                  ],
                },
              ],
            },
          },
        ],
      },
      { text: FINAL_TEXT },
    ],
  });

  writeFileSync(
    path.join(agentDir, "models.json"),
    JSON.stringify(
      {
        providers: {
          mock: {
            api: "openai-completions",
            apiKey: "mock-key",
            baseUrl: mock.baseUrl,
            models: [
              {
                id: "mock-model",
                name: "Mock Model",
                contextWindow: 8192,
                maxTokens: 512,
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
      `exec ${shQuote(nodeBin)} ${shQuote(piCli)} --offline --no-extensions --no-skills --no-context-files --no-prompt-templates --no-themes --no-approve --session-dir ${shQuote(sessionDir)} --provider mock --model mock-model --tools ask_user_question -e ${shQuote(EXTENSION)}`,
      "",
    ].join("\n"),
    { mode: 0o755 },
  );

  const requirements = [];
  const captures = {};
  let blocker = null;
  let dialogVisible = false;
  let dialogOk = false;
  let answeredOk = false;
  let answerObserved = false;
  let exitedAfterCtrlD = false;
  let started = false;
  let sessionFile = null;
  let session = null;
  let requests = [];
  let toolResult = null;

  try {
    startSession({
      socket: SOCKET,
      session: SESSION,
      cwd: workDir,
      command: `exec /bin/sh ${shQuote(wrapperPath)}`,
      width: 120,
      height: 40,
    });
    started = true;

    const ready = await waitForPane({
      socket: SOCKET,
      session: SESSION,
      predicate: (pane) =>
        /mock-model|Ask anything|pi v1|We are offline|Type your message/i.test(pane),
      timeoutMs: 12000,
    });
    captures.initial = trimCapture(ready.pane);

    sendLiteral(SOCKET, SESSION, "Stelle eine Rückfrage.");
    sendKey(SOCKET, SESSION, "Enter");

    const dialog = await waitForPane({
      socket: SOCKET,
      session: SESSION,
      predicate: (pane) =>
        pane.includes(QUESTION) &&
        pane.includes(OPTION_A) &&
        pane.includes(OPTION_B),
      timeoutMs: 20000,
    });
    dialogVisible = dialog.ok;
    dialogOk = dialog.ok;
    captures.dialog = trimCapture(dialog.pane);
    if (!dialog.ok) {
      blocker = `Question dialog did not appear within 20 s. Last pane: ${trimCapture(dialog.pane, 30)}`;
    }

    requirements.push(
      requirement(
        "tui-started",
        "pi interactive TUI starts under the tmux PTY",
        started && captures.initial.length > 0 ? "pass" : "fail",
        { started, initialPane: captures.initial },
      ),
    );
    requirements.push(
      requirement(
        "dialog-visible",
        "Question and both options are visible in the pane",
        dialogVisible ? "pass" : "fail",
        {
          question: QUESTION,
          optionA: OPTION_A,
          optionB: OPTION_B,
          pane: captures.dialog,
        },
      ),
    );

    if (dialogVisible) {
      // Documented key: digits act on the numbered row. 1 confirms Option A.
      sendKey(SOCKET, SESSION, "1");

      const answered = await waitForPane({
        socket: SOCKET,
        session: SESSION,
        predicate: (pane) => pane.includes(FINAL_TEXT),
        timeoutMs: 15000,
      });
      answeredOk = answered.ok;
      answerObserved = answered.ok;
      captures.afterAnswer = trimCapture(answered.pane);
      if (!answered.ok) {
        blocker = `Answer key was sent but final assistant text "${FINAL_TEXT}" did not appear within 15 s.`;
      }

      // Ctrl+D exits when the editor is empty.
      sendKey(SOCKET, SESSION, "C-d");
      exitedAfterCtrlD = await waitForSessionExit({
        socket: SOCKET,
        session: SESSION,
        timeoutMs: 5000,
      });
      captures.afterExit = (() => {
        try {
          return trimCapture(capturePane(SOCKET, SESSION));
        } catch {
          return "(tmux session already gone)";
        }
      })();
    }

    sessionFile = findNewestJsonl(sessionDir);
    session = sessionFile ? await parseSessionFile(sessionFile) : null;
    requests = readRequests(requestsLog);

    const call = session?.toolCalls.find((entry) => entry.name === "ask_user_question") ?? null;
    toolResult = call && session
      ? session.toolResults.find((entry) => entry.toolCallId === call.id) ?? null
      : null;
    const answerInSession = Boolean(toolResult?.text?.includes(OPTION_A));
    const answerInModelContext = requestMessagesContain(requests, OPTION_A);

    requirements.push(
      requirement(
        "key-sequence-applied",
        "Digit key 1 confirms Option A and closes the dialog",
        answerObserved ? "pass" : "fail",
        {
          keySequence: KEY_SEQUENCE,
          finalText: FINAL_TEXT,
          paneAfterAnswer: captures.afterAnswer ?? null,
        },
      ),
    );
    requirements.push(
      requirement(
        "session-tool-call",
        "Session JSONL contains the ask_user_question tool call",
        call ? "pass" : "fail",
        {
          sessionFile,
          toolCalls: session?.toolCalls?.map((entry) => entry.name) ?? [],
        },
      ),
    );
    requirements.push(
      requirement(
        "session-answer",
        "Session tool result contains the selected answer",
        answerInSession ? "pass" : "fail",
        toolResult
          ? { isError: toolResult.isError, text: toolResult.text }
          : null,
      ),
    );
    requirements.push(
      requirement(
        "model-received-answer",
        "The next model request contains the answer text",
        answerInModelContext ? "pass" : "fail",
        {
          requestCount: requests.length,
          lastRequestMessages: requests.at(-1)?.parsed?.messages ?? null,
        },
      ),
    );
    requirements.push(
      requirement(
        "clean-exit",
        "Ctrl+D exits the TUI without a kill",
        exitedAfterCtrlD ? "pass" : "fail",
        {
          key: "C-d",
          exited: exitedAfterCtrlD,
          afterExit: captures.afterExit ?? null,
        },
      ),
    );
    requirements.push(
      requirement(
        "no-timeout",
        "No harness timeout or forced kill was needed",
        dialogOk && answeredOk ? "pass" : "fail",
        {
          dialogWaitMs: 20000,
          answerWaitMs: 15000,
          blocker,
        },
      ),
    );
  } catch (error) {
    blocker = `Harness error: ${String(error?.stack ?? error)}`;
    requirements.push(
      requirement("harness", "Experiment completes", "fail", blocker),
    );
  } finally {
    killSession(SOCKET, SESSION);
    killServer(SOCKET);
    await mock.close();
  }

  const verdictValue = verdict(requirements, blocker ? null : null);
  const finalVerdict = !dialogVisible
    ? "not-tested"
    : verdictValue;

  const result = {
    id: "02b-ask-user-tui",
    package: PACKAGE,
    title: "rpiv-ask-user-question: interactive TUI overlay under tmux",
    hypothesis:
      "Under a real tmux PTY, pi 1.4.0 shows the package's tabbed single-question dialog; pressing the documented row digit 1 selects Option A and the answer reaches the session and the next model request.",
    method:
      "Mock provider + isolated agent root + tmux PTY. Start pi interactively with --tools ask_user_question and -e <package>, send the prompt, wait for the dialog, press 1, wait for the final text, then Ctrl+D. Session JSONL and provider request log are inspected.",
    commandShape: `${shQuote(nodeBin)} <cli.js> --offline --no-extensions --no-skills --no-context-files --no-prompt-templates --no-themes --no-approve --session-dir <sessions> --provider mock --model mock-model --tools ask_user_question -e ${EXTENSION}`,
    environment: {
      node: process.version,
      nodeBin,
      piCli,
      package: PACKAGE,
      packageVersion: JSON.parse(
        readFileSync(path.join(EXTENSION_DIR, "package.json"), "utf8"),
      ).version,
      tmuxSocket: SOCKET,
      tmuxSession: SESSION,
      terminal: "120x40",
    },
    keySequence: KEY_SEQUENCE,
    captures,
    session: {
      file: sessionFile,
      toolCalls: session?.toolCalls ?? [],
      toolResult,
      customEntries: session?.customEntries ?? [],
    },
    requests: {
      count: requests.length,
      last: requests.at(-1)?.parsed ?? null,
    },
    requirements,
    verdict: finalVerdict,
    blocker,
    limitations: [
      "Only the single-question, single-select path is exercised.",
      "The TUI is driven by tmux send-keys, not by a human; terminal dimensions are fixed at 120x40.",
      "The rpiv:ask-user:prompt/answer event bus is not exercised.",
    ],
  };

  const resultsDir = path.join(base, "results");
  mkdirSync(resultsDir, { recursive: true });
  const outputPath = path.join(resultsDir, "02b-ask-user-tui.json");
  writeFileSync(outputPath, JSON.stringify(result, null, 2));

  console.log(`Result: ${outputPath}`);
  console.log(`Verdict: ${finalVerdict.toUpperCase()}`);
  for (const req of requirements) {
    console.log(`${req.status.toUpperCase().padEnd(10)} ${req.id}`);
  }
  if (blocker) console.log(`Blocker: ${blocker}`);
  if (!answerObserved && captures.afterAnswer) {
    console.log("After-answer pane:");
    console.log(captures.afterAnswer);
  }

  process.exitCode = finalVerdict === "pass" ? 0 : finalVerdict === "not-tested" ? 2 : 1;
}

await main();
