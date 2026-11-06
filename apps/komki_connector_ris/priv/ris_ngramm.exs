# N-gram comparison for synthetic RIS cassettes (ticket #313).
#
#     elixir apps/komki_connector_ris/priv/ris_ngramm.exs \
#       --synthetisch <dir> --echt <dir> [--gramm <n>]
#
# Release gate before every commit of synthetic cassettes: an n-gram
# comparison against the real recordings checks that no real content has
# slipped through. Compared are word n-grams (default: 6 words) over all
# string values of the response bodies, with Base64-HTML decoded; one
# matching n-gram is a finding. Structural and boilerplate texts (session
# of the city council …) share short spans, but never six words — hence
# the threshold.
#
# Runs locally at the user's machine over the decrypted real cassettes
# (unseal → run → seal), because no agent ever reads real cassettes. The
# messages name file names and the found span itself — that one may be
# visible: it is precisely the leak.
#
# OTP only, no deps — like the sibling scripts.

Code.require_file("./ris_http.exs", __DIR__)

defmodule KomkiConnectorRis.RisNgramm do
  @moduledoc false

  @usage "Aufruf: --synthetisch <dir> --echt <dir> [--gramm <n>]"
  @standard_gramm 6

  @type fund :: {String.t(), String.t()}

  @doc """
  Checks the word n-grams of all response strings of the synthetic
  cassettes against those of the real ones. Returns the findings per file
  (name, span) and the number of files checked.
  """
  @spec pruefen(Path.t(), Path.t(), pos_integer()) :: %{
          funde: [fund()],
          geprueft: non_neg_integer()
        }
  def pruefen(synthetisch, echt, n \\ @standard_gramm) do
    echte = gram_menge(echt, n)

    je_datei =
      synthetisch
      |> kassetten_texte()
      |> Enum.map(fn {datei, texte} ->
        {datei, texte |> woerter() |> gramme(n) |> Enum.uniq() |> treffer(echte)}
      end)

    %{
      funde: Enum.filter(je_datei, fn {_datei, streifen} -> streifen != [] end),
      geprueft: length(je_datei)
    }
  end

  @doc false
  @spec parse_cli([String.t()]) :: {:ok, keyword()} | {:error, String.t()}
  def parse_cli(argv) do
    case parse_flags(argv, []) do
      {:ok, opts} ->
        cond do
          not Keyword.has_key?(opts, :synthetisch) ->
            {:error, @usage}

          not Keyword.has_key?(opts, :echt) ->
            {:error, @usage}

          not File.dir?(opts[:synthetisch]) ->
            {:error, "Synthetik-Verzeichnis existiert nicht: #{opts[:synthetisch]}"}

          not File.dir?(opts[:echt]) ->
            {:error, "Echt-Verzeichnis existiert nicht: #{opts[:echt]}"}

          true ->
            {:ok, opts}
        end

      {:error, _} ->
        {:error, @usage}
    end
  end

  defp parse_flags([], acc), do: {:ok, acc}

  defp parse_flags(["--synthetisch", wert | rest], acc),
    do: parse_flags(rest, Keyword.put(acc, :synthetisch, wert))

  defp parse_flags(["--echt", wert | rest], acc),
    do: parse_flags(rest, Keyword.put(acc, :echt, wert))

  defp parse_flags(["--gramm", wert | rest], acc),
    do: parse_flags(rest, Keyword.put(acc, :gramm, wert))

  defp parse_flags(_other, _acc), do: {:error, @usage}

  @doc false
  @spec gramm_aus(keyword()) :: {:ok, pos_integer()} | {:error, String.t()}
  def gramm_aus(opts) do
    case Keyword.get(opts, :gramm) do
      nil ->
        {:ok, @standard_gramm}

      wert ->
        case Integer.parse(wert) do
          {n, ""} when n >= 2 -> {:ok, n}
          _other -> {:error, "--gramm erwartet eine Zahl ab 2"}
        end
    end
  end

  # --- Reading cassettes ------------------------------------------------------------

  defp gram_menge(dir, n) do
    dir
    |> kassetten_texte()
    |> Enum.flat_map(fn {_datei, texte} -> texte |> woerter() |> gramme(n) end)
    |> MapSet.new()
  end

  # All string values per cassette: response JSON bodies recursively, with
  # Base64-HTML decoded; non-JSON bodies (e.g. PDFs) as raw text.
  defp kassetten_texte(dir) do
    dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.sort()
    |> Enum.map(fn name ->
      kassette = name |> Path.expand(dir) |> File.read!() |> :json.decode()
      roh = antwort_body(kassette)

      texte =
        case decode_json(roh) do
          {:ok, term} when is_map(term) or is_list(term) -> strings(term)
          _other -> [roh]
        end

      {name, texte}
    end)
  end

  defp antwort_body(kassette) do
    case Map.fetch(kassette["response"], "body_b64") do
      {:ok, b64} -> Base.decode64!(b64)
      :error -> Map.get(kassette["response"], "body", "")
    end
  end

  defp decode_json(body) do
    {:ok, :json.decode(body)}
  rescue
    _ -> :error
  end

  defp strings(map) when is_map(map),
    do: Enum.flat_map(map, fn {_schluessel, wert} -> strings(wert) end)

  defp strings(list) when is_list(list), do: Enum.flat_map(list, &strings/1)

  defp strings(binaer) when is_binary(binaer), do: [klartext(binaer)]
  defp strings(_wert), do: []

  # Like the connector (Top.plain): Base64 that decodes as UTF-8 with
  # tags is HTML and is considered decoded; everything else stays as-is.
  defp klartext(binaer) do
    case Base.decode64(binaer) do
      {:ok, dekodiert} ->
        if String.valid?(dekodiert) and dekodiert =~ "<" and dekodiert =~ ">",
          do: dekodiert,
          else: binaer

      :error ->
        binaer
    end
  end

  # --- Grams ------------------------------------------------------------------------

  defp woerter(texte) do
    texte
    |> Enum.join(" ")
    |> String.downcase()
    |> then(&String.split(&1, ~r|[^[:alnum:]\p{L}\p{N}-]+|u, trim: true))
  end

  defp gramme(worte, n) do
    anzahl = length(worte)

    if anzahl < n do
      []
    else
      Enum.map(0..(anzahl - n)//1, fn i -> worte |> Enum.slice(i, n) |> Enum.join(" ") end)
    end
  end

  defp treffer(gramme_liste, echte) do
    Enum.filter(gramme_liste, &MapSet.member?(echte, &1))
  end
end

KomkiConnectorRis.RisHttp.cli(System.argv(), fn argv ->
  alias KomkiConnectorRis.RisNgramm

  case RisNgramm.parse_cli(argv) do
    {:ok, opts} ->
      case RisNgramm.gramm_aus(opts) do
        {:ok, n} ->
          ergebnis = RisNgramm.pruefen(opts[:synthetisch], opts[:echt], n)

          IO.puts(
            "ris_ngramm: #{ergebnis.geprueft} Dateien geprueft, " <>
              "#{length(ergebnis.funde)} Datei(en) mit Fund"
          )

          Enum.each(ergebnis.funde, fn {datei, streifen} ->
            Enum.each(streifen, &IO.puts("ris_ngramm: FUND #{datei}: #{&1}"))
          end)

          if ergebnis.funde != [], do: exit({:shutdown, 1})

        {:error, meldung} ->
          IO.puts(:stderr, "ris_ngramm: #{meldung}")
          exit({:shutdown, 1})
      end

    {:error, usage} ->
      IO.puts(:stderr, "ris_ngramm: #{usage}")
      exit({:shutdown, 1})
  end
end)
