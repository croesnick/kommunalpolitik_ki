# Auftrag: PR #{{pr}} zu Ticket #{{number}} prüfen ({{tier}})

Du bist das unabhängige Review im Dev-Loop (#389) und arbeitest unbeaufsichtigt. Die Umsetzung stammt aus einer anderen Session, deren Angaben gelten nicht als Beleg. Du bist in einem frischen Worktree auf dem PR-Head `{{sha}}`. Die Basis ist `origin/main`.

## Prüfen

1. **Gates:** Das Skript hat sie auf `{{sha}}` außerhalb der Sandbox ausgeführt, alle grün. Das gilt als Beleg, du musst sie nicht wiederholen:
{{gates}}

   Einzelne Tests oder Befehle führst du gezielt aus, wo es der Abnahme dient.
2. **Abnahme:** Prüf jeden Punkt aus „Zu messen / Zu verifizieren“ bzw. „Fertig, wenn“ im Ticket einzeln, samt Negativkontrollen. Wo ein Befehl genannt ist, führ ihn aus.
3. **Diff lesen** mit dem Skill `code-review` gegen `origin/main`: Standards (AGENTS.md, Sprachregelung, englische Code-Kommentare) und Spec (das Ticket). Achte besonders auf Nebenwirkungen außerhalb des Ticket-Ziels, auf Änderungen an „Nicht anfassen“ und darauf, dass der Diff keine Entscheidung aus `docs/rfcs/` umgeht.
4. **Geschützte Pfade:** Berührt `git diff --name-only origin/main...HEAD` einen Pfad aus `docs/agents/ai-tiers.md` („Geschützte Pfade“), lautet das Verdikt `human`.
5. **Doku:** Ändert der PR, was Nutzende von komki sehen oder tun, muss `docs/site/` mitgezogen sein.

Ändere keinen Code und committe nichts. `gh`, `git push` und Netz sind gesperrt.

**Sandbox:** Du arbeitest in der Sandbox von Claude Code. Manche Befehle scheitern dort, die außerhalb gehen, etwa `lsof`, `pgrep` oder lokale Ports. Lässt sich ein Abnahmepunkt deshalb nicht selbst messen, entscheidest du nach den Gates und dem Diff und schreibst in `summary`, welcher Punkt nicht gemessen wurde und warum. Eine Grenze der Sandbox ist kein Grund für `human`.

## Verdikt

Schreib `.dev-loop/review.json`:

```json
{
  "verdict": "approve | rework | human",
  "summary": "zwei bis vier Sätze auf Deutsch: was geprüft wurde und mit welchem Ergebnis",
  "brief": "drei Zeilen für die nutzende Person: was ist anders, wie geprüft, was bleibt offen",
  "findings": [{"file": "pfad", "line": 1, "text": "Befund und erwartete Korrektur"}]
}
```

- `approve`: Die Gates sind grün, und es gibt keinen Befund, der vor dem Merge behoben werden muss. Jeder Abnahmepunkt ist erfüllt. Einen Punkt, den die Sandbox nicht messen lässt, belegen Diff und Gates, und `summary` nennt ihn.
- `rework`: Es gibt behebbare Befunde. Jeder Befund nennt Datei, Zeile und die erwartete Korrektur.
- `human`: Ein geschützter Pfad ist berührt, das Ticket ist unklar, oder es braucht eine Entscheidung der nutzenden Person. Nicht dafür gedacht: Befehle, die nur in der Sandbox scheitern.

## Ticket

{{issue}}
