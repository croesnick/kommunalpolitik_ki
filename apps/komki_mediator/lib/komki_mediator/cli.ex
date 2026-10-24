defmodule KomkiMediator.CLI do
  @moduledoc """
  Escript-Einstiegspunkt `komki-mediator`: stellt fehlende Aufstellung
  bereit, laedt Gamma und Raum und startet Vermittlung + loopback-Listener.

      komki-mediator --base <dir> --port <n> [--connectors-dir <pfad>]
      komki-mediator verify-journal [--base <dir>]
      komki-mediator --help
      komki-mediator --version

  * `--base`    (Default: KOMKI_HOME oder ~/.local/share/komki)
  * `--port`    (Default: 49525)
  * `--connectors-dir` Verzeichnis der Connector-Sockets `<id>.sock`
    (Default: `<base>/run/connectors`, Connector-Vertrag §2)
  * `--version` gibt die Fassung "komki-mediator/2" aus.

  Bei schlechten Argumenten oder Ladefehlern erscheint eine einzeilige
  JSON-Fehlermeldung auf stderr und Exit 1. Nach dem Start kommt eine
  einzeilige Startnotiz (Port, Fassung, registry_id) auf stdout; danach
  blockiert der Escript ewig (er stirbt, wenn die Hauptschleife
  zurueckkehren wuerde).

  Credentials: der MVP ist ohne Zugangsdaten; die Architektur haelt
  zukuenftige Connector-Credentials ausschliesslich im Vermittlerprozess
  (Zustand) - nie in der mcp.json von pi, nie in Tool-Antworten.
  """

  alias KomkiMediator.{Gamma, Room}

  @default_port 49_525

  def main(argv) do
    case parse(argv) do
      :help ->
        IO.puts(usage())

      :version ->
        IO.puts(KomkiMediator.Fassung.fassung_id())

      {:error, message} ->
        error_exit(%{"error" => "usage", "detail" => message})

      {:run, opts} ->
        run(opts)

      {:verify_journal, opts} ->
        verify_journal(opts)
    end
  end

  # -------------------------------------------------------------------------
  # verify-journal (Ticket #139)
  # -------------------------------------------------------------------------

  defp verify_journal(%{base: base}) do
    path = journal_path(base)

    case File.read(path) do
      {:ok, content} ->
        case KomkiMediator.Journal.verify(content) do
          {:ok, head} ->
            IO.puts(
              JSON.encode!(Map.merge(%{"result" => "valid", "journal" => path}, stringify(head)))
            )

          {:error, detail} ->
            IO.puts(
              JSON.encode!(
                Map.merge(%{"result" => "invalid", "journal" => path}, stringify(detail))
              )
            )

            halt(1)
        end

      {:error, reason} ->
        error_exit(%{"error" => "journal", "detail" => jsonable(reason)})
    end
  end

  defp stringify(map), do: Map.new(map, fn {k, v} -> {Atom.to_string(k), v} end)

  # -------------------------------------------------------------------------
  # Start
  # -------------------------------------------------------------------------

  defp run(%{base: base, port: port} = opts) do
    with :ok <- ensure_runtime_apps(),
         :ok <- provision(base),
         {:ok, gamma} <-
           tagged(Gamma.load(Path.join(mediator_dir(base), "registry.json")), "registry.json"),
         {:ok, room} <- tagged(Room.load(mediator_dir(base)), "room.json") do
      {:ok, _} =
        KomkiMediator.Supervisor.start_link(
          {{journal_path(base), append_only: true}, gamma, room, port,
           %{connectors_dir: connectors_dir(opts)}}
        )

      IO.puts(startup_note(base, port, gamma))
      Process.sleep(:infinity)
    else
      {:error, reason} -> error_exit(reason)
    end
  end

  defp ensure_runtime_apps do
    for app <- [:bandit, :anubis_mcp] do
      {:ok, _} = Application.ensure_all_started(app)
    end

    :ok
  end

  defp provision(base) do
    case KomkiMediator.Templates.provision!(base) do
      :ok -> :ok
      :already_provisioned -> :ok
    end
  end

  # Den Fehlerfuehrenden Dateinamen davorgesetzt (registry.json /
  # room.json); das strukturierte Detail in JSON-wuerdiger Faessung bleibt
  # drin.
  defp tagged({:ok, value}, _file), do: {:ok, value}

  defp tagged({:error, reason}, file),
    do: {:error, %{"error" => file, "detail" => jsonable(reason)}}

  # -------------------------------------------------------------------------
  # Argumente (handgerollt, wie komki_policy)
  # -------------------------------------------------------------------------

  defp parse(["verify-journal" | rest]) do
    case parse_flags(rest, %{base: default_base(), port: @default_port}) do
      {:run, opts} -> {:verify_journal, opts}
      other -> other
    end
  end

  defp parse(argv) do
    parse_flags(argv, %{base: default_base(), port: @default_port})
  end

  defp parse_flags(["--help" | _rest], _acc), do: :help
  defp parse_flags(["--version" | _rest], _acc), do: :version

  defp parse_flags(["--base", value | rest], acc),
    do: parse_flags(rest, Map.put(acc, :base, value))

  defp parse_flags(["--connectors-dir", value | rest], acc),
    do: parse_flags(rest, Map.put(acc, :connectors_dir, value))

  defp parse_flags(["--port", value | rest], acc) do
    case Integer.parse(value) do
      {port, ""} when port > 0 and port <= 65_535 ->
        parse_flags(rest, Map.put(acc, :port, port))

      _ ->
        {:error, "--port erwartet eine ganzzahlige Portnummer (1..65535), erhalten: " <> value}
    end
  end

  defp parse_flags([element | _rest], _acc),
    do: {:error, "unerwartetes Argument: " <> Kernel.inspect(element)}

  defp parse_flags([], acc), do: {:run, acc}

  defp default_base do
    System.get_env("KOMKI_HOME") || Path.join(System.user_home!(), ".local/share/komki")
  end

  # -------------------------------------------------------------------------
  # Ausgaben und Pfade
  # -------------------------------------------------------------------------

  defp mediator_dir(base), do: Path.join(base, "mediator")

  defp connectors_dir(%{connectors_dir: dir}), do: dir
  defp connectors_dir(%{base: base}), do: Path.join([base, "run", "connectors"])

  defp journal_path(base), do: Path.join([mediator_dir(base), "journal", "pdr.jsonl"])

  defp startup_note(base, port, gamma) do
    JSON.encode!(%{
      "base" => base,
      "port" => port,
      "fassung_id" => KomkiMediator.Fassung.fassung_id(),
      "registry_id" => gamma.registry_id
    })
  end

  defp error_exit(reason) do
    IO.puts(:stderr, JSON.encode!(error_payload(reason)))
    halt(1)
  end

  defp error_payload(%{"error" => _} = map), do: map
  defp error_payload(reason), do: %{"error" => "startup", "detail" => reason}

  # JSON-wuerdige Faessung von strukturierten Fehlergruenden (POSIX-Tupel
  # sind nicht kodierbar; Atome werden Strings).
  defp jsonable(value) when is_boolean(value) or is_number(value), do: value
  defp jsonable(value) when is_binary(value), do: value
  defp jsonable(nil), do: nil
  defp jsonable(value) when is_atom(value), do: Atom.to_string(value)
  defp jsonable(value) when is_tuple(value), do: Kernel.inspect(value)
  defp jsonable(value) when is_list(value), do: Enum.map(value, &jsonable/1)

  defp jsonable(value) when is_map(value) do
    Map.new(value, fn {key, inner} -> {to_string(key), jsonable(inner)} end)
  end

  # Der Start blockiert ewig (Process.sleep(:infinity)) oder haelt ueber
  # error_exit — beide Pfade sind bewusst ohne lokalen Rueckkehr, fuer
  # dialyzer vermerkt.
  @dialyzer {:nowarn_function, run: 1, error_exit: 1, halt: 1, verify_journal: 1}
  defp halt(code), do: System.halt(code)

  defp usage do
    """
    komki-mediator --base <dir> --port <n> [--connectors-dir <pfad>]
    komki-mediator verify-journal [--base <dir>]
    komki-mediator --help
    komki-mediator --version
    """
  end
end
