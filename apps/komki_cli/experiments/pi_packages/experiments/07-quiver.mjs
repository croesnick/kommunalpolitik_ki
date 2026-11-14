import { readdir, readFile } from "node:fs/promises";
import path from "node:path";

import { PACKAGES, packageDir } from "../lib/config.mjs";
import {
  mockToolList,
  requirement,
  summarizeRun,
  verdictOf,
} from "../lib/experiment.mjs";
import { writePdfFixture } from "../lib/fixtures.mjs";
import { runPi } from "../lib/runner.mjs";
import { resultsFor } from "../lib/session.mjs";

const PACKAGE = PACKAGES.quiver;
const EXTENSION = path.join(packageDir(PACKAGE), "extensions", "doc_to_md.ts");

async function findMarkdown(dir, out = []) {
  let entries;
  try {
    entries = await readdir(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) await findMarkdown(full, out);
    else if (entry.isFile() && entry.name.endsWith(".md")) out.push(full);
  }
  return out;
}

export const meta = {
  id: "07-quiver",
  package: PACKAGE,
  title: "pi-quiver: doc_to_md only, offline PDF extraction",
  hypothesis:
    "Loading only extensions/doc_to_md.ts registers no fetch/Slack tool; a minimal PDF is converted to a Markdown bundle. Without uv, the pure-JS unpdf tier may be degraded but should still extract text.",
};

export async function run(ctx) {
  const requirements = [];
  const runs = {};

  const fixture = path.join(ctx.runRoot, "A", "work", "fixture.pdf");
  await writePdfFixture(fixture, "TOP 1 Bahnhofstraße");

  const a = await runPi({
    id: "A",
    runRoot: ctx.runRoot,
    extensions: [EXTENSION],
    tools: "doc_to_md",
    prompt: "Wandle das PDF in Markdown um.",
    timeoutMs: 30000,
    responses: [
      {
        toolCalls: [
          {
            name: "doc_to_md",
            arguments: {
              path: fixture,
              outputDir: path.join(ctx.runRoot, "A", "work", "out"),
            },
          },
        ],
      },
      { text: "Fertig." },
    ],
  });
  runs.A = summarizeRun(a);

  const declared = mockToolList(a);
  requirements.push(
    requirement(
      "only-doc-to-md",
      "Only doc_to_md is registered (no fetch/Slack)",
      declared.includes("doc_to_md") &&
        declared.every((name) => name === "doc_to_md")
        ? "pass"
        : "fail",
      { declaredTools: declared },
    ),
  );

  const call = a.session?.toolCalls.find((c) => c.name === "doc_to_md");
  const result = call && a.session ? resultsFor(a.session, call)[0] : null;
  requirements.push(
    requirement(
      "tool-executed",
      "doc_to_md executes and returns a handle",
      result && !result.isError ? "pass" : "fail",
      result ? { isError: result.isError, text: result.text.slice(0, 3000) } : "no tool result",
    ),
  );

  const markdownFiles = await findMarkdown(path.join(a.workDir, "out"));
  let extracted = null;
  if (markdownFiles[0]) {
    const text = await readFile(markdownFiles[0], "utf8");
    extracted = /TOP 1 Bahnhofstra/i.test(text);
  }
  requirements.push(
    requirement(
      "markdown-bundle",
      "A Markdown bundle is written",
      markdownFiles.length > 0 ? "pass" : "fail",
      { markdownFiles },
    ),
  );
  requirements.push(
    requirement(
      "text-extracted",
      "Extracted Markdown contains 'TOP 1 Bahnhofstraße'",
      extracted ? "pass" : "fail",
      {
        extracted,
        markdownPreview: markdownFiles[0]
          ? (await readFile(markdownFiles[0], "utf8")).slice(0, 1500)
          : null,
        stderrTail: (a.stderr ?? "").slice(-2500),
      },
    ),
  );

  const nonMock = a.requests.filter((r) => !r.url.startsWith("/v1/"));
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
      "Only extensions/doc_to_md.ts is loaded. A hand-built one-page PDF (WinAnsi, text 'TOP 1 Bahnhofstraße') is converted with PATH=/usr/bin:/bin, so uv is unavailable and the pure-JS fallback must be used.",
    commandShape:
      "node <pi-cli> --print --mode json ... --tools doc_to_md -e extensions/doc_to_md.ts <prompt>",
    requirements,
    verdict: verdictOf(requirements),
    runs,
    limitations: [
      "The PDF is synthetic and contains a single text line, not a real Ratsinformationssystem document.",
      "No OCR path is exercised; only the local non-OCR tier is in scope.",
    ],
  };
}
