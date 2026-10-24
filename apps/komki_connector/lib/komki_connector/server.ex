defmodule KomkiConnector.Server do
  @moduledoc """
  Connector-Seite des Frame-Protokolls (CONTRACT.md §3, §4).

  Ein Connector implementiert das Behaviour und ruft `run/3` aus seinem
  Escript-Einstieg auf:

      creds = KomkiConnector.Server.read_credentials()
      KomkiConnector.Server.run(MyConnector, socket_path, init_arg)

  `run/3` bindet den Unix-Socket (Datei danach `0600`), nimmt
  Verbindungen an und beantwortet je Verbindung genau eine Anfrage. Die
  reservierte Operation `ping` beantwortet der Server selbst aus dem
  Manifest. Parameter werden vor `handle_op/4` gegen das Manifest-Schema
  geprueft (`KomkiConnector.Params`) — ein Connector sieht nie
  ungepruefte Argumente.
  """

  require Logger

  alias KomkiConnector.{Frame, Manifest, Params}

  @recv_timeout 15_000

  @doc ~s(Manifest-ID des Connectors: "ris", "web" oder "vault".)
  @callback manifest_id() :: String.t()

  @doc "Zustand aus dem Init-Argument (Credentials, Optionen) aufbauen."
  @callback init(term()) :: {:ok, term()} | {:error, String.t()}

  @doc "Eine gepruefte Operation ausfuehren."
  @callback handle_op(op :: String.t(), params :: map(), context :: map(), state :: term()) ::
              {:ok, map()} | {:error, String.t(), String.t()}

  @doc """
  Liest genau eine JSON-Zeile mit Credentials von stdin (CONTRACT.md §4).
  Leere Eingabe ergibt `%{}`. Werte muessen Strings sein.
  """
  @spec read_credentials(IO.device()) :: {:ok, %{String.t() => String.t()}} | {:error, String.t()}
  def read_credentials(device \\ :stdio) do
    case IO.read(device, :eof) do
      :eof -> {:ok, %{}}
      {:error, reason} -> {:error, "stdin: #{inspect(reason)}"}
      data -> parse_credentials(String.trim(IO.iodata_to_binary(data)))
    end
  end

  defp parse_credentials(""), do: {:ok, %{}}

  defp parse_credentials(line) do
    case safe_json(line) do
      {:ok, map} when is_map(map) -> string_map(map)
      _ -> {:error, "Credentials sind kein JSON-Objekt"}
    end
  end

  defp string_map(map) do
    if Enum.all?(map, fn {k, v} -> is_binary(k) and is_binary(v) end),
      do: {:ok, map},
      else: {:error, "Credentials muessen String-Werte sein"}
  end

  defp safe_json(line) do
    {:ok, :json.decode(line)}
  rescue
    _ -> :error
  end

  @doc """
  Bindet den Socket und bedient Anfragen, bis der Prozess beendet wird.
  Mit `opts[:once]` (Tests) kehrt `listen/3` mit dem Listener zurueck,
  statt zu blockieren — dann `serve/3` selbst aufrufen.
  """
  @spec run(module(), Path.t(), term()) :: no_return() | {:error, term()}
  def run(module, socket_path, init_arg) do
    with {:ok, state} <- module.init(init_arg),
         {:ok, listener} <- listen(socket_path) do
      Logger.info("connector #{module.manifest_id()} lauscht auf #{socket_path}")
      accept_loop(listener, module, state)
    end
  end

  @doc "Socket binden (stale Datei wird entfernt), Rechte auf 0600 setzen."
  @spec listen(Path.t()) :: {:ok, port()} | {:error, term()}
  def listen(socket_path) do
    _ = File.rm(socket_path)

    opts = [{:ifaddr, {:local, String.to_charlist(socket_path)}} | Frame.socket_opts()]

    with {:ok, listener} <- :gen_tcp.listen(0, opts),
         :ok <- File.chmod(socket_path, 0o600) do
      {:ok, listener}
    end
  end

  @doc "Annahmeschleife: je Verbindung ein Prozess, eine Anfrage."
  @spec accept_loop(port(), module(), term()) :: no_return()
  def accept_loop(listener, module, state) do
    case :gen_tcp.accept(listener) do
      {:ok, sock} ->
        {:ok, pid} = Task.start(fn -> serve(sock, module, state) end)
        _ = :gen_tcp.controlling_process(sock, pid)
        accept_loop(listener, module, state)

      {:error, :closed} ->
        exit(:normal)

      {:error, reason} ->
        Logger.error("accept fehlgeschlagen: #{inspect(reason)}")
        accept_loop(listener, module, state)
    end
  end

  @doc "Eine Verbindung bedienen: Anfrage lesen, beantworten, schliessen."
  @spec serve(port(), module(), term()) :: :ok
  def serve(sock, module, state) do
    started = System.monotonic_time(:millisecond)

    reply =
      case :gen_tcp.recv(sock, 0, @recv_timeout) do
        {:ok, bin} -> handle_frame(bin, module, state)
        {:error, _} -> nil
      end

    if reply do
      bin =
        case Frame.encode(reply) do
          {:ok, bin} ->
            bin

          {:error, :too_large} ->
            {:ok, bin} =
              Frame.encode(Frame.error(reply["call_id"], "too-large", "Antwort > 1 MiB"))

            bin
        end

      _ = :gen_tcp.send(sock, bin)
      log(module, reply, started)
    end

    :gen_tcp.close(sock)
  end

  @doc false
  # Oeffentlich fuer Tests: ein Frame (Binary) zur Antwort-Map.
  @spec handle_frame(binary(), module(), term()) :: map()
  def handle_frame(bin, module, state) do
    with {:ok, frame} <- Frame.decode(bin),
         {:ok, call_id, op, params, context} <- shape(frame) do
      dispatch(module, call_id, op, params, context, state)
    else
      {:error, :bad_frame} -> Frame.error("", "bad-request", "ungueltiger Frame")
      {:error, call_id, detail} -> Frame.error(call_id, "bad-request", detail)
    end
  end

  defp shape(%{"call_id" => call_id, "op" => op, "params" => params} = frame)
       when is_binary(call_id) and is_binary(op) and is_map(params) do
    case Map.get(frame, "context", %{}) do
      context when is_map(context) -> {:ok, call_id, op, params, context}
      _ -> {:error, call_id, "context muss ein Objekt sein"}
    end
  end

  defp shape(frame), do: {:error, to_string(frame["call_id"] || ""), "Frame-Felder fehlen"}

  defp dispatch(module, call_id, "ping", _params, _context, _state) do
    manifest = Manifest.fetch!(module.manifest_id())

    Frame.ok(call_id, %{"fassung" => manifest.fassung, "ops" => Enum.sort(Map.keys(manifest.ops))})
  end

  defp dispatch(module, call_id, op, params, context, state) do
    manifest = Manifest.fetch!(module.manifest_id())

    with {:ok, spec} <- fetch_op(manifest, op),
         {:ok, checked} <- Params.check(spec.params, params) do
      run_op(module, call_id, op, checked, context, state)
    else
      {:error, :unknown_op} -> Frame.error(call_id, "unknown-op", "unbekannte Operation: #{op}")
      {:error, {:params, detail}} -> Frame.error(call_id, "bad-request", detail)
    end
  end

  defp fetch_op(manifest, op) do
    case Map.fetch(manifest.ops, op) do
      {:ok, spec} -> {:ok, spec}
      :error -> {:error, :unknown_op}
    end
  end

  defp run_op(module, call_id, op, params, context, state) do
    case module.handle_op(op, params, context, state) do
      {:ok, result} when is_map(result) -> Frame.ok(call_id, result)
      {:error, code, detail} -> Frame.error(call_id, code, detail)
    end
  rescue
    e ->
      Logger.error("handle_op #{op} abgestuerzt: #{Exception.message(e)}")
      Frame.error(call_id, "internal", "interner Fehler")
  end

  # Log ohne Payload: Operation (aus call_id nicht ableitbar), Ergebnis, Dauer.
  defp log(module, reply, started) do
    ms = System.monotonic_time(:millisecond) - started
    outcome = if reply["ok"], do: "ok", else: get_in(reply, ["error", "code"])

    Logger.info(
      "connector=#{module.manifest_id()} call=#{reply["call_id"]} outcome=#{outcome} ms=#{ms}"
    )
  end
end
