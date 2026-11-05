# Struktur-Extraktor fuer RIS-Kassetten (priv/ris_recorder.exs).
#
#     elixir apps/komki_connector_ris/priv/ris_struktur.exs --cassette <dir> \
#       [--out <datei>]
#
# Ergaenzung zum Skelett-Bericht fuer den Generator aus #313: Das Strukturprofil
# traegt die Belegung je Sitzung und TOP — welche Sitzungsteile geschuetzt sind,
# welche TOPs restricted, wie viele Textbloecke, Abstimmungen und Dokumente sie
# haben, wie lang ihre Titel sind. Keine Inhalte: tragbar ist nur, was Gaeste am
# RIS ebenfalls sehen koennten. Titellaengen nur fuer nachweislich oeffentliche
# TOPs (restricted=false UND ungeschuetzter Sitzungsteil, fail-closed wie der
# Connector-Filter), Abstimmungsergebnisse nie, Gremien nur als anonyme Indizes,
# Dokumentnamen und Suchterme nie. Nicht verstandene Endpunkte werden nur
# gezaehlt (uebersprungen).
#
# Der Generator (#313) liest Skelett-Bericht (Formate) plus Strukturprofil
# (Belegung) und fuellt beides mit erfundenen Inhalten (Universum Gartenstadt).
#
# Nur OTP, keine Deps — wie die Geschwister-Skripte.

Code.require_file("./ris_http.exs", __DIR__)

