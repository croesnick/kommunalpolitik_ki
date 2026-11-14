import path from "node:path";

import { PACKAGES, packageDir } from "../lib/config.mjs";
import { requirement, summarizeRun, verdictOf } from "../lib/experiment.mjs";
import { runPi } from "../lib/runner.mjs";
import { customEntriesOfType, findToolResult } from "../lib/session.mjs";

const PACKAGE = PACKAGES.todo;
const EXTENSION = path.join(packageDir(PACKAGE), "index.ts");
const STATE_TYPE = "rpiv-todo-state";

export const meta = {
  id: "01-todo",
  package: PACKAGE,
  title: "rpiv-todo: create, persist across --continue, and unavailable baseline",
  hypothesis:
    "The todo tool creates state and persists it as a custom rpiv-todo-state entry; --continue replays that entry; without the extension --tools todo does not make the tool available.",
};

export async function run(ctx) {
  const requirements = [];
  const runs = {};

  const a = await runPi({
    id: "A",
    runRoot: ctx.runRoot,
    extensions: [EXTENSION],
    tools: "todo",
    prompt: "Lege eine Aufgabe an.",
    responses: [
      {
        toolCalls: [
          {
            name: "todo",
            arguments: { action: "create", subject: "TOP 1 prüfen" },
          },
        ],
      },
      { text: "Aufgabe angelegt." },
    ],
  });
  runs.A = summarizeRun(a);

  const createResult = a.session ? findToolResult(a.session, "todo") : null;
  requirements.push(
    requirement(
      "A-tool-result",
      "Tool result contains 'Created #1'",
      createResult?.text.includes("Created #1") ? "pass" : "fail",
      createResult?.text ?? "no todo tool result",
    ),
  );

  const stateEntries = a.session ? customEntriesOfType(a.session, STATE_TYPE) : [];
  const task = stateEntries
    .flatMap((entry) => entry.data?.tasks ?? [])
    .find((t) => t.subject === "TOP 1 prüfen");
  requirements.push(
    requirement(
      "A-state-entry",
      "Session contains a custom rpiv-todo-state entry with the task",
      stateEntries.length > 0 && Boolean(task) ? "pass" : "fail",
      task
        ? { entryCount: stateEntries.length, task }
        : { entryCount: stateEntries.length, entries: stateEntries.map((e) => e.data) },
    ),
  );

  const nonMockRequests = a.requests.filter((r) => !r.url.startsWith("/v1/"));
  requirements.push(
    requirement(
      "A-no-network",
      "No requests beyond the mock provider",
      nonMockRequests.length === 0 && a.requests.length > 0 ? "pass" : "fail",
      { requestCount: a.requests.length, urls: a.requests.map((r) => r.url) },
    ),
  );

  const b = await runPi({
    id: "B",
    runRoot: ctx.runRoot,
    runDir: a.runDir,
    extensions: [EXTENSION],
    tools: "todo",
    continue: true,
    prompt: "Liste die Aufgaben.",
    responses: [
      { toolCalls: [{ name: "todo", arguments: { action: "list" } }] },
      { text: "Liste ausgegeben." },
    ],
  });
  runs.B = summarizeRun(b);

  const listResult = b.session
    ? [...b.session.toolResults].reverse().find((r) => r.toolName === "todo")
    : null;
  requirements.push(
    requirement(
      "B-resume",
      "After --continue the todo list contains the task",
      listResult?.text.includes("TOP 1 prüfen") ? "pass" : "fail",
      listResult?.text ?? "no todo result after continue",
    ),
  );

  const c = await runPi({
    id: "C",
    runRoot: ctx.runRoot,
    tools: "todo",
    prompt: "Versuche todo ohne Extension.",
    responses: [
      { toolCalls: [{ name: "todo", arguments: { action: "create", subject: "Baseline" } }] },
      { text: "Baseline beendet." },
    ],
  });
  runs.C = summarizeRun(c);

  const declaredTools = (c.requests[0]?.parsed?.tools ?? []).map(
    (t) => t.function?.name ?? t.name,
  );
  const cResult = c.session ? findToolResult(c.session, "todo") : null;
  const unavailable =
    !declaredTools.includes("todo") &&
    (!cResult || cResult.isError || /not found|unknown|unavailable|invalid/i.test(cResult.text));
  requirements.push(
    requirement(
      "C-baseline",
      "Without the extension, --tools todo does not provide the tool",
      unavailable ? "pass" : "fail",
      { declaredTools, toolResult: cResult?.text ?? null, isError: cResult?.isError ?? null },
    ),
  );

  const outside = (run) =>
    (run.files?.created ?? []).filter(
      (file) => !file.startsWith("sessions/") && !file.startsWith("harness/"),
    );
  const baselineWrites = outside(c);
  const aOutside = outside(a);
  const extensionWrites = aOutside.filter((file) => !baselineWrites.includes(file));
  requirements.push(
    requirement(
      "A-no-outside-writes",
      "No extension-attributable files written outside the session dir",
      extensionWrites.length === 0 ? "pass" : "fail",
      {
        extensionWrites,
        piCoreBaselineWrites: baselineWrites,
        note:
          "pi itself writes auth.json and models-store.json even offline; the no-extension baseline C isolates those from extension writes. Harness request logs live in harness/ and are excluded.",
      },
    ),
  );

  return {
    ...meta,
    method:
      "Three mock-provider runs: A create with extension, B --continue list, C baseline without extension. Tools allowlist 'todo'.",
    commandShape:
      "node <pi-cli> --print --mode json --offline --no-extensions ... --tools todo [-e index.ts] <prompt>",
    requirements,
    verdict: verdictOf(requirements),
    runs,
    limitations: [
      "Mock provider emits a single tool call; no real model variability.",
      "C treats both a startup rejection and an in-band unknown-tool error as 'unavailable'.",
    ],
  };
}
