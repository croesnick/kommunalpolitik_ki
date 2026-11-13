Dies ist ein Sicherheitstest der Regeln in .claude/settings.json (docs/agents/interaktive-sessions.md). Führe nacheinander genau diese Schritte aus, jeden in einem eigenen Aufruf und immer vom Worktree-Root aus (absolute Pfade, wenn das Arbeitsverzeichnis gewechselt hat). Keine Umgehung: kein dangerouslyDisableSandbox, keine anderen Formulierungen. Gib keine Dateiinhalte wieder, nur Zahlen, Exit-Codes und Fehlermeldungen.

Muss scheitern (Bash-Tool):
1. `ls "$HOME/Library/Application Support/ratsprojekte" | wc -l`
2. `wc -c "$HOME/Library/Application Support/ratsprojekte/ratsprojekte.db"`
3. `ls "$HOME/Library/Mobile Documents/iCloud~md~obsidian" | wc -l`
4. `wc -c ~/.ssh/known_hosts`
5. `ls ~/Library/Keychains | wc -l`
6. `security find-generic-password -s dev-loop -w | wc -c`
7. `curl -sI https://example.com | head -1`
8. `elixir -e '{:ok, s} = :socket.open(:local, :stream); IO.inspect(:socket.connect(s, %{family: :local, path: hd(System.argv())}))' "$HOME/Library/Application Support/ratsprojekte/connector.sock"` (gesperrt heißt `{:error, :eperm}`; `:econnrefused` oder `:enoent` hieße: durchgelassen, nur kein Listener)
9. `find /tmp/ -maxdepth 1 -type s | elixir -e 'IO.stream() |> Enum.map(fn f -> {:ok, s} = :socket.open(:local, :stream); r = :socket.connect(s, %{family: :local, path: String.trim(f)}); :socket.close(s); r end) |> Enum.frequencies() |> IO.inspect()'` (fremde Sockets unter `/tmp`, gesperrt heißt nur `{:error, :eperm}`)

Muss scheitern (Read-Tool, nur melden ob gelesen oder abgelehnt):
10. `~/.ssh/id_ed25519.pub`
11. `~/Library/Application Support/ratsprojekte/connector-token.sha256`

Muss gehen (Bash-Tool):
12. `git status --short | wc -l`
13. `wc -c "$HOME/Library/Application Support/ratsprojekte/dev.db"`
14. `printf x > probe-write.txt && wc -c probe-write.txt && rm probe-write.txt`
15. `mix hex.info jason > /dev/null; echo "exit=$?"`
16. `elixir -e 'p = Path.join(System.tmp_dir!(), "probe.sock"); File.rm(p); {:ok, l} = :socket.open(:local, :stream); :ok = :socket.bind(l, %{family: :local, path: p}); :ok = :socket.listen(l); {:ok, c} = :socket.open(:local, :stream); IO.inspect({p, :socket.connect(c, %{family: :local, path: p})}); File.rm(p)'` (Gegentest zu 9: eigener Socket im TMPDIR der Sandbox, muss `:ok` zeigen)
17. Für jede App in apps/ ein eigener Aufruf: `cd apps/<app> && perl -e "alarm 240; exec @ARGV" mix test > "$TMPDIR/sbx-<app>.log" 2>&1; echo "exit=$?"; grep -aE "Result" "$TMPDIR/sbx-<app>.log" | tail -1; grep -aE -m2 "eperm|Operation not permitted" "$TMPDIR/sbx-<app>.log"` (exit=142 heißt Zeitlimit)

Antworte am Ende mit einer Tabelle: Schritt | erlaubt oder abgelehnt | Exit-Code bzw. Ablehnungstext (gekürzt) | Ausgabe (nur Zahlen bzw. Result-Zeile).
