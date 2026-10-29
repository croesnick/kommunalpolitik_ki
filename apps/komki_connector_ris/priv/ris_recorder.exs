# Aufzeichnungs-Proxy fuer die RIS-API (risapi1.komuna.net/web/).
#
#     elixir apps/komki_connector_ris/priv/ris_recorder.exs --port 4020 \
#       [--upstream https://risapi1.komuna.net/web/] [--out <verzeichnis>]
#
# Der Proxy nimmt Anfragen entgegen (komki-connector-ris mit --base-url
# http://127.0.0.1:4020/ oder ratsinfo mit RIS_BASE_URL=http://127.0.0.1:4020/),
# leitet sie 1:1 an das echte RIS weiter und schreibt jeden Austausch als
# Kassette: <out>/<nr>-<methode>-<pfad>.json mit Anfrage (Methode, Pfad,
# Query, Kopfzeilen) und Antwort (Status, Kopfzeilen, Body base64).
#
# Die Kassetten enthalten echte Daten und bleiben deshalb lokal
# (.gitignore: priv/cassettes/). Bestimmt redigiert, ohne jedes LLM:
# authorization-/cookie-Kopfzeilen, set-cookie sowie die Felder
# login/password/token/access_token/jwt in JSON-Bodies werden beim Schreiben
# durch "<redacted>" ersetzt. Dem Client und dem Upstream reicht der Proxy
# alles unveraendert durch — nur die Datei auf der Platte ist redigiert.
#
# Pfade ohne /web/-Praefix geben (Basis also http://127.0.0.1:<port>/, nicht
# .../<port>/web/); der Proxy ergaenzt den Praefix upstream-seitig.
# Zurueckspielen: priv/mock_ris.exs --port 4010 --mode replay --cassette <out>.
#
# Nur OTP (gen_tcp, httpc, ssl, json), keine Deps — wie mock_ris.exs.

