import { execFile } from "node:child_process";
import { stat } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";

import { NODE_BIN, PACKAGES, packageDir } from "../lib/config.mjs";
import {
  mockToolList,
  requirement,
  summarizeRun,
  verdictOf,
} from "../lib/experiment.mjs";
import { writeTextFile, fillerBytes } from "../lib/fixtures.mjs";
import { runPi } from "../lib/runner.mjs";
import { resultsFor } from "../lib/session.mjs";

const execFileAsync = promisify(execFile);
const PACKAGE = PACKAGES.context;
const EXTENSION = path.join(packageDir(PACKAGE), "dist", "index.js");

function versionAtLeast(version, minimum) {
  const parse = (v) => v.replace(/^v/, "").split(".").map(Number);
  const a = parse(version);
  const b = parse(minimum);
  for (let i = 0; i < 3; i += 1) {
    if ((a[i] ?? 0) !== (b[i] ?? 0)) return (a[i] ?? 0) > (b[i] ?? 0);
  }
  return true;
}

async function exists(file) {
  try {
    await stat(file);
    return true;
  } catch {
    return false;
  }
}

export const meta = {
  id: "05-context",
  package: PACKAGE,
  title: "pi-context: hard Node >= 24.15 prerequisite and large-read retrieval",
  hypothesis:
    "The package requires Node >= 24.15.0 for node:sqlite/FTS5; on Node 24.11.1 it either fails to load or runs degraded. The retrieval loop is only a pass if the receipt/search/DB chain actually works.",
};

export async function run(ctx) {
  const requirements = [];
  const runs = {};

  const { stdout: nodeVersionRaw } = await execFileAsync(NODE_BIN, ["--version"]);
  const nodeVersion = nodeVersionRaw.trim();
  const meetsPrereq = versionAtLeast(nodeVersion, "24.15.0");
  requirements.push(
    requirement(
      "node-prereq",
      "Node >= 24.15.0",
      meetsPrereq ? "pass" : "fail",
      { nodeVersion, required: ">=24.15.0", source: "package.json engines + README.md:45" },
    ),
  );

  const filePath = path.join(ctx.runRoot, "A", "work", "gross.txt");
  const body = `${fillerBytes(39 * 1024)}\nDer Suchbegriff Bahnhofstraße steht genau hier.\n`;
  await writeTextFile(filePath, body);

  const a = await runPi({
    id: "A",
    runRoot: ctx.runRoot,
    extensions: [EXTENSION],
    tools: "read,context_search,context_get,context_list,context_stats",
    prompt: "Lies @gross.txt und suche darin nach Bahnhofstraße.",
    responses: [
      { toolCalls: [{ name: "read", arguments: { path: filePath } }] },
      {
        toolCalls: [
          { name: "context_search", arguments: { query: "Bahnhofstraße" } },
        ],
      },
      { text: "Fertig." },
    ],
  });
  runs.A = summarizeRun(a);

  const loaded = a.session?.toolCalls?.some((call) => call.name.startsWith("context_")) ?? false;
  requirements.push(
    requirement(
      "loads",
      "Extension loads and registers context tools",
      loaded ? "pass" : "fail",
      {
        declaredTools: mockToolList(a),
        contextCalls: a.session?.toolCalls?.map((c) => c.name) ?? [],
        stderrTail: (a.stderr ?? "").slice(-3000),
        extensionErrors: a.events.filter((e) => e.type === "extension_error"),
      },
    ),
  );

  const readCall = a.session?.toolCalls.find((c) => c.name === "read");
  const readResult = readCall && a.session ? resultsFor(a.session, readCall)[0] : null;
  const receipt = Boolean(readResult?.text?.includes("[context-sidecar]"));
  requirements.push(
    requirement(
      "receipt",
      "Large-file read result is replaced by a context-sidecar receipt",
      receipt ? "pass" : "fail",
      readResult ? readResult.text.slice(0, 2000) : "no read result",
    ),
  );

  const searchCall = a.session?.toolCalls.find((c) => c.name === "context_search");
  const searchResult = searchCall && a.session ? resultsFor(a.session, searchCall)[0] : null;
  requirements.push(
    requirement(
      "search",
      "context_search finds the term",
      searchResult && !searchResult.isError && /Bahnhofstra/i.test(searchResult.text) ? "pass" : "fail",
      searchResult ? { isError: searchResult.isError, text: searchResult.text.slice(0, 2000) } : "no context_search result",
    ),
  );

  const dbPath = path.join(a.agentDir, "context.db");
  const dbInsideAgentDir = await exists(dbPath);
  requirements.push(
    requirement(
      "db-in-agent-dir",
      "SQLite DB is written inside the agent dir (context.db)",
      dbInsideAgentDir ? "pass" : "fail",
      { dbPath, exists: dbInsideAgentDir, agentDir: a.agentDir },
    ),
  );

  const declared = mockToolList(a);
  requirements.push(
    requirement(
      "export-not-allowlisted",
      "context_export is not in the declared tool list",
      declared.includes("context_export") ? "fail" : "pass",
      { declaredTools: declared },
    ),
  );

  return {
    ...meta,
    method:
      "Version gate from package.json/README, then a 40 KB read followed by context_search against the mock provider. Startup errors, declared tools, receipt, search result and DB location are recorded.",
    commandShape:
      "node <pi-cli> --print --mode json ... --tools read,context_search,context_get,context_list,context_stats -e dist/index.js <prompt>",
    requirements,
    verdict: verdictOf(requirements),
    runs,
    limitations: [
      "Node 24.11.1 is below the package's declared engine; any runtime failure is expected and recorded, not worked around.",
      "context_export is registered by the package but deliberately excluded from the allowlist, so absence here only proves allowlist behaviour.",
    ],
  };
}
