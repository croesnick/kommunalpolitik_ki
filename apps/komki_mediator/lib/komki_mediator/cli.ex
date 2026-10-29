defmodule KomkiMediator.CLI do
  @moduledoc """
  Escript-Einstiegspunkt `komki-mediator`: stellt fehlende Aufstellung
  bereit, laedt Gamma und Raum und startet Vermittlung + Socket-Listener.

      komki-mediator --base <dir> [--socket <pfad>] [--token-file <pfad>] [--connectors-dir <pfad>]
      komki-mediator verify-journal [--base <dir>]
      komki-mediator --help
      komki-mediator --version

  * `--base`       (Default: KOMKI_HOME oder ~/.local/share/komki)
  * `--socket`     (Default: `<base>/run/mediator.sock`) — der einzige
    Listener (Unix-Socket, Rechte 0600; Ticket #143, CONTRACT §8)
  * `--token-file` (Default: `<base>/run/mediator.token`) — 64 Hex-Zeichen,
    geschrieben von `komki up`. Fehlt die Datei oder ist sie ungueltig,
    verweigert der Vermittler den Start (fail-closed). Das Token steht nie
    in argv.
  * `--connectors-dir` Verzeichnis der Connector-Sockets `<id>.sock`
    (Default: `<base>/run/connectors`, Connector-Vertrag §2)
  * `--version` gibt die Fassung "komki-mediator/3" aus.

  Bedient schon ein anderer Prozess den Socket, verweigert der Start; eine
  verwaiste Socket-Datei wird ersetzt.

  Bei schlechten Argumenten oder Ladefehlern erscheint eine einzeilige
  JSON-Fehlermeldung auf stderr und Exit 1. Nach dem Start kommt eine
  einzeilige Startnotiz (Socket, Fassung, registry_id) auf stdout; danach
  blockiert der Escript ewig (er stirbt, wenn die Hauptschleife
  zurueckkehren wuerde).

  Credentials: der MVP ist ohne Zugangsdaten; die Architektur haelt
  zukuenftige Connector-Credentials ausschliesslich im Vermittlerprozess
  (Zustand) - nie in der mcp.json von pi, nie in Tool-Antworten.
  """

  alias KomkiMediator.{Gamma, Room}

  # So lange wartet eine blockierte Ausgabe auf `komki go` (Ticket #98);
  # danach bleibt es beim deny.
  @go_timeout_ms 120_000

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

  defp run(%{base: base} = opts) do
    socket = Map.get(opts, :socket) || Path.join([base, "run", "mediator.sock"])
    token_file = Map.get(opts, :token_file) || Path.join([base, "run", "mediator.token"])

    with {:ok, token} <- load_token(token_file),
         :ok <- socket_free(socket),
         :ok <- quiet_logging(),
         :ok <- ensure_runtime_apps(),
         :ok <- provision(base),
         {:ok, gamma} <-
           tagged(Gamma.load(Path.join(mediator_dir(base), "registry.json")), "registry.json"),
         {:ok, room} <- tagged(Room.load(mediator_dir(base)), "room.json") do
      {:ok, _} =
        KomkiMediator.Supervisor.start_link(
          {{journal_path(base), append_only: true}, gamma, room,
           %{
             socket: socket,
             token: token,
             connectors_dir: connectors_dir(opts),
             go: %{dir: Path.join(mediator_dir(base), "go"), timeout_ms: @go_timeout_ms}
           }}
        )

      IO.puts(startup_note(base, socket, gamma))
      Process.sleep(:infinity)
    else
      {:error, reason} -> error_exit(reason)
    end
  end

  defp connectors_dir(%{connectors_dir: dir}), do: dir
  defp connectors_dir(%{base: base}), do: Path.join([base, "run", "connectors"])

  @doc """
  Liest das Kanal-Token (Ticket #143): genau 64 Hex-Zeichen (klein), ein
  abschliessender Zeilenumbruch ist erlaubt. Fehler nennen den Pfad, nie
  den Inhalt.
  """
  @spec load_token(Path.t()) :: {:ok, String.t()} | {:error, map()}
  def load_token(path) do
    case File.read(path) do
      {:ok, content} ->
        token = String.trim_trailing(content, "\n")

        if Regex.match?(~r/\A[0-9a-f]{64}\z/, token),
          do: {:ok, token},
          else: {:error, %{"error" => "token", "detail" => "ungueltiges Token in " <> path}}

      {:error, reason} ->
        {:error,
         %{
           "error" => "token",
           "detail" => path <> ": " <> List.to_string(:file.format_error(reason))
         }}
    end
  end

  @doc "Verweigert, wenn ein anderer Prozess den Socket bedient; eine verwaiste Datei ist frei."
  @spec socket_free(Path.t()) :: :ok | {:error, map()}
  def socket_free(socket) do
    case :gen_tcp.connect({:local, socket}, 0, [:binary, active: false], 1000) do
      {:ok, conn} ->
        :gen_tcp.close(conn)
        {:error, %{"error" => "socket", "detail" => "bereits in Benutzung: " <> socket}}

      {:error, _reason} ->
        :ok
    end
  end

  @doc """
  Haelt Tool-Argumente und -Ergebnisse aus dem Log (Ticket #185): anubis
  schreibt auf `debug` jede MCP-Nachricht vollstaendig mit, und ohne
  Konfiguration gilt Elixirs Standard-Level `:debug`. Der Vermittler
  schaltet das Protokoll-Logging von anubis ab und hebt das Level auf
  `:info`; die eigenen Logzeilen (etwa 401) nennen nie Inhalte.
  """
  @spec quiet_logging() :: :ok
  def quiet_logging do
    Application.put_env(:anubis_mcp, :log, false)
    Logger.configure(level: :info)
  end

  defp ensure_runtime_apps do
    for app <- [:bandit, :anubis_mcp] do
      {:ok, _} = Application.ensure_all_started(app)
    end

    :ok
  end

  defp provision(base) do
    case KomkiMediator.Templates.provision!(base) do
      :ok ->
        :ok

      :already_provisioned ->
        :ok

      {:migrated, what} ->
        IO.puts(:stderr, JSON.encode!(%{"note" => "Vorlagen aktualisiert", "detail" => what}))
        :ok
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
    case parse_flags(rest, %{base: default_base()}) do
      {:run, opts} -> {:verify_journal, opts}
      other -> other
    end
  end

  defp parse(argv) do
    parse_flags(argv, %{base: default_base()})
  end

  defp parse_flags(["--help" | _rest], _acc), do: :help
  defp parse_flags(["--version" | _rest], _acc), do: :version

  defp parse_flags(["--base", value | rest], acc),
    do: parse_flags(rest, Map.put(acc, :base, value))

  defp parse_flags(["--socket", value | rest], acc),
    do: parse_flags(rest, Map.put(acc, :socket, value))

  defp parse_flags(["--token-file", value | rest], acc),
    do: parse_flags(rest, Map.put(acc, :token_file, value))

  defp parse_flags(["--connectors-dir", value | rest], acc),
    do: parse_flags(rest, Map.put(acc, :connectors_dir, value))

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

  defp journal_path(base), do: Path.join([mediator_dir(base), "journal", "pdr.jsonl"])

  defp startup_note(base, socket, gamma) do
    JSON.encode!(%{
      "base" => base,
      "socket" => socket,
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
    komki-mediator --base <dir> [--socket <pfad>] [--token-file <pfad>]
    komki-mediator verify-journal [--base <dir>]
    komki-mediator --help
    komki-mediator --version
    """
  end
end
