# Skelett-Extraktor fuer RIS-Kassetten (priv/ris_recorder.exs und
# handgeschriebene Fixtures).
#
#     elixir apps/komki_connector_ris/priv/ris_skeleton.exs --cassette <dir> \
#       [--out <datei>] [--compare <dir2>]
#
# Erster Schritt des Synthetic-Konzepts (README, "Aufzeichnung und Replay"):
# Aus echten Aufzeichnungen wird eine rein strukturelle Formatspezifikation
# gewonnen — rekursive Schluesselmengen, Typen und Formen (ISO-Datum, Base64-
# HTML, ID-Muster), keine Inhalte. Der Bericht ist committbar; er ist der
# Vertrag zwischen echtem RIS und Mock und die Vorlage fuer den spaeteren
# synthetischen Generator.
#
# --compare extrahiert zwei Kassettenverzeichnisse und meldet Abweichungen
# (Endpunkte, Query-Schluessel, Status, Schema-Drift); Exit-Code 1 bei Drift.
# Toleriert werden optionale Schluessel und ueberlappende Array-Laengen — die
# schwanken mit den Aufnahmen; driftig ist nur das strukturell andere Format.
# Damit laesst sich pruefen, ob der synthetische Mock formatgetreu ist.
#
# Nur OTP, keine Deps — wie mock_ris.exs.

Code.require_file("./ris_http.exs", __DIR__)

