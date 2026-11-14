import { readdir } from "node:fs/promises";
import path from "node:path";

import { PACKAGES, packageDir } from "../lib/config.mjs";
import {
  mockToolList,
  requirement,
  summarizeRun,
  verdictOf,
} from "../lib/experiment.mjs";
import { writeSessionFixture } from "../lib/fixtures.mjs";
import { runPi } from "../lib/runner.mjs";
import { resultsFor } from "../lib/session.mjs";

const PACKAGE = PACKAGES.hermes;
const EXTENSION = path.join(packageDir(PACKAGE), "src", "index.ts");

async function walkFiles(dir, out = []) {
  let entries;
  try {
    entries = await readdir(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) await walkFiles(full, out);
    else if (entry.isFile()) out.push(full);
  }
  return out;
}

export const meta = {
  id: "08-hermes",
  package: PACKAGE,
  title: "pi-hermes-memory: anchor-only session search, no memory writes",
  hypothesis:
    "The extension loads despite --ignore-scripts (better-sqlite3 ships prebuilds); with lazy policy-only config and sessionSearch.variant=anchors it returns path:startLine-endLine anchors and does not create memory databases or Markdown files.",
};

export async function run(ctx) {
  const requirements = [];
  const runs = {};

  const config = {
    lazyInitialization: true,
    memoryMode: "policy-only",
    memoryPolicyStyle: "none",
    reviewEnabled: false,
    correctionDetection: false,
    flushOnCompact: false,
    flushOnShutdown: false,
    autoConsolidate: false,
    standingInstructionsEnabled: false,
    usageHitTrackingEnabled: false,
    quickCheckOnOpen: false,
    sessionSearch: { variant: "anchors" },
  };

  const a = await runPi({
    id: "A",
    runRoot: ctx.runRoot,
    extensions: [EXTENSION],
    tools: "session_search",
    prompt: "Suche in alten Sitzungen nach Bahnhofstraße.",
    timeoutMs: 30000,
    responses: [
      {
        toolCalls: [
          {
            name: "session_search",
            arguments: {
              markdown: "all:\n- Bahnhofstraße\nlimit: 5",
            },
          },
        ],
      },
      { text: "Fertig." },
    ],
    agentFiles: [
      {
        path: "hermes-memory-config.json",
        content: JSON.stringify(config, null, 2),
      },
    ],
  });

  // The fixture must live where the package looks: <agentDir>/sessions.
  // Create it before the run would be ideal; this run has already started, so
  // the fixture is written for a second invocation below.
  const fixture = path.join(a.agentDir, "sessions", "fixture-session.jsonl");
  await writeSessionFixture(fixture, { cwd: a.workDir });
  runs.A = summarizeRun(a);

  const declared = mockToolList(a);
  const loaded = declared.includes("session_search");
  requirements.push(
    requirement(
      "loads",
      "Extension loads and registers session_search",
      loaded ? "pass" : "fail",
      {
        declaredTools: declared,
        stderrTail: (a.stderr ?? "").slice(-4000),
        extensionErrors: a.events.filter((e) => e.type === "extension_error"),
      },
    ),
  );

  // Run once more now that the fixture exists (same isolated run dir).
  const a2 = await runPi({
    id: "A2",
    runRoot: ctx.runRoot,
    runDir: a.runDir,
    sessionDir: path.join(a.runDir, "sessions-search"),
    extensions: [EXTENSION],
    tools: "session_search",
    prompt: "Suche in alten Sitzungen nach Bahnhofstraße.",
    timeoutMs: 30000,
    responses: [
      {
        toolCalls: [
          {
            name: "session_search",
            arguments: {
              markdown: "all:\n- Bahnhofstraße\nlimit: 5",
            },
          },
        ],
      },
      { text: "Fertig." },
    ],
  });
  runs.A2 = summarizeRun(a2);

  const call = a2.session?.toolCalls.find((c) => c.name === "session_search");
  const result = call && a2.session ? resultsFor(a2.session, call)[0] : null;
  const anchored = Boolean(result && /\.jsonl:\d+-\d+/.test(result.text));
  requirements.push(
    requirement(
      "anchor-search",
      "session_search variant anchors returns path:startLine-endLine anchors",
      anchored ? "pass" : "fail",
      result
        ? { isError: result.isError, text: result.text.slice(0, 2000) }
        : "no session_search result",
    ),
  );

  const files = await walkFiles(a2.agentDir);
  const memoryArtifacts = files.filter(
    (file) =>
      /(sessions?\.db|\.db(?:-wal|-shm)?$|MEMORY\.md$|USER\.md$|STANDING\.md$)/i.test(file),
  );
  requirements.push(
    requirement(
      "no-memory-writes",
      "No memory DB or Markdown files are written",
      memoryArtifacts.length === 0 ? "pass" : "fail",
      { memoryArtifacts, allFiles: files.map((f) => path.relative(a2.agentDir, f)) },
    ),
  );

  return {
    ...meta,
    method:
      "Lazy policy-only config with review/correction/flush disabled and anchors variant. A first run checks loading; the fixture is then placed in <agentDir>/sessions and a second run exercises session_search.",
    commandShape:
      "node <pi-cli> --print --mode json ... --tools session_search -e src/index.ts <prompt>",
    requirements,
    verdict: verdictOf(requirements),
    runs,
    limitations: [
      "The fixture is written between A and A2; A is a load check only.",
      "Only the anchor variant is exercised; legacy SQLite search is deliberately not activated.",
    ],
  };
}
