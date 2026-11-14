#!/usr/bin/env node
import { execFile } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

import {
  NODE_BIN,
  PACKAGES,
  PI_VERSION,
  packageDir,
  runRoot,
} from "./lib/config.mjs";
import { scanPackage } from "./lib/static-scan.mjs";

import * as todo from "./experiments/01-todo.mjs";
import * as askUser from "./experiments/02-ask-user.mjs";
import * as toolRepair from "./experiments/03-tool-repair.mjs";
import * as vcc from "./experiments/04-vcc.mjs";
import * as context from "./experiments/05-context.mjs";
import * as permissions from "./experiments/06-permissions.mjs";
import * as quiver from "./experiments/07-quiver.mjs";
import * as hermes from "./experiments/08-hermes.mjs";

const execFileAsync = promisify(execFile);
const EXPERIMENTS = [
  todo,
  askUser,
  toolRepair,
  vcc,
  context,
  permissions,
  quiver,
  hermes,
];

function stamp(date = new Date()) {
  return date.toISOString().replace(/[:.]/g, "-");
}

function mdCell(value) {
  return String(value ?? "")
    .replace(/\|/g, "\\|")
    .replace(/\n/g, "<br>");
}

function statusLabel(status) {
  if (status === "pass") return "PASS";
  if (status === "fail") return "FAIL";
  return "NOT TESTED";
}

async function versions() {
  const { stdout: nodeVersion } = await execFileAsync(NODE_BIN, ["--version"]);
  const entries = {};
  for (const [key, name] of Object.entries(PACKAGES)) {
    try {
      const scan = await scanPackage(packageDir(name));
      entries[key] = scan.package;
    } catch (error) {
      entries[key] = { name, error: String(error) };
    }
  }
  return { nodeVersion: nodeVersion.trim(), packages: entries };
}

function labbook({ date, root, versions: v, results, scans }) {
  const lines = [];
  lines.push("# Pi-Package Experiments — Labbook");
  lines.push("");
  lines.push(`- Date: ${date}`);
  lines.push(`- pi version: ${PI_VERSION}`);
  lines.push(`- Node version: ${v.nodeVersion}`);
  lines.push(`- Results root: ${root}`);
  lines.push("- Provider: local OpenAI-compatible mock, no external network");
  lines.push("");
  lines.push("## Package versions");
  lines.push("");
  lines.push("| Package | Version | License |");
  lines.push("|---|---|---|");
  for (const [key, pkg] of Object.entries(v.packages)) {
    lines.push(
      `| ${key}: ${mdCell(pkg?.name ?? "?")} | ${mdCell(pkg?.version ?? "?")} | ${mdCell(pkg?.license ?? "?")} |`,
    );
  }
  lines.push("");
  lines.push("## Verdicts");
  lines.push("");
  lines.push("| Experiment | Package | Verdict |");
  lines.push("|---|---|---|");
  for (const result of results) {
    lines.push(
      `| ${result.id} | ${mdCell(result.package)} | ${mdCell(result.verdictDetail ?? result.verdict.toUpperCase())} |`,
    );
  }
  lines.push("");

  for (const result of results) {
    lines.push(`## ${result.id} — ${result.title}`);
    lines.push("");
    lines.push(`- Package: \`${result.package}\``);
    lines.push(
      `- Verdict: **${result.verdictDetail ?? result.verdict.toUpperCase()}**`,
    );
    lines.push("");
    lines.push("### Hypothesis");
    lines.push("");
    lines.push(result.hypothesis);
    lines.push("");
    lines.push("### Method");
    lines.push("");
    lines.push(result.method);
    lines.push("");
    lines.push("### Command shape");
    lines.push("");
    lines.push("```text");
    lines.push(result.commandShape);
    lines.push("```");
    lines.push("");
    lines.push("### Requirements");
    lines.push("");
    lines.push("| ID | Requirement | Status | Observed |");
    lines.push("|---|---|---|---|");
    for (const req of result.requirements) {
      lines.push(
        `| ${mdCell(req.id)} | ${mdCell(req.requirement)} | ${statusLabel(req.status)}${req.gating ? "" : " (non-gating)"} | ${mdCell(
          typeof req.observed === "string"
            ? req.observed
            : JSON.stringify(req.observed),
        )} |`,
      );
    }
    lines.push("");
    lines.push("### Observed runs");
    lines.push("");
    for (const [name, run] of Object.entries(result.runs ?? {})) {
      lines.push(
        `- ${name}: exit=${run?.code ?? "?"} signal=${run?.signal ?? "null"} timedOut=${run?.timedOut} requests=${run?.requestCount} stderr=${mdCell((run?.stderrTail ?? "").slice(-400))}`,
      );
    }
    lines.push("");
    lines.push("### Limitations");
    lines.push("");
    for (const limitation of result.limitations ?? []) lines.push(`- ${limitation}`);
    lines.push("");
  }

  lines.push("## Static analysis");
  lines.push("");
  lines.push(
    "Counts are raw textual matches in package sources excluding nested `node_modules`. `setActiveTools` and `registerProvider` are allowlist risks and are flagged explicitly.",
  );
  lines.push("");
  lines.push(
    "| Package | Files | fetch | http.request | https.request | net.connect | child_process | spawn( | exec( | eval( | new Function | setActiveTools | registerProvider | process.env | Risks |",
  );
  lines.push("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|");
  for (const [key, scan] of Object.entries(scans)) {
    const c = scan.counts;
    lines.push(
      `| ${key} | ${scan.filesScanned} | ${c.fetch} | ${c["http.request"]} | ${c["https.request"]} | ${c["net.connect"]} | ${c.child_process} | ${c["spawn("]} | ${c["exec("]} | ${c["eval("]} | ${c["new Function"]} | ${c.setActiveTools} | ${c.registerProvider} | ${c["process.env"]} | ${mdCell(scan.allowlistRisks.join(", ") || "none")} |`,
    );
  }
  lines.push("");
  lines.push("### Scan match details");
  lines.push("");
  for (const [key, scan] of Object.entries(scans)) {
    lines.push(`#### ${key} (${scan.package?.name ?? "?"} ${scan.package?.version ?? "?"})`);
    lines.push("");
    lines.push(
      `- dependencies: \`${JSON.stringify(scan.package?.dependencies ?? {})}\``,
    );
    lines.push(
      `- scripts: \`${JSON.stringify(scan.package?.scripts ?? {})}\``,
    );
    lines.push(`- allowlist risks: ${scan.allowlistRisks.join(", ") || "none"}`);
    lines.push("");
    if (scan.matches.length === 0) {
      lines.push("- no matches");
    } else {
      for (const match of scan.matches.slice(0, 200)) {
        lines.push(
          `- \`${match.pattern}\` ${match.file}:${match.line} — ${match.snippet}`,
        );
      }
      if (scan.matches.length > 200) {
        lines.push(`- ... ${scan.matches.length - 200} more matches in results.json`);
      }
    }
    lines.push("");
  }

  lines.push("## Notes");
  lines.push("");
  lines.push(
    "- All runs are offline against the mock provider; `PATH=/usr/bin:/bin`; no package was installed during the run.",
  );
  lines.push(
    "- Results are deterministic in structure but depend on pi's own token estimates and event ordering.",
  );
  lines.push(
    '- "NOT TESTED" is a valid result; non-gating rows do not turn a verdict into a failure.',
  );
  lines.push("");
  return lines.join("\n");
}

