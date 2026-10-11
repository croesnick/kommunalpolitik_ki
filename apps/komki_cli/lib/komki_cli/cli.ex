defmodule KomkiCli.CLI do
  @moduledoc """
  Escript-Einstiegspunkt `komki` (Ticket #74): Launcher fuer die gepinnte
  Modellkombination aus dem Ticket-#70-Beschluss.

  Befehle (Vertrag):

      komki version
      komki init  [--gguf-from PATH] [--port N] [--ctx N] [--force]
      komki doctor
      komki up    [--ctx N]
      komki down
      komki status
      komki run "PROMPT" [--mode text|json] [--scratch PATH]
      komki session [--continue] [--detach]
      komki session-chain [--continue]   # intern: Pane-Einstieg der Session

  Exit-Codes (Vertrag):

      | Code | Bedeutung |
      |------|-----------|
      | `0`  | Erfolg |
      | `2`  | Usage-/Konfigurationsfehler (unbekannter Befehl, fehlende/unbekannte Optionen, fehlende config.json, GGUF-SHA-Abweichung, nicht laufender llama-server bei `run`/`session`) |
      | `3`  | Doctor-/Boot-Gate-Fail (Profil-Drift oder sandbox-exec-Boot-Pleite; Weiterbetrieb verweigert) |
      | `4`  | Runtime-Fail (llama-server oder pi beendet nicht erfolgreich) |

  **CLI-Surface-Isolation:** argv-Parsing/Help/Validierung (optimus) UND alle
  menschlichen Ausgaben (Farben via IO.ANSI, Verdict-Zeilen, Spinner/Statuszeile)
  liegen ausschliesslich HIER, hinter kleinen Funktionen — ein weiteres
  Library-Retrofit beruehrt nur diese Schicht, nie Profile/Llama/Pi/Config.
  `KomkiCli.Steps` liefert strukturierte Resultate, die unten gerendert werden.
  """

  @version "0.1.0"

  @type outcome :: {String.t(), non_neg_integer()}

  # Evidenz fuer die Grenz-Gates: Probebericht im Beschluss zu Ticket #70
  # (Issue-Kommentar) und der Seatbelt-Survey im Repo.
  @probe_doc_hint "Nachweise: Ticket #70 (Probebericht im Beschluss), " <>
                    "docs/research/2026-10-05-seatbelt-survey.md"

  # ===========================================================================
  # Einstieg (komki_policy-Muster: hard main, testbares run/1 ohne halt)
  # ===========================================================================

  @doc false
  @spec main([binary()]) :: no_return()
  def main(argv) do
    {output, code} = run(argv)
    IO.write(output)
    halt(code)
  end

  @doc false
  @dialyzer {:nowarn_function, halt: 1}
  def halt(code), do: System.halt(code)

  @doc "Testbare Kernfunktion: `{output, exit_code}` ohne System.halt."
  @spec run(term()) :: outcome()
  def run(argv) when is_list(argv) do
    dispatch(argv)
  rescue
    exception -> {"internal error: " <> Exception.format(:error, exception) <> "\n", 2}
  catch
    kind, thrown ->
      {"internal error " <> Kernel.inspect(kind) <> ": " <> Kernel.inspect(thrown) <> "\n", 2}
  end

  def run(_), do: {"unexpected non-list argv; run \"komki --help\"\n", 2}

  # ===========================================================================
  # Optimus: parsing/help/validierung (alles CLI-Surface)
  # ===========================================================================

  defp cli do
    Optimus.new!(
      name: "komki",
      description:
        "Launcher fuer die gepinnte Modellkombination (Ticket #74; Entscheidungen: Ticket #70)",
      version: @version,
      author: "Carsten Roesnick-Neugebauer",
      subcommands: [
        version: [name: "version", description: "Versiondrucker"],
        init: [
          name: "init",
          description: "KomKI-CLI-Instanz anlegen (config + Profil + pi-home + GGUF-SHA-Gate)",
          options: [
            gguf_from: [
              value_name: "PATH",
              long: "gguf-from",
              help:
                "GGUF-Quelle (Kopie; default: das Staging-Artefakt unter ~/.local/share/komki/models-staging/)"
            ],
            port: [
              value_name: "N",
              long: "port",
              parser: :integer,
              help: "llama-server-Port (default 49524, gepinnt)"
            ],
            ctx: [
              value_name: "N",
              long: "ctx",
              parser: :integer,
              help: "llama-Kontextgroesse (default 8192)"
            ]
          ],
          flags: [
            force: [long: "force", help: "bestehende config.json ueberschreiben"]
          ]
        ],
        doctor: [name: "doctor", description: "alle Checks; Boot-Gate ist Pflicht vor jedem Lauf"],
        up: [
          name: "up",
          description: "llama-server starten (doctor-quick zuerst; Health-Poll nach)",
          options: [
            ctx: [
              value_name: "N",
              long: "ctx",
              parser: :integer,
              help: "Kontextgroesse Override fuer diesen Start"
            ]
          ]
        ],
        down: [
          name: "down",
          description:
            "llama-server stoppen (Aufraeumweg ohne Boot-Gate; nur eigener pidfile-Prozess)"
        ],
        status: [name: "status", description: "Zustandsabfrage (base, gguf, port, llama)"],
        run: [
          name: "run",
          description: "pi-Einmallauf unter Profil (+ full doctor zuerst)",
          args: [
            prompt: [
              value_name: "PROMPT",
              required: true,
              help: "Prompt (quoted; nicht mit -- beginnend)"
            ]
          ],
          options: [
            mode: [
              value_name: "TEXT|JSON",
              long: "mode",
              help: "pi-Ausgabe-Modus (default text)"
            ],
            scratch: [
              value_name: "PATH",
              long: "scratch",
              help: "Scratch-Verzeichnis (default base/runs/<UTC-Stamp>)"
            ]
          ]
        ],
        session: [
          name: "session",
          description: "interaktive pi-Session in tmux (full doctor zuerst)",
          flags: [
            continue: [long: "continue", help: "vorherige Session fortsetzen (pi --continue)"],
            detach: [
              long: "detach",
              help: "Session ohne attach starten; spaeter 'tmux attach -t komki'"
            ]
          ]
        ],
        session_chain: [
          name: "session-chain",
          description: "intern: pi-Kette als Port-Kind (Pane-Einstieg von 'session')",
          flags: [
            continue: [long: "continue", help: "vorherige Session fortsetzen (pi --continue)"]
          ]
        ]
      ]
    )
  end

  defp dispatch(argv) do
    case Optimus.parse(cli(), argv) do
      {:ok, [command], result} -> dispatch_command(command, result)
      {:ok, %Optimus.ParseResult{}} -> {"no command given; run \"komki --help\"\n", 2}
      {:error, errors} -> {error_line(errors) <> "\n", 2}
      {:error, _path, errors} -> {error_line(errors) <> "\n", 2}
      :help -> help_text([])
      {:help, path} -> help_text(path)
      :version -> {"komki " <> @version <> "\n", 0}
    end
  end

  @doc false
  @spec help_text(Optimus.subcommand_path()) :: outcome()
  def help_text(subcommand_path) do
    lines = Optimus.Help.help(cli(), subcommand_path, 80)
    {Enum.join(lines, "\n") <> "\n", 0}
  end

  defp error_line(errors) do
    "Error: " <>
      Enum.join(Optimus.Errors.format_errors(errors), ", ") <>
      "; run \"komki --help\" fuer usage"
  end

  # ===========================================================================
  # Befehle → Steps-Struktur kann gerendert werden
  # ===========================================================================

  defp dispatch_command(:version, _result), do: {"komki " <> @version <> "\n", 0}

  defp dispatch_command(:init, result),
    do: render(KomkiCli.Steps.init(optimus_opts(result)))

  defp dispatch_command(:doctor, _result), do: render(KomkiCli.Steps.doctor())

  defp dispatch_command(:up, result),
    do: render(up_with_progress(optimus_opts(result)))

  defp dispatch_command(:down, _result), do: render(KomkiCli.Steps.down())
  defp dispatch_command(:status, _result), do: render(KomkiCli.Steps.status())

  defp dispatch_command(:session, result),
    do: render(KomkiCli.Steps.session(optimus_opts(result)))

  defp dispatch_command(:session_chain, result),
    do: render(KomkiCli.Steps.session_chain(optimus_opts(result)))

  defp dispatch_command(:run, result) do
    opts =
      result.args
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
      |> Map.merge(optimus_opts(result))

    if Map.get(opts, "prompt") in ["--help", "-h"] do
      # Hilfe-Wunsch statt Prompt: ohne Guard fiele --help an pi durch und
      # stoesse einen echten Lauf an (Orchestrator-Fund im Smoke 5d).
      help_text([:run])
    else
      render(KomkiCli.Steps.run(opts))
    end
  end

  defp optimus_opts(result) do
    pairs = map_options(result.options) ++ map_flags(result.flags)
    set_pairs = Enum.reject(pairs, fn {_key, value} -> is_nil(value) end)
    Map.new(set_pairs)
  end

  defp map_options(%{} = options) do
    # Key-Mapping: Atom -> String, Underscores -> Dashes (gguf_from -> gguf-from)
    Enum.map(options, fn {key, value} ->
      {key |> Atom.to_string() |> String.replace("_", "-"), value}
    end)
  end

  defp map_flags(%{} = flags) do
    # Nur gesetzte Flags weiterreichen ("force"): Steps prueft Map.has_key?
    # (un kube "false" waere ein cryptischer Schreibzugriff auf die config).
    for {key, present?} <- Enum.to_list(flags),
        present? do
      {key |> Atom.to_string() |> String.replace("_", "-"), "true"}
    end
  end

  # ===========================================================================
  # Spinner/Statuszeile: nur hier (keine Library); waehrend des blockierenden
  # `up`-Pfads (doctor-quick + llama Health-Poll) schreibt ein Nebenprozess
  # Status-Frames, danach raeumt :stop die Zeile ueber \r-Overwrite frei.
  # ===========================================================================

  defp up_with_progress(opts) do
    # Eigenes Spinner-Miniwerkzeug (keine Library): schreibt Statusframes, während
    # der blockierende Lauf (doctor-quick + llama Health-Poll) läuft.
    spid = spawn(fn -> spin(0, "warte auf llama-server (doctor-quick + health) ...") end)

    result =
      try do
        KomkiCli.Steps.up(opts)
      after
        send(spid, :stop)
        Process.sleep(150)
      end

    result
  end

  defp spin(i, msg) do
    receive do
      :stop ->
        # Statuszeile abräumen (Leerzeilen-Overwrite ohne Rückstände).
        IO.write("\r" <> String.duplicate(" ", 80) <> "\r")
    after
      120 ->
        frame = Enum.at(["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"], rem(i, 10))

        IO.write("\r" <> IO.ANSI.faint() <> frame <> " " <> msg <> IO.ANSI.reset())

        spin(i + 1, msg)
    end
  end

  # ===========================================================================
  # Render-Flaeche (alle menschlichen Ausgaben; ANSI nur hier)
  # ===========================================================================

  @spec render(KomkiCli.Steps.result()) :: outcome()
  defp render({:inited, cfg, gguf_lines}), do: render_init(cfg, gguf_lines)
  defp render({:checks, checks, summary}), do: render_doctor(checks, summary)

  defp render({:llama_up, pid}),
    do: {green() <> "llama up: pid " <> to_string(pid) <> reset() <> " (health 200)\n", 0}

  defp render({:llama_down}),
    do: {green() <> "llama down: pidfile entfernt, pid abwesend" <> reset() <> "\n", 0}

  defp render({:llama_down, :already}),
    do: {green() <> "llama: bereits gestoppt (kein pidfile)" <> reset() <> "\n", 0}

  defp render({:llama_down, :stale, reason}),
    do: {green() <> "llama down: " <> reason <> reset() <> "\n", 0}

  defp render({:status, cfg, llama_state}),
    do:
      {Enum.join(
         [
           "base:   " <> cfg.base_dir,
           "gguf:   " <> cfg.gguf_path,
           "port:   " <> to_string(cfg.port),
           "llama:  " <> render_llama_state(llama_state)
         ],
         "\n"
       ) <> "\n", 0}

  defp render({:run_ok, scratch, out}),
    do: {"scratch: " <> scratch <> "\n" <> String.trim_trailing(out) <> "\n", 0}

  defp render({:run_error, scratch, out, pi_code}),
    do: {"scratch: " <> scratch <> "\npi exit " <> to_string(pi_code) <> ":\n" <> out <> "\n", 4}

  defp render({:session, message}),
    do: {green() <> String.trim_trailing(message) <> reset() <> "\n", 0}

  # Interner Pane-Lauf: Exit-Code von pi geht 1:1 an tmux durch.
  defp render({:chain_exit, 0}), do: {"", 0}

  defp render({:chain_exit, code}),
    do: {"pi exit " <> to_string(code) <> "\n", code}

  defp render({:error, reason, code}),
    do: {red() <> String.trim_trailing(reason) <> reset() <> "\n", code}

  defp green, do: if(IO.ANSI.enabled?(), do: IO.ANSI.green(), else: "")
  defp red, do: if(IO.ANSI.enabled?(), do: IO.ANSI.red(), else: "")
  defp reset, do: if(IO.ANSI.enabled?(), do: IO.ANSI.reset(), else: "")

  defp render_init(cfg, gguf_lines) do
    lines =
      [
        "init ok",
        "base-dir:   " <> cfg.base_dir,
        "config:     " <> KomkiCli.Config.config_path(cfg.base_dir),
        "profile:    " <> cfg.profile_path,
        "pi-home:    " <> cfg.pi_home,
        "port:       " <> to_string(cfg.port),
        "ctx:        " <> to_string(cfg.ctx)
      ] ++ gguf_lines

    {Enum.join(lines, "\n") <> "\n", 0}
  end

  # Verdict-Zeilen: die einzige Farbstelle; ganze Zeilen gesetzt (substring-sicher fuer Tests).
  defp render_doctor(checks, summary) do
    lines =
      Enum.map(checks, fn %{name: name, ok: ok, reason: reason} ->
        head = if ok, do: green() <> "ok" <> reset(), else: red() <> "FAIL" <> reset()
        tail = if reason in [nil, ""], do: "", else: " (" <> reason <> ")"
        head <> ": " <> name <> tail
      end)

    summary_line =
      cond do
        summary == :ok ->
          green() <> "doctor: ok" <> reset()

        summary == :boot_gate_fail ->
          red() <>
            "doctor: FAIL (Boot-Gate rot — Weiterbetrieb verweigert; " <>
            @probe_doc_hint <> ")" <> reset()

        true ->
          red() <> "doctor: FAIL" <> reset()
      end

    {Enum.join(lines ++ [summary_line], "\n") <> "\n", if(summary == :ok, do: 0, else: 3)}
  end

  defp render_llama_state({:running, pid}), do: "running (pid " <> to_string(pid) <> ")"

  defp render_llama_state({:health_only, :no_pidfile}),
    do: "port antwortet /health aber kein pidfile (fremder Prozess?)"

  defp render_llama_state(:stopped), do: "stopped"
  defp render_llama_state({:error, reason}), do: "error: " <> reason
end