defmodule KomkiConnectorRis.RisSkeleton do
  @moduledoc false

  @usage "Aufruf: --cassette <dir> [--out <datei>] [--compare <dir>]"

  @spec extract(Path.t()) :: map()
  def extract(dir) do
    endpoints =
      dir
      |> cassette_files()
      |> Enum.map(&load_cassette/1)
      |> Enum.map(&endpoint/1)
      |> Enum.reduce(%{}, &merge_endpoint/2)

    %{"version" => 1, "endpoints" => endpoints}
  end

  @doc """
  Vergleicht zwei Extrakte und liefert die sortierten Abweichungen als
  Klartextzeilen (leer = formatgetreu). Toleriert werden optionale Schluessel
  und ueberlappende Array-Laengen; gemeldet wird nur struktureller Drift.
  """
  @spec compare(map(), map()) :: [String.t()]
  def compare(a, b) do
    (only(a["endpoints"], b["endpoints"], "Endpunkt nur in links") ++
       only(b["endpoints"], a["endpoints"], "Endpunkt nur in rechts") ++
       common_differences(a["endpoints"], b["endpoints"]))
    |> Enum.sort()
  end

  @doc false
  @spec parse_cli([String.t()]) :: {:ok, keyword()} | {:error, String.t()}
  def parse_cli(argv) do
    case parse_flags(argv, []) do
      {:ok, opts} ->
        cond do
          not Keyword.has_key?(opts, :cassette) ->
            {:error, @usage}

          # Tippfehler hier melden, nicht erst als File.ls!-Stacktrace.
          not File.dir?(opts[:cassette]) ->
            {:error, "Kassettenverzeichnis existiert nicht: #{opts[:cassette]}"}

          not is_nil(opts[:compare]) and not File.dir?(opts[:compare]) ->
            {:error, "Vergleichsverzeichnis existiert nicht: #{opts[:compare]}"}

          true ->
            {:ok, opts}
        end

      {:error, _} ->
        {:error, @usage}
    end
  end

  defp parse_flags([], acc), do: {:ok, acc}

  defp parse_flags(["--cassette", value | rest], acc),
    do: parse_flags(rest, Keyword.put(acc, :cassette, value))

  defp parse_flags(["--out", value | rest], acc),
    do: parse_flags(rest, Keyword.put(acc, :out, value))

  defp parse_flags(["--compare", value | rest], acc),
    do: parse_flags(rest, Keyword.put(acc, :compare, value))

  defp parse_flags(_other, _acc), do: {:error, @usage}

  # --- Kassetten laden --------------------------------------------------------

  defp cassette_files(dir) do
    dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.sort()
    |> Enum.map(&Path.join(dir, &1))
  end

  defp load_cassette(file) do
    %{"request" => request, "response" => response} = file |> File.read!() |> :json.decode()

    request_body =
      case Map.fetch(request, "body_b64") do
        {:ok, b64} -> Base.decode64!(b64)
        :error -> Map.get(request, "body", "")
      end

    response_body =
      case Map.fetch(response, "body_b64") do
        {:ok, b64} -> Base.decode64!(b64)
        :error -> Map.get(response, "body", "")
      end

    %{
      request: request,
      request_body: request_body,
      response: response,
      response_body: response_body
    }
  end

  # --- Endpunkt-Bericht ---------------------------------------------------------

  # "/guestmeetings/4711" wird zu "/guestmeetings/{id}",
  # "/guestagendaitems/1001-1" zu "/guestagendaitems/{meetingId-agendaId}".
  defp endpoint(%{request: request, response: response} = cassette) do
    key =
      "#{request["method"]} #{normalize_path(request["path"])}"

    value = %{
      "query_keys" => query_keys(request),
      "request_headers" => header_names(request["headers"]),
      "statuses" => [response["status"]],
      "response_headers" => header_names(response["headers"]),
      "request_body" => body_schema(cassette.request_body),
      "response_body" => body_schema(cassette.response_body)
    }

    {key, value}
  end

  defp normalize_path(path) do
    path
    |> String.split("/", trim: true)
    |> Enum.map(&normalize_segment/1)
    |> Enum.join("/")
    |> then(&("/" <> &1))
  end

  defp normalize_segment(segment) do
    cond do
      Regex.match?(~r/^\d+$/, segment) -> "{id}"
      Regex.match?(~r/^\d+-\d+$/, segment) -> "{meetingId-agendaId}"
      true -> segment
    end
  end

  defp query_keys(request) do
    case Map.get(request, "query") do
      # JSON-null dekodiert :json als :null; aeltere Kassetten (vor dem
      # nil-Fix) trugen den String "nil" — alle heissen: kein Query.
      nil -> []
      :null -> []
      "nil" -> []
      query -> query |> URI.decode_query() |> Map.keys() |> Enum.sort()
    end
  end

  defp header_names(headers),
    do: headers |> Enum.map(&Enum.at(&1, 0)) |> Enum.sort() |> Enum.uniq()

  # --- Schema -------------------------------------------------------------------

  # JSON-Bodies werden strukturell zerlegt; alles andere ist HTML oder Binaer.
  defp body_schema(body) do
    case decode_json(body) do
      {:ok, term} ->
        schema(term)

      :error ->
        cond do
          body == "" -> %{"type" => "empty"}
          String.valid?(body) and body =~ "<" and body =~ ">" -> %{"type" => "html"}
          true -> %{"type" => "binary"}
        end
    end
  end

  defp schema(%{} = map) do
    %{"type" => "object", "keys" => Map.new(map, fn {k, v} -> {k, schema(v)} end)}
  end

  defp schema(list) when is_list(list) do
    base = %{"type" => "array", "min_items" => length(list), "max_items" => length(list)}

    # Leere Arrays bekommen kein "items": nil wuerde :json als String "nil"
    # kodieren.
    case Enum.reduce(list, nil, &merge_schema(schema(&1), &2)) do
      nil -> base
      items -> Map.put(base, "items", items)
    end
  end

  defp schema(:null), do: %{"type" => "null"}
  defp schema(value) when is_boolean(value), do: %{"type" => "boolean"}
  defp schema(value) when is_integer(value), do: %{"type" => "integer"}
  defp schema(value) when is_float(value), do: %{"type" => "number"}

  defp schema(value) when is_binary(value),
    do: %{"type" => "string", "formats" => [string_format(value)]}

  # Formen ohne Inhalte: Datum, ID-Muster, Base64-HTML, URL, sonst Text.
  defp string_format(value) do
    cond do
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/, value) -> "iso-datetime"
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, value) -> "date"
      Regex.match?(~r/^\d+-\d+$/, value) -> "id-pair"
      Regex.match?(~r/^\d+$/, value) -> "digits"
      String.starts_with?(value, "http://") or String.starts_with?(value, "https://") -> "url"
      base64_html?(value) -> "base64-html"
      true -> "text"
    end
  end

  # Base64-Heuristik: Zeichensatz und Laenge passen und die Dekodierung ergibt
  # gueltiges UTF-8 mit Tags — sonst ist es schlicht Text.
  defp base64_html?(value) do
    if Regex.match?(~r|^[A-Za-z0-9+/]+={0,2}$|, value) and byte_size(value) > 16 do
      case Base.decode64(value) do
        {:ok, decoded} ->
          String.valid?(decoded) and decoded =~ "<" and decoded =~ ">"

        :error ->
          false
      end
    else
      false
    end
  end

  defp decode_json(body) do
    {:ok, :json.decode(body)}
  rescue
    _ -> :error
  end

  # --- Mergen ---------------------------------------------------------------------

  defp merge_endpoint({key, value}, acc) do
    Map.update(acc, key, value, fn existing -> merge_reports(existing, value) end)
  end

  defp merge_reports(a, b) do
    %{
      "query_keys" => Enum.uniq(a["query_keys"] ++ b["query_keys"]) |> Enum.sort(),
      "request_headers" => Enum.uniq(a["request_headers"] ++ b["request_headers"]) |> Enum.sort(),
      "statuses" => Enum.uniq(a["statuses"] ++ b["statuses"]) |> Enum.sort(),
      "response_headers" =>
        Enum.uniq(a["response_headers"] ++ b["response_headers"]) |> Enum.sort(),
      "request_body" => merge_schema(a["request_body"], b["request_body"]),
      "response_body" => merge_schema(a["response_body"], b["response_body"])
    }
  end

  # nil = noch kein Sample (leere Arrays); sonst Vereinigung der Schemata.
  defp merge_schema(nil, b) when b != nil, do: b
  defp merge_schema(a, nil) when a != nil, do: a
  defp merge_schema(nil, nil), do: nil

  defp merge_schema(%{"type" => type_a} = a, %{"type" => type_b} = b) do
    if type_a == type_b do
      merge_same(a, b)
    else
      # "mixed" kann selbst wieder gemergt werden: die Mitglieder zaehlen,
      # nicht der Marker — sonst gehen fruehere Typen verloren.
      %{
        "type" => "mixed",
        "types" => Enum.uniq(member_types(a) ++ member_types(b)) |> Enum.sort()
      }
    end
  end

  defp member_types(%{"type" => "mixed", "types" => types}), do: types
  defp member_types(%{"type" => type}), do: [type]

  defp merge_same(%{"type" => "object"} = a, %{"type" => "object"} = b) do
    keys = Map.merge(a["keys"], b["keys"], fn _k, x, y -> merge_schema(x, y) end)
    only_one_side = Map.keys(a["keys"]) -- Map.keys(b["keys"])
    only_one_side = only_one_side ++ (Map.keys(b["keys"]) -- Map.keys(a["keys"]))

    %{
      "type" => "object",
      "keys" => keys,
      "optional" =>
        Enum.uniq(only_one_side ++ Map.get(a, "optional", []) ++ Map.get(b, "optional", []))
        |> Enum.sort()
    }
  end

  defp merge_same(%{"type" => "array"} = a, %{"type" => "array"} = b) do
    base = %{
      "type" => "array",
      "min_items" => min(a["min_items"], b["min_items"]),
      "max_items" => max(a["max_items"], b["max_items"])
    }

    case merge_schema(Map.get(a, "items"), Map.get(b, "items")) do
      nil -> base
      items -> Map.put(base, "items", items)
    end
  end

  defp merge_same(%{"type" => "string"} = a, %{"type" => "string"} = b) do
    %{"type" => "string", "formats" => Enum.uniq(a["formats"] ++ b["formats"]) |> Enum.sort()}
  end

  defp merge_same(%{"type" => "mixed"} = a, %{"type" => "mixed"} = b) do
    %{"type" => "mixed", "types" => Enum.uniq(a["types"] ++ b["types"]) |> Enum.sort()}
  end

  defp merge_same(a, _b), do: a

  # --- Vergleichen ------------------------------------------------------------------

  defp only(a, b, label) do
    a
    |> Map.keys()
    |> Kernel.--(Map.keys(b))
    |> Enum.map(&"#{label}: #{&1}")
  end

  defp common_differences(a, b) do
    keys = Map.keys(a) -- (Map.keys(a) -- Map.keys(b))

    Enum.flat_map(keys, fn key ->
      endpoint_differences(key, a[key], b[key])
    end)
    |> Enum.sort()
  end

  defp endpoint_differences(name, a, b) do
    [
      list_diff(name, "query_keys", a["query_keys"], b["query_keys"]),
      list_diff(name, "request_headers", a["request_headers"], b["request_headers"]),
      list_diff(name, "statuses", a["statuses"], b["statuses"]),
      list_diff(name, "response_headers", a["response_headers"], b["response_headers"]),
      schema_diff("#{name}: request_body", a["request_body"], b["request_body"]),
      schema_diff("#{name}: response_body", a["response_body"], b["response_body"])
    ]
    |> List.flatten()
  end

  defp list_diff(_name, _field, same, same), do: []

  defp list_diff(name, field, a, b) do
    ["#{name}: #{field}: #{inspect(Enum.sort(a))} vs #{inspect(Enum.sort(b))}"]
  end

  defp schema_diff(_path, nil, nil), do: []
  defp schema_diff(path, nil, b), do: ["#{path}: nur in rechts (#{b["type"]})"]
  defp schema_diff(path, a, nil), do: ["#{path}: nur in links (#{a["type"]})"]

  defp schema_diff(path, %{"type" => type_a} = a, %{"type" => type_b} = b) do
    if type_a != type_b do
      ["#{path}: Typ #{type_a} vs #{type_b}"]
    else
      schema_diff_same(path, a, b)
    end
  end

  defp schema_diff_same(path, %{"type" => "object"} = a, %{"type" => "object"} = b) do
    a_keys = Map.keys(a["keys"])
    b_keys = Map.keys(b["keys"])
    optional_a = Map.get(a, "optional", [])
    optional_b = Map.get(b, "optional", [])

    only_left = a_keys -- b_keys
    only_right = b_keys -- a_keys

    # Optionale Schluessel duerfen auf der Gegenseite fehlen (real antwortet
    # sie nur manchmal). Verpflichtende fehlen heisst Format-Drift.
    left_msgs =
      only_left
      |> Enum.reject(&(&1 in optional_a))
      |> Enum.map(&"#{path}.#{&1}: Schluessel nur in links")

    right_msgs =
      only_right
      |> Enum.reject(&(&1 in optional_b))
      |> Enum.map(&"#{path}.#{&1}: Schluessel nur in rechts")

    common =
      Enum.flat_map(a_keys -- only_left, fn key ->
        schema_diff("#{path}.#{key}", a["keys"][key], b["keys"][key])
      end)

    left_msgs ++ right_msgs ++ common
  end

  defp schema_diff_same(path, %{"type" => "array"} = a, %{"type" => "array"} = b) do
    # Beobachtete Laengen schwanken mit den Aufnahmen; driftig ist nur, wenn
    # die Bereiche sich gar nicht ueberlappen.
    range =
      if a["max_items"] < b["min_items"] or b["max_items"] < a["min_items"] do
        [
          "#{path}: Kardinalitaet entkoppelt: #{a["min_items"]}..#{a["max_items"]} vs #{b["min_items"]}..#{b["max_items"]}"
        ]
      else
        []
      end

    range ++ schema_diff("#{path}[]", Map.get(a, "items"), Map.get(b, "items"))
  end

  defp schema_diff_same(path, %{"type" => "string"} = a, %{"type" => "string"} = b) do
    if Enum.sort(a["formats"]) == Enum.sort(b["formats"]) do
      []
    else
      [
        "#{path}: Formate #{inspect(Enum.sort(a["formats"]))} vs #{inspect(Enum.sort(b["formats"]))}"
      ]
    end
  end

  defp schema_diff_same(path, %{"type" => "mixed"} = a, %{"type" => "mixed"} = b) do
    if Enum.sort(a["types"]) == Enum.sort(b["types"]) do
      []
    else
      ["#{path}: Typen #{inspect(Enum.sort(a["types"]))} vs #{inspect(Enum.sort(b["types"]))}"]
    end
  end

  defp schema_diff_same(_path, _a, _b), do: []
end

KomkiConnectorRis.RisHttp.cli(System.argv(), fn argv ->
  case KomkiConnectorRis.RisSkeleton.parse_cli(argv) do
    {:ok, opts} ->
      report = KomkiConnectorRis.RisSkeleton.extract(opts[:cassette])
      json = report |> :json.encode() |> IO.iodata_to_binary()

      if out = opts[:out] do
        File.write!(out, json <> "\n")
        IO.puts("ris_skeleton: Bericht nach #{out}")
      else
        IO.puts(json)
      end

      if compare_dir = opts[:compare] do
        differences =
          KomkiConnectorRis.RisSkeleton.compare(
            report,
            KomkiConnectorRis.RisSkeleton.extract(compare_dir)
          )

        if differences == [] do
          IO.puts("ris_skeleton: keine Abweichungen")
        else
          Enum.each(differences, &IO.puts("ris_skeleton: #{&1}"))
          exit({:shutdown, 1})
        end
      end

    {:error, usage} ->
      IO.puts(:stderr, "ris_skeleton: #{usage}")
      exit({:shutdown, 1})
  end
end)
