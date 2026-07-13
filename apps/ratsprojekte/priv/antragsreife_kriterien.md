# Antragsreife-Kriterien

Dieses Dokument definiert die Kriterien, nach denen das MCP-Tool
`check_antragsreife` ein Projekt der Stadtratsarbeit bewertet. Es ist
versionisiert und für den Stadtrat lesbar formuliert.

Stand: 2025-07-13

## Überblick

Drei Klassen von Kriterien, scharf getrennt:

1. **Hard Gates** — strukturelle Muss-Kriterien. Werden vom Tool deterministisch
   in Elixir geprüft. Ein `fail` bei einem Hard Gate blockiert die Antragsreife.
2. **Soft Gates** — inhaltliche Kriterien, die das Tool als `pending` markiert.
   Der AI-Harness bewertet diese per LLM anhand der Projektdaten.
3. **Politische Kriterien** — vom Stadtrat persönlich zu prüfen. Das Tool
   markiert diese als `unchecked` und gibt nur Hinweise. Die KI bewertet diese
   nicht (GO-Prinzip: politische Verantwortung bleibt beim Menschen).

## 1. Hard Gates (deterministisch, im Tool geprüft)

| Kriterium | Prüfung |
|---|---|
| `quellen_vorhanden` | Mindestens eine Quelle mit URL und Abrufdatum vorhanden (Projekt-Quellen + alle Strang-Quellen gezählt). |
| `adressat_gesetzt` | Feld `projekt.adressat` gesetzt und nicht leer (z.B. "Stadtrat", "Bürgermeister", "Vergabeausschuss"). |
| `beschlussvorschlag_konkret` | Feld `projekt.beschlussvorschlag` gesetzt, nicht leer, länger als 20 Zeichen. |
| `realisierungsstrang_vorhanden` | Mindestens ein Realisierungsstrang vorhanden. |
| `vorbedingungen_erfuellt` | Status `pass`, wenn alle Stränge alle Vorbedingungen erfüllt haben; `warn`, wenn Vorbedingungen offen sind. |

Status-Werte: `pass` | `fail` | `warn`.

## 2. Soft Gates (LLM-bewertet durch den AI-Harness)

Das Tool liefert Hinweise, der AI-Harness bewertet per LLM anhand der
Projektdaten (Beschlussvorschlag, Beschreibung, Stränge, Vorbedingungen).

| Kriterium | Hinweis |
|---|---|
| `finanzierung_angesprochen` | Prüfe, ob Beschlussvorschlag oder Beschreibung Finanzierung erwähnt. |
| `rechtliche_grundlagen_genannt` | Prüfe `strang.rechtliche_grundlage` und `vorbedingung.rechtliche_grundlage`. |
| `fristen_gesetzt` | Prüfe `schritt.frist` auf Vorhandensein und Realismus. |

Status-Werte: `pending` (vom Tool gesetzt, bis der AI-Harness bewertet).

## 3. Politische Kriterien (vom Stadtrat zu prüfen)

Das Tool markiert diese als `unchecked`. Die KI bewertet diese nicht —
politische Verantwortung bleibt beim Stadtrat (GO-Prinzip).

| Kriterium | Hinweis |
|---|---|
| `tonalitaet_sachlich` | Ist der Beschlussvorschlag sachlich formuliert? |
| `konsensfaehigkeit` | Ist der Antrag mehrheitsfähig? |
| `widerspruch_fraktionsposition` | Widerspricht der Antrag der Fraktionsposition? |

Status-Werte: `unchecked` (vom Tool gesetzt, bis der Stadtrat bewertet).

## Empfehlung-Logik

Das Tool leitet aus den Hard Gates eine Empfehlung ab:

- Alle Hard Gates `pass` → `empfehlung: "antragsreif"`
- Mindestens ein Hard Gate `fail` → `empfehlung: "nicht_antragsreif"`
- Alle Hard Gates `pass`, aber Vorbedingungen offen (`warn`) → `empfehlung: "antragsreif_mit_vorbehalten"`

Soft Gates und Politische Kriterien gehen nicht in die Empfehlung ein —
sie sind bewertungsfähig, nicht entscheidungsblockierend.
