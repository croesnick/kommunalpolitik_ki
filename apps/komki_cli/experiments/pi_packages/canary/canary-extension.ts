/**
 * Seatbelt canary extension for the real komki pi profile.
 *
 * Loaded with `pi -e <this file>` after being copied into the profile's
 * scratch directory (the sandbox only grants read access there). It records
 * only booleans and error metadata — never credential values.
 */

import { execFile } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";

function errorInfo(error) {
  const cause = error && error.cause;
  return {
    ok: false,
    name: error?.name ?? "Error",
    message: String(error?.message ?? error),
    code: error?.code ?? null,
    cause: cause
      ? {
          name: cause.name ?? null,
          message: String(cause.message ?? cause),
          code: cause.code ?? null,
          errno: cause.errno ?? null,
          syscall: cause.syscall ?? null,
        }
      : null,
  };
}

async function checkFetch(label, url) {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(3000) });
    return {
      ok: true,
      label,
      status: response.status,
      redirected: response.redirected,
    };
  } catch (error) {
    return { ...errorInfo(error), label };
  }
}

function checkExec() {
  return new Promise((resolve) => {
    let settled = false;
    const done = (value) => {
      if (!settled) {
        settled = true;
        resolve(value);
      }
    };

    try {
      execFile(
        "/bin/echo",
        ["canary"],
        { timeout: 3000 },
        (error, stdout, stderr) => {
          if (error) {
            done({
              ...errorInfo(error),
              stderr: stderr ? String(stderr).slice(0, 500) : null,
            });
            return;
          }
          done({ ok: true, stdout: String(stdout).trim() });
        },
      );
    } catch (error) {
      // Node can throw EPERM synchronously when the sandbox denies the
      // fork/exec before a child process exists.
      done({ ...errorInfo(error), synchronous: true });
    }
  });
}

async function checkWrite(file) {
  try {
    await writeFile(file, "komki canary escape attempt\n", "utf8");
    return { ok: true, file };
  } catch (error) {
    return { ...errorInfo(error), file };
  }
}

async function checkReadable(file) {
  try {
    // Read and discard: the point is whether the in-process extension can
    // reach the credential at all. Only a boolean leaves this function.
    await readFile(file);
    return true;
  } catch {
    return false;
  }
}

async function guard(fn) {
  try {
    return await fn();
  } catch (error) {
    return errorInfo(error);
  }
}

async function runChecks() {
  // Each probe is isolated: a synchronous EPERM in one must not hide the
  // results of the others.
  const checks = {};
  checks.externalFetch = await guard(() =>
    checkFetch("external", "https://example.com"),
  );
  checks.execFileEcho = await guard(() => checkExec());
  checks.tmpWrite = await guard(() => checkWrite("/tmp/komki-canary-escape.txt"));
  checks.mockFetch = process.env.KOMKI_CANARY_MOCK_URL
    ? await guard(() =>
        checkFetch("mock-provider", process.env.KOMKI_CANARY_MOCK_URL),
      )
    : { ok: false, label: "mock-provider", message: "KOMKI_CANARY_MOCK_URL missing" };
  checks.mediatorTokenInEnv =
    typeof process.env.KOMKI_MEDIATOR_TOKEN === "string" &&
    process.env.KOMKI_MEDIATOR_TOKEN.length > 0;
  checks.llamaKeyReadable = process.env.KOMKI_CANARY_LLAMA_KEY
    ? await guard(() => checkReadable(process.env.KOMKI_CANARY_LLAMA_KEY))
    : false;

  // The provider key is also present in the agent's models.json. That file
  // lives in pi-home and is readable by the extension even when the separate
  // llama.key file is outside the profile's read scope. Record booleans only.
  const agentDir = process.env.PI_CODING_AGENT_DIR;
  checks.modelsJsonReadable = agentDir
    ? await guard(() => checkReadable(`${agentDir}/models.json`))
    : false;
  checks.modelsJsonHasApiKey = false;
  if (agentDir) {
    try {
      const raw = await readFile(`${agentDir}/models.json`, "utf8");
      const parsed = JSON.parse(raw);
      const providers = Object.values(parsed?.providers ?? {});
      checks.modelsJsonHasApiKey = providers.some(
        (provider) =>
          typeof provider?.apiKey === "string" && provider.apiKey.length > 0,
      );
    } catch {
      // keep false
    }
  }
  checks.authJsonReadable = agentDir
    ? await guard(() => checkReadable(`${agentDir}/auth.json`))
    : false;
  checks.resultPath = process.env.KOMKI_CANARY_RESULT ?? null;
  checks.cwd = process.cwd();
  checks.node = process.version;
  checks.pid = process.pid;

  return {
    ranAt: new Date().toISOString(),
    sandboxExec: process.env.KOMKI_CANARY_SANDBOX_EXEC === "1",
    checks,
  };
}

export default function (pi) {
  pi.on("session_start", async () => {
    const resultPath = process.env.KOMKI_CANARY_RESULT;
    let payload;
    try {
      payload = await runChecks();
    } catch (error) {
      payload = {
        ranAt: new Date().toISOString(),
        sandboxExec: process.env.KOMKI_CANARY_SANDBOX_EXEC === "1",
        harnessError: errorInfo(error),
      };
    }

    if (resultPath) {
      try {
        await writeFile(resultPath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
      } catch (error) {
        // The runner observes a missing result file; keep the error visible
        // on stderr without writing outside the allowed scope.
        const info = errorInfo(error);
        process.stderr.write(`canary-result-write-failed: ${info.name}: ${info.message}\n`);
      }
    }
  });
}
