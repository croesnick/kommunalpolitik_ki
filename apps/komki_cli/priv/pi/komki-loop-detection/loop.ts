// Counting of identical tool calls in a row (Ticket #383). Kept free of pi
// imports so that node --test runs it directly.

/**
 * The LOOP_REPEATS-th identical call in a row stops the run. Same threshold
 * as the smoke harness (TOOL_LOOP_REPEATS in experiments/pi_packages/smoke/
 * measure.mjs): in the #372 proxy logs benign repeats reached 3, loops 7 and
 * more, up to 647 calls until the timeout.
 */
export const LOOP_REPEATS = 5;

const SERVER_PREFIX = "mcp__komki__";

/** Tool name plus arguments with sorted keys: equal calls, equal signature. */
export function signature(toolName: string, input: unknown): string {
	const args =
		input && typeof input === "object" && !Array.isArray(input)
			? Object.fromEntries(Object.entries(input).sort(([a], [b]) => a.localeCompare(b)))
			: input;
	return JSON.stringify([toolName, args ?? null]);
}

export type LoopCounter = { next(signature: string): number; reset(): void };

/** `next` returns how often this signature has now occurred in a row. */
export function createLoopCounter(): LoopCounter {
	let last: string | undefined;
	let repeats = 0;
	return {
		next(sig) {
			repeats = sig === last ? repeats + 1 : 1;
			last = sig;
			return repeats;
		},
		reset() {
			last = undefined;
			repeats = 0;
		},
	};
}

/** Notice for the user when komki stops the run. */
export function stopNotice(toolName: string, repeats: number): string {
	const name = toolName.startsWith(SERVER_PREFIX) ? toolName.slice(SERVER_PREFIX.length) : toolName;
	return `komki hat den Lauf angehalten: ${repeats}-mal hintereinander derselbe Aufruf (${name}). Mit einer neuen Nachricht geht es weiter.`;
}

/** Text the model sees as the result of the blocked call. */
export const BLOCK_REASON =
	"Abgebrochen: Dieser Aufruf ist identisch mit den vorigen. Das Ergebnis liegt dir schon vor; der Lauf endet hier.";
