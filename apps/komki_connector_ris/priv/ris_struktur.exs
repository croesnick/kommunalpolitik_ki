# Structure extractor for RIS cassettes (priv/ris_recorder.exs).
#
#     elixir apps/komki_connector_ris/priv/ris_struktur.exs --cassette <dir> \
#       [--out <file>]
#
# Companion to the skeleton report for the generator from #313: the structure
# profile carries the occupancy per meeting and TOP -- which meeting parts are
# protected, which TOPs are restricted, how many text blocks, votes and
# documents they have, how long their titles are. No contents: only what
# guests could also see in the RIS is portable. Title lengths only for
# verifiably public TOPs (restricted=false AND unprotected meeting part,
# fail-closed like the connector filter), voting results never, committees
# only as anonymous indices, document names and search terms never. Endpoints
# that are not understood are only counted (skipped).
#
# The generator (#313) reads the skeleton report (formats) plus the structure
# profile (occupancy) and fills both with invented contents (Gartenstadt
# universe).
#
# OTP only, no deps -- like the sibling scripts.

Code.require_file("./ris_http.exs", __DIR__)

defmodule KomkiConnectorRis.RisStruktur do
  @moduledoc false

  alias KomkiConnectorRis.RisHttp

  @usage "Aufruf: --cassette <dir> [--out <datei>]"

  @spec extract(Path.t()) :: map()
  def extract(dir) do
    classified =
      dir
      |> RisHttp.cassette_files()
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
      "downloads" => for({:download, ext} <- classified, do: ext) |> Enum.sort(),
      "uebersprungen" => count_skipped(classified)
    }
  end

  @doc false
  @spec parse_cli([String.t()]) :: {:ok, keyword()} | {:error, String.t()}
  def parse_cli(argv) do
    case RisHttp.parse_flags(argv, cassette: :string, out: :string) do
      {:ok, opts} ->
        cond do
          not Keyword.has_key?(opts, :cassette) ->
            {:error, @usage}

          not File.dir?(opts[:cassette]) ->
            {:error, "Kassettenverzeichnis existiert nicht: #{opts[:cassette]}"}

          true ->
            {:ok, opts}
        end

      :error ->
        {:error, @usage}
    end
  end

  # --- Loading cassettes -------------------------------------------------------

  defp load_cassette(file) do
    %{"request" => request, "response" => response} = file |> File.read!() |> :json.decode()

    %{request: request, response: response, response_body: RisHttp.part_body(response)}
  end

  # --- Classifying -------------------------------------------------------------

  # Order: documents before agendaitems, so the download path is never
  # mistaken for a TOP detail.
  defp classify(cassette) do
    path = cassette.request["path"]

    cond do
      cassette.response["status"] != 200 ->
        {:skip, endpoint_key(cassette)}

      String.starts_with?(path, "/agendaitems/documents/") ->
        {:download, fileext(cassette.response)}

      Regex.match?(~r|^/agendaitems/\d+-\d+$|, path) ->
        case RisHttp.decode_json(cassette.response_body) do
          {:ok, body} when is_map(body) -> {:top, body}
          _ -> {:skip, endpoint_key(cassette)}
        end

      Regex.match?(~r|^/meetings/\d+$|, path) ->
        case RisHttp.decode_json(cassette.response_body) do
          {:ok, body} when is_map(body) -> {:meeting, body}
          _ -> {:skip, endpoint_key(cassette)}
        end

      true ->
        {:skip, endpoint_key(cassette)}
    end
  end

  # Endpoint key without concrete ids: digits become {id}, pairs become
  # {meetingId-agendaId}, triples become {meetingId-agendaId-documentId}.
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
      Regex.match?(~r/^\d+-\d+-\d+$/, segment) -> "{meetingId-agendaId-documentId}"
      Regex.match?(~r/^\d+-\d+$/, segment) -> "{meetingId-agendaId}"
      Regex.match?(~r/^\d+$/, segment) -> "{id}"
      true -> segment
    end
  end

  # --- Profiles ----------------------------------------------------------------

  # gremium_name is transient: it goes into the index first, then out.
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

    # Fail-closed: only if the TOP is listed as public in a recorded agenda
    # (restricted=false in an unprotected part) may its title length enter the
    # profile -- never from the detail body alone.
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
      "application/octet-stream" <> _ -> "octet-stream"
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

  # --- Visibility and flags ------------------------------------------------------

  # A TOP is verifiably public only with restricted=false in an unprotected
  # part -- the ids for this come exclusively from recorded agendas
  # (meetings/{id}), never from TOP details.
  defp public_top_ids(sitzungen) do
    sitzungen
    |> Enum.flat_map(& &1["teile"])
    |> Enum.reject(& &1["protectedpart"])
    |> Enum.flat_map(& &1["tops"])
    |> Enum.reject(& &1["restricted"])
    |> Enum.map(& &1["id"])
    |> MapSet.new()
  end

  # Fail-closed as in the connector: everything except an explicit false
  # counts as non-public or protected, respectively.
  defp restricted?(value), do: value != false
  defp protected?(value), do: value != false

  # Capability flags: missing values count as absent.
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
