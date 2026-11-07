# Geteiltes Geruest der RIS-Skriptfamilie: mock_ris, ris_recorder, ris_skeleton,
# ris_struktur, ris_gartenstadt, ris_ngramm und ris_cassettes. Wer ein neues
# Familienmitglied schreibt, findet hier die Bausteine und kopiert nichts mehr
# vom Nachbarn.
#
# Jedes Skript bleibt eigenstaendig startbar und laedt diese Datei per
# Code.require_file — weiterhin nur OTP, keine Deps. Hier lebt, was sonst in
# den Skripten dupliziert waere: der Sockel-Kram, das Kassetten-Listing, der
# JSON-Dekode, der Koerper-Dekode und das Flag-Geruest der Aufrufzeile.

defmodule KomkiConnectorRis.RisHttp do
  @moduledoc false

  @timeout 5_000

  @doc """
  Liest eine HTTP-Anfrage vom Sockel: `{:ok, Methode, Pfad, Kopfzeilen, Body}`
  oder `:error`. Der Body wird komplett gelesen (auch wenn ihn nur der
  Recorder braucht): ein Socket mit ungelesenen Daten sendet beim Schliessen
  RST, die Antwort kaeme beim Client nie an.
  """
  @spec read_request(:gen_tcp.socket()) ::
          {:ok, atom() | String.t(), String.t(), [{String.t(), String.t()}], binary()} | :error
  def read_request(sock) do
    case :gen_tcp.recv(sock, 0, @timeout) do
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
    case :gen_tcp.recv(sock, 0, @timeout) do
      {:ok, :http_eoh} ->
        {:ok, Enum.reverse(acc)}

      {:ok, {:http_header, _, key, _, value}} ->
        read_headers(sock, [{header_name(key), value} | acc])

      _ ->
        :error
    end
  end

  # Laengenbasiertes recv ist nur im Raw-Modus erlaubt; auf einem
  # packet: :http_bin Sockel liefert es :einval. Nach dem Kopfzeilenende
  # deshalb auf :raw umschalten, bevor der Body gelesen wird.
  defp read_body(sock, method, target, headers) do
    case header(headers, "content-length") do
      nil ->
        {:ok, method, target, headers, ""}

      value ->
        case Integer.parse(value) do
          {n, _rest} when n > 0 ->
            :ok = :inet.setopts(sock, packet: :raw)

            case :gen_tcp.recv(sock, n, @timeout) do
              {:ok, body} -> {:ok, method, target, headers, body}
              _ -> :error
            end

          _ ->
            {:ok, method, target, headers, ""}
        end
    end
  end

  @doc "Wert der ersten Kopfzeile mit `name` (kleingeschrieben) oder `nil`."
  @spec header([{String.t(), String.t()}], String.t()) :: String.t() | nil
  def header(headers, name) do
    Enum.find_value(headers, fn
      {^name, value} -> value
      _other -> nil
    end)
  end

  # Bekannte Kopfzeilen kommen als Atom, unbekannte (X-Orgkey & Co.) als
  # Binaer-String oder Zeichenliste (auch :httpc-Antworten nutzen das Format).
  @doc false
  @spec header_name(atom() | String.t() | charlist()) :: String.t()
  def header_name(key) when is_atom(key), do: key |> Atom.to_string() |> String.downcase()
  def header_name(key) when is_binary(key), do: String.downcase(key)
  def header_name(key) when is_list(key), do: key |> List.to_string() |> String.downcase()

  @doc "Pfad und Query eines Anfrageziels (`/pfad?a=b` → `{\"/pfad\", \"a=b\"}`)."
  @spec split_target(String.t()) :: {String.t(), String.t() | nil}
  def split_target(target) do
    case String.split(target, "?", parts: 2) do
      [path] -> {path, nil}
      [path, query] -> {path, query}
    end
  end

  @doc """
  Methodenname als String. Standardmethoden liefert das HTTP-Paket als Atom,
  ungewoehnliche (z. B. PROPFIND) als Binaer-String — beide werden hier
  normalisiert, damit Atom.to_string nirgends crasht.
  """
  @spec method_label(atom() | String.t()) :: String.t()
  def method_label(method) when is_atom(method), do: Atom.to_string(method)
  def method_label(method) when is_binary(method), do: method

  @doc """
  Sortierte Pfade aller `*.json`-Kassetten eines Verzeichnisses (Aufnahmen
  des Recorders oder handgeschriebene Fixtures). Wie bisher `File.ls!`: Ein
  unlesbares Verzeichnis wirft. `*.json.enc` (ris_cassettes) endet nicht auf
  `.json`, die Mengen sind disjunkt.
  """
  @spec cassette_files(Path.t()) :: [Path.t()]
  def cassette_files(dir) do
    dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.sort()
    |> Enum.map(&Path.join(dir, &1))
  end

  @doc "`:json.decode` mit Auffangnetz: `{:ok, term}` bei gueltigem JSON, sonst `:error`."
  @spec decode_json(binary()) :: {:ok, term()} | :error
  def decode_json(body) do
    {:ok, :json.decode(body)}
  rescue
    _ -> :error
  end

  @doc """
  Koerper eines Kassetten-Teils (`request` oder `response`): `body_b64` wird
  mit `Base.decode64!` dekodiert (ungueltiges Base64 wirft), sonst gilt
  `body`, sonst `""` — handgeschriebene Fixtures tragen den Koerper im
  Klartext, Recorder-Kassetten base64.
  """
  @spec part_body(map()) :: term()
  def part_body(part) do
    case Map.fetch(part, "body_b64") do
      {:ok, b64} -> Base.decode64!(b64)
      :error -> Map.get(part, "body", "")
    end
  end

  @doc """
  `:ok`, wenn `path` ausserhalb jedes Git-Repos liegt (auch Worktrees, deren
  `.git` eine Datei ist), sonst `{:error, {:in_repo, repo}}`. Vorhandene
  Pfade werden per realpath aufgeloest — ein Symlink, der in ein Repo
  fuehrt, umgeht die Pruefung sonst. Noch nicht existierende Enden (der
  Recorder legt sein --out erst nach der Pruefung an) bleiben lexikalisch:
  aufgeloest wird der laengste existierende Vorfahre.
  """
  @spec repo_free?(Path.t()) :: :ok | {:error, {:in_repo, Path.t()}}
  def repo_free?(path) do
    path
    |> Path.expand()
    |> resolved()
    |> ancestors()
    |> Enum.find(&File.exists?(Path.join(&1, ".git")))
    |> case do
      nil -> :ok
      repo -> {:error, {:in_repo, repo}}
    end
  end

  # Symlinks aufloesen, soweit sie existieren (realpath gibt es in OTP 29
  # nicht mehr): erst der Pfad selbst, dann die Vorfahren. Schutz gegen
  # Zyklen (a -> b -> a): nach 64 Hops wird lexikalisch weitergearbeitet —
  # schlimmstenfalls greift dann die alte, rein lexikalische Pruefung.
  defp resolved(path), do: resolved_loop(Path.expand(path), 0)

  defp resolved_loop(path, hops) when hops >= 64, do: path

  defp resolved_loop(path, hops) do
    case File.read_link(path) do
      {:ok, target} ->
        resolved_loop(Path.expand(target, Path.dirname(path)), hops + 1)

      {:error, _reason} ->
        case Path.dirname(path) do
          ^path -> path
          parent -> Path.join(resolved_loop(parent, hops + 1), Path.basename(path))
        end
    end
  end

  defp ancestors(path) do
    parent = Path.dirname(path)
    if parent == path, do: [path], else: [path | ancestors(parent)]
  end

  @doc """
  Flag-Geruest der Aufrufzeile: `--flag wert`-Paare in beliebiger Reihenfolge.
  `kinds` nennt die erlaubten Flaggen (ohne `--`) und ihre Wertart: `:string`
  uebernimmt das naechste Token, `:integer` verlangt eine ganze Zahl. Ein
  unbekanntes Flag, ein Flag ohne Wert oder ein Wert ohne Flag wird mit
  `:error` abgewiesen — die Meldung dazu liefert die Aufrufstelle (Usage).
  Keine Argumente sind gueltig; ob ein Flag fehlen darf, entscheidet die
  Aufrufstelle. (ris_cassettes mischt Verb und Pfad dazu und behaelt deshalb
  seinen eigenen Parser.)
  """
  @spec parse_flags([String.t()], keyword(:string | :integer)) :: {:ok, keyword()} | :error
  def parse_flags(argv, kinds) do
    known = Map.new(kinds, fn {key, kind} -> {Atom.to_string(key), {key, kind}} end)
    parse_flags(argv, known, [])
  end

  defp parse_flags([], _known, acc), do: {:ok, acc}

  defp parse_flags(["--" <> name, value | rest], known, acc) do
    case Map.fetch(known, name) do
      {:ok, {key, :string}} -> parse_flags(rest, known, Keyword.put(acc, key, value))
      {:ok, {key, :integer}} -> parse_flags_integer(key, value, rest, known, acc)
      :error -> :error
    end
  end

  defp parse_flags(_argv, _known, _acc), do: :error

  defp parse_flags_integer(key, value, rest, known, acc) do
    case Integer.parse(value) do
      {n, ""} -> parse_flags(rest, known, Keyword.put(acc, key, n))
      _keine_ganze_zahl -> :error
    end
  end

  @doc """
  CLI-Einsprung der priv-Skripte: `runner` laeuft nur, wenn Argumente da sind
  und kein Testlauf vorliegt (`mix test` laedt die Skripte per
  Code.require_file — ohne Argumente oder im Test nichts tun). Alles andere
  fuehrt zum Runner, der fuer eine klare Meldung sorgen muss — nie still
  enden. `:force` ruft den Runner auch im Test auf (fuer Tests des Runners).
  """
  @spec cli([String.t()], (keyword() -> any()), boolean()) :: any()
  def cli(argv, runner, force \\ false) do
    cond do
      argv == [] -> :ok
      not force and under_mix_test?() -> :ok
      true -> runner.(argv)
    end
  end

  # Mix.env() crasht ohne gestartetes Mix (plain `elixir`): dann ist es kein
  # Testlauf.
  defp under_mix_test? do
    Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and mix_env() == :test
  end

  defp mix_env do
    Mix.env()
  rescue
    _ -> :dev
  end
end