async function main() {
  const timestamp = stamp();
  const root = runRoot(timestamp);
  const resultsDir = path.join(root, "results");
  await mkdir(resultsDir, { recursive: true });

  const v = await versions();
  const scans = {};
  for (const [key, name] of Object.entries(PACKAGES)) {
    scans[key] = await scanPackage(packageDir(name));
  }

  const results = [];
  for (const experiment of EXPERIMENTS) {
    let moduleResult;
    try {
      moduleResult = await experiment.run({
        runRoot: path.join(root, "work", experiment.meta.id),
      });
    } catch (error) {
      moduleResult = {
        ...experiment.meta,
        method: "Harness error before/during the experiment.",
        commandShape: "see experiment module",
        requirements: [
          {
            id: "harness",
            requirement: "Experiment completes",
            status: "fail",
            observed: String(error?.stack ?? error),
            gating: true,
          },
        ],
        verdict: "fail",
        runs: {},
        limitations: ["Harness exception; verdict is not evidence about the package."],
      };
    }
    moduleResult.staticScan = scans[
      Object.entries(PACKAGES).find(([, name]) => name === moduleResult.package)?.[0]
    ] ?? null;
    results.push(moduleResult);
    await writeFile(
      path.join(resultsDir, `${moduleResult.id}.json`),
      JSON.stringify({ ...moduleResult, staticScan: moduleResult.staticScan }, null, 2),
    );
    console.log(
      `${moduleResult.id.padEnd(16)} ${moduleResult.verdict.toUpperCase().padEnd(12)} ${moduleResult.package}`,
    );
  }

  const combined = {
    date: new Date().toISOString(),
    piVersion: PI_VERSION,
    nodeVersion: v.nodeVersion,
    packages: v.packages,
    results,
    staticScans: scans,
  };
  await writeFile(path.join(root, "results.json"), JSON.stringify(combined, null, 2));
  await writeFile(
    path.join(root, "LABBOOK.md"),
    labbook({
      date: new Date().toISOString(),
      root,
      versions: v,
      results,
      scans,
    }),
  );

  console.log("");
  console.log(`Results root: ${root}`);
  console.log(`LABBOOK: ${path.join(root, "LABBOOK.md")}`);
  const failed = results.filter((r) => r.verdict === "fail");
  const partial = results.filter((r) => r.verdict === "partial");
  const conditional = results.filter((r) => r.verdict === "conditional");
  console.log(
    `Summary: ${results.length - failed.length - partial.length - conditional.length} pass, ${partial.length} partial, ${conditional.length} conditional, ${failed.length} fail`,
  );
  if (failed.length > 0) {
    console.log(`Failed: ${failed.map((r) => r.id).join(", ")}`);
  }
  if (partial.length > 0) {
    console.log(`Partial: ${partial.map((r) => r.id).join(", ")}`);
  }
  if (conditional.length > 0) {
    console.log(`Conditional: ${conditional.map((r) => r.id).join(", ")}`);
  }
}

await main();