defmodule KomkiConnectorRis.RisRecorder do
  @moduledoc false

  @redacted "<redacted>"
  @default_upstream "https://risapi1.komuna.net/web/"
  @profile :ris_recorder
  @timeout_ms 60_000

  # Hop-by-hop-Kopfzeilen und Rahmenfelder: weder aufzeichnen noch
  # weiterreichen (content-length wird aus dem Body neu gesetzt).
  @drop ~w(connection keep-alive proxy-authenticate proxy-authorization te trailer
          transfer-encoding upgrade accept-encoding host content-length)

  # Geheimnisse: Werte werden nur in der Kassette redigiert.
  @secret_request_headers ~w(authorization cookie proxy-authorization)
  @secret_response_headers ~w(set-cookie)
  @secret_request_body_keys ~w(login password token access_token jwt)
  @secret_response_body_keys ~w(token access_token jwt)

  @spec start(keyword()) :: {:ok, pid(), :inet.port_number(), String.t()} | {:error, term()}
  def start(opts \\ []) do
    port = Keyword.get(opts, :port, 0)
    upstream = Keyword.get(opts, :upstream, @default_upstream)
    out = Keyword.get(opts, :out) || default_out()
    File.mkdir_p!(out)

    with {:ok, _} <- Application.ensure_all_started([:inets, :ssl, :public_key]) do
      _ = :inets.stop(:httpc, @profile)
      {:ok, _pid} = :inets.start(:httpc, profile: @profile)

      parent = self()
      counter = :atomics.new(1, signed: false)

      pid =
        spawn(fn ->
          listen_opts = [
            :binary,
            packet: :http_bin,
            active: false,
            reuseaddr: true,
            ip: {127, 0, 0, 1}
          ]

          case :gen_tcp.listen(port, listen_opts) do
            {:ok, listener} ->
              {:ok, actual} = :inet.port(listener)
              send(parent, {:ris_recorder, self(), {:ok, actual}})
              accept_loop(listener, upstream, out, counter)

            {:error, reason} ->
              send(parent, {:ris_recorder, self(), {:error, reason}})
          end
        end)

      receive do
        {:ris_recorder, ^pid, {:ok, actual}} -> {:ok, pid, actual, out}
        {:ris_recorder, ^pid, {:error, reason}} -> {:error, reason}
      after
        5_000 -> {:error, :timeout}
      end
    end
  end

  @spec stop(pid()) :: true
  def stop(pid), do: Process.exit(pid, :kill)

  @doc "Ersetzt die Werte der Kopfzeilen in `secret` durch \"<redacted>\"."
  @spec scrub_headers([{String.t(), String.t()}], [String.t()]) :: [{String.t(), String.t()}]
  def scrub_headers(headers, secret) do
    for {name, value} <- headers do
      if name in secret, do: {name, @redacted}, else: {name, value}
    end
  end

  @doc "Ersetzt binaere Werte der Schluessel `keys` rekursiv durch \"<redacted>\"."
  @spec redact_json(term(), [String.t()]) :: term()
  def redact_json(map, keys) when is_map(map) do
    Map.new(map, fn {key, value} ->
      if is_binary(value) and key in keys,
        do: {key, @redacted},
        else: {key, redact_json(value, keys)}
    end)
  end

  def redact_json(list, keys) when is_list(list), do: Enum.map(list, &redact_json(&1, keys))
  def redact_json(other, _keys), do: other

  # --- Server ----------------------------------------------------------------

  defp accept_loop(listener, upstream, out, counter) do
    {:ok, sock} = :gen_tcp.accept(listener)
    pid = spawn(fn -> serve(sock, upstream, out, counter) end)
    :ok = :gen_tcp.controlling_process(sock, pid)
    send(pid, :go)
    accept_loop(listener, upstream, out, counter)
  end

  defp serve(sock, upstream, out, counter) do
    receive do
      :go -> :ok
    end

    case read_request(sock) do
      {:ok, method, target, headers, body} ->
        case forward(method, target, headers, body, upstream) do
          {:ok, status, resp_headers, resp_body} ->
            n = :atomics.add_get(counter, 1, 1)
            IO.puts("ris_recorder: #{n} #{method} #{target} -> #{status}")
            write_cassette(n, out, method, target, headers, body, status, resp_headers, resp_body)
            respond(sock, status, resp_headers, resp_body)

          {:error, reason} ->
            IO.puts("ris_recorder: #{method} #{target} -> Fehler: #{inspect(reason)}")
            respond(sock, 502, [], ~s({"error":"upstream-error"}))
        end

      :error ->
        respond(sock, 400, [], ~s({"error":"bad request"}))
    end

    :gen_tcp.close(sock)
  end

  defp read_request(sock) do
    case :gen_tcp.recv(sock, 0, 5_000) do
      {:ok, {:http_request, method, {:abs_path, target}, _version}} ->
        case read_headers(sock, []) do
          {:ok, headers} -> read_body(sock, method, target, headers)
          :error -> :error
        end

      _ ->
        :error
    end
  end

  defp read_headers(sock, acc) do
    case :gen_tcp.recv(sock, 0, 5_000) do
      {:ok, :http_eoh} ->
        {:ok, Enum.reverse(acc)}

      {:ok, {:http_header, _, key, _, value}} ->
        read_headers(sock, [{header_name(key), value} | acc])

      _ ->
        :error
    end
  end

  # Der Body wird gelesen, auch wenn ihn nur die Kassette braucht: ein Socket
  # mit ungelesenen Daten sendet beim Schliessen RST, die Antwort kaeme beim
  # Client nie an.
  defp read_body(sock, method, target, headers) do
    case content_length(headers) do
      n when n > 0 ->
        case :gen_tcp.recv(sock, n, 5_000) do
          {:ok, body} -> {:ok, method, target, headers, body}
          _ -> :error
        end

      _ ->
        {:ok, method, target, headers, ""}
    end
  end

  # Ohne List.keyfind: dessen Position-Semantik hat sich in Elixir 1.20
  # geaendert (0-basiert, Default nil statt false). Eigenes Lookup ist
  # versionssicher.
  defp content_length(headers) do
    case header(headers, "content-length") do
      nil ->
        0

      value ->
        case Integer.parse(value) do
          {n, _rest} -> n
          :error -> 0
        end
    end
  end

  defp header(headers, name) do
    Enum.find_value(headers, fn
      {^name, value} -> value
      _other -> nil
    end)
  end

  # Bekannte Kopfzeilen kommen als Atom, unbekannte (X-Orgkey & Co.) als
  # Binaer-String oder Zeichenliste.
  defp header_name(key) when is_atom(key), do: key |> Atom.to_string() |> String.downcase()
  defp header_name(key) when is_binary(key), do: String.downcase(key)
  defp header_name(key) when is_list(key), do: key |> List.to_string() |> String.downcase()

  # --- Weiterleitung -----------------------------------------------------------

  # httpc will Kleinbuchstaben; das HTTP-Paket liefert :GET/:POST.
  defp http_method(:GET), do: :get
  defp http_method(:POST), do: :post
  defp http_method(:HEAD), do: :head
  defp http_method(:PUT), do: :put
  defp http_method(:DELETE), do: :delete
  defp http_method(:OPTIONS), do: :options
  defp http_method(:PATCH), do: :patch

  defp forward(method, target, headers, body, upstream) do
    url = upstream <> String.trim_leading(target, "/")

    fwd =
      for {name, value} <- headers, name not in @drop do
        {String.to_charlist(name), String.to_charlist(value)}
      end

    request =
      if method == :GET do
        {String.to_charlist(url), fwd}
      else
        content_type = header(headers, "content-type") || "application/octet-stream"
        {String.to_charlist(url), fwd, String.to_charlist(content_type), body}
      end

    case :httpc.request(
           http_method(method),
           request,
           http_options(url),
           [body_format: :binary],
           @profile
         ) do
      {:ok, {{_version, status, _reason}, resp_headers, resp_body}} ->
        {:ok, status, normalize_headers(resp_headers), resp_body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp http_options(url) do
    base = [timeout: @timeout_ms, connect_timeout: @timeout_ms, autoredirect: false]

    case URI.parse(url) do
      %URI{scheme: "https", host: host} ->
        [ssl: ssl_options(host)] ++ base

      # Klartext (nur Loopback): leere ssl-Option ist Pflicht, sonst
      # berechnet httpc seinen Default ueber den Schluesselbund.
      _ ->
        [ssl: []] ++ base
    end
  end

  defp ssl_options(host) do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(host),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)],
      depth: 4
    ]
  end

  defp normalize_headers(headers) do
    for {key, value} <- headers do
      {header_name(key), to_string(value)}
    end
  end

  # --- Kassette ----------------------------------------------------------------

  defp write_cassette(
         n,
         out,
         method,
         target,
         req_headers,
         req_body,
         status,
         resp_headers,
         resp_body
       ) do
    {path, query} = split_target(target)

    cassette = %{
      "request" => %{
        "method" => String.upcase(Atom.to_string(method)),
        "path" => path,
        "query" => query,
        "headers" => req_headers |> scrub_headers(@secret_request_headers) |> json_headers(),
        "body_b64" => Base.encode64(scrub_json_body(req_body, @secret_request_body_keys))
      },
      "response" => %{
        "status" => status,
        "headers" => resp_headers |> scrub_headers(@secret_response_headers) |> json_headers(),
        "body_b64" => Base.encode64(scrub_json_body(resp_body, @secret_response_body_keys))
      }
    }

    file = Path.join(out, filename(n, method, path))
    File.write!(file, IO.iodata_to_binary(:json.encode(cassette)) <> "\n")
  end

  # JSON-Bodies werden dekodiert, redigiert und neu kodiert; alles andere
  # (z. B. PDF-Downloads) bleibt bytetreu.
  defp scrub_json_body(body, keys) do
    case decode_json(body) do
      {:ok, term} -> IO.iodata_to_binary(:json.encode(redact_json(term, keys)))
      :error -> body
    end
  end

  defp decode_json(body) do
    {:ok, :json.decode(body)}
  rescue
    _ -> :error
  end

  # :json.encode kennt keine Tupel: Kopfzeilen als [name, value]-Listen.
  defp json_headers(headers), do: Enum.map(headers, &Tuple.to_list/1)

  defp split_target(target) do
    case String.split(target, "?", parts: 2) do
      [path] -> {path, nil}
      [path, query] -> {path, query}
    end
  end

  defp filename(n, method, path) do
    slug =
      path
      |> String.trim_leading("/")
      |> String.replace(~r/[^A-Za-z0-9]+/, "-")
      |> String.trim_trailing("-")

    name = String.downcase(Atom.to_string(method))
    "#{String.pad_leading(Integer.to_string(n), 4, "0")}-#{name}-#{slug}.json"
  end

  defp default_out do
    stamp = Calendar.strftime(NaiveDateTime.utc_now(), "%Y%m%dT%H%M%SZ")
    Path.join([Path.dirname(__ENV__.file), "cassettes", stamp])
  end

  # --- Antwort an den Client ------------------------------------------------------

  defp respond(sock, status, headers, body) do
    kept =
      for {name, value} <- headers, name not in @drop do
        "#{name}: #{value}\r\n"
      end

    head =
      IO.iodata_to_binary([
        "HTTP/1.1 #{status} X\r\n",
        kept,
        "content-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n"
      ])

    :gen_tcp.send(sock, head <> body)
  end
end

case System.argv() do
  ["--port", port | rest] ->
    opts =
      case rest do
        ["--upstream", upstream, "--out", out] -> [upstream: upstream, out: out]
        ["--upstream", upstream] -> [upstream: upstream]
        ["--out", out] -> [out: out]
        [] -> []
      end

    case KomkiConnectorRis.RisRecorder.start(Keyword.put(opts, :port, String.to_integer(port))) do
      {:ok, _pid, actual, out} ->
        IO.puts("ris_recorder lauscht auf http://127.0.0.1:#{actual}/ (Kassetten nach #{out})")
        Process.sleep(:infinity)

      {:error, reason} ->
        IO.puts(:stderr, "ris_recorder: Start fehlgeschlagen: #{inspect(reason)}")
        exit({:shutdown, 1})
    end

  _ ->
    :ok
end
