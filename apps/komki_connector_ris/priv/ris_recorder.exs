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
# Die Kassetten enthalten echte, auch nicht-oeffentliche Daten. Sie liegen
# deshalb nie im Repo-Baum (sonst koennte jedes Werkzeug, das im Repo
# arbeitet, sie lesen): Standard ist ~/.local/share/kommunalpolitik_ki/
# ris-cassettes/<zeitstempel>, ein --out innerhalb eines Git-Repos wird
# abgewiesen, Verzeichnis und Dateien sind nur fuer den Eigentuemer lesbar.
#
# Bestimmt geschwaerzt, ohne jedes LLM: authorization-/cookie-Kopfzeilen,
# set-cookie, beim Login (/auth) jeder Wert in Anfrage und Antwort, sonst die
# Felder token/access_token/jwt in JSON-Bodies. Dem Client und dem Upstream
# reicht der Proxy alles unveraendert durch — nur die Datei auf der Platte
# ist geschwaerzt.
#
# Pfade ohne /web/-Praefix geben (Basis also http://127.0.0.1:<port>/, nicht
# .../<port>/web/); der Proxy ergaenzt den Praefix upstream-seitig.
# Zurueckspielen: priv/mock_ris.exs --port 4010 --mode replay --cassette <out>.
#
# Nur OTP (gen_tcp, httpc, ssl, json), keine Deps — wie mock_ris.exs.

Code.require_file("./ris_http.exs", __DIR__)

