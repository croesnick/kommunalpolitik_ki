export function requirement(id, text, status, observed, { gating = true } = {}) {
  return { id, requirement: text, status, observed, gating };
}

export function verdictOf(requirements) {
  const gating = requirements.filter((r) => r.gating);
  if (gating.some((r) => r.status === "fail")) return "fail";
  if (gating.some((r) => r.status === "not-tested")) return "partial";
  if (gating.length === 0) return "not-tested";
  return "pass";
}

export function summarizeRun(run) {
  if (!run) return null;
  const eventCounts = {};
  for (const event of run.events ?? []) {
    eventCounts[event.type] = (eventCounts[event.type] ?? 0) + 1;
  }
  return {
    code: run.code,
    signal: run.signal,
    timedOut: run.timedOut,
    durationMs: run.durationMs,
    spawnError: run.spawnError,
    stdoutBytes: Buffer.byteLength(run.stdout ?? ""),
    stderrTail: (run.stderr ?? "").slice(-2000),
    parseErrors: run.parseErrors ?? [],
    eventCounts,
    requestCount: run.requests?.length ?? 0,
    sessionFile: run.sessionFile,
    toolResults: (run.session?.toolResults ?? []).map((r) => ({
      toolName: r.toolName,
      isError: r.isError,
      text: r.text.slice(0, 1200),
    })),
    newFiles: run.files?.created ?? [],
    removedFiles: run.files?.removed ?? [],
  };
}

export function mockToolList(run) {
  const body = run?.requests?.[0]?.parsed;
  return (body?.tools ?? []).map((tool) => tool.function?.name ?? tool.name);
}

export function systemPromptOf(run) {
  const body = run?.requests?.[0]?.parsed;
  const message = (body?.messages ?? []).find((m) => m.role === "system");
  return message ? JSON.stringify(message) : null;
}

export function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
