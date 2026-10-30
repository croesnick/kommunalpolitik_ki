# Skill-Evals: Benchmark gegen das Zielmodell (Ticket #292)

Misst die Skills des Repos gegen das Modell, das sie im Produktivbetrieb
ausführt: Gemma 4 26B im llama-server der komki-Instanz, angesprochen über pi
wie in `komki run` — nicht gegen Claude. Die Konvention (Ort, Fallformat,
Bewerter, Pflichtfelder der `BENCHMARK.md`) steht in
[`docs/agents/skill-evals.md`](../../../../../docs/agents/skill-evals.md); die
Suiten gehören zum jeweiligen Skill unter `skills/<name>/evals/`.

```bash
komki up   # llama-server der komki-Instanz (Live-Instanz, nicht vom Runner gestartet)

# Ein Skill messen, Bericht nach skills/<name>/BENCHMARK.md schreiben:
node apps/komki_cli/experiments/pi_packages/skill-evals/run.mjs \
  --skill sitzungsvorbereitung --baseline 9c50fa1

# Varianten:
#   --cases a,b        nur bestimmte Fälle
#   --laeufe 5         Läufe je Arm übersteuern (Default steht je Fall, Minimum 5)
#   --baseline <ref>   Git-Stand der „vorigen Fassung“ (Default origin/main)
#   --notizen <datei>  Stichproben-Notizen, landen im Bericht
#   --trockenlauf      Suite laden, Regexe prüfen, Plan ausgeben — ohne Server
#   --root <verz>      Laufverzeichnis (Default $TMPDIR/komki-pi-experiments/runs/…)
```

Kosten: 30–80 s je Lauf (Skill im Kontext ≈ 8–9 k Prompt-Tokens; die alte
858-Zeilen-Fassung ≈ 25 k). Drei Arme × 5 Läufe ≈ 15 Minuten je
verhalten-Fall. Messungen im Hintergrund fahren und vorher `komki status`
prüfen — der Server ist die geteilte Live-Instanz; der Runner gleicht jedes
Logfenster gegen die eigene Request-Zählung ab (Fremdlast) und nennt
verzeichnete Läufe im Bericht.

Der Runner ist bewusst Node/mjs: Er baut auf dem Vorlauf aus #158 auf
(`../lib/provider.mjs`, `../lib/runner.mjs`, `../smoke/measure.mjs`,
`factTokens`/`classifyNumbers` aus `../smoke/fixtures.mjs`) und neuert die
Zahl-Bewerter nicht nach. Eine Portierung nach Elixir wäre eine Neuvermessung
des Messwegs, kein Refactor.
