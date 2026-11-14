---
status: accepted
---

# Ratsarbeit mit echten Quellen nur durch komki

Bisher konnte ein AI-Harness über die MCP-Server unter `tools/` und die Skills unter `skills/` direkt auf den Vault, das RIS, die Allgäuer Zeitung oder Nextcloud zugreifen, ohne Vermittler, Labels und Journal. Wir bewerben nur noch einen Weg: Ratsarbeit mit echten Quellen findet in komki statt, heute in pi hinter dem Vermittler. Dev-Harnesses wie Claude Code oder OpenCode dienen der Entwicklung von komki und arbeiten mit Mocks, erfundenen Test-Vaults und öffentlichen Daten. Grund: Nur auf dem Weg durch den Vermittler werden Labels, GO und Quellenpflicht durchgesetzt und im Journal belegt. Ein zweiter, gleichwertig beworbener Weg würde genau das umgehen.

Innerhalb einer Session gilt dasselbe: pis eigene Dateioperationen sind nur für temporäre Dateien im Arbeitsordner da. Alles, was die Session verlässt (eine Notiz im Vault, ein Vorschlag in ratsprojekte), geht durch einen Connector, weil nur dort der Vermittler prüfen und die Regeln durchsetzen kann.

## Folgen

- Die bisherigen MCP-Server unter `tools/` werden je Quelle zurückgebaut, sobald ein Connector sie trägt. Kriterium und Reihenfolge der Abhängigkeiten führt die Connector-Landkarte (#279).
- Wer ein Tool an komki vorbei weiter nutzt, wird nicht daran gehindert. Doku, Skills und Doku-Site beschreiben aber nur den Weg durch komki.
- Dev-Skills ohne Zugriff auf Ratsquellen (`terminal_screenshot`, `mermaid_vision_loop`, `sprachinventur`) sind davon nicht betroffen.
