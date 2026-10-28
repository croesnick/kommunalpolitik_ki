defmodule KomkiConnector.Client do
  @moduledoc """
  Vermittler-Seite des Frame-Protokolls: eine Verbindung je Aufruf
  (verbinden, eine Anfrage, eine Antwort, schliessen). Timeout 15 s
  (CONTRACT.md §3).

  Das Token des Connectors liest der Client je Aufruf aus der Datei neben
  dem Socket (`KomkiConnector.Token.for_socket/1`); ein neu gestarteter
  Connector bringt so ohne Neustart des Vermittlers sein neues Token mit.

  Fehlertexte eines Connectors gelangen nie weiter: Der Client ersetzt sie
  durch den festen Text des Fehlercodes (`KomkiConnector.Frame.describe/1`).
  Sonst waere der Freitext ein Kanal am Gate 2 vorbei in den Modellkontext.
  """

  alias KomkiConnector.{Frame, Token}

  @default_timeout 15_000

  @type reply :: {:ok, map()} | {:error, %{String.t() => String.t()}}

  @doc """
  Fuehrt einen Aufruf gegen den Connector-Socket aus. Liefert
  `{:ok, result}` oder `{:error, %{"code" => ..., "detail" => ...}}` —
  Transportfehler werden auf die geschlossenen Fehlercodes abgebildet.
  """
  @spec call(Path.t(), String.t(), String.t(), map(), map(), keyword()) :: reply()
  def call(socket_path, call_id, op, params, context \\ %{}, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    deadline = System.monotonic_time(:millisecond) + timeout

    with {:ok, sock} <- connect(socket_path, timeout) do
      try do
        with {:ok, token} <- token(socket_path),
             {:ok, frame} <- encode(Frame.request(token, call_id, op, params, context)) do
          exchange(sock, frame, call_id, remaining(deadline))
        end
      after
        :gen_tcp.close(sock)
      end
    end
  end

  defp token(socket_path) do
    case Token.read(Token.for_socket(socket_path)) do
      {:ok, token} -> {:ok, token}
      :error -> err("unauthorized", "Connector-Token fehlt")
    end
  end

  defp encode(map) do
    case Frame.encode(map) do
      {:ok, bin} -> {:ok, bin}
      {:error, :too_large} -> err("too-large", "Anfrage ueberschreitet 1 MiB")
    end
  end

  defp connect(path, timeout) do
    case :gen_tcp.connect({:local, String.to_charlist(path)}, 0, Frame.socket_opts(), timeout) do
      {:ok, sock} -> {:ok, sock}
      {:error, :timeout} -> err("upstream-timeout", "Connector antwortet nicht")
      {:error, reason} -> err("upstream-error", "Connector nicht erreichbar: #{inspect(reason)}")
    end
  end

  defp exchange(sock, frame, call_id, timeout) do
    with :ok <- send_frame(sock, frame),
         {:ok, bin} <- recv(sock, timeout),
         {:ok, reply} <- decode(bin) do
      interpret(reply, call_id)
    end
  end

  defp send_frame(sock, frame) do
    case :gen_tcp.send(sock, frame) do
      :ok -> :ok
      {:error, reason} -> err("upstream-error", "Senden fehlgeschlagen: #{inspect(reason)}")
    end
  end

  defp recv(sock, timeout) do
    case :gen_tcp.recv(sock, 0, max(timeout, 0)) do
      {:ok, bin} -> {:ok, bin}
      {:error, :timeout} -> err("upstream-timeout", "Connector-Antwort nach Timeout")
      {:error, reason} -> err("upstream-error", "Empfang fehlgeschlagen: #{inspect(reason)}")
    end
  end

  defp decode(bin) do
    case Frame.decode(bin) do
      {:ok, reply} -> {:ok, reply}
      {:error, :bad_frame} -> err("upstream-error", "ungueltiger Antwort-Frame")
    end
  end

  # Die Antwort muss zur eigenen call_id gehoeren; sonst ist sie nicht
  # zuordenbar und wird verworfen (fail-closed).
  defp interpret(%{"call_id" => call_id, "ok" => true, "result" => result}, call_id)
       when is_map(result),
       do: {:ok, result}

  defp interpret(
         %{"call_id" => call_id, "ok" => false, "error" => %{"code" => code}},
         call_id
       )
       when is_binary(code) do
    code = if code in Frame.error_codes(), do: code, else: "internal"
    {:error, %{"code" => code, "detail" => Frame.describe(code)}}
  end

  # Abweisung ohne Token: der Connector nennt bewusst keine call_id.
  defp interpret(%{"call_id" => "", "ok" => false, "error" => %{"code" => "unauthorized"}}, _),
    do: err("unauthorized", Frame.describe("unauthorized"))

  defp interpret(_reply, _call_id), do: err("upstream-error", "Antwort passt nicht zur Anfrage")

  defp remaining(deadline), do: deadline - System.monotonic_time(:millisecond)

  defp err(code, detail), do: {:error, %{"code" => code, "detail" => detail}}
end
