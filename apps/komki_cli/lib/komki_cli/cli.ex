defmodule KomkiCli.CLI do
  @moduledoc """
  CLI-Einstiegspunkt `komki` (Ticket #74): Launcher fuer die gepinnte
  Modellkombination aus dem Ticket-#70-Beschluss. Dual-Betrieb (Ticket #75):
  als Escript ruft der Starter `main/1` direkt auf; als Burrito-Release
  startet `KomkiCli.Application.start/2` dieselbe Funktion mit
  `KomkiCli.Runtime.argv/0`.

  Befehle (Vertrag):

      komki version
      komki setup [--demo] [--vault-dir PATH] [--gguf-from PATH] [--port N]
      komki secret set NAME | komki secret list
      komki journal verify
      komki init  [--gguf-from PATH] [--port N] [--ctx N]
                  [--vault-dir PATH] [--ris-base-url URL] [--ris-mock-port N] [--force]
      komki doctor
      komki up    [--ctx N]
      komki down
      komki status
      komki go
      komki run "PROMPT" [--mode text|json] [--scratch PATH] [--timeout SEKUNDEN] [--capture-denials]
      komki session [--continue] [--detach]
      komki session-chain [--continue]   # intern: Pane-Einstieg der Session
      komki label import FILE [--db PATH]
      komki label quarantine OBJ@VER [--content-ref PATH] [--origin TEXT]
                       --decided-by ID --basis TEXT [--db PATH]
      komki label classify OBJ@VER [--label BINDUNG ...] --decided-by ID
                      --basis TEXT [--db PATH]
      komki label list [--db PATH]
      komki label show binding BINDUNGS-ID [--db PATH]
      komki label show object OBJ@VER [--db PATH]
      komki label export [--out PATH] [--db PATH]

  Exit-Codes (Vertrag):

      | Code | Bedeutung |
      |------|-----------|
      | `0`  | Erfolg |
      | `2`  | Usage-/Konfigurationsfehler (unbekannter Befehl, fehlende/unbekannte Optionen, fehlende config.json, GGUF-SHA-Abweichung, nicht laufender llama-server bei `run`/`session`; `label`: Registrierungs-, DB- und Store-Fehler — Ticket #91) |
      | `3`  | Doctor-/Boot-Gate-Fail (Profil-Drift oder sandbox-exec-Boot-Pleite; Weiterbetrieb verweigert) |
      | `4`  | Runtime-Fail (llama-server, komki-mediator oder pi beendet nicht erfolgreich; mit `--capture-denials` auch fehlgeschlagene Denial-Capture oder Berichtspersistenz) |

  Die `label`-Befehle (Ticket #91, SQLite-Registry des RFC-0003-Modells)
  kennen nur Erfolg (0) und Eingabefehler (2) — sie sind rein lokal und
  ohne Boot-Gate.

  **CLI-Surface-Isolation:** argv-Parsing/Help/Validierung (optimus) UND alle
  menschlichen Ausgaben (Farben via IO.ANSI, Verdict-Zeilen, Spinner/Statuszeile)
  liegen ausschliesslich HIER, hinter kleinen Funktionen — ein weiteres
  Library-Retrofit beruehrt nur diese Schicht, nie Profile/Llama/Pi/Config.
  `KomkiCli.Steps` liefert strukturierte Resultate, die unten gerendert werden.
  """

  @version "0.1.0"

  @type outcome :: {String.t(), non_neg_integer()}

  # Beleg fuer die Grenz-Gates: Probebericht im Beschluss zu Ticket #70
  # (Issue-Kommentar) und der Seatbelt-Survey im Repo.
  @probe_doc_hint "Nachweise: Ticket #70 (Probebericht im Beschluss), " <>
                    "docs/research/2026-10-05-seatbelt-survey.md"

  # ===========================================================================
  # Einstieg (komki_policy-Muster: hard main, testbares run/1 ohne halt)
  # ===========================================================================

  @doc false
  @spec main([binary()]) :: no_return()
  def main(argv) do
    # Multicall (Ticket #179): `komki komki-mediator ...` usw. startet die
    # Rolle; deren Einstieg blockiert und beendet die VM selbst.
    case KomkiCli.Roles.dispatch(argv) do
      {module, rest} ->
        # Kehrt eine Rolle zurueck (etwa `--help`), endet das Programm wie
        # ein eigenstaendiges Escript mit Exit 0.
        module.main(rest)
        halt(0)

      nil ->
        main_cli(argv)
    end
  end

  @spec main_cli([binary()]) :: no_return()
  defp main_cli(argv) do
    # NIF-Bootstrap (Muster aus ratsinfo/lib/ratsinfo/cli.ex, Ticket #91):
    # Im Escript-Kontext sind NIF-priv-Verzeichnisse gezippt und koennen
    # von dort nicht dlopen-geladen werden; daher das physische
    # exqlite-ebin aus dem Build-Tree auf den Code-Pfad bringen. Im
    # Mix-Kontext (dev/test) ist der Pfad bereits korrekt — No-Op.
    for path <- exqlite_ebin_paths() do
      Code.prepend_path(path)
    end

    {output, code} = run(argv)
    IO.write(output)
    halt(code)
  end

  # Exqlite ist die einzige NIF-Abhaengigkeit (SQLite-Registry des
  # Label-Store). `Application.app_dir(:exqlite)/ebin` schaut auf dem
  # Code-Pfad; im Escript-Kontext ist exqlite im Zip und der Pfad zeigt in
  # das Zip-Archiv — die NIF muss aber vom realen Dateisystem laden. Die
  # Build-Tree-Pfade decken den Escript-Alltag ab (`mix escript.build`).
  defp exqlite_ebin_paths do
    base = Path.dirname(:escript.script_name())

    paths = [
      # Paket-Layout (Ticket #180): komki und lib/exqlite nebeneinander
      Path.join([base, "lib/exqlite/ebin"]),
      Path.join([base, "_build/dev/lib/exqlite/ebin"]),
      Path.join([base, "../_build/dev/lib/exqlite/ebin"]),
      Path.join([Application.app_dir(:exqlite), "ebin"])
    ]

    Enum.filter(paths, &File.dir?/1)
  rescue
    _ -> []
  end

  @doc false
  @dialyzer {:nowarn_function, halt: 1}
  def halt(code), do: System.halt(code)

  @doc "Testbare Kernfunktion: `{output, exit_code}` ohne System.halt."
  @spec run(term()) :: outcome()
  def run(argv) when is_list(argv) do
    # Log-Auszuege der Rollen koennen Latin-1-Bytes tragen (Rollen laufen mit
    # LANG=C); ungueltiges UTF-8 ersetzen statt beim Ausgeben abzustuerzen.
    {output, code} = dispatch(argv)
    {String.replace_invalid(output), code}
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
      description: "komki: KI-Recherche für die Ratsarbeit in einer abgeschotteten Umgebung",
      version: @version,
      author: "Carsten Roesnick-Neugebauer",
      subcommands: with_about(subcommands())
    )
  end

  # Optimus listet Unterbefehle mit ihrem `about`; die Kurzbeschreibung ist
  # dieselbe wie die `description` der jeweiligen Hilfe-Seite.
  defp with_about(subcommands) do
    Enum.map(subcommands, fn {key, spec} ->
      spec =
        spec
        |> Keyword.put_new(:about, spec[:description])
        |> Keyword.update(:subcommands, [], &with_about/1)

      {key, spec}
    end)
  end

  defp subcommands do
    [
      version: [name: "version", description: "Version anzeigen"],
      setup: [
        name: "setup",
        description:
          "geführte Einrichtung: Werkzeuge prüfen, Instanz anlegen, Schlüssel hinterlegen, starten",
        options: [
          vault_dir: [
            value_name: "PATH",
            long: "vault-dir",
            help: "eigener Vault (sonst Frage; Enter wählt den Test-Vault)"
          ],
          gguf_from: [
            value_name: "PATH",
            long: "gguf-from",
            help: "vorhandene Modelldatei (GGUF) verwenden"
          ],
          port: [
            value_name: "N",
            long: "port",
            parser: :integer,
            help: "llama-server-Port (default 49524; anderer Port für eine zweite Instanz)"
          ]
        ],
        flags: [
          demo: [
            long: "demo",
            help: "Test-Vault mit erfundenen Notizen verwenden, ohne zu fragen"
          ]
        ]
      ],
      secret: [
        name: "secret",
        description: "Schlüssel im macOS-Schlüsselbund verwalten (Werte werden nie angezeigt)",
        subcommands: [
          set: [
            name: "set",
            description:
              "Schlüssel verdeckt eingeben und ablegen (z.B. 'komki secret set brave')",
            args: [
              name: [
                value_name: "NAME",
                required: true,
                help: "Kurzname, siehe 'komki secret list'"
              ]
            ]
          ],
          list: [name: "list", description: "erwartete Schlüssel und ob sie vorhanden sind"]
        ]
      ],
      journal: [
        name: "journal",
        description: "Entscheidungs-Journal des Vermittlers",
        subcommands: [
          verify: [
            name: "verify",
            description: "prüfen, dass die Kette lückenlos und unverändert ist"
          ]
        ]
      ],
      init: [
        name: "init",
        description:
          "Instanz von Hand anlegen (macht setup mit; Modell wird per Prüfsumme geprüft)",
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
            help: "llama-Kontextgröße (default 131072)"
          ],
          vault_dir: [
            value_name: "PATH",
            long: "vault-dir",
            help:
              "Vault des Vault-Connectors (default <base>/vault, anfangs leer; leer gesetzt: abgeschaltet)"
          ],
          ris_base_url: [
            value_name: "URL",
            long: "ris-base-url",
            help: "RIS-API-Basis (default https://risapi1.komuna.net/web/)"
          ],
          ris_mock_port: [
            value_name: "N",
            long: "ris-mock-port",
            parser: :integer,
            help: "RIS-Mock auf 127.0.0.1:N statt echter API (ohne Egress-Proxy)"
          ]
        ],
        flags: [
          force: [long: "force", help: "bestehende config.json überschreiben"]
        ]
      ],
      doctor: [
        name: "doctor",
        description:
          "alles prüfen: Werkzeuge, Profile, Start in der Sandbox (läuft vor jedem run und jeder session)"
      ],
      up: [
        name: "up",
        description:
          "llama-server, Egress, Connectoren und Vermittler starten (prüft vorher kurz, wartet bis alles antwortet)",
        options: [
          ctx: [
            value_name: "N",
            long: "ctx",
            parser: :integer,
            help: "Kontextgröße Override für diesen Start"
          ]
        ]
      ],
      down: [
        name: "down",
        description: "alles stoppen, was komki gestartet hat (fremde Prozesse bleiben unberührt)"
      ],
      go: [
        name: "go",
        description:
          "gesperrte Aufrufe ansehen und einzeln freigeben (GO gilt einmal, nur für diesen Aufruf)"
      ],
      status: [
        name: "status",
        description:
          "zeigt, was läuft (llama, Egress, Connectoren, Vermittler) und wo die Instanz liegt"
      ],
      run: [
        name: "run",
        description:
          "einen Auftrag einmal ausführen und die Antwort ausgeben (startet komki bei Bedarf)",
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
            help: "Scratch-Verzeichnis unterhalb base/runs/ (default base/runs/<UTC-Stamp>)"
          ],
          timeout: [
            value_name: "SEKUNDEN",
            long: "timeout",
            parser: :integer,
            help: "Laufzeit-Limit für pi (default 600); danach Abbruch mit Exit 4"
          ]
        ],
        flags: [
          capture_denials: [
            long: "capture-denials",
            help:
              "Sandbox-Ablehnungen des Laufs aus dem macOS-Log einsammeln, redigieren und unter <base>/denials/ ablegen"
          ]
        ]
      ],
      session: [
        name: "session",
        description: "interaktiv mit pi arbeiten, in tmux (startet komki bei Bedarf)",
        flags: [
          continue: [long: "continue", help: "vorherige Session fortsetzen (pi --continue)"],
          detach: [
            long: "detach",
            help: "Session im Hintergrund starten; der Befehl zum Andocken steht in der Ausgabe"
          ]
        ]
      ],
      session_chain: [
        name: "session-chain",
        description: "intern: pi-Kette als Port-Kind (Pane-Einstieg von 'session')",
        flags: [
          continue: [long: "continue", help: "vorherige Session fortsetzen (pi --continue)"]
        ]
      ],
      label: [
        name: "label",
        description:
          "SQLite-Registry: Bindungen, Labels, Quarantäne und Γ-Export (Ticket #91; RFC 0003 R.2)",
        subcommands: [
          import: [
            name: "import",
            description: "Store aus Registry-Datei füllen (komki-label-store/2, Merge)",
            args: [
              file: [
                value_name: "FILE",
                required: true,
                help: "Pfad der komki-label-store/2-JSON-Datei"
              ]
            ],
            options: [db: db_opt()]
          ],
          quarantine: [
            name: "quarantine",
            description:
              "Objekt in Quarantäne (Eingang eines neuen Objekts oder Rückholung; R.2.5)",
            args: [
              object: [
                value_name: "OBJ@VER",
                required: true,
                help: "Objektreferenz OBJ@VER (Version kebab, z.B. v42)"
              ]
            ],
            options: [
              db: db_opt(),
              content_ref: content_ref_opt(),
              origin: origin_opt(),
              decided_by: decided_by_opt(),
              basis: basis_opt()
            ]
          ],
          classify: [
            name: "classify",
            description:
              "Erstklassifikation/Neuklassifikation (menschlicher Akt; Λ=∅ ist legitimes leeres Label)",
            args: [
              object: [
                value_name: "OBJ@VER",
                required: true,
                help: "Objektreferenz OBJ@VER"
              ]
            ],
            options: [
              db: db_opt(),
              label: label_opt(),
              decided_by: decided_by_opt(),
              basis: basis_opt()
            ]
          ],
          list: [
            name: "list",
            description: "Übersicht: Bindungen und Objektstände",
            options: [db: db_opt()]
          ],
          show: [
            name: "show",
            description: "Einzelansichten (Binding R.2.2/Objekt-Historie)",
            subcommands: [
              binding: [
                name: "binding",
                description: "Volle Bindungsdefinition (alle R.2.2-Felder)",
                args: [
                  binding: [
                    value_name: "BINDUNGS-ID",
                    required: true,
                    help: "Bindungskennung <kebab>@<int>"
                  ]
                ],
                options: [db: db_opt()]
              ],
              object: [
                name: "object",
                description: "Objekt-Metadaten + Entscheidungshistorie",
                args: [
                  object: [
                    value_name: "OBJ@VER",
                    required: true,
                    help: "Objektreferenz OBJ@VER"
                  ]
                ],
                options: [db: db_opt()]
              ]
            ]
          ],
          export: [
            name: "export",
            description: "Γ-Export: komki-registry/2 JSON (stdout oder --out)",
            options: [db: db_opt(), out: out_opt()]
          ]
        ]
      ]
    ]
  end

  defp dispatch(argv) do
    case trailing_help(argv) do
      {:help, [_ | _] = prefix} ->
        # Trailing "--help"/"-h" auf dem Subcommand-Pfad (`komki label
        # --help`): Optimus behandelt nur das Top-Level ["--help"]-
        # Special (optimus.ex parse_specials/2); der `help`-Einstieg
        # liefert dieselbe usage-Ausgabe mit Exit 0.
        dispatch(["help" | prefix])

      _ ->
        parse_dispatch(argv)
    end
  end

  defp trailing_help(argv) do
    case Enum.split(argv, -1) do
      {prefix, token} when token in [["--help"], ["-h"]] -> {:help, prefix}
      _ -> :none
    end
  end

  defp parse_dispatch(argv) do
    case Optimus.parse(cli(), argv) do
      {:ok, [group | tail], result} when group in [:label, :secret, :journal] ->
        dispatch_group(group, tail, result)

      # Top-Level-Befehle (Vertrag ab version bis session-chain):
      {:ok, [command], result} ->
        dispatch_command(command, result)

      {:ok, %Optimus.ParseResult{}} ->
        {"no command given; run \"komki --help\"\n", 2}

      {:error, errors} ->
        {error_line(errors) <> "\n", 2}

      {:error, _path, errors} ->
        {error_line(errors) <> "\n", 2}

      :help ->
        help_text([])

      {:help, path} ->
        help_text(path)

      :version ->
        {"komki " <> @version <> "\n", 0}
    end
  end

  # Befehlsgruppen: label (Ticket #91), secret und journal (Ticket #176)
  defp dispatch_group(:label, tail, result), do: dispatch_label_tail(tail, result)
  defp dispatch_group(:secret, [:set], result), do: secret_set(result.args.name)
  defp dispatch_group(:secret, [:list], _result), do: secret_list()
  defp dispatch_group(:journal, [:verify], _result), do: render(KomkiCli.Steps.journal_verify())

  defp dispatch_label_tail([sub], result) do
    render(KomkiCli.LabelSteps.label_command(sub, label_opts(result)))
  end

  defp dispatch_label_tail([:show, which], result) do
    render(KomkiCli.LabelSteps.label_show(which, label_opts(result)))
  end

  @doc false
  @spec help_text(Optimus.subcommand_path()) :: outcome()
  def help_text(subcommand_path) do
    lines = Optimus.Help.help(cli(), subcommand_path, 80)
    {Enum.join(lines, "\n") <> "\n", 0}
  end

  defp error_line(errors) do
    "Error: " <> Enum.join(format_errors(errors), ", ") <> "; run \"komki --help\" für usage"
  end

  # Optimus formatiert Parse-Fehler bedingungslos farbig (IO.ANSI.red/bright/
  # reset ohne enabled?-Pruefung, siehe optimus/lib/optimus/errors.ex): Ohne
  # eigenes Gate landen die Farbcodes auch in gepipeten Ausgaben — unter dem
  # Escript genauso wie unter der Burrito-Binary (Pilot-Fund 2026-10-11).
  # Der farblose Zweig haelt dieselbe "- msg"-Form.
  defp format_errors(errors) do
    if KomkiCli.Runtime.ansi_enabled?() do
      Optimus.Errors.format_errors(errors)
    else
      Enum.map(errors, &("- " <> IO.iodata_to_binary(&1)))
    end
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

  defp dispatch_command(:go, _result),
    do:
      KomkiCli.GoSteps.run(KomkiCli.Config.default_base(), %{
        say: &IO.puts/1,
        confirm: &KomkiCli.Prompt.confirm/2
      })

  defp dispatch_command(:setup, result),
    do: render(KomkiCli.Setup.run(optimus_opts(result), setup_ui()))

  defp dispatch_command(:session, result),
    do: render(KomkiCli.Steps.session(optimus_opts(result), &show_start/1))

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
      render(KomkiCli.Steps.run(opts, &show_start/1))
    end
  end

  # run/session ohne vorheriges `komki up` (Ticket #176): Steps meldet den
  # Start ueber diesen Rueckruf, die Zeilen erscheinen sofort (die Session
  # uebernimmt danach das Terminal).
  defp show_start(up) do
    {out, _code} = render(up)
    IO.write("komki war nicht gestartet, jetzt gestartet:\n" <> out)
  end

  # ===========================================================================
  # setup und secret (Ticket #176): interaktiv, deshalb schreiben sie direkt
  # aufs Terminal; Fragen und verdeckte Eingabe in KomkiCli.Prompt.
  # ===========================================================================

  defp setup_ui do
    %{
      say: &IO.puts/1,
      ask: &KomkiCli.Prompt.ask/2,
      confirm: &KomkiCli.Prompt.confirm/2,
      secret: &KomkiCli.Prompt.secret/1,
      render: fn result ->
        {out, _code} = render(result)
        IO.write(out)
      end
    }
  end

  defp secret_set(name) do
    case KomkiCli.Secrets.fetch(name) do
      {:ok, entry} ->
        IO.puts(entry.label <> " (Schlüsselbund-Eintrag '" <> entry.service <> "')")
        message = KomkiCli.Setup.store_secret(entry, setup_ui())
        code = if String.starts_with?(message, "gespeichert"), do: 0, else: 2
        {message <> "\n", code}

      :error ->
        names = Enum.map_join(KomkiCli.Secrets.all(), ", ", & &1.name)
        {"unbekannter Schlüssel '" <> name <> "'; bekannt: " <> names <> "\n", 2}
    end
  end

  defp secret_list do
    lines =
      Enum.map(KomkiCli.Secrets.all(), fn entry ->
        state =
          if KomkiCli.Secrets.present?(entry), do: green() <> "vorhanden", else: red() <> "fehlt"

        String.pad_trailing(entry.name, 10) <>
          state <> reset() <> "  " <> entry.label <> " ('" <> entry.service <> "')"
      end)

    {Enum.join(lines, "\n") <> "\n", 0}
  end

  # label-Subcommands: args (file/object/binding) mit String-Schluesseln
  # mischen, dann an LabelSteps uebergeben.
  defp label_opts(result) do
    args = Map.new(result.args, fn {key, value} -> {Atom.to_string(key), value} end)
    Map.merge(optimus_opts(result), args)
  end

  # ===========================================================================
  # label-Optionen (Ticket #91): Registry-DB default am Root des
  # Basisverzeichnisses (NICHT unter pi-home/Scratch — auserhalb der
  # Sandbox-Schreibhoheit, R.2.1).
  # ===========================================================================

  defp db_opt do
    [
      value_name: "PATH",
      long: "db",
      default: KomkiCli.LabelStore.default_path(),
      help: "Registry-DB-Pfad"
    ]
  end

  defp content_ref_opt do
    [
      value_name: "PATH",
      long: "content-ref",
      help: "Inhaltsreferenz (Pfad/Hash; Pflicht bei neuem Objekt)"
    ]
  end

  defp origin_opt do
    [
      value_name: "TEXT",
      long: "origin",
      help: "Herkunft des Objekts (Freitext; Pflicht bei neuem Objekt)"
    ]
  end

  defp decided_by_opt do
    [
      value_name: "ID",
      long: "decided-by",
      required: true,
      help: "Beobachter-ID der entscheidenden Person (R.2.5: nur Typ \"person\" entscheidet)"
    ]
  end

  defp basis_opt do
    [
      value_name: "TEXT",
      long: "basis",
      required: true,
      help: "Begründung + Quelle (Quellenpflicht, AGENTS.md §6)"
    ]
  end

  defp label_opt do
    [
      value_name: "BINDUNG",
      long: "label",
      multiple: true,
      help: "Bindungslabel (wiederholbar; ohne Angabe = ausdrücklich leeres Label Λ=∅)"
    ]
  end

  defp out_opt do
    [
      value_name: "PATH",
      long: "out",
      help: "Zieldatei (default: stdout)"
    ]
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
    # Spinner nur mit aktivierten Farben (Terminal): gepipete Aufrufe bekämen
    # sonst \r-Frame- und ANSI-Reste ins Log (gleiche Klasse wie der
    # Optimus-Fehler-Fund aus dem Burrito-Pilot 2026-10-11; unter dem Escript
    # identisch). Gepipet laeuft `up` stumm, das Health-Ergebnis kommt.
    if KomkiCli.Runtime.ansi_enabled?() do
      spid = spawn(fn -> spin(0, "warte auf llama-server (doctor-quick + health) ...") end)

      result =
        try do
          KomkiCli.Steps.up(opts)
        after
          send(spid, :stop)
          Process.sleep(150)
        end

      result
    else
      KomkiCli.Steps.up(opts)
    end
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

  defp write_denial_footer(nil), do: :ok

  defp write_denial_footer(summary) do
    IO.write(:stderr, KomkiCli.Denials.footer(summary) <> "\n")
  end

  @doc false
  @spec run_exit_code(KomkiCli.Steps.denial_summary() | nil) :: non_neg_integer()
  def run_exit_code(nil), do: 0
  def run_exit_code(%{status: "ok"}), do: 0
  def run_exit_code(%{status: _status}), do: 4

  @doc false
  @spec render_result(KomkiCli.Steps.result()) :: outcome()
  def render_result(result), do: render(result)

  @spec render(
          KomkiCli.Steps.result()
          | KomkiCli.LabelSteps.result()
          | {:setup, :ok}
          | {:journal, map()}
        ) :: outcome()
  defp render({:inited, cfg, gguf_lines}), do: render_init(cfg, gguf_lines)
  defp render({:checks, checks, summary}), do: render_doctor(checks, summary)

  # Ticket #102: up startet llama-server UND den Vermittler (zwei
  # Zustandszeilen); der Vermittler kann auch :already sein (healthz gruen,
  # kein Neustart — Idempotenz).
  defp render(
         {:up, %{llama: pid, connectors: connectors, mediator: {:started, mediator_pid, health}}}
       ),
       do:
         {green() <>
            "llama up: pid " <>
            to_string(pid) <>
            reset() <>
            " (health 200)\n" <>
            connector_up_lines(connectors) <>
            green() <>
            "mediator up: pid " <>
            to_string(mediator_pid) <>
            reset() <>
            " (tools: " <>
            mediator_tools_line(health) <> ")\n", 0}

  defp render({:up, %{llama: pid, connectors: connectors, mediator: {:already, health}}}),
    do:
      {green() <>
         "llama up: pid " <>
         to_string(pid) <>
         reset() <>
         " (health 200)\n" <>
         connector_up_lines(connectors) <>
         green() <>
         "mediator: bereits laufend (healthz ok, tools: " <>
         mediator_tools_line(health) <> ")" <> reset() <> "\n", 0}

  # Stoppreihenfolge wie up rueckwaerts: Vermittler-Zeile zuerst.
  defp render({:down, %{llama: llama, connectors: connectors, mediator: mediator} = down}),
    do:
      {Enum.map_join(
         [{"mediator", mediator}] ++ connectors ++ [{"llama", llama}],
         fn {name, state} -> down_line(name, state) <> "\n" end
       ) <> orphans_line(Map.get(down, :orphans, 0)), 0}

  defp render(
         {:status, cfg, %{llama: llama_state, connectors: connectors, mediator: mediator_state}}
       ) do
    rows =
      [
        {"base", cfg.base_dir},
        {"gguf", cfg.gguf_path},
        {"port", to_string(cfg.port)},
        {"mediator-sock", KomkiCli.Channel.socket_path(cfg)},
        {"llama", state_line(llama_state, "/health")}
      ] ++
        Enum.map(connectors, fn {name, state} -> {name, state_line(state, "")} end) ++
        [{"mediator", state_line(mediator_state, "/healthz")}]

    # Eine Spalte fuer alle Werte, so breit wie die laengste Bezeichnung
    # (connector-documents, #169).
    width = rows |> Enum.map(fn {label, _} -> String.length(label) end) |> Enum.max()

    {Enum.map_join(rows, "", fn {label, value} ->
       String.pad_trailing(label <> ":", width + 2) <> value <> "\n"
     end), 0}
  end

  # pi-Ausgabe ist Modell-Output: nie roh aufs Terminal (Ticket #132).
  # Denial-Footer auf stderr (beide pi-Modi, Ticket #125): der stdout-Vertrag
  # bleibt der pi-Ausgabe vorbehalten. Ein fehlgeschlagener Capture- oder
  # Persistenzpfad ist auch bei pi-Erfolg ein Runtime-Fail (Exit 4).
  defp render({:run_ok, scratch, out, denial_summary}) do
    write_denial_footer(denial_summary)

    {"scratch: " <>
       scratch <> "\n" <> String.trim_trailing(KomkiCli.Terminal.sanitize(out)) <> "\n",
     run_exit_code(denial_summary)}
  end

  defp render({:run_error, scratch, out, pi_code, denial_summary}) do
    write_denial_footer(denial_summary)

    {"scratch: " <>
       scratch <>
       "\npi exit " <> to_string(pi_code) <> ":\n" <> KomkiCli.Terminal.sanitize(out) <> "\n", 4}
  end

  defp render({:setup, :ok}), do: {"", 0}

  defp render({:journal, %{"result" => "valid"} = result}),
    do:
      {green() <>
         "Journal ok: " <>
         to_string(result["records"]) <>
         " Einträge, lückenlos verkettet und unverändert" <>
         reset() <> "\n" <> "Kopf: " <> to_string(result["head_hash"]) <> "\n", 0}

  defp render({:journal, result}),
    do: {red() <> "Journal UNGUELTIG: " <> JSON.encode!(result) <> reset() <> "\n", 4}

  defp render({:session, message}),
    do: {green() <> String.trim_trailing(message) <> reset() <> "\n", 0}

  # Interner Pane-Lauf: Exit-Code von pi geht 1:1 an tmux durch.
  defp render({:chain_exit, 0}), do: {"", 0}

  defp render({:chain_exit, code}),
    do: {"pi exit " <> to_string(code) <> "\n", code}

  # ----------------------------------------------------------------- label (#91)

  defp render({:label_imported, counts}) do
    {"label import ok: " <>
       to_string(counts.bindings) <>
       " Bindung(en), " <>
       to_string(counts.environments) <>
       " Umgebung(en), " <>
       to_string(counts.observers) <>
       " Beobachter, " <>
       to_string(counts.fact_fields) <>
       " Fakt-Feld(er) neu\n", 0}
  end

  defp render({:label_quarantine, state}),
    do: {"label quarantine ok: " <> state.object <> " (classification quarantine)\n", 0}

  defp render({:label_classify, state}) do
    {"label classify ok: " <>
       state.object <>
       " (classification classified, labels: " <>
       render_labels(state.labels) <> ")\n", 0}
  end

  defp render({:label_list, bindings, objects}) do
    lines = [
      section("Bindungen:", render_binding_summaries(bindings)),
      section("Objekte:", render_object_summaries(objects))
    ]

    {Enum.join(lines, "\n") <> "\n", 0}
  end

  defp render({:label_show_binding, binding}) do
    lines =
      [
        "binding " <> binding.id,
        "  bezeichnung:  " <> binding.bezeichnung,
        "  bereich:      " <> binding.geltungsbereich,
        "  verantwortlich: " <> binding.verantwortliche_stelle,
        "  readers:      " <> Enum.join(binding.readers, ", "),
        "  operations:   " <> JSON.encode!(binding.operations),
        "  auflagen:     " <> JSON.encode!(binding.auflagen),
        "  registered_at: " <> binding.registered_at
      ] ++ render_relaxation_authorities(binding.relaxation_authorities)

    {Enum.join(lines, "\n") <> "\n", 0}
  end

  defp render({:label_show_object, object, decisions}) do
    header = [
      object.object_id <> "@" <> object.version,
      "  content_ref:   " <> object.content_ref,
      "  origin:        " <> object.origin
    ]

    history = [
      "  Entscheidungen (" <> to_string(length(decisions)) <> "):"
      | Enum.map(decisions, &render_decision/1)
    ]

    {Enum.join(header ++ history, "\n") <> "\n", 0}
  end

  defp render({:label_export, nil, json}), do: {json, 0}

  defp render({:label_export, path, _json}),
    do: {"Γ-Export geschrieben: " <> path <> "\n", 0}

  defp render({:error, reason, code}),
    do: {red() <> String.trim_trailing(reason) <> reset() <> "\n", code}

  defp render_decision(decision) do
    "  #" <>
      to_string(decision.id) <>
      " " <>
      decision.classification <>
      " labels=" <>
      JSON.encode!(decision.labels) <>
      " von " <>
      decision.decided_by <>
      " um " <>
      decision.decided_at <>
      " — basis: " <> decision.basis
  end

  defp render_labels([]), do: "(leer; ausdrückliches Λ=∅)"

  defp render_labels(labels), do: Enum.join(labels, ", ")

  defp section(title, []), do: title <> " (keine)"

  defp section(title, lines), do: Enum.join([title | lines], "\n")

  defp render_binding_summaries(bindings) do
    Enum.map(bindings, fn binding ->
      "  " <> binding.id <> " — " <> binding.bezeichnung
    end)
  end

  defp render_object_summaries(objects) do
    Enum.map(objects, fn object ->
      "  " <>
        object.object <>
        "  classification=" <>
        to_string(object.classification) <>
        "  labels=" <> JSON.encode!(object.labels)
    end)
  end

  # Strukturierte Lockerungsbefugnis (R.2.2): je Eintrag eine Zeile —
  # wer (authority) welche Einschraenkung (restriction) fuer welche Ausgabe
  # (output) lockern darf.
  defp render_relaxation_authorities([]),
    do: ["  relaxation_authorities: [] (keine Lockerung zulässig, R.2.2)"]

  defp render_relaxation_authorities(entries) do
    [
      "  relaxation_authorities:"
      | Enum.map(entries, fn
          %{} = entry ->
            "    " <>
              entry["authority"] <>
              " lockert '" <>
              entry["restriction"] <>
              "' für Ausgabe '" <> entry["output"] <> "'"

          _flat ->
            "    (unlesbarer Eintrag — Store-Stand vor komki-label-store/2)"
        end)
    ]
  end

  # Farb-Gate: unter Burrito (stdout-Pipe des Wrappers, Regression #234)
  # entscheidet das Wrapper-eigene _IS_TTY, sonst IO.ANSI.enabled?/0 —
  # siehe KomkiCli.Runtime.ansi_enabled?/0.
  defp green, do: if(KomkiCli.Runtime.ansi_enabled?(), do: IO.ANSI.green(), else: "")
  defp red, do: if(KomkiCli.Runtime.ansi_enabled?(), do: IO.ANSI.red(), else: "")
  defp reset, do: if(KomkiCli.Runtime.ansi_enabled?(), do: IO.ANSI.reset(), else: "")

  defp render_init(cfg, gguf_lines) do
    lines =
      [
        "init ok",
        "base-dir:   " <> cfg.base_dir,
        "config:     " <> KomkiCli.Config.config_path(cfg.base_dir),
        "profile:    " <> cfg.profile_path,
        "pi-home:    " <> cfg.pi_home,
        "port:       " <> to_string(cfg.port),
        "mediator-sock: " <> KomkiCli.Channel.socket_path(cfg),
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

  # Zustandszeilen (status): EINE parametrisierte Kaskade fuer llama und
  # Vermittler — beide Zustandstypen (`KomkiCli.Llama.status/1` /
  # `KomkiCli.Mediator.status/1`) sind strukturell identisch, der einzige
  # Unterschied ist der Health-Pfad (Ticket #102/Vermittler-Zeile).
  defp state_line({:running, pid}, _health_path), do: "running (pid " <> to_string(pid) <> ")"

  defp state_line({:health_only, :no_pidfile}, health_path),
    do: "port antwortet " <> health_path <> " aber kein pidfile (fremder Prozess?)"

  defp state_line(:stopped, _health_path), do: "stopped"
  defp state_line(:disabled, _health_path), do: "abgeschaltet (Konfiguration)"
  defp state_line({:error, reason}, _health_path), do: "error: " <> reason

  # Fassung-Tools im up-Output: kleine Ehrlichkeit der Schnittstelle — der
  # Nutzer sieht, was pi per mcp.json freigeschaltet bekommt.
  # Ticket #146: Egress und Connectoren zwischen llama und Vermittler.
  defp connector_up_lines(connectors) do
    Enum.map_join(connectors, fn
      {name, {:started, pid}} ->
        green() <> name <> " up: pid " <> to_string(pid) <> reset() <> "\n"

      {name, {:already, pid}} ->
        green() <> name <> ": bereits laufend (pid " <> to_string(pid) <> ")" <> reset() <> "\n"
    end)
  end

  defp mediator_tools_line(%{"tools" => tools}) when is_list(tools), do: Enum.join(tools, ", ")
  defp mediator_tools_line(_), do: "?"

  defp orphans_line(0), do: ""

  defp orphans_line(count),
    do:
      green() <>
        "pi: " <> Integer.to_string(count) <> " verwaiste Session(s) beendet" <> reset() <> "\n"

  defp down_line(component, :ok),
    do: green() <> component <> " gestoppt" <> reset()

  defp down_line(component, :already),
    do: green() <> component <> ": bereits gestoppt (kein pidfile)" <> reset()

  defp down_line(component, {:stale, reason}),
    do: green() <> component <> " down: " <> reason <> reset()
end
