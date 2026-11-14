import { readdir, readFile } from "node:fs/promises";
import path from "node:path";

export const SCAN_PATTERNS = [
  { id: "fetch", re: /\bfetch\s*\(/g },
  { id: "http.request", re: /\bhttp\.request\b/g },
  { id: "https.request", re: /\bhttps\.request\b/g },
  { id: "net.connect", re: /\bnet\.connect\b/g },
  { id: "child_process", re: /\bchild_process\b/g },
  { id: "spawn(", re: /\bspawn\s*\(/g },
  { id: "exec(", re: /\bexec\s*\(/g },
  { id: "eval(", re: /\beval\s*\(/g },
  { id: "new Function", re: /\bnew\s+Function\b/g },
  { id: "setActiveTools", re: /\bsetActiveTools\b/g },
  { id: "registerProvider", re: /\bregisterProvider\b/g },
  { id: "process.env", re: /\bprocess\.env\b/g },
];

const TEXT_EXTENSIONS = new Set([
  ".ts",
  ".tsx",
  ".js",
  ".mjs",
  ".cjs",
  ".json",
  ".md",
  ".py",
  ".sh",
  ".yaml",
  ".yml",
]);

function isTextFile(name) {
  return TEXT_EXTENSIONS.has(path.extname(name).toLowerCase());
}

async function walk(root, current = root, out = []) {
  let entries;
  try {
    entries = await readdir(current, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const entry of entries) {
    if (entry.name === "node_modules" || entry.name === ".git") continue;
    const full = path.join(current, entry.name);
    if (entry.isDirectory()) await walk(root, full, out);
    else if (entry.isFile() && isTextFile(entry.name)) out.push(full);
  }
  return out.sort();
}

function scanText(text, file) {
  const matches = [];
  const lines = text.split("\n");
  for (const pattern of SCAN_PATTERNS) {
    pattern.re.lastIndex = 0;
    for (const [i, line] of lines.entries()) {
      pattern.re.lastIndex = 0;
      if (!pattern.re.test(line)) continue;
      matches.push({
        pattern: pattern.id,
        file,
        line: i + 1,
        snippet: line.trim().slice(0, 240),
      });
    }
  }
  return matches;
}

export async function scanPackage(packagePath) {
  const files = await walk(packagePath);
  const matches = [];
  for (const file of files) {
    let text;
    try {
      text = await readFile(file, "utf8");
    } catch {
      continue;
    }
    matches.push(...scanText(text, path.relative(packagePath, file)));
  }

  let pkg = null;
  try {
    pkg = JSON.parse(await readFile(path.join(packagePath, "package.json"), "utf8"));
  } catch {}

  const byPattern = {};
  for (const pattern of SCAN_PATTERNS) {
    byPattern[pattern.id] = matches.filter((m) => m.pattern === pattern.id).length;
  }

  const riskPatterns = ["setActiveTools", "registerProvider"];
  const allowlistRisks = riskPatterns.filter((id) => byPattern[id] > 0);

  return {
    packagePath,
    package: pkg
      ? {
          name: pkg.name,
          version: pkg.version,
          license: pkg.license,
          type: pkg.type,
          dependencies: pkg.dependencies ?? {},
          optionalDependencies: pkg.optionalDependencies ?? {},
          peerDependencies: pkg.peerDependencies ?? {},
          scripts: pkg.scripts ?? {},
          pi: pkg.pi ?? null,
        }
      : null,
    filesScanned: files.length,
    counts: byPattern,
    allowlistRisks,
    matches,
  };
}
