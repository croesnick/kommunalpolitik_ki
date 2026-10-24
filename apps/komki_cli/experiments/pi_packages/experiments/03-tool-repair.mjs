import { readFile, stat } from "node:fs/promises";
import path from "node:path";

import { PACKAGES, packageDir } from "../lib/config.mjs";
import {
  requirement,
  summarizeRun,
  systemPromptOf,
  verdictOf,
} from "../lib/experiment.mjs";
import { runPi } from "../lib/runner.mjs";
import { findToolResult } from "../lib/session.mjs";

const PACKAGE = PACKAGES.toolRepair;
const EXTENSION = path.join(packageDir(PACKAGE), "tool-repair.ts");

function malformedArguments(target) {
  return JSON.stringify({
    path: [target],
    content: { text: "Hallo" },
  });
}

async function fileState(file) {
  try {
    return { exists: true, content: await readFile(file, "utf8") };
  } catch {
    return { exists: false, content: null };
  }
}

export const meta = {
  id: "03-tool-repair",
  package: PACKAGE,
  title: "pi-tool-repair: malformed write arguments, baseline vs repair",
  hypothesis:
    "Baseline fails on {path:[string], content:{text:string}}; with the extension the call is repaired and the file is written; the system prompt is unchanged.",
};

export async function run(ctx) {
  const requirements = [];
  const runs = {};

  const aRunRoot = path.join(ctx.runRoot, "shared");
  const a = await runPi({
    id: "A",
    runRoot: aRunRoot,
    tools: "write",
    prompt: "Schreibe Hallo nach repaired.txt.",
    responses: [
      {
        toolCalls: [
          {
            name: "write",
            arguments: malformedArguments(path.join(aRunRoot, "A", "work", "repaired.txt")),
          },
        ],
      },
      { text: "Fertig." },
    ],
  });
  runs.A = summarizeRun(a);

  const target = path.join(a.workDir, "repaired.txt");
  const aFile = await fileState(target);
  const aResult = a.session ? findToolResult(a.session, "write") : null;
  requirements.push(
    requirement(
      "A-no-file",
      "Baseline: no file is written",
      aFile.exists ? "fail" : "pass",
      { target, ...aFile },
    ),
  );
  requirements.push(
    requirement(
      "A-error",
      "Baseline: write tool result is an error",
      aResult?.isError ? "pass" : "fail",
      aResult ? { isError: aResult.isError, text: aResult.text } : "no write result",
    ),
  );

  // Same runDir/workDir for byte-identical system prompt; the two sessions stay
  // separate through an explicit second session dir.
  const b = await runPi({
    id: "B",
    runRoot: aRunRoot,
    runDir: a.runDir,
    sessionDir: path.join(a.runDir, "sessions-repair"),
    extensions: [EXTENSION],
    tools: "write",
    prompt: "Schreibe Hallo nach repaired.txt.",
    responses: [
      {
        toolCalls: [
          {
            name: "write",
            arguments: malformedArguments(target),
          },
        ],
      },
      { text: "Fertig." },
    ],
  });
  runs.B = summarizeRun(b);

  const bFile = await fileState(target);
  const bResult = b.session ? findToolResult(b.session, "write") : null;
  requirements.push(
    requirement(
      "B-file",
      "With extension: file exists with content 'Hallo'",
      bFile.exists && bFile.content === "Hallo" ? "pass" : "fail",
      { target, ...bFile, result: bResult?.text ?? null },
    ),
  );

  const repairedCall = b.session?.toolCalls.find((c) => c.name === "write") ?? null;
  const repaired =
    repairedCall &&
    typeof repairedCall.arguments?.path === "string" &&
    repairedCall.arguments?.content === "Hallo";
  requirements.push(
    requirement(
      "B-repaired-call",
      "Session shows a repaired write call (path string, content string)",
      repaired ? "pass" : "fail",
      { arguments: repairedCall?.arguments ?? null },
    ),
  );

  // Diagnostic: a shape pi-tool-repair documents as repairable (alias field).
  // This separates "extension did not load" from "the brief's shape is unsupported".
  const target2 = path.join(a.workDir, "repaired2.txt");
  const d = await runPi({
    id: "D",
    runRoot: aRunRoot,
    runDir: a.runDir,
    sessionDir: path.join(a.runDir, "sessions-repair-diagnostic"),
    extensions: [EXTENSION],
    tools: "write",
    prompt: "Schreibe Hallo nach repaired2.txt.",
    responses: [
      {
        toolCalls: [
          {
            name: "write",
            arguments: JSON.stringify({ file_path: target2, content: "Hallo" }),
          },
        ],
      },
      { text: "Fertig." },
    ],
  });
  runs.D = summarizeRun(d);
  const dFile = await fileState(target2);
  const dCall = d.session?.toolCalls.find((c) => c.name === "write");
  requirements.push(
    requirement(
      "D-alias-repair",
      "Diagnostic: documented file_path alias is repaired",
      dFile.exists && dFile.content === "Hallo" && dCall?.arguments?.path === target2
        ? "pass"
        : "fail",
      { file: dFile, arguments: dCall?.arguments ?? null, stderrTail: (d.stderr ?? "").slice(-1500) },
      { gating: false },
    ),
  );

  const promptA = systemPromptOf(a);
  const promptB = systemPromptOf(b);
  requirements.push(
    requirement(
      "system-prompt-identical",
      "First-request system prompt bytes are identical in A and B",
      promptA && promptB && promptA === promptB ? "pass" : "fail",
      {
        equal: promptA === promptB,
        bytesA: promptA?.length ?? null,
        bytesB: promptB?.length ?? null,
        firstDifference:
          promptA && promptB && promptA !== promptB
            ? [...promptA].findIndex((ch, i) => ch !== promptB[i])
            : null,
      },
    ),
  );

  const nonMock = [...a.requests, ...b.requests].filter((r) => !r.url.startsWith("/v1/"));
  requirements.push(
    requirement(
      "no-network",
      "No requests beyond the mock provider",
      nonMock.length === 0 ? "pass" : "fail",
      { urls: nonMock.map((r) => r.url) },
    ),
  );

  return {
    ...meta,
    method:
      "A baseline without extension, B with -e tool-repair.ts. Both in the same run/work directory with separate session dirs so the system prompt is comparable byte-for-byte. Malformed arguments are identical.",
    commandShape:
      "node <pi-cli> --print --mode json ... --tools write [-e tool-repair.ts] <prompt>",
    requirements,
    verdict: verdictOf(requirements),
    runs,
    limitations: [
      "The malformed shape is exactly the brief's {path:[...],content:{text:...}}; pi-tool-repair 0.3.9 has no documented array-to-string or object-to-string rule, so a failure here is a genuine package limitation.",
      "System prompt identity is checked on the first request only.",
    ],
  };
}
