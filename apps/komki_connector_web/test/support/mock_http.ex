defmodule KomkiConnectorWeb.MockHttp do
  @moduledoc """
  Minimaler HTTP/1.1-Server fuer Tests (nur OTP, `:gen_tcp` auf
  127.0.0.1). Je Verbindung eine Anfrage: die geparste Anfrage geht als
  `{:mock_request, req}` an den Test-Prozess, die Antwort liefert der
  Responder (`{status, body}` oder `:hang` fuer Timeouts). Mit
  `raw: true` wird nur die erste Zeile gemeldet und die Verbindung
  geschlossen (Proxy-Attrappe fuer CONNECT).
  """

  @doc "Startet den Server; liefert `{port, stop_fun}`."
  def start(responder, opts \\ []) do
    owner = self()

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

    {:ok, port} = :inet.port(listener)
    pid = spawn(fn -> loop(listener, owner, responder, opts) end)
    :ok = :gen_tcp.controlling_process(listener, pid)
    {port, fn -> Process.exit(pid, :kill) end}
  end

  defp loop(listener, owner, responder, opts) do
    case :gen_tcp.accept(listener) do
      {:ok, sock} ->
        child = spawn(fn -> handle(sock, owner, responder, opts) end)
        _ = :gen_tcp.controlling_process(sock, child)
        loop(listener, owner, responder, opts)

      {:error, _} ->
        :ok
    end
  end

  defp handle(sock, owner, responder, opts) do
    head = read_head(sock, "")
    req = parse(head)
    send(owner, {:mock_request, req})

    if opts[:raw] do
      :gen_tcp.close(sock)
    else
      respond(sock, responder.(req))
    end
  end

  defp read_head(sock, acc) do
    if String.contains?(acc, "\r\n\r\n") do
      acc
    else
      case :gen_tcp.recv(sock, 0, 5_000) do
        {:ok, data} -> read_head(sock, acc <> data)
        {:error, _} -> acc
      end
    end
  end

  defp parse(head) do
    [line | header_lines] = head |> String.split("\r\n\r\n") |> hd() |> String.split("\r\n")
    [method, target | _] = String.split(line, " ")

    headers =
      Map.new(header_lines, fn h ->
        [k, v] = String.split(h, ":", parts: 2)
        {String.downcase(k), String.trim(v)}
      end)

    %{method: method, target: target, headers: headers, line: line}
  end

  defp respond(sock, :hang) do
    Process.sleep(5_000)
    :gen_tcp.close(sock)
  end

  defp respond(sock, {status, body}) do
    resp =
      "HTTP/1.1 #{status} X\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
        body

    :ok = :gen_tcp.send(sock, resp)
    :gen_tcp.close(sock)
  end
end
