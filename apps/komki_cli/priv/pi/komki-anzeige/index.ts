// pi-Extension: zeichnet die Tool-Aufrufe des Vermittlers (Server `komki`)
// lesbar statt als Roh-JSON. Nur Anzeige: die Extension registriert keine
// tool_call- oder tool_result-Handler und ändert damit weder Entscheidungen
// noch den Modellkontext. Die Gestaltung steht in view.ts.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { keyText } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";
import { callLine, layout, type Paint, resultRows, type Row, SERVER_PREFIX } from "./view.ts";

function component(rows: () => Row[]) {
	return {
		render(width: number): string[] {
			return layout(rows(), width, wrapTextWithAnsi, visibleWidth).map((l) => truncateToWidth(l, width));
		},
		invalidate() {},
	};
}

function paint(theme: any): Paint {
	return {
		fg: (token, text) => theme.fg(token, text),
		bold: (text) => theme.bold(text),
	};
}

export default function (pi: ExtensionAPI) {
	pi.registerToolRenderer((toolName, next) => {
		if (!toolName.startsWith(SERVER_PREFIX)) return next();
		return {
			renderCall(args, theme) {
				return component(() => [{ body: callLine(toolName, args, paint(theme)) ?? toolName }]);
			},
			renderResult(result, { expanded, isPartial }, theme) {
				const p = paint(theme);
				if (isPartial) return component(() => [{ body: p.fg("warning", "läuft …") }]);
				const block = result.content?.[0];
				const text = block?.type === "text" ? block.text : "";
				// Ohne Tastenbelegung (etwa im HTML-Export) der Standard.
				const expandKey = keyText("app.tools.expand") || "ctrl+o";
				return component(() => resultRows(toolName, text, { expanded, expandKey }, p) ?? []);
			},
		};
	});
}
