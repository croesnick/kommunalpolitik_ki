// pi extension: stops a run when the model issues the same tool call
// LOOP_REPEATS times in a row (Ticket #383). pi 1.4.0 itself has no limit on
// turns or tool calls; in #372 one such loop ran for an hour until the
// timeout. The LOOP_REPEATS-th call is blocked with `terminate`, which ends
// the run after this batch, and the user gets a notice: in the session as a
// TUI notification, in `komki run` on stderr, once per run. The next prompt
// starts a new run and with it a new count.
//
// pi ends a run only when every call of a batch sets `terminate`. If the
// model sends the repeats as one batch of parallel calls, the calls before
// the LOOP_REPEATS-th still run, and pi grants one more turn; a following
// batch of repeats is blocked as a whole and ends the run.
//
// A resource and usability limit, not a security boundary: every call still
// goes through the mediator's gates.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { BLOCK_REASON, createLoopCounter, LOOP_REPEATS, signature, stopNotice } from "./loop.ts";

export default function (pi: ExtensionAPI) {
	const counter = createLoopCounter();
	let notified = false;

	pi.on("agent_start", async () => {
		counter.reset();
		notified = false;
	});

	pi.on("tool_call", async (event, ctx) => {
		const repeats = counter.next(signature(event.toolName, event.input));
		if (repeats < LOOP_REPEATS) return undefined;

		if (!notified) {
			const notice = stopNotice(event.toolName, repeats);
			if (ctx.hasUI) ctx.ui.notify(notice, "warning");
			else process.stderr.write(`[${notice}]\n`);
			notified = true;
		}
		return { block: true, reason: BLOCK_REASON, terminate: true };
	});
}
