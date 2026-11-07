// Tests of the loop detection extension (priv/pi/komki-loop-detection/loop.ts).
// Run: node --test apps/komki_cli/test/pi/*.test.ts

import assert from "node:assert/strict";
import { test } from "node:test";
import { createLoopCounter, LOOP_REPEATS, signature, stopNotice } from "../../priv/pi/komki-loop-detection/loop.ts";

const read = signature("mcp__komki__vault_read", { path: "notizen/a.md" });

test("the LOOP_REPEATS-th identical call in a row is the first one to stop", () => {
	const counter = createLoopCounter();
	const counts = Array.from({ length: LOOP_REPEATS }, () => counter.next(read));
	assert.deepEqual(counts, Array.from({ length: LOOP_REPEATS }, (_, i) => i + 1));
	assert.equal(counts.filter((n) => n >= LOOP_REPEATS).length, 1);
});

test("a different call in between starts the count again", () => {
	const counter = createLoopCounter();
	const other = signature("mcp__komki__vault_read", { path: "notizen/b.md" });
	for (let i = 0; i < 3 * LOOP_REPEATS; i++) assert.ok(counter.next(i % 2 ? other : read) < LOOP_REPEATS);
});

test("argument key order does not hide a repeat", () => {
	const a = signature("todo", { action: "update", id: 2, status: "completed" });
	const b = signature("todo", { status: "completed", id: 2, action: "update" });
	assert.equal(a, b);
	assert.notEqual(a, signature("todo", { action: "update", id: 3, status: "completed" }));
});

test("reset clears the count (a new run of the agent)", () => {
	const counter = createLoopCounter();
	for (let i = 0; i < LOOP_REPEATS - 1; i++) counter.next(read);
	counter.reset();
	assert.equal(counter.next(read), 1);
});

test("the notice names the tool without the server prefix and the count", () => {
	const notice = stopNotice("mcp__komki__vault_read", LOOP_REPEATS);
	assert.match(notice, /vault_read/);
	assert.doesNotMatch(notice, /mcp__komki__/);
	assert.match(notice, new RegExp(`${LOOP_REPEATS}-mal`));
});
