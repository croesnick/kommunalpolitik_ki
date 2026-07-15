defmodule Ratsinfo.CLI do
  @moduledoc """
  CLI-Entry-Point für ratsinfo.

  Usage: ratsinfo <command> [options]

  Commands:
    inspect-source   API-Verfügbarkeit prüfen
    sync             Sitzungen + Dokumente lokal speichern
    sessions         Sitzungen auflisten
    search <query>   Lokale Volltextsuche
    show <id>        Sitzungsdetails anzeigen
    open <id>        Dokument öffnen
    stats            Datenbank-Statistik
  """

  alias Ratsinfo.{ApiClient, Auth, Store}

  @spec main([String.t()]) :: :ok
  def main(args \\ System.argv()) do
    # Im escript-Kontext sind NIF-priv-Verzeichnisse gezippt und können von dort
    # nicht dlopen-geladen werden. Exqlite-priv auf Code-Pfad bringen, damit die
    # sqlite3_nif.so direkt vom Dateisystem lädt. Im normalen `mix run`-Kontext
    # ist der Pfad bereits korrekt und der Append ist ein No-Op.
    for path <- nif_priv_paths() do
      Code.prepend_path(path)
    end

    {:ok, _} = Application.ensure_all_started(:ratsinfo)

    optimus = build_cli()
    parsed = Optimus.parse(optimus, args)
    run(parsed)
  end

  # Exqlite ist die einzige NIF-Abhängigkeit. `:code.priv_dir(:exqlite)` schaut
  # auf dem Code-Pfad nach dem ebin-Verzeichnis der App und leitet daraus den
  # priv-Pfad ab. Im escript-Kontext ist exqlite im Zip gezippt und der Pfad
  # zeigt in das Zip-Archiv — die NIF-`.so` kann aber nicht daraus dlopen-geladen
  # werden. Wir bringen das physische ebin-Verzeichnis aus dem Build-Tree auf den
  # Code-Pfad, so dass `priv_dir` auf das reale Dateisystem zeigt.
  defp nif_priv_paths do
    base = Path.dirname(:escript.script_name())

    paths = [
      Path.join([base, "_build/dev/lib/exqlite/ebin"]),
      Path.join([base, "../_build/dev/lib/exqlite/ebin"]),
      Path.join([Application.app_dir(:exqlite), "ebin"])
    ]

    Enum.filter(paths, &File.dir?/1)
  end

  defp build_cli do
    Optimus.new!(
      name: "ratsinfo",
      description: "Ratsinformationssystem Buchloe — CLI",
      version: "0.1.0",
      author: "Carsten Roesnick-Neugebauer",
      subcommands: [
        inspect_source: [
          name: "inspect-source",
          description: "API-Verfügbarkeit prüfen",
          options: [
            client_id: [
              value_name: "CLIENT_ID",
              short: "c",
              long: "client",
              help: "Client-ID (32=Stadt Buchloe, 2445=VGem)",
              default: "32"
            ]
          ]
        ],
        sync: [
          name: "sync",
          description: "Sitzungen + TOPs + Texte lokal speichern",
          options: [
            from: [
              value_name: "DATE",
              short: "f",
              long: "from",
              help: "Startdatum (YYYY-MM-DD)",
              default: "#{Date.utc_today().year}-01-01"
            ],
            to: [
              value_name: "DATE",
              short: "t",
              long: "to",
              help: "Enddatum (YYYY-MM-DD)",
              default: "#{Date.utc_today().year}-12-31"
            ],
            client_id: [
              value_name: "CLIENT_ID",
              short: "c",
              long: "client",
              help: "Client-ID (32=Stadt Buchloe, 2445=VGem)",
              default: "32"
            ]
          ]
        ],
        sessions: [
          name: "sessions",
          description: "Gespeicherte Sitzungen auflisten",
          options: [
            client_id: [
              value_name: "CLIENT_ID",
              short: "c",
              long: "client",
              help: "Client-ID (nur mit --remote)",
              default: "32"
            ]
          ],
          flags: [
            remote: [
              short: "r",
              long: "remote",
              help: "Von API abrufen statt aus lokaler DB"
            ]
          ]
        ],
        search: [
          name: "search",
          description: "Lokale Volltextsuche über gespeicherte Texte",
          args: [
            query: [
              value_name: "QUERY",
              help: "Suchbegriff",
              required: true
            ]
          ],
          options: [
            limit: [
              value_name: "N",
              short: "n",
              long: "limit",
              help: "Maximale Anzahl Treffer",
              default: "20"
            ]
          ]
        ],
        show: [
          name: "show",
          description: "Sitzungsdetails anzeigen",
          args: [
            id: [
              value_name: "SITZUNG_ID",
              help: "Sitzungs-ID",
              required: true,
              parser: :integer
            ]
          ]
        ],
        open: [
          name: "open",
          description: "Dokument öffnen",
          args: [
            id: [
              value_name: "DOKUMENT_ID",
              help: "Dokument-ID",
              required: true
            ]
          ]
        ],
        stats: [
          name: "stats",
          description: "Datenbank-Statistik"
        ],
        ris_search: [
          name: "ris-search",
          description: "Volltextsuche direkt im RIS (authentifiziert)",
          args: [
            query: [
              value_name: "QUERY",
              help: "Suchbegriff",
              required: true
            ]
          ],
          options: [
            client_id: [
              value_name: "CLIENT_ID",
              short: "c",
              long: "client",
              help: "Client-ID",
              default: "32"
            ]
          ]
        ]
      ]
    )
  end

  defp run({:ok, [command], result}), do: run_command(command, result)
  defp run({:error, reason}), do: IO.puts("Error: #{format_error(reason)}")
  defp run({:error, _path, reason}), do: IO.puts("Error: #{format_error(reason)}")
  defp run(:help), do: :ok
  defp run(:version), do: IO.puts("ratsinfo 0.1.0")

  defp format_error(reason) when is_list(reason), do: Enum.join(reason, ", ")
  defp format_error(reason), do: inspect(reason)

  # --- Commands ---

  defp run_command(:inspect_source, opts) do
    client_id = String.to_integer(opts.options.client_id)

    IO.puts("RIS API Verfügbarkeit prüfen...")
    IO.puts("Client-ID: #{client_id}")

    case ApiClient.list_sitzungen(client_id: client_id, from: "2025-01-01", until: "2025-12-31") do
      {:ok, sitzungen} ->
        IO.puts("\n✓ API erreichbar")
        IO.puts("  #{length(sitzungen)} Sitzungen gefunden (2025)")

        if sitzungen != [] do
          IO.puts("\n  Beispiel:")
          s = hd(sitzungen)
          IO.puts("  #{s["meetingdate"]} — #{s["name"]}")
          IO.puts("  ID: #{s["id"]}, Gremium: #{s["committeename"]}")
        end

        {:ok, token} = Auth.get_token()
        IO.puts("\n✓ Login erfolgreich (Token gecacht)")

        {:ok, gremien} = ApiClient.list_gremien(token, client_id: client_id)
        IO.puts("  #{length(gremien)} Gremien gefunden")

      {:error, reason} ->
        IO.puts("\n✗ API nicht erreichbar: #{inspect(reason)}")
    end

    :ok
  end

  defp run_command(:sync, opts) do
    :ok = Store.init()

    from = opts.options.from
    to = opts.options.to
    client_id = String.to_integer(opts.options.client_id)

    IO.puts("Sitzungen synchronisieren (#{from} bis #{to}, Client #{client_id})...")

    {:ok, sitzungen} = ApiClient.list_sitzungen(client_id: client_id, from: from, until: to)
    IO.puts("#{length(sitzungen)} Sitzungen gefunden")

    {:ok, token} = Auth.get_token()

    {count, _} = :timer.tc(fn -> sync_sitzungen(sitzungen, token) end)

    IO.puts("\nSync abgeschlossen in #{div(count, 1000)}ms")
    print_stats()
    :ok
  end

  defp run_command(:sessions, opts) do
    if opts.flags[:remote] do
      client_id = String.to_integer(opts.options.client_id)
      {:ok, sitzungen} = ApiClient.list_sitzungen(client_id: client_id)
      print_remote_sessions(sitzungen)
    else
      :ok = Store.init()
      sitzungen = Store.list_sitzungen()
      print_local_sitzungen(sitzungen)
    end

    :ok
  end

  defp run_command(:search, opts) do
    :ok = Store.init()

    query = opts.args.query
    limit = String.to_integer(opts.options.limit)

    case Store.search(query, limit: limit) do
      {:ok, []} ->
        IO.puts("Keine Treffer für '#{query}'")
        IO.puts("Hinweis: Führe zuerst 'ratsinfo sync' aus um Texte zu indexieren")

      {:ok, results} ->
        IO.puts("#{length(results)} Treffer für '#{query}':\n")
        Enum.each(results, &print_search_result/1)
    end

    :ok
  end

  defp run_command(:show, opts) do
    :ok = Store.init()

    id = opts.args.id

    case Store.get_sitzung(id) do
      nil ->
        IO.puts("Sitzung #{id} nicht gefunden. Führe 'ratsinfo sync' aus.")
        {:ok, token} = Auth.get_token()

        case ApiClient.get_sitzung(id, token) do
          {:ok, sitzung} -> print_sitzung_detail(sitzung)
          {:error, reason} -> IO.puts("Fehler beim Abrufen: #{inspect(reason)}")
        end

      sitzung ->
        print_sitzung(sitzung)
        tops = Store.list_tops(id)
        print_tops(tops)
    end

    :ok
  end

  defp run_command(:open, opts) do
    :ok = Store.init()

    doc_id = opts.args.id

    case Store.get_dokument(doc_id) do
      nil ->
        IO.puts("Dokument #{doc_id} nicht gefunden. Führe 'ratsinfo sync' aus.")

      dokument ->
        download_and_open(dokument)
    end

    :ok
  end

  defp run_command(:stats, _opts) do
    :ok = Store.init()
    print_stats()
    :ok
  end

  defp run_command(:ris_search, opts) do
    {:ok, token} = Auth.get_token()
    client_id = String.to_integer(opts.options.client_id)

    case ApiClient.fulltext_search(opts.args.query, token: token, client_id: client_id) do
      {:ok, result} ->
        agendaitems = result["agendaitems"] || []
        documents = result["documents"] || []
        meetingdocuments = result["meetingdocuments"] || []

        IO.puts(
          "#{length(agendaitems)} TOPs, #{length(documents)} Dokumente, #{length(meetingdocuments)} Sitzungsdokumente\n"
        )

        agendaitems
        |> Enum.take(20)
        |> Enum.each(&print_ris_search_result/1)

      {:error, reason} ->
        IO.puts("Fehler: #{inspect(reason)}")
    end

    :ok
  end

  # --- Download Helpers ---

  defp download_and_open(dokument) do
    download_dir = download_path()
    File.mkdir_p!(download_dir)

    filename = build_filename(dokument)
    local_path = Path.join(download_dir, filename)

    if dokument.downloaded and File.exists?(local_path) do
      IO.puts("Bereits heruntergeladen: #{local_path}")
    else
      IO.puts("Lade Dokument #{dokument.id} herunter...")

      {:ok, token} = Auth.get_token()

      case ApiClient.download_dokument(dokument.id, token) do
        {:ok, binary} ->
          File.write!(local_path, binary)
          Store.mark_downloaded(dokument.id, local_path)
          IO.puts("Gespeichert: #{local_path}")

        {:error, reason} ->
          IO.puts("Download fehlgeschlagen: #{inspect(reason)}")
          :ok
      end
    end

    open_file(local_path)
  end

  defp download_path do
    System.get_env("RATSINFO_DOWNLOAD_DIR") ||
      Path.join(System.user_home!(), ".cache/ratsinfo/downloads")
  end

  defp build_filename(dokument) do
    name = dokument.name || dokument.id
    ext = dokument.fileext || ".pdf"
    # Dateisystem-sicheren Namen erzeugen
    safe_name = name |> String.replace(~r/[^\w\-]/, "_") |> String.trim("_")
    "#{safe_name}#{ext}"
  end

  defp open_file(path) do
    cmd = if macos?(), do: "open", else: "xdg-open"
    System.cmd(cmd, [path], stderr_to_stdout: true)
  end

  defp macos? do
    :os.type() == {:unix, :darwin}
  end

  # --- Sync Helpers ---

  defp sync_sitzungen(sitzungen, token) do
    Enum.each(sitzungen, fn sitzung ->
      sync_single_sitzung(sitzung, token)
    end)
  end

  defp sync_single_sitzung(sitzung, token) do
    IO.puts("  #{sitzung["meetingdate"]} — #{sitzung["name"]}")

    case ApiClient.get_sitzung(sitzung["id"], token) do
      {:ok, detail} ->
        {:ok, _} = Store.save_sitzung(detail)
        all_tops = extract_all_tops(detail)
        Store.save_tops(sitzung["id"], all_tops)
        sync_top_details(all_tops, sitzung["id"], token)

      {:error, reason} ->
        IO.puts("    ⚠ #{inspect(reason)}")
    end
  end

  defp extract_all_tops(detail) do
    Enum.flat_map(detail["parts"] || [], fn part -> part["agendaitems"] || [] end)
  end

  defp sync_top_details(tops, sitzung_id, token) do
    Enum.each(tops, fn top ->
      [meeting_id, agenda_id] = String.split(top["id"], "-", parts: 2)
      sync_single_top(top, meeting_id, agenda_id, sitzung_id, token)
    end)
  end

  defp sync_single_top(top, meeting_id, agenda_id, sitzung_id, token) do
    case ApiClient.get_top(meeting_id, agenda_id, token) do
      {:ok, top_detail} ->
        textbloecke = top_detail["textblocks"] || []
        dokumente = top_detail["documents"] || []

        Store.save_dokumente(top["id"], sitzung_id, dokumente)
        Store.save_textbloecke(top["id"], sitzung_id, textbloecke)

      {:error, reason} ->
        IO.puts("    ⚠ TOP #{top["id"]}: #{inspect(reason)}")
    end
  end

  # --- Print Helpers ---

  defp print_stats do
    stats = Store.stats()
    IO.puts("\nDatenbank-Statistik:")
    IO.puts("  Sitzungen: #{stats.sitzungen}")
    IO.puts("  TOPs:      #{stats.tops}")
    IO.puts("  Dokumente: #{stats.dokumente}")
    IO.puts("  Texte:     #{stats.texte}")
  end

  defp print_remote_sessions(sitzungen) do
    IO.puts("#{length(sitzungen)} Sitzungen:\n")

    Enum.each(sitzungen, fn s ->
      IO.puts("  #{s["meetingdate"]} [#{s["id"]}] #{s["name"]}")
      IO.puts("    Gremium: #{s["committeename"]}, Ort: #{s["loc_name"]}")
    end)
  end

  defp print_local_sitzungen(sitzungen) do
    IO.puts("#{length(sitzungen)} Sitzungen:\n")

    Enum.each(sitzungen, fn s ->
      IO.puts("  #{s.datum} [#{s.id}] #{s.name}")
      IO.puts("    Gremium: #{s.gremium}, Ort: #{s.ort}")
    end)
  end

  defp print_search_result(result) do
    IO.puts("  [#{result.nummer}] #{result.titel}")
    IO.puts("  #{result.sitzung_name} (#{result.datum}) — #{result.gremium}")
    IO.puts("  #{result.caption}: ...#{result.snippet}...")
    IO.puts("")
  end

  defp print_sitzung(sitzung) do
    IO.puts("Sitzung #{sitzung.id}: #{sitzung.name}")
    IO.puts("  Datum:    #{sitzung.datum}")
    IO.puts("  Gremium:  #{sitzung.gremium}")
    IO.puts("  Ort:      #{sitzung.ort}")
    IO.puts("  Mandant:  #{sitzung.client_name}")
  end

  defp print_sitzung_detail(sitzung) do
    IO.puts("Sitzung #{sitzung["id"]}: #{sitzung["name"]}")
    IO.puts("  Datum:    #{sitzung["meetingdate"]}")
    IO.puts("  Gremium:  #{sitzung["committeename"]}")
    IO.puts("  Ort:      #{sitzung["locationname"]}")
  end

  defp print_tops(tops) do
    IO.puts("\nTagesordnungspunkte:")

    Enum.each(tops, fn top ->
      marker = if top.restricted, do: "🔒", else: "  "
      IO.puts("  #{marker} [#{top.nummer}] #{top.titel}")
    end)
  end

  defp print_ris_search_result(item) do
    IO.puts("  [#{item["numbering"]}] #{item["name"]}")
    IO.puts("  #{item["meetingname"]} (#{item["meetingdate"]})")
    IO.puts("  ID: #{item["id"]}")
    IO.puts("")
  end
end
