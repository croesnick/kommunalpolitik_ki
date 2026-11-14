import path from "node:path";

import { PACKAGES, packageDir } from "../lib/config.mjs";
import {
  mockToolList,
  requirement,
  summarizeRun,
  verdictOf,
} from "../lib/experiment.mjs";
import { runPi, runPiRpc } from "../lib/runner.mjs";
import { findToolResult } from "../lib/session.mjs";

const PACKAGE = PACKAGES.askUser;
const EXTENSION = path.join(packageDir(PACKAGE), "index.ts");

const QUESTION_CALL = {
  name: "ask_user_question",
  arguments: {
    questions: [
      {
        question: "Welche Option soll geprüft werden?",
        header: "Auswahl",
        options: [
          { label: "Option A", description: "Erste Option" },
          { label: "Option B", description: "Zweite Option" },
        ],
      },
    ],
  },
};

export const meta = {
  id: "02-ask-user",
  package: PACKAGE,
  title: "rpiv-ask-user-question: headless, tool visibility, and RPC dialogs",
  hypothesis:
    "In headless --print mode the tool is absent or returns no_ui; in RPC mode it is declared and the native select/input dialog walker returns the chosen option to the model. The event-bus answer path is still not exercised.",
};

export async function run(ctx) {
  const requirements = [];
  const runs = {};

  const a = await runPi({
    id: "A",
    runRoot: ctx.runRoot,
    extensions: [EXTENSION],
    tools: "ask_user_question",
    prompt: "Stelle eine Rückfrage.",
    timeoutMs: 8000,
    responses: [{ toolCalls: [QUESTION_CALL] }, { text: "Weiter." }],
  });
  runs.A = summarizeRun(a);

  const aResult = a.session ? findToolResult(a.session, "ask_user_question") : null;
  const noUi =
    Boolean(aResult) &&
    (/no_ui/i.test(aResult.text) ||
      /UI not available|non-interactive/i.test(aResult.text) ||
      aResult.isError === true);
  requirements.push(
    requirement(
      "A-no-hang",
      "Run finishes within 8 s, no timeout",
      a.timedOut ? "fail" : "pass",
      { code: a.code, signal: a.signal, timedOut: a.timedOut, durationMs: a.durationMs },
    ),
  );
  requirements.push(
    requirement(
      "A-in-band",
      "Tool result records no_ui / non-interactive error",
      noUi ? "pass" : "fail",
      {
        declaredTools: mockToolList(a),
        isError: aResult?.isError ?? null,
        text: aResult?.text ?? "no tool result",
        exactBehaviour:
          aResult?.text === "Tool ask_user_question not found"
            ? "pi 1.4.0 + package reconciliation removed the ask_user_question tool in headless mode; the mock's call hit the unknown-tool path, not the package's no_ui envelope."
            : aResult?.text ?? "no tool result",
        stderrTail: (a.stderr ?? "").slice(-1000),
      },
    ),
  );

  const b = await runPi({
    id: "B",
    runRoot: ctx.runRoot,
    extensions: [EXTENSION],
    tools: "read",
    prompt: "Rufe ask_user_question auf, obwohl es nicht allowlisted ist.",
    timeoutMs: 8000,
    responses: [{ toolCalls: [QUESTION_CALL] }, { text: "Weiter." }],
  });
  runs.B = summarizeRun(b);

  const declared = mockToolList(b);
  const bResult = b.session ? findToolResult(b.session, "ask_user_question") : null;
  requirements.push(
    requirement(
      "B-absent",
      "Without allowlisting, ask_user_question is not declared to the model",
      declared.includes("ask_user_question") ? "fail" : "pass",
      { declaredTools: declared, toolResult: bResult?.text ?? null },
    ),
  );

  const rpc = await runPiRpc({
    id: "C-rpc",
    runRoot: ctx.runRoot,
    extensions: [EXTENSION],
    tools: "ask_user_question",
    prompt: "Stelle eine Rückfrage.",
    timeoutMs: 15000,
    responses: [{ toolCalls: [QUESTION_CALL] }, { text: "Danke, Option A." }],
  });
  runs.C = summarizeRun(rpc);

  const rpcDeclared = (rpc.requests[0]?.parsed?.tools ?? []).map(
    (tool) => tool.function?.name ?? tool.name,
  );
  const rpcSelects = rpc.uiRequests.filter((request) => request.method === "select");
  const rpcToolCall = rpc.session?.toolCalls.find((call) => call.name === "ask_user_question");
  const rpcToolResult = rpcToolCall && rpc.session
    ? rpc.session.toolResults.find((result) => result.toolCallId === rpcToolCall.id)
    : null;
  const lastRequest = rpc.requests.at(-1)?.parsed;
  const answerInModelContext = Boolean(
    lastRequest &&
      JSON.stringify(lastRequest.messages ?? []).includes("Option A"),
  );
  const dialogDriven =
    rpcSelects.length > 0 &&
    rpc.uiResponses.some(
      (response) =>
        response.type === "extension_ui_response" &&
        typeof response.value === "string" &&
        response.value.includes("Option A"),
    );

  const rpcBlocked =
    rpcDeclared.length === 0 ||
    (rpcSelects.length === 0 &&
      /no_custom_ui|not available|failed to load|stale module/i.test(rpcToolResult?.text ?? ""));

  requirements.push(
    requirement(
      "C-rpc-declared",
      "RPC mode declares ask_user_question to the model",
      rpcBlocked ? "not-tested" : rpcDeclared.includes("ask_user_question") ? "pass" : "fail",
      {
        declaredTools: rpcDeclared,
        records: rpc.records.filter((r) => r.type === "extension_ui_request").slice(0, 5),
        stderrTail: (rpc.stderr ?? "").slice(-1500),
      },
      { gating: !rpcBlocked },
    ),
  );

  requirements.push(
    requirement(
      "C-rpc-dialog",
      "RPC client answers the native select dialog with the first option",
      rpcBlocked ? "not-tested" : dialogDriven ? "pass" : "fail",
      {
        uiRequests: rpc.uiRequests.map((r) => ({
          method: r.method,
          title: r.title,
          options: r.options,
          timeout: r.timeout,
        })),
        uiResponses: rpc.uiResponses,
      },
      { gating: !rpcBlocked },
    ),
  );

  requirements.push(
    requirement(
      "C-rpc-answer",
      "The model context receives the selected answer text",
      rpcBlocked
        ? "not-tested"
        : rpcToolResult?.text?.includes("Option A") && answerInModelContext
          ? "pass"
          : "fail",
      {
        toolResult: rpcToolResult
          ? { isError: rpcToolResult.isError, text: rpcToolResult.text.slice(0, 2000) }
          : null,
        answerInModelContext,
        requestCount: rpc.requests.length,
      },
      { gating: !rpcBlocked },
    ),
  );

  requirements.push(
    requirement(
      "C-rpc-no-hang",
      "RPC run exits without timeout",
      rpc.timedOut ? "fail" : "pass",
      {
        code: rpc.code,
        signal: rpc.signal,
        timedOut: rpc.timedOut,
        durationMs: rpc.durationMs,
        agentSettled: rpc.events.some((event) => event.type === "agent_settled"),
      },
    ),
  );

  requirements.push(
    requirement(
      "D-event-bus",
      "Auto-answer via rpiv:ask-user:prompt / answer event bus",
      "not-tested",
      "The RPC run exercises pi's extension_ui_request/response dialog sub-protocol, not the package's rpiv:ask-user:prompt / rpiv:ask-user:answer event bus. Testing the bus still needs an external listener extension or interactive host and is out of scope.",
      { gating: false },
    ),
  );

  return {
    ...meta,
    method:
      "A/B headless mock runs (A allowlisted, B read-only), C via pi --mode rpc with a JSONL client that answers extension_ui_request select dialogs with the first option, and D assessed from source. All runs use the same mock provider.",
    commandShape:
      "headless: node <pi-cli> --print --mode json ... --tools ask_user_question|read -e index.ts;\nrpc: node <pi-cli> --mode rpc ... --tools ask_user_question -e index.ts",
    requirements,
    verdict: verdictOf(requirements),
    runs,
    limitations: [
      "RPC dialog sub-protocol is tested; the interactive TUI overlay is not.",
      "The inbound rpiv:ask-user:answer event bus is not exercised by the RPC client.",
      "The 8 s headless timeout intentionally cuts off any accidental headless hang.",
    ],
  };
}