defmodule KomkiConnectorRis.RisStruktur do
  @moduledoc false

  @usage "Aufruf: --cassette <dir> [--out <datei>]"

  @spec extract(Path.t()) :: map()
  def extract(dir) do
    classified =
      dir
      |> cassette_files()
      |> Enum.map(&load_cassette/1)
      |> Enum.map(&classify/1)

    sitzungen = for {:meeting, body} <- classified, do: meeting_profile(body)

    public_ids = public_top_ids(sitzungen)

    tops =
      for {:top, body} <- classified, do: top_profile(body, public_ids)

    gremien = committee_indices(sitzungen)

    %{
      "version" => 1,
      "gremien" => map_size(gremien),
      "sitzungen" =>
        sitzungen |> Enum.sort_by(& &1["id"]) |> Enum.map(&finalize_sitzung(&1, gremien)),
      "tops" => Enum.sort_by(tops, & &1["id"]),
      "downloads" => for({:download, ext} <- classified, do: ext),
      "uebersprungen" => count_skipped(classified)
    }
  end

  @doc false
  @spec parse_cli([String.t()]) :: {:ok, keyword()} | {:error, String.t()}
  def parse_cli(argv) do
    case parse_flags(argv, []) do
      {:ok, opts} ->
        cond do
          not Keyword.has_key?(opts, :cassette) ->
            {:error, @usage}

          not File.dir?(opts[:cassette]) ->
            {:error, "Kassettenverzeichnis existiert nicht: #{opts[:cassette]}"}

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

  defp parse_flags(_other, _acc), do: {:error, @usage}

  # --- Kassetten laden ---------------------------------------------------------

  defp cassette_files(dir) do
    dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.sort()
    |> Enum.map(&Path.join(dir, &1))
  end

  defp load_cassette(file) do
    %{"request" => request, "response" => response} = file |> File.read!() |> :json.decode()

    response_body =
      case Map.fetch(response, "body_b64") do
        {:ok, b64} -> Base.decode64!(b64)
        :error -> Map.get(response, "body", "")
      end

    %{request: request, response: response, response_body: response_body}
  end

  # --- Klassifizieren ----------------------------------------------------------

  # Reihenfolge: documents vor agendaitems, damit der Download-Pfad nie als
  # TOP-Detail missverstanden wird.
  defp classify(cassette) do
    path = cassette.request["path"]

    cond do
      cassette.response["status"] != 200 ->
        {:skip, endpoint_key(cassette)}

      String.starts_with?(path, "/agendaitems/documents/") ->
        {:download, fileext(cassette.response)}

      Regex.match?(~r|^/agendaitems/\d+-\d+$|, path) ->
        case decode_json(cassette.response_body) do
          {:ok, body} when is_map(body) -> {:top, body}
          _ -> {:skip, endpoint_key(cassette)}
        end

      Regex.match?(~r|^/meetings/\d+$|, path) ->
        case decode_json(cassette.response_body) do
          {:ok, body} when is_map(body) -> {:meeting, body}
          _ -> {:skip, endpoint_key(cassette)}
        end

      true ->
        {:skip, endpoint_key(cassette)}
    end
  end

  # Endpunktschluessel ohne konkrete Ids: Ziffern zu {id}, Paare zu
  # {meetingId-agendaId}, Tripel zu {meetingId-agendaId-docId}.
  defp endpoint_key(cassette) do
    path =
      cassette.request["path"]
      |> String.split("/", trim: true)
      |> Enum.map(&normalize_segment/1)
      |> Enum.join("/")

    "#{cassette.request["method"]} /#{path}"
  end

  defp normalize_segment(segment) do
    cond do
      Regex.match?(~r/^\d+-\d+-\d+$/, segment) -> "{meetingId-agendaId-docId}"
      Regex.match?(~r/^\d+-\d+$/, segment) -> "{meetingId-agendaId}"
      Regex.match?(~r/^\d+$/, segment) -> "{id}"
      true -> segment
    end
  end

  defp decode_json(body) do
    {:ok, :json.decode(body)}
  rescue
    _ -> :error
  end

  # --- Profile -----------------------------------------------------------------

  # gremium_name ist transient: Es fliegt erst in den Index, dann raus.
  defp meeting_profile(body) do
    %{
      "id" => body["id"],
      "datum" => body["meetingdate"],
      "nummer" => body["num"],
      "state" => body["state"],
      "gremium_name" => body["committeename"],
      "teile" => Enum.map(array(body["parts"]), &teil_profile/1),
      "dokumente" => Enum.map(array(body["documents"]), &sitzungs_dokument/1)
    }
  end

  defp finalize_sitzung(sitzung, gremien) do
    sitzung
    |> Map.put("gremium", Map.get(gremien, sitzung["gremium_name"]))
    |> Map.delete("gremium_name")
  end

  defp teil_profile(%{} = teil) do
    protected = protected?(teil["protectedpart"])

    %{
      "protectedpart" => protected,
      "tops" => Enum.map(array(teil["agendaitems"]), &top_im_teil(&1, protected))
    }
  end

  defp top_im_teil(%{} = top, protected) do
    profile = %{
      "id" => top["id"],
      "numbering" => top["numbering"],
      "restricted" => restricted?(top["restricted"]),
      "documentcount" => top["documentcount"],
      "downloadallowed" => flag(top["downloadallowed"])
    }

    if profile["restricted"] == false and protected == false do
      Map.put(profile, "titellaenge", String.length(top["name"] || ""))
    else
      profile
    end
  end

  defp top_profile(body, public_ids) do
    profile = %{
      "id" => body["id"],
      "numbering" => body["numbering"],
      "restricted" => restricted?(body["restricted"]),
      "textsanddocsvisible" => flag(body["textsanddocsvisible"]),
      "downloadallowed" => flag(body["downloadallowed"]),
      "textbloecke" => length(array(body["textblocks"])),
      "abstimmungen" => length(array(body["votings"])),
      "conorderitems" => length(array(body["conorderitems"])),
      "dokumente" => Enum.map(array(body["documents"]), &top_dokument/1)
    }

    # Fail-closed: Nur wenn der TOP in einer aufgezeichneten Tagesordnung als
    # oeffentlich belegt ist (restricted=false in ungeschuetztem Teil), darf
    # seine Titellaenge ins Profil — nie nach dem Detail-Body allein.
    if profile["restricted"] == false and body["id"] in public_ids do
      Map.put(profile, "titellaenge", String.length(body["name"] || ""))
    else
      profile
    end
  end

  defp sitzungs_dokument(%{} = dokument),
    do: %{"fileext" => dokument["fileext"], "isprotected" => flag(dokument["isprotected"])}

  defp top_dokument(%{} = dokument),
    do: %{"fileext" => dokument["fileext"], "guestvisible" => flag(dokument["guestvisible"])}

  defp fileext(response) do
    case header_value(response["headers"], "content-type") do
      "application/pdf" <> _ -> "pdf"
      "application/json" <> _ -> "json"
      "text/html" <> _ -> "html"
      _ -> "unbekannt"
    end
  end

  defp header_value(headers, name) do
    Enum.find_value(array(headers), fn
      [^name, value] -> value
      _other -> nil
    end)
  end

  defp count_skipped(classified) do
    Enum.reduce(classified, %{}, fn
      {:skip, key}, acc -> Map.update(acc, key, 1, &(&1 + 1))
      _other, acc -> acc
    end)
  end

  # --- Sichtbarkeit und Flaggen --------------------------------------------------

  # Nachweislich oeffentlich ist ein TOP nur mit restricted=false in einem
  # ungeschuetzten Teil — die Ids dafuer stammen ausschliesslich aus
  # aufgezeichneten Tagesordnungen (meetings/{id}), nie aus TOP-Details.
  defp public_top_ids(sitzungen) do
    sitzungen
    |> Enum.flat_map(& &1["teile"])
    |> Enum.reject(& &1["protectedpart"])
    |> Enum.flat_map(& &1["tops"])
    |> Enum.reject(& &1["restricted"])
    |> Enum.map(& &1["id"])
    |> MapSet.new()
  end

  # Fail-closed wie im Connector: alles ausser explizit false gilt als
  # nicht-oeffentlich bzw. geschuetzt.
  defp restricted?(value), do: value != false
  defp protected?(value), do: value != false

  # Faehigkeits-Flaggen: fehlende Werte gelten als abwesend.
  defp flag(value), do: value == true

  defp committee_indices(sitzungen) do
    sitzungen
    |> Enum.map(& &1["gremium_name"])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.with_index(1)
    |> Map.new(fn {name, index} -> {name, "c#{index}"} end)
  end

  defp array(nil), do: []
  defp array(list) when is_list(list), do: list
  defp array(_other), do: []
end

KomkiConnectorRis.RisHttp.cli(System.argv(), fn argv ->
  case KomkiConnectorRis.RisStruktur.parse_cli(argv) do
    {:ok, opts} ->
      profil = KomkiConnectorRis.RisStruktur.extract(opts[:cassette])
      json = profil |> :json.encode() |> IO.iodata_to_binary()

      if out = opts[:out] do
        File.write!(out, json <> "\n")
        IO.puts("ris_struktur: Profil nach #{out}")
      else
        IO.puts(json)
      end

    {:error, usage} ->
      IO.puts(:stderr, "ris_struktur: #{usage}")
      exit({:shutdown, 1})
  end
end)
