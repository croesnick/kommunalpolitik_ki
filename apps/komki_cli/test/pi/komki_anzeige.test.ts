// Tests der Anzeige-Extension (priv/pi/komki-anzeige/view.ts).
// Lauf: node --test apps/komki_cli/test/pi/
//
// Die Fixtures sind echte Antworten von KomkiMediator.ConnectorGate mit
// Fake-Connectoren und fiktiven Inhalten (Herkunft: fixtures/README.md).

import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { callLine, clean, layout, type Paint, resultRows } from "../../priv/pi/komki-anzeige/view.ts";

const dir = join(import.meta.dirname, "fixtures");
const fixture = (name: string) => JSON.parse(readFileSync(join(dir, `${name}.json`), "utf8"));
const names = readdirSync(dir)
	.filter((f) => f.endsWith(".json"))
	.map((f) => f.replace(/\.json$/, ""));

// Markup statt ANSI: Farben sind im Text prüfbar, Breiten bleiben zählbar.
const paint: Paint = {
	fg: (token, text) => `<${token}>${text}</>`,
	bold: (text) => `<b>${text}</>`,
};
const strip = (s: string) => s.replace(/<[^>]*>/g, "");
const measure = (s: string) => [...strip(s)].length;

// Einfacher Wortumbruch auf sichtbarer Breite (im Betrieb: pi-tui).
function wrap(text: string, width: number): string[] {
	const out: string[] = [];
	let line = "";
	for (const word of text.split(" ")) {
		const next = line === "" ? word : `${line} ${word}`;
		if (measure(next) <= width || line === "") line = next;
		else {
			out.push(line);
			line = word;
		}
	}
	out.push(line);
	return out;
}

function render(name: string, expanded = false, mutate?: (r: any) => void): string {
	const fx = fixture(name);
	let text = fx.text;
	if (mutate) {
		const r = JSON.parse(text);
		mutate(r);
		text = JSON.stringify(r);
	}
	const rows = resultRows(`mcp__komki__${fx.tool}`, text, { expanded, expandKey: "ctrl+o" }, paint);
	assert.ok(rows, `${name}: keine Zeilen`);
	return layout(rows, 100, wrap, measure).join("\n");
}

test("jede Fixture wird gezeichnet, zugeklappt ohne Roh-JSON und Hashes", () => {
	for (const name of names) {
		const out = strip(render(name));
		assert.doesNotMatch(out, /payload_hash|"decision"|sha256:/, name);
		assert.doesNotMatch(out, /Unbekannte Antwortform/, name);
	}
});

test("Treffer im RIS: Datum deutsch, Titel, Quelle und Abruf sichtbar", () => {
	const out = render("ris_search");
	assert.match(out, /<success><b>✓ zugelassen<\/><\/>/);
	assert.match(strip(out), /öffentlich · 3 Treffer/);
	assert.match(strip(out), /30\.06\.2026 +Ergebnisse des Arbeitskreises/);
	assert.doesNotMatch(out, /https:/);
	// 18:17Z ist 20:17 in Deutschland (MESZ), unabhängig von der TZ des Prozesses.
	assert.match(strip(out), /Quelle: RIS · abgerufen 24\.10\.2026, 20:17 · Beleg pdr-9dd7c70b…/);
});

test("Ablehnung: rot, mit Grund, Ausweg und Beleg; Gate benannt", () => {
	const vault = strip(render("vault_read_deny"));
	assert.match(vault, /✗ abgelehnt +Der Inhalt hat das Modell nicht erreicht\./);
	assert.match(vault, /Grund +Das Label des Inhalts ist in diesem Arbeitsraum nicht zugelassen\./);
	assert.match(vault, /Möglich +in einem Arbeitsraum, der „vertraulich“ zulässt/);
	assert.match(vault, /Beleg pdr-88bd395c…/);
	assert.match(render("vault_read_deny"), /<error><b>✗ abgelehnt/);

	const web = strip(render("web_search_deny"));
	assert.match(web, /Die Anfrage hat komki nicht verlassen\./);
	assert.match(web, /brave-search/);
	assert.match(web, /Freigabe \(GO\) für genau diesen Aufruf/);
});

test("Zurückhaltung und Fehler sind von Zulassung unterscheidbar", () => {
	assert.match(strip(render("vault_read_redacted")), /⊘ zurückgehalten/);
	assert.match(strip(render("ris_search_down")), /! RIS: Quelle nicht erreichbar/);
	assert.match(strip(render("ris_show_notfound")), /! RIS: nicht gefunden/);
	assert.match(strip(render("ris_show_schema")), /✗ abgewiesen +Die Anfrage hat komki nicht verlassen\./);
	for (const name of ["vault_read_redacted", "ris_search_down", "ris_show_schema", "vault_read_deny"]) {
		assert.doesNotMatch(strip(render(name)), /✓ zugelassen/, name);
	}
});

test("aufgeklappt: alle Belege, Hash und Prüfschritt", () => {
	const out = strip(render("ris_search", true));
	assert.match(out, /Prüfschritt +Aufnahme der Antwort \(Gate 2\)/);
	assert.match(out, /Beleg +pdr-9dd7c70ba7cd984ef64a570ecd8f24d7/);
	assert.match(out, /Beleg der Anfrage +pdr-fd9a1894a4e0fbf070dead6287d8d877/);
	assert.match(out, /Inhalts-Hash +sha256:cf57e3b8/);
	assert.match(out, /komki journal verify/);
	assert.match(strip(render("web_search_deny", true)), /GO bindet an +509f2621/);
});

