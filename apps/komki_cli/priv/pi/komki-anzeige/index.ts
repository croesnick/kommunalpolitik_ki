// pi-Extension: zeichnet die Tool-Aufrufe des Vermittlers (Server `komki`)
// lesbar statt als Roh-JSON und zeigt Raum, Labels und Raumdokumente (Kopf-
// und Fußzeile, /raum, /dokumente, /hilfe). Die Extension registriert weder
// tool_call- noch tool_result-Handler und ändert damit weder Entscheidungen
// noch den Modellkontext. Sie beobachtet nur tool_execution_end (ohne
// Rückgabewert), um die letzte Dokumentliste zu kennen. Ihre Ausgaben sind
// Session-Einträge, die pi nicht ans Modell schickt. Die Gestaltung steht in
// view.ts und raum.ts. Eine Ausnahme von der reinen Anzeige: /resume und
// /import zu einer fremden Session bricht sie ab (Ticket #295, unten).

import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { keyText } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";
import { dokumenteRows, headerRows, hilfeRows, parseRaum, type Raum, raumName, raumRows, statusText } from "./raum.ts";
import { callLine, documentsOf, layout, type Paint, type RoomDocument, resultRows, type Row, SERVER_PREFIX } from "./view.ts";

const INFO = "komki-info";

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

function readRaum(path: unknown): Raum | undefined {
	if (typeof path !== "string" || path === "") return undefined;
	try {
		return parseRaum(readFileSync(path, "utf8"));
	} catch {
		return undefined;
	}
}

type Info = { kind: "raum" | "dokumente" | "hilfe" };

export default function (pi: ExtensionAPI) {
	let raum: Raum | undefined;
	let docs: RoomDocument[] | undefined;

	pi.registerFlag("komki-raum", { description: "Raumbild von komki (raum.json)", type: "string" });

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

	// Ausgaben der Befehle: Session-Einträge, die pi nicht ans Modell schickt.
	pi.registerEntryRenderer<Info>(INFO, (entry, _options, theme) => {
		const p = paint(theme);
		const kind = entry.data?.kind;
		return component(() => (kind === "raum" ? raumRows(raum, p) : kind === "dokumente" ? dokumenteRows(docs, p) : hilfeRows(p)));
	});

	pi.registerCommand("raum", {
		description: "Raum, Zweck, Labels und Weg nach draußen",
		handler: async () => pi.appendEntry<Info>(INFO, { kind: "raum" }),
	});
	pi.registerCommand("dokumente", {
		description: "Die Raumdokumente, die pi zuletzt aufgelistet hat",
		handler: async () => pi.appendEntry<Info>(INFO, { kind: "dokumente" }),
	});
	pi.registerCommand("hilfe", {
		description: "Befehle von komki in pi",
		handler: async () => pi.appendEntry<Info>(INFO, { kind: "hilfe" }),
	});

	let redraw = () => {};

	pi.on("session_start", async (_event, ctx) => {
		raum = readRaum(pi.getFlag("komki-raum"));
		if (ctx.mode !== "tui") return;
		// pi setzt den Fenstertitel bei jedem Session-Ereignis neu und nimmt
		// den Session-Namen hinein; ein eigener Titel hielte nicht.
		pi.setSessionName(`komki · ${raumName(raum)}`);
		ctx.ui.setHeader((_tui, theme) => component(() => [{ body: "" }, ...headerRows(raum, paint(theme))]));
		// Fußzeile: links der Raum, rechts Modell und Kontextfüllung. Ersetzt
		// pis Fußzeile mit Arbeitsverzeichnis und Modellnamen.
		ctx.ui.setFooter((tui, theme) => {
			redraw = () => tui.requestRender();
			return {
				render(width: number): string[] {
					const left = theme.fg("muted", statusText(raum, docs));
					const used = ctx.getContextUsage()?.percent;
					const right = theme.fg("dim", `lokales Modell${typeof used === "number" ? ` · Kontext ${Math.round(used)} %` : ""}`);
					const pad = " ".repeat(Math.max(1, width - visibleWidth(left) - visibleWidth(right)));
					return [truncateToWidth(left + pad + right, width)];
				},
				invalidate() {},
				dispose() {
					redraw = () => {};
				},
			};
		});
	});

	// Ticket #295: /resume und /import holten eine andere Session samt
	// Kontext in diesen Raum, auch eine aus einem strengeren. Fortsetzen geht
	// nur mit komki session --continue, das den Raum prüft. Das Profil sperrt
	// fremde Sessions ohnehin; hier gibt es statt eines Lesefehlers einen
	// Hinweis. Erlaubt bleibt der Wechsel zu einer vorhandenen Datei im
	// eigenen Verzeichnis (nach /new, /fork, /clone): derselbe Raum. /import
	// zielt auf eine Kopie, die es noch nicht gibt, und bleibt damit zu.
	pi.on("session_before_switch", async (event, ctx) => {
		if (event.reason !== "resume") return;
		const target = event.targetSessionFile;
		const own = resolve(ctx.sessionManager.getSessionDir());
		if (target && existsSync(target) && dirname(resolve(target)) === own) return;
		ctx.ui.notify(
			"In komki geht das nicht: Eine andere Session brächte ihren Kontext in diesen Raum. Beende pi mit /quit und setze die letzte Session mit komki session --continue fort.",
			"warning",
		);
		return { cancel: true };
	});

	// Nur beobachten: Die letzte Antwort von list_documents speist /dokumente
	// und die Fußzeile. Andere Werkzeuge und Fehler ändern nichts.
	pi.on("tool_execution_end", async (event) => {
		if (event.toolName !== `${SERVER_PREFIX}list_documents` || event.isError) return;
		const block = event.result?.content?.[0];
		if (block?.type !== "text") return;
		try {
			const found = documentsOf(JSON.parse(block.text));
			if (!found) return;
			docs = found;
			redraw();
		} catch {
			// Andere Antwortform: Liste bleibt, wie sie war.
		}
	});
}
