# Auftrag: Ticket #{{number}} umsetzen ({{tier}})

Du arbeitest unbeaufsichtigt im Dev-Loop (#389). Niemand beantwortet Rückfragen. Du bist in einem eigenen Worktree auf dem Branch `{{branch}}`, der von `origin/main` abzweigt.

## Vertrag

Das Ticket unten ist der Vertrag. Lies vor dem ersten Edit:

- `docs/agents/lane-protocol.md`: Ticket als Vertrag lesen, Gates, eskalieren statt umdeuten
- `docs/agents/ai-tiers.md`: geschützte Pfade und Zielbild
- `AGENTS.md`: Architektur-Prinzipien, Sprachregelung, Doku-Site-Pflicht

Den Weg findest du selbst. Nimm die kleinste Lösung, die „Fertig, wenn“ bzw. „Zu messen“ erfüllt. Was das Ticket als „Bewusst offen“ oder „Nicht anfassen“ nennt, bleibt unberührt.

## Arbeitsweise

- Arbeite testgetrieben mit dem Skill `tdd`, wo es eine sinnvolle Seam gibt.
- Trägt das Ticket das Label `bug`, reproduziere zuerst mit dem Skill `diagnosing-bugs`, ergänze einen Regressionstest und fixe dann.
- Committe auf den aktuellen Branch und nenne `#{{number}}` in jeder Commit-Message.
- Du hast keinen Zugriff auf GitHub. `gh`, `git push` und Netz sind gesperrt. Was du über das Ticket wissen musst, steht unten.
- Arbeite nur in diesem Worktree.

## Gates

Vor dem Abschluss müssen diese Befehle im Worktree grün sein. Das Skript prüft sie danach selbst noch einmal.

```bash
mix format --check-formatted
mix workspace.run -t compile -- --warnings-as-errors
mix workspace.run -t credo --exclude ratsprojekte -- --strict
mix workspace.run -t test --affected --base origin/main
```

## Eskalieren

Lege `.dev-loop/blocked.md` an und höre auf, ohne weiterzubauen, wenn einer dieser Fälle eintritt:

- Die Umsetzung berührt einen geschützten Pfad aus `docs/agents/ai-tiers.md`.
- Dein Weg widerspricht einer Entscheidung aus `docs/rfcs/`.
- Das Ticket widerspricht sich oder dem Code.
- Eine Entscheidung gehört der nutzenden Person (GO-Prinzip).

Schreib in die Datei, was du gefunden hast, und deinen Vorschlag, auf Deutsch und knapp.

## Ergebnis

Schreib zum Abschluss zwei Dateien (sie sind gitignored, committe sie nicht):

1. `.dev-loop/pr.md`: In der ersten Zeile steht der PR-Titel auf Deutsch. Darunter folgt der PR-Text mit den Abschnitten `Gebaut`, `Bewusst offen` und `Verifiziert` (welche Gates und Befehle du ausgeführt hast) und einer Zeile `Closes #{{number}}`. Deckt der PR das Ticket bewusst nur teilweise ab, schreib stattdessen `Refs #{{number}}` und einen Satz, was fehlt.
2. `.dev-loop/brief.md`: drei Zeilen für die nutzende Person, die entscheiden soll. Was ist anders, wie wurde es geprüft, was bleibt offen?

## Hinweise aus der vorigen Runde

{{findings}}

## Ticket

{{issue}}
