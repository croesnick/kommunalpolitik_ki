defmodule WegwerfHub.Durchstich.Stack do
  @moduledoc """
  DURCHSTICH #409 (Wegwerf, nie gemergt): Die Prozessstange des
  Durchstichs — Wegwerf-Instanz (KOMKI_HOME), Wegwerf-Hub und der
  ratsprojekte-Connector als Rolle des komki-Escripts, gestartet wie
  `komki up` es täte, nur ohne llama, pi und Egress (der geskriptete
  Agent ersetzt pi). Dazu der MCP-Fähnchenfahrer über den
  Vermittler-Socket (Initialize, Session-Kopf, tools/call — wie
  `komki-relay.js`), die GO-Gegenseite (Herzschlag, Antwortdateien mit
  `KomkiMediator.Go`) und der Journal-Leser.

  Nichts davon berührt die echte Instanz unter ~/.local/share/komki:
  Basis ist immer das Wegwerf-Verzeichnis.
  """

  alias KomkiMediator.Journal
  alias KomkiPolicy.JSON

  @http_timeout 200_000
  @ready_timeout 15_000
  @call_timeout 140_000

  @type t :: %{
          base: Path.t(),
          hub_dir: Path.t(),
          med_socket: Path.t(),
          med_token: String.t(),
          conn_token: String.t(),
          hub_token: String.t(),
          hub_socket: Path.t(),
          komki: Path.t(),
          hub_bin: Path.t(),
          go_dir: Path.t(),
          journal: Path.t(),
          pids: %{optional(atom()) => pos_integer()},
          logs: %{optional(atom()) => Path.t()},
          mcp_session: String.t() | nil,
          rpc_id: integer()
        }

  # Escrips aus dem Zweig-Bestand (mix run läuft im App-Verzeichnis).
  @komki_escript Path.expand("../../../../komki_cli/komki", __DIR__)
  @hub_escript Path.expand("../../../wegwerf-hub", __DIR__)

  # ---------------------------------------------------------------------------
  # Verzeichnisse, Tokens, Boot
  # ---------------------------------------------------------------------------

  @doc "Frischer Wegwerf-Bestand: altes weg, Verzeichnisse und Tokens hin."
  @spec frisch(Path.t(), Path.t()) :: t()
  def frisch(base, hub_dir) do
    journal = Path.join([base, "mediator", "journal", "pdr.jsonl"])
    if File.exists?(journal), do: System.cmd("/usr/bin/chflags", ["nouappnd", journal])
    File.rm_rf(base)
    File.rm_rf(hub_dir)

    File.mkdir_p!(Path.join([base, "run", "connectors"]))
    File.mkdir_p!(Path.join([base, "mediator"]))
    File.mkdir_p!(Path.join([base, "tmp"]))
    File.mkdir_p!(hub_dir)

    File.chmod!(Path.join([base, "run"]), 0o700)
    File.chmod!(Path.join([base, "run", "connectors"]), 0o700)
    File.chmod!(hub_dir, 0o700)

    med_token = token()
    conn_token = token()
    hub_token = token()

    # KEIN Zeilenumbruch: die CLI-Seite (Channel) toleriert ihn nicht.
    File.write!(Path.join([base, "run", "mediator.token"]), med_token)
    File.write!(Path.join([base, "run", "connectors", "ratsprojekte.token"]), conn_token)
    File.chmod!(Path.join([base, "run", "mediator.token"]), 0o600)
    File.chmod!(Path.join([base, "run", "connectors", "ratsprojekte.token"]), 0o600)

    # Der Hub kennt nur den Hash (#415); der Klartext reist in der
    # stdin-Zeile des Connectors. Hier spielt die Bootschrift die Rolle
    # des token-erzeugenden komki.
    hash = Base.encode16(:crypto.hash(:sha256, hub_token), case: :lower)
    File.write!(Path.join(hub_dir, "token-hash"), hash)
    File.chmod!(Path.join(hub_dir, "token-hash"), 0o600)

    %{
      base: base,
      hub_dir: hub_dir,
      med_socket: Path.join([base, "run", "mediator.sock"]),
      med_token: med_token,
      conn_token: conn_token,
      hub_token: hub_token,
      hub_socket: Path.join(hub_dir, "hub.sock"),
      komki: @komki_escript,
      hub_bin: @hub_escript,
      go_dir: Path.join([base, "mediator", "go"]),
      journal: journal,
      pids: %{},
      logs: %{},
      mcp_session: nil,
      rpc_id: 0
    }
  end

  defp token, do: Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)

  @doc "Hub, Connector und Vermittler starten, auf Bereitschaft warten."
  @spec boot(t()) :: t()
  def boot(st) do
    {st, hub_pid} = spawn_log(st, st.hub_bin, ["--dir", st.hub_dir, "serve"], :hub)
    wait_log!(st, :hub, "lauscht auf", "wegwerf-hub")

    # Credentials als 0600-Datei an stdin — nie argv, nie Umgebung, nie
    # ps. Die Datei verschwindet, sobald der Connector gelesen hat.
    creds =
      Jason.encode!(%{
        "KOMKI_CONNECTOR_TOKEN" => st.conn_token,
        "KOMKI_HUB_TOKEN" => st.hub_token
      }) <> "\n"

    creds_file = Path.join([st.base, "tmp", "connector-creds.json"])
    File.write!(creds_file, creds)
    File.chmod!(creds_file, 0o600)

    {st, conn_pid} =
      spawn_log(
        st,
        st.komki,
        [
          "komki-connector-ratsprojekte",
          "--socket",
          Path.join([st.base, "run", "connectors", "ratsprojekte.sock"]),
          "--hub-socket",
          st.hub_socket
        ],
        :conn,
        creds_file
      )

    wait_log!(st, :conn, "listening on", "ratsprojekte-Connector")
    File.rm!(creds_file)

    st = boot_mediator(st)
    wait_healthz!(st)

    mcp_initialize(%{st | pids: Map.merge(st.pids, %{hub: hub_pid, conn: conn_pid})})
  end

  @doc "Vermittler (neu) starten — auch für Raumwechsel (room.json vorher schreiben)."
  @spec boot_mediator(t()) :: t()
  def boot_mediator(st) do
    {st, pid} = spawn_log(st, st.komki, ["komki-mediator", "--base", st.base], :mediator)
    wait_log!(st, :mediator, "fassung_id", "Vermittler")
    %{st | pids: Map.put(st.pids, :mediator, pid), mcp_session: nil}
  end

  @doc "Vermittler stoppen (SIGTERM, wie komki down)."
  @spec stop_mediator(t()) :: t()
  def stop_mediator(st) do
    kill(st.pids[:mediator])
    %{st | pids: Map.delete(st.pids, :mediator)}
  end

  @doc "Hub stoppen und neu starten (11.13b)."
  @spec restart_hub(t()) :: t()
  def restart_hub(st) do
    kill(st.pids[:hub])

    {st, pid} = spawn_log(st, st.hub_bin, ["--dir", st.hub_dir, "serve"], :hub)
    wait_log!(st, :hub, "lauscht auf", "wegwerf-hub")
    %{st | pids: Map.put(st.pids, :hub, pid)}
  end

  @doc "Alle Prozesse stoppen (SIGTERM)."
  @spec shutdown(t()) :: :ok
  def shutdown(st) do
    Enum.each(st.pids, fn {_name, pid} -> kill(pid) end)
    :ok
  end

  defp kill(nil), do: :ok

  defp kill(pid) do
    _ = System.cmd("/bin/kill", ["-TERM", Integer.to_string(pid)], stderr_to_stdout: true)
    warte_tot(pid, System.monotonic_time(:millisecond) + 5_000)
  end

  defp warte_tot(pid, deadline) do
    {_, code} = System.cmd("/bin/kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true)

    cond do
      code != 0 ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        _ = System.cmd("/bin/kill", ["-9", Integer.to_string(pid)], stderr_to_stdout: true)
        :ok

      true ->
        Process.sleep(100)
        warte_tot(pid, deadline)
    end
  end

  # nohup … & echo $! — wie KomkiCli.Proc.spawn_detached, nur ohne env -i:
  # Der Wegwerf läuft im selben Benutzerkonto wie die Bootschrift selbst.
  defp spawn_log(st, bin, args, name, stdin_file \\ nil) do
    log_file = Path.join([st.base, "tmp", "#{name}.log"])
    File.write!(log_file, "")

    line =
      "nohup " <>
        quote_bin(bin) <>
        " " <>
        Enum.map_join(args, " ", &quote_bin/1) <>
        if(stdin_file, do: " < " <> quote_bin(stdin_file), else: "") <>
        " > " <> quote_bin(log_file) <> " 2>&1 & echo $!"

    {out, 0} = System.cmd("/bin/sh", ["-c", line], cd: st.base)
    pid = out |> String.trim() |> String.to_integer()
    {put_in(st.logs[name], log_file), pid}
  end

  defp wait_log!(st, name, needle, wer) do
    log_file = st.logs[name]
    deadline = System.monotonic_time(:millisecond) + @ready_timeout

    unless wait_log(log_file, needle, deadline) do
      raise "Bootsstillstand: #{wer} meldet sich nicht (Log: #{log_file})"
    end
  end

  defp wait_log(log_file, needle, deadline) do
    content = if File.exists?(log_file), do: File.read!(log_file), else: ""

    cond do
      String.contains?(content, needle) -> true
      System.monotonic_time(:millisecond) > deadline -> false
      true -> Process.sleep(100) && wait_log(log_file, needle, deadline)
    end
  end

  defp wait_healthz!(st) do
    deadline = System.monotonic_time(:millisecond) + @ready_timeout

    unless healthz(st, deadline) do
      raise "Bootsstillstand: Vermittler antwortet nicht auf healthz"
    end
  end

  defp healthz(st, deadline) do
    case http(st.med_socket, "GET", "/healthz", bearer: st.med_token) do
      {200, _, body} ->
        unless String.contains?(body, "rp_fakt_vorschlagen") do
          raise "Vermittler ohne rp_fakt_vorschlagen — falscher komki-Bestand?"
        end

        true

      _ ->
        if System.monotonic_time(:millisecond) > deadline do
          false
        else
          Process.sleep(200)
          healthz(st, deadline)
        end
    end
  end

  # ---------------------------------------------------------------------------
  # HTTP über Unix-Socket (eine Anfrage, eine Antwort, schliessen)
  # ---------------------------------------------------------------------------

  @doc "Eine HTTP-Anfrage über den Unix-Socket; liest bis zum Socket-Ende."
  @spec http(Path.t(), String.t(), String.t(), keyword()) ::
          {pos_integer(), %{String.t() => String.t()}, String.t()}
  def http(socket, method, path, opts \\ []) do
    body = Keyword.get(opts, :body)
    bearer = Keyword.get(opts, :bearer)
    headers = Keyword.get(opts, :headers, [])
    session = Keyword.get(opts, :mcp_session)

    head =
      [
        "#{method} #{path} HTTP/1.1",
        "Host: localhost",
        "Connection: close"
      ] ++
        if(bearer, do: ["Authorization: Bearer " <> bearer], else: []) ++
        if(session, do: ["Mcp-Session-Id: " <> session], else: []) ++
        ["Accept: application/json, text/event-stream"] ++
        headers ++
        if(body,
          do: [
            "Content-Type: application/json",
            "Content-Length: " <> Integer.to_string(byte_size(body))
          ],
          else: []
        )

    request = Enum.join(head, "\r\n") <> "\r\n\r\n" <> (body || "")

    {:ok, sock} =
      :gen_tcp.connect({:local, socket}, 0, [:binary, packet: :raw, active: false], @http_timeout)

    :ok = :gen_tcp.send(sock, request)
    response = recv_all(sock)
    :ok = :gen_tcp.close(sock)
    parse_response(response)
  end

  defp recv_all(sock, acc \\ "") do
    case :gen_tcp.recv(sock, 0, @http_timeout) do
      {:ok, chunk} -> recv_all(sock, acc <> chunk)
      {:error, :closed} -> acc
      {:error, reason} -> raise "Socket-Lesefehler: #{inspect(reason)}"
    end
  end

  defp parse_response(response) do
    [head, body] = String.split(response, "\r\n\r\n", parts: 2)
    [status_line | header_lines] = String.split(head, "\r\n")
    status = status_line |> String.split(" ") |> Enum.at(1) |> String.to_integer()

    headers =
      Map.new(header_lines, fn line ->
        case String.split(line, ":", parts: 2) do
          [name, value] -> {String.downcase(String.trim(name)), String.trim(value)}
          _ -> {"", ""}
        end
      end)

    # SSE-Rümpfe (data:-Zeilen) wie JSON-RPC behandeln, wie das Relay.
    body =
      if String.contains?(Map.get(headers, "content-type", ""), "text/event-stream") do
        sse_daten(body)
      else
        body
      end

    {status, headers, body}
  end

  defp sse_daten(text) do
    text
    |> String.split("\r\n\r\n")
    |> Enum.flat_map(fn event ->
      event
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map(&String.trim_leading(&1, "data:"))
      |> Enum.reject(&(&1 == ""))
    end)
    |> Enum.join("\n")
  end

  # ---------------------------------------------------------------------------
  # MCP-Fähnchenfahrer (wie komki-relay.js: initialize, Session, tools/call)
  # ---------------------------------------------------------------------------

  @doc "Nach Vermittler-(Neu)start: Bereitschaft und MCP-Sitzung."
  @spec verbinden(t()) :: t()
  def verbinden(st) do
    wait_healthz!(st)
    mcp_initialize(st)
  end

  defp mcp_initialize(st) do
    {200, headers, body} =
      http(st.med_socket, "POST", "/mcp",
        bearer: st.med_token,
        body:
          Jason.encode!(%{
            "jsonrpc" => "2.0",
            "id" => 1,
            "method" => "initialize",
            "params" => %{
              "protocolVersion" => "2025-11-25",
              "capabilities" => %{},
              "clientInfo" => %{"name" => "durchstich-409", "version" => "0.1"}
            }
          })
      )

    session = Map.get(headers, "mcp-session-id")

    {202, _, _} =
      http(st.med_socket, "POST", "/mcp",
        bearer: st.med_token,
        mcp_session: session,
        body:
          Jason.encode!(%{
            "jsonrpc" => "2.0",
            "method" => "notifications/initialized",
            "params" => %{}
          })
      )

    if is_nil(session) or body == "", do: raise("MCP-Initialize gescheitert: #{body}")
    %{st | mcp_session: session, rpc_id: 2}
  end

  @doc "Ein tools/call gegen den Vermittler; Antwort ist das Gate-Ergebnis als Map."
  @spec tools_call(t(), String.t(), map(), String.t() | nil) :: {:ok, map()} | {:error, term()}
  def tools_call(st, tool, arguments, session \\ "durchstich-409") do
    body =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => System.unique_integer([:positive]),
        "method" => "tools/call",
        "params" => %{"name" => tool, "arguments" => arguments}
      })

    headers =
      if session,
        do: ["X-Komki-Session: " <> session, "Accept: application/json, text/event-stream"],
        else: ["Accept: application/json, text/event-stream"]

    {status, _, resp} =
      http(st.med_socket, "POST", "/mcp",
        bearer: st.med_token,
        mcp_session: st.mcp_session,
        headers: headers,
        body: body
      )

    case {status, JSON.parse(resp)} do
      {200, {:ok, %{"result" => %{"content" => [%{"text" => text} | _]}}}} ->
        case JSON.parse(text) do
          {:ok, term} when is_map(term) -> {:ok, term}
          _ -> {:error, {:kein_gate_json, text}}
        end

      {200, {:ok, %{"error" => error}}} ->
        {:error, error}

      {other, _} ->
        {:error, {:http, other, String.slice(resp, 0, 300)}}
    end
  end

  # ---------------------------------------------------------------------------
  # GO-Gegenseite: Herzschlag, Anfragen lesen, Antworten atomar schreiben
  # ---------------------------------------------------------------------------

  @doc "Herzschlag erneuern (jemand hört zu)."
  @spec zuhoeren(Path.t()) :: :ok
  def zuhoeren(go_dir) do
    File.mkdir_p!(go_dir)
    File.touch(Path.join(go_dir, "listener"))
    :ok
  end

  @doc "Offene, unquittierte Anfragen (Request-Datei da, Antwort fehlt)."
  @spec anstehende(Path.t()) :: [map()]
  def anstehende(go_dir) do
    go_dir
    |> Path.join("*.request.json")
    |> Path.wildcard()
    |> Enum.reject(fn path ->
      File.exists?(String.replace_suffix(path, ".request.json", ".answer.json"))
    end)
    |> Enum.map(fn path ->
      {:ok, request} = path |> File.read!() |> JSON.parse()
      request
    end)
  end

  @doc "GO erteilen: Freigabe `komki-release/1` atomar neben die Anfrage."
  @spec go_geben(Path.t(), map()) :: map()
  def go_geben(go_dir, request) do
    release = KomkiMediator.Go.release_for(request, System.os_time(:second))
    antwort(go_dir, request["call_hash"], release)
    release
  end

  @doc "Beliebiges Term als Antwortdatei schreiben (atomar)."
  @spec antwort(Path.t(), String.t(), map()) :: :ok
  def antwort(go_dir, call_hash, term) do
    KomkiMediator.Go.write_atomic(Path.join(go_dir, call_hash <> ".answer.json"), term)
  end

  @doc """
  Ein tools/call mit automatischer GO-Gegenseite: hält den Herzschlag
  frisch, beobachtet die GO-Anfragen dieses Aufrufs (erkannt am Titel
  des Vorschlags) und beantwortet jede neue Anfrage. `answer` ist eine
  Funktion von der Anfrage (Default: normales GO) oder ein festes Term
  (Verweigerung, Replay). `listener: false` lässt den Herzschlag weg —
  niemand hört zu. Ergebnis: {Antwort, gesehene Anfragen, gegebene Antworten}.
  """
  @spec aufruf_mit_go(t(), map(), keyword()) :: {map(), [map()], [map()]}
  def aufruf_mit_go(st, arguments, opts \\ []) do
    listener = Keyword.get(opts, :listener, true)
    answer = Keyword.get(opts, :answer)
    titel = get_in(arguments, ["titel"])

    if listener, do: zuhoeren(st.go_dir)

    caller = Task.async(fn -> tools_call(st, "rp_fakt_vorschlagen", arguments) end)

    {response, gesehen, antworten} =
      go_schleife(
        st,
        caller,
        titel,
        answer,
        listener,
        [],
        [],
        System.monotonic_time(:millisecond)
      )

    Task.shutdown(caller, :brutal_kill)
    {response, gesehen, antworten}
  end

  defp go_schleife(st, caller, titel, answer, listener, gesehen, antworten, start) do
    if listener, do: zuhoeren(st.go_dir)

    matching = anstehende_fuer(st, titel) -- gesehen

    {gesehen, antworten} =
      Enum.reduce(matching, {gesehen, antworten}, &beantworte(st, answer, &1, &2))

    case Task.yield(caller, 250) do
      {:ok, {:ok, response}} ->
        {response, Enum.reverse(gesehen), Enum.reverse(antworten)}

      {:ok, {:error, reason}} ->
        {{:error, reason}, Enum.reverse(gesehen), Enum.reverse(antworten)}

      {:exit, reason} ->
        raise "Aufruf gestorben: #{inspect(reason)}"

      nil ->
        if System.monotonic_time(:millisecond) - start > @call_timeout do
          raise "Zeitüberschreitung des Aufrufs (#{titel})"
        else
          go_schleife(st, caller, titel, answer, listener, gesehen, antworten, start)
        end
    end
  end

  defp beantworte(st, answer, request, {gesehen, antworten}) do
    term =
      cond do
        is_function(answer, 1) -> answer.(request)
        answer -> answer
        true -> KomkiMediator.Go.release_for(request, System.os_time(:second))
      end

    antwort(st.go_dir, request["call_hash"], term)
    {[request | gesehen], [term | antworten]}
  end

  defp anstehende_fuer(st, titel) do
    Enum.filter(anstehende(st.go_dir), fn request ->
      request["tool"] == "rp_fakt_vorschlagen" and request["params"]["titel"] == titel
    end)
  end

  # ---------------------------------------------------------------------------
  # Journal
  # ---------------------------------------------------------------------------

  @doc "Alle PDR-Datensätze, älteste zuerst."
  @spec journal(t()) :: [map()]
  def journal(st) do
    case File.read(st.journal) do
      {:ok, ""} ->
        []

      {:ok, raw} ->
        raw
        |> Journal.split_records()
        |> Enum.map(fn chunk ->
          {:ok, record} = JSON.parse(chunk)
          record
        end)

      {:error, _} ->
        []
    end
  end

  @doc "call_id des Aufrufs aus der Antwort (ausgeführt: Vorbeleg; sonst über die decision_id im Journal)."
  @spec call_id([map()], map()) :: String.t() | nil
  def call_id(records, response) do
    cond do
      is_binary(response["emit_decision_id"]) -> response["emit_decision_id"]
      is_binary(response["decision_id"]) -> finde_call_id(records, response["decision_id"])
      true -> nil
    end
  end

  defp finde_call_id(records, decision_id) do
    Enum.find_value(records, fn record ->
      if record["decision_id"] == decision_id, do: record["call_id"]
    end)
  end

  @doc "Die Datensätze eines Aufrufs (call_id gesetzt und passend), in Journalordnung."
  @spec datensaetze(t(), String.t() | nil) :: [map()]
  def datensaetze(st, nil), do: journal(st)

  def datensaetze(st, call_id) do
    Enum.filter(journal(st), &(&1["call_id"] == call_id))
  end

  @doc "Kurzform der Kette: [{rule, decision, outcome}]."
  @spec kette([map()]) :: [tuple()]
  def kette(records) do
    Enum.map(records, fn record -> {record["rule"], record["decision"], record["outcome"]} end)
  end

  # ---------------------------------------------------------------------------
  # Hub-Zugriff (direkt auf die Dateien des Wegwerf-Hubs)
  # ---------------------------------------------------------------------------

  @doc "Anzahl der beim Hub eingegangenen Connector-Anfragen."
  @spec hub_anfragen(t()) :: non_neg_integer()
  def hub_anfragen(st), do: WegwerfHub.Store.anfragen(st.hub_dir)

  @doc "POST gegen den Hub-Socket, wie der Connector ihn fährt (Default: mit Hub-Token)."
  @spec hub_post(t(), String.t(), map(), keyword()) :: {pos_integer(), String.t()}
  def hub_post(st, path, body, opts \\ []) do
    bearer = Keyword.get(opts, :bearer, st.hub_token)

    headers =
      [{"Content-Type", "application/json"}] ++
        if(bearer, do: [{"Authorization", "Bearer " <> bearer}], else: [])

    raw = Jason.encode!(body)

    request =
      "POST #{path} HTTP/1.1\r\nHost: localhost\r\n" <>
        Enum.map_join(headers, "\r\n", fn {k, v} -> k <> ": " <> v end) <>
        "\r\nContent-Length: " <>
        Integer.to_string(byte_size(raw)) <>
        "\r\nConnection: close\r\n\r\n" <> raw

    {:ok, sock} =
      :gen_tcp.connect({:local, st.hub_socket}, 0, [:binary, packet: :raw, active: false], 5_000)

    :ok = :gen_tcp.send(sock, request)
    response = recv_all(sock)
    :ok = :gen_tcp.close(sock)

    {status, _headers, resp} = parse_response(response)
    {status, resp}
  end

  defp quote_bin(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"
end