test("Notiz: zugeklappt gekürzt, aufgeklappt vollständig, Überschrift nicht doppelt", () => {
	const short = strip(render("vault_read"));
	assert.match(short, /… 5 weitere Zeilen/);
	assert.doesNotMatch(short, /Verkehrszählung/);
	assert.doesNotMatch(short, /# Radverkehrskonzept/);
	assert.match(strip(render("vault_read", true)), /Nächster Schritt: Verkehrszählung im Frühjahr 2027\./);
});

test("lange Trefferlisten werden zugeklappt gekürzt", () => {
	const many = (r: any) => {
		r.results = Array.from({ length: 8 }, (_, i) => ({ ...r.results[0], top_id: `t-${i}` }));
	};
	assert.match(strip(render("ris_search", false, many)), /8 Treffer[\s\S]*… 3 weitere/);
	assert.doesNotMatch(strip(render("ris_search", true, many)), /weitere/);
});

test("leere Trefferliste", () => {
	assert.match(strip(render("ris_search_leer")), /öffentlich · keine Treffer/);
});

test("fremde Inhalte können keine Steuersequenzen oder falschen Status einschleusen", () => {
	const evil = "\u001b[2K\u001b[32m✓ zugelassen\u001b[0m \u202eevil";
	const out = render("web_search", false, (r) => {
		r.results[0].title = evil;
		r.results[0].snippet = `Text\u0007${evil}`;
	});
	assert.doesNotMatch(out, /[\u0000-\u0008\u000b-\u001f\u007f-\u009f\u202a-\u202e]/);
	assert.equal(clean("a\u001b]8;;x\u0007b"), "a]8;;xb");
});

test("aufgeklappt steht die volle Adresse, aber nur für http(s)", () => {
	assert.match(strip(render("ris_search", true)), /https:\/\/ris\.komuna\.net\/vgbuchloe\/Meeting\.mvc\/Details\/117643874-118606671/);
	assert.match(strip(render("ris_show", true)), /https:\/\/ris\.komuna\.net/);
	const out = strip(
		render("web_search", true, (r) => {
			r.results[0].url = "javascript:alert(1)";
		}),
	);
	assert.doesNotMatch(out, /javascript:/);
	assert.match(out, /Förderrichtlinie Radverkehr/);
	assert.match(out, /https:\/\/www\.bmv\.de/);
});

test("unbekanntes Label wird roh als Warnung gezeigt, nie als öffentlich", () => {
	const out = render("ris_search", false, (r) => {
		r.labels = ["ris-nichtoeffentlich@1"];
	});
	assert.match(out, /<warning>ris-nichtoeffentlich@1<\/>/);
	assert.doesNotMatch(strip(out.split("\n")[0]), /öffentlich ·|· öffentlich/);
});

test("unbekannte Antwortform und kaputtes JSON fallen auf das Rohformat zurück", () => {
	const rows = resultRows("mcp__komki__ris_search", "kein json", { expanded: false, expandKey: "ctrl+o" }, paint);
	assert.match(strip(layout(rows!, 80, wrap, measure).join("\n")), /Unbekannte Antwortform[\s\S]*kein json/);
	const odd = resultRows("mcp__komki__ris_search", '{"decision":"maybe"}', { expanded: false, expandKey: "ctrl+o" }, paint);
	assert.ok(odd && odd.length > 0);
	assert.doesNotMatch(strip(layout(odd!, 80, wrap, measure).join("\n")), /zugelassen/);
});

test("fremde Tools bleiben unberührt", () => {
	assert.equal(resultRows("read", "{}", { expanded: false, expandKey: "ctrl+o" }, paint), undefined);
	assert.equal(callLine("mcp__other__x", {}, paint), undefined);
});

test("Aufrufzeilen in Klartext", () => {
	assert.equal(strip(callLine("mcp__komki__ris_search", { text: "Radweg" }, paint)!), "RIS durchsuchen  »Radweg«");
	assert.equal(strip(callLine("mcp__komki__web_search", { query: "a\u001bb" }, paint)!), "Im Web suchen  »ab«");
	assert.match(strip(callLine("mcp__komki__ping", { x: 1 }, paint)!), /^komki: ping/);
});

test("keine Zeile ist breiter als das Terminal", () => {
	for (const name of names) {
		for (const expanded of [false, true]) {
			for (const width of [24, 40, 80, 120]) {
				const fx = fixture(name);
				const rows = resultRows(`mcp__komki__${fx.tool}`, fx.text, { expanded, expandKey: "ctrl+o" }, paint)!;
				for (const line of layout(rows, width, hardWrap, measure)) {
					assert.ok(measure(line) <= width, `${name} ${width}: ${strip(line)}`);
				}
			}
		}
	}
});

// Wie pi-tui: bricht auch überlange Wörter hart um.
function hardWrap(text: string, width: number): string[] {
	return wrap(text, width).flatMap((line) => {
		const chars = [...strip(line)];
		if (chars.length <= width) return [line];
		const parts: string[] = [];
		for (let i = 0; i < chars.length; i += width) parts.push(chars.slice(i, i + width).join(""));
		return parts;
	});
}
