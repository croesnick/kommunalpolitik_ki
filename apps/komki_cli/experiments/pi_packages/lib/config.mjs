import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const HOME = os.homedir();

export const PI_VERSION = process.env.KOMKI_PI_VERSION ?? "1.4.0";

function npmGlobalRoot() {
  try {
    return execFileSync("npm", ["root", "-g"], { encoding: "utf8" }).trim();
  } catch {
    return null;
  }
}

function locatePiCli() {
  if (process.env.KOMKI_PI_CLI) return process.env.KOMKI_PI_CLI;
  const root = npmGlobalRoot();
  if (root) {
    const candidate = path.join(
      root,
      "@earendil-works/pi-coding-agent",
      "dist",
      "bundle",
      "cli.js",
    );
    if (fs.existsSync(candidate)) return candidate;
  }
  throw new Error(
    "pi CLI not found. Set KOMKI_PI_CLI to the pi-coding-agent dist/bundle/cli.js path.",
  );
}

export const NODE_BIN = process.env.KOMKI_PI_NODE_BIN ?? process.execPath;
export const PI_CLI = locatePiCli();

export const EXPERIMENTS_ROOT =
  process.env.KOMKI_PI_EXPERIMENTS_DIR ??
  path.join(os.tmpdir(), "komki-pi-experiments");

export const VENDOR_NODE_MODULES = path.join(EXPERIMENTS_ROOT, "vendor", "node_modules");

export const PACKAGES = {
  todo: "@juicesharp/rpiv-todo",
  askUser: "@juicesharp/rpiv-ask-user-question",
  toolRepair: "pi-tool-repair",
  vcc: "@sting8k/pi-vcc",
  context: "@spences10/pi-context",
  permissions: "@gotgenes/pi-permission-system",
  quiver: "pi-quiver",
  hermes: "pi-hermes-memory",
};

export function packageDir(name) {
  return path.join(VENDOR_NODE_MODULES, name);
}

export function runRoot(stamp = timestamp()) {
  return path.join(EXPERIMENTS_ROOT, "runs", stamp);
}

export function timestamp(date = new Date()) {
  return date.toISOString().replace(/[:.]/g, "-");
}

export const MOCK_MODEL = "mock-model";
export const MOCK_PROVIDER = "mock";
export const DEFAULT_CONTEXT_WINDOW = 8192;

export { HOME };