defmodule KomkiConnectorRis.RisRecorder do
  @moduledoc false

  alias KomkiConnectorRis.RisHttp

  @redacted "<redacted>"
  @default_upstream "https://risapi1.komuna.net/web/"
  @profile :ris_recorder
  @timeout_ms 60_000

  @usage "Aufruf: --port <port> [--upstream <url>] [--out <verzeichnis>]"

  # Hop-by-hop-Kopfzeilen und Rahmenfelder: weder aufzeichnen noch
  # weiterreichen (content-length wird aus dem Body neu gesetzt).
  @drop ~w(connection keep-alive proxy-authenticate proxy-authorization te trailer
          transfer-encoding upgrade accept-encoding host content-length)

  # Geheimnisse: Werte werden nur in der Kassette redigiert.
  @secret_request_headers ~w(authorization cookie proxy-authorization)
  @secret_response_headers ~w(set-cookie)
  @secret_body_keys ~w(login password token access_token jwt)

  # Login: hier ist praktisch alles geheim (Zugangsdaten, Token, womoeglich
  # Refresh-Token und Profildaten in unbekannten Feldern). Statt einer
  # Sperrliste wird jeder Wert geschwaerzt; die Struktur bleibt erhalten.
  @auth_path "/auth"

  @spec start(keyword()) :: {:ok, pid(), :inet.port_number(), String.t()} | {:error, term()}
  def start(opts \\ []) do
    port = Keyword.get(opts, :port, 0)

    # Ohne abschliessenden Schraegstrich wuerde jeder Pfad verlorengehen
    # (https://host/webguestmeetings) — wie bei Ratsinfo.Config.base_url/0.
    upstream =
      Keyword.get(opts, :upstream, @default_upstream)
      |> String.trim_trailing("/")
      |> then(&(&1 <> "/"))

    out = Path.expand(Keyword.get(opts, :out) || default_out())

    with :ok <- check_out(out),
         :ok <- prepare_out(out),
         {:ok, _} <- Application.ensure_all_started([:inets, :ssl, :public_key]) do
      _ = :inets.stop(:httpc, @profile)
      {:ok, _pid} = :inets.start(:httpc, profile: @profile)

      parent = self()
      counter = :atomics.new(1, signed: false)
      # Nummerierung schliesst an vorhandene Kassetten an, damit eine zweite
      # Session in dasselbe --out-Verzeichnis nichts ueberschreibt.
      :atomics.put(counter, 1, next_index(out))

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

  @doc false
  @spec parse_cli([String.t()]) :: {:ok, keyword()} | {:error, String.t()}
  def parse_cli(argv) do
    case parse_flags(argv, []) do
      {:ok, opts} ->
        if Keyword.has_key?(opts, :port), do: {:ok, opts}, else: {:error, @usage}

      {:error, _} ->
        {:error, @usage}
    end
  end

  # Flags in beliebiger Reihenfolge; Unbekanntes oder Ungueltiges fuehrt zur
  # Meldung statt zum stillen Nichtstun.
  defp parse_flags([], acc), do: {:ok, acc}

  defp parse_flags(["--port", value | rest], acc) do
    case Integer.parse(value) do
      {port, ""} -> parse_flags(rest, Keyword.put(acc, :port, port))
      _ -> {:error, @usage}
    end
  end

  defp parse_flags(["--upstream", value | rest], acc),
    do: parse_flags(rest, Keyword.put(acc, :upstream, value))

  defp parse_flags(["--out", value | rest], acc),
    do: parse_flags(rest, Keyword.put(acc, :out, value))

  defp parse_flags(_other, _acc), do: {:error, @usage}

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

  @doc "Ersetzt jeden String-Wert rekursiv durch \"<redacted>\" (Struktur bleibt)."
  @spec redact_all(term()) :: term()
  def redact_all(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, redact_all(v)} end)
  def redact_all(list) when is_list(list), do: Enum.map(list, &redact_all/1)
  def redact_all(value) when is_binary(value), do: @redacted
  def redact_all(other), do: other

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

    case RisHttp.read_request(sock) do
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

  # --- Weiterleitung -----------------------------------------------------------

  # httpc will Kleinbuchstaben. Standardmethoden liefert das HTTP-Paket als
  # Atom (:GET, :POST ...), ungewoehnliche als Binaer-String — beides landet
  # hier als charlist bei httpc.
  defp http_method(:GET), do: :get
  defp http_method(:POST), do: :post
  defp http_method(:HEAD), do: :head
  defp http_method(:PUT), do: :put
  defp http_method(:DELETE), do: :delete
  defp http_method(:OPTIONS), do: :options
  defp http_method(:PATCH), do: :patch
  defp http_method(other), do: other |> RisHttp.method_label() |> String.downcase()

  defp forward(method, target, headers, body, upstream) do
    url = upstream <> String.trim_leading(target, "/")

    fwd =
      for {name, value} <- headers, name not in @drop do
        {String.to_charlist(name), String.to_charlist(value)}
      end

    request =
      if RisHttp.method_label(method) == "GET" do
        {String.to_charlist(url), fwd}
      else
        content_type = RisHttp.header(headers, "content-type") || "application/octet-stream"
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
      {RisHttp.header_name(key), to_string(value)}
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
    {path, query} = RisHttp.split_target(target)

    cassette = %{
      "request" => %{
        "method" => method |> RisHttp.method_label() |> String.upcase(),
        "path" => path,
        # :json kodiert nil als String "nil" — JSON-null heisst :null.
        "query" => query || :null,
        "headers" => req_headers |> scrub_headers(@secret_request_headers) |> json_headers(),
        "body_b64" => Base.encode64(scrub_body(path, req_body))
      },
      "response" => %{
        "status" => status,
        "headers" => resp_headers |> scrub_headers(@secret_response_headers) |> json_headers(),
        "body_b64" => Base.encode64(scrub_body(path, resp_body))
      }
    }

    file = Path.join(out, filename(n, method, path))
    File.write!(file, IO.iodata_to_binary(:json.encode(cassette)) <> "\n")
    File.chmod!(file, 0o600)
  end

  # JSON-Bodies werden dekodiert, geschwaerzt und neu kodiert; alles andere
  # (z. B. PDF-Downloads) bleibt bytetreu — ausser beim Login, dort wird ein
  # Nicht-JSON-Body ganz ersetzt.
  defp scrub_body(@auth_path, body) do
    case decode_json(body) do
      {:ok, term} -> IO.iodata_to_binary(:json.encode(redact_all(term)))
      :error when body == "" -> body
      :error -> @redacted
    end
  end

  defp scrub_body(_path, body) do
    case decode_json(body) do
      {:ok, term} -> IO.iodata_to_binary(:json.encode(redact_json(term, @secret_body_keys)))
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

  defp filename(n, method, path) do
    slug =
      path
      |> String.trim_leading("/")
      |> String.replace(~r/[^A-Za-z0-9]+/, "-")
      |> String.trim_trailing("-")

    name = method |> RisHttp.method_label() |> String.downcase()
    "#{String.pad_leading(Integer.to_string(n), 4, "0")}-#{name}-#{slug}.json"
  end

  defp next_index(out) do
    case File.ls(out) do
      {:ok, files} ->
        files
        |> Enum.map(&cassette_num/1)
        |> Enum.max(fn -> 0 end)

      _ ->
        0
    end
  end

  defp cassette_num(file) do
    case Regex.run(~r/^(\d+)-/, file) do
      [_full, num] -> String.to_integer(num)
      _other -> 0
    end
  end

  defp default_out do
    stamp = Calendar.strftime(NaiveDateTime.utc_now(), "%Y%m%dT%H%M%SZ")
    Path.join([System.user_home!(), ".local/share/kommunalpolitik_ki/ris-cassettes", stamp])
  end

  @doc """
  `:ok`, wenn `out` ausserhalb jedes Git-Repos liegt (auch Worktrees, deren
  `.git` eine Datei ist, und Symlinks hinein — RisHttp.repo_free?/1), sonst
  `{:error, {:out_in_repo, repo}}`.
  """
  @spec check_out(Path.t()) :: :ok | {:error, {:out_in_repo, Path.t()}}
  def check_out(out) do
    case RisHttp.repo_free?(out) do
      :ok -> :ok
      {:error, {:in_repo, repo}} -> {:error, {:out_in_repo, repo}}
    end
  end

  # Nur fuer den Eigentuemer: die Kassetten tragen nicht-oeffentliche Inhalte.
  defp prepare_out(out) do
    File.mkdir_p!(out)
    File.chmod!(out, 0o700)
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

KomkiConnectorRis.RisHttp.cli(System.argv(), fn argv ->
  case KomkiConnectorRis.RisRecorder.parse_cli(argv) do
    {:ok, opts} ->
      case KomkiConnectorRis.RisRecorder.start(opts) do
        {:ok, _pid, actual, out} ->
          IO.puts("ris_recorder lauscht auf http://127.0.0.1:#{actual}/ (Kassetten nach #{out})")
          Process.sleep(:infinity)

        {:error, {:out_in_repo, repo}} ->
          IO.puts(
            :stderr,
            "ris_recorder: --out liegt im Git-Repo #{repo}; Kassetten enthalten " <>
              "nicht-oeffentliche Daten und gehoeren ausserhalb jedes Repos"
          )

          exit({:shutdown, 1})

        {:error, reason} ->
          IO.puts(:stderr, "ris_recorder: Start fehlgeschlagen: #{inspect(reason)}")
          exit({:shutdown, 1})
      end

    {:error, usage} ->
      IO.puts(:stderr, "ris_recorder: #{usage}")
      exit({:shutdown, 1})
  end
end)
