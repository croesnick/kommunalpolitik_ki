import { stat } from "node:fs/promises";
import path from "node:path";

import { PACKAGES, packageDir } from "../lib/config.mjs";
import {
  mockToolList,
  requirement,
  summarizeRun,
  verdictOf,
} from "../lib/experiment.mjs";
import { runPi } from "../lib/runner.mjs";
import { resultsFor } from "../lib/session.mjs";

const PACKAGE = PACKAGES.permissions;
const EXTENSION = path.join(packageDir(PACKAGE), "src", "index.ts");

async function exists(file) {
  try {
    await stat(file);
    return true;
  } catch {
    return false;
  }
}

function configFor(workDir) {
  return {
    yoloMode: false,
    permissionReviewLog: true,
    permission: {
      "*": "allow",
      read: "allow",
      write: {
        "*": "deny",
        [`${workDir}/*`]: "allow",
      },
      path_write: {
        "*": "deny",
        [`${workDir}/*`]: "allow",
      },
      external_directory: {
        "*": "deny",
        [`${workDir}/*`]: "allow",
      },
    },
  };
}

function writeCalls(workDir, runDir) {
  return [
    {
      name: "write",
      arguments: { path: path.join(workDir, "ok.txt"), content: "ok" },
    },
    {
      name: "write",
      arguments: { path: path.join(runDir, "escape.txt"), content: "escape" },
    },
  ];
}

export const meta = {
  id: "06-permissions",
  package: PACKAGE,
  title: "pi-permission-system: path boundary for write",
  hypothesis:
    "Without the extension both writes succeed; with a global config denying writes outside the work dir, ok.txt succeeds and escape.txt is denied without an interactive prompt.",
};

export async function run(ctx) {
  const requirements = [];
  const runs = {};

  const aRoot = path.join(ctx.runRoot, "shared");
  const aRunDir = path.join(aRoot, "A");
  const aWork = path.join(aRunDir, "work");
  const a = await runPi({
    id: "A",
    runRoot: aRoot,
    tools: "write",
    prompt: "Schreibe zwei Dateien.",
    responses: [
      { toolCalls: writeCalls(aWork, aRunDir) },
      { text: "Fertig." },
    ],
  });
  runs.A = summarizeRun(a);

  const aOk = await exists(path.join(aWork, "ok.txt"));
  const aEscape = await exists(path.join(aRunDir, "escape.txt"));
  requirements.push(
    requirement(
      "A-baseline",
      "Baseline: both writes succeed",
      aOk && aEscape ? "pass" : "fail",
      { ok: aOk, escape: aEscape, results: a.session?.toolResults ?? [] },
    ),
  );

  const bRoot = path.join(ctx.runRoot, "shared");
  const bRunDir = path.join(bRoot, "B");
  const bWork = path.join(bRunDir, "work");
  const config = configFor(bWork);
  const b = await runPi({
    id: "B",
    runRoot: bRoot,
    extensions: [EXTENSION],
    tools: "write",
    prompt: "Schreibe zwei Dateien.",
    timeoutMs: 15000,
    responses: [
      { toolCalls: writeCalls(bWork, bRunDir) },
      { text: "Fertig." },
    ],
    agentFiles: [
      {
        path: "extensions/pi-permission-system/config.json",
        content: JSON.stringify(config, null, 2),
      },
    ],
  });
  runs.B = summarizeRun(b);

  const bOk = await exists(path.join(bWork, "ok.txt"));
  const bEscape = await exists(path.join(bRunDir, "escape.txt"));
  requirements.push(
    requirement(
      "B-work-allowed",
      "With extension: work/ok.txt succeeds",
      bOk ? "pass" : "fail",
      { file: path.join(bWork, "ok.txt"), exists: bOk },
    ),
  );
  requirements.push(
    requirement(
      "B-escape-denied",
      "With extension: run/escape.txt is denied and absent",
      !bEscape ? "pass" : "fail",
      { file: path.join(bRunDir, "escape.txt"), exists: bEscape },
    ),
  );

  const escapeCall = b.session?.toolCalls.find(
    (call) => call.arguments?.path === path.join(bRunDir, "escape.txt"),
  );
  const escapeResults = escapeCall && b.session ? resultsFor(b.session, escapeCall) : [];
  requirements.push(
    requirement(
      "B-in-band-denial",
      "The denied write returns an error result",
      escapeResults.some((r) => r.isError) ? "pass" : "fail",
      escapeResults.map((r) => ({ isError: r.isError, text: r.text.slice(0, 1000) })),
    ),
  );

  requirements.push(
    requirement(
      "B-no-hang",
      "No interactive permission prompt / timeout",
      b.timedOut ? "fail" : "pass",
      { timedOut: b.timedOut, durationMs: b.durationMs, code: b.code },
    ),
  );

  const declared = mockToolList(b);
  requirements.push(
    requirement(
      "hidden-tools",
      "Disallowed tools are hidden when all patterns deny",
      "not-tested",
      {
        declaredTools: declared,
        reason:
          "The configured write surface has an allow exception for <work>/*, so the package's documented rule (hide only when every pattern denies) predicts write stays visible. Hiding was therefore not exercised in this policy.",
      },
      { gating: false },
    ),
  );

  return {
    ...meta,
    method:
      "A baseline without extension and B with the package plus a global config at <agentDir>/extensions/pi-permission-system/config.json. Both try write inside work and outside it.",
    commandShape:
      "node <pi-cli> --print --mode json ... --tools write [-e src/index.ts] <prompt>",
    requirements,
    verdict: verdictOf(requirements),
    runs,
    limitations: [
      "Config uses deny (not ask) specifically to avoid a headless prompt; this tests the boundary, not the interactive dialog.",
      "Project-level config and trust gating are not exercised.",
    ],
  };
}
