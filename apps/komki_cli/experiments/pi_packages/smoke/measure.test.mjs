// node --test smoke/measure.test.mjs
import assert from "node:assert/strict";
import { test } from "node:test";

import { TOOL_LOOP_REPEATS, toolCallLoops } from "./measure.mjs";

const call = (name, args) => ({ name, arguments: JSON.stringify(args) });
const request = (at, ...toolCalls) => ({ at, body: "{}", response: { toolCalls } });
const update2 = call("todo", { action: "update", id: 2, status: "completed" });

test("a run of identical tool calls at the threshold is a loop", () => {
  const records = [
    request("t0", call("read", { path: "notiz-c.md" })),
    ...Array.from({ length: TOOL_LOOP_REPEATS }, (_, i) => request(`t${i + 1}`, update2)),
    request("t9"),
  ];
  assert.deepEqual(toolCallLoops(records), [
    { name: "todo", arguments: '{"action":"update","id":2,"status":"completed"}', repeats: TOOL_LOOP_REPEATS, firstAt: "t1" },
  ]);
});

test("short retries and alternating calls are no loop", () => {
  const read = call("read", { path: "notiz-b.md" });
  const records = [
    ...Array.from({ length: TOOL_LOOP_REPEATS - 1 }, () => request("t", read)),
    ...Array.from({ length: 2 * TOOL_LOOP_REPEATS }, (_, i) => request("t", i % 2 ? read : update2)),
  ];
  assert.deepEqual(toolCallLoops(records), []);
});

test("argument key order and whitespace do not hide a loop", () => {
  const variants = [
    update2,
    { name: "todo", arguments: '{"status": "completed", "id": 2, "action": "update"}' },
    { function: { name: "todo", arguments: '{ "id":2,"action":"update","status":"completed" }' } },
  ];
  const records = Array.from({ length: TOOL_LOOP_REPEATS }, (_, i) => request(`t${i}`, variants[i % 3]));
  assert.equal(toolCallLoops(records)[0]?.repeats, TOOL_LOOP_REPEATS);
});

test("a request without tool calls ends the run; compaction summaries are skipped", () => {
  const summary = {
    at: "s",
    body: JSON.stringify({ messages: [{ role: "system", content: "You are a context summarization assistant. …" }] }),
    response: { toolCalls: [] },
  };
  const half = Math.ceil(TOOL_LOOP_REPEATS / 2);
  const broken = [
    ...Array.from({ length: half }, () => request("t", update2)),
    request("answer"),
    ...Array.from({ length: half }, () => request("t", update2)),
  ];
  assert.deepEqual(toolCallLoops(broken), []);

  const bridged = [
    ...Array.from({ length: half }, () => request("t", update2)),
    summary,
    ...Array.from({ length: half }, () => request("t", update2)),
  ];
  assert.equal(toolCallLoops(bridged)[0]?.repeats, 2 * half);
});
