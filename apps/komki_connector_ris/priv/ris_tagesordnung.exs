# Tagesordnung eines Sitzungstags als Klartext lesen und auf ungelöste
# HTML-Entities pruefen (#547). Das Skript faehrt dieselben Wege wie der
# Connector (KomkiConnectorRis): Sitzungsliste, Detail je Sitzung, je
# oeffentlichem TOP die Textbloecke — und zaehlt, was nach der Dekodierung
# (KomkiConnectorRis.Top) noch wie eine HTML-Entity aussieht.
#
#     cd apps/komki_connector_ris
#     mix run priv/ris_tagesordnung.exs -- --datum 2026-11-17 [--anmelden]
#
# Anders als die Familien-Skripte ohne App-Code (ris_recorder & Co., per
# `elixir` startbar) braucht dieses die App-Module: `mix run` aus dem
# App-Verzeichnis. Ohne --anmelden laeuft es als Gast; dann liefern die
# Endpunkte meist keine Textbloecke und die Zaehlung sagt nichts ueber die
# Entity-Dekodierung. Mit --anmelden liest es das Zugangssiegel aus dem
# macOS-Schluesselbund (Eintrag ris-zugang, wie komki ihn anlegt) und oeffnet
# es ueber komki-tresor: genau eine Freigabe per Touch ID pro Lauf, wie bei
# jeder Anmeldung im laufenden komki (Entscheid 2026-10-25 in #148).
# Schluesselbund- und Tresor-Bausteine teilt es mit ris_cassettes, das sie
# als Familienmitglied bereithaelt; davor markiert es sich als Lader, damit
# deren Einschnitt die Aufrufzeile nicht als eigene behandelt.
#
# Ausgabe: je Sitzung die TOPs (Nummer, Titel, Zeichen, ungelöste Entities),
# am Ende „Texte mit ungelösten HTML-Entities: N“. Was nicht lesbar war,
# steht je Sitzung und TOP als Lesefehler in eigenen Zeilen und zaehlt in
# der Summe „Lesefehler: N“ mit in den Exit-Code: Ein Bericht „0“ ueber
# ungelesene Texte waere ein falsches Entlastungszeugnis. Meldungen nennen
# nie Zugangsdaten, Siegel oder Token. Exit-Codes: 0 ohne ungelöste Entities
# und ohne Lesefehler, 1 fachlicher Befund (keine Sitzung, Lesefehler,
# ungelöste Entities), 2 Aufruf falsch.

Code.require_file("./ris_http.exs", __DIR__)

# Bibliotheks-Modus fuer ris_cassettes: erst markieren, dann laden.
Process.put({KomkiConnectorRis.RisCassettes, :als_bibliothek}, true)
Code.require_file("./ris_cassettes.exs", __DIR__)

defmodule KomkiConnectorRis.RisTagesordnung do
  @moduledoc false

  alias KomkiConnectorRis.{Api, Http, Top}
  alias KomkiConnectorRis.{RisCassettes, RisHttp}

  @default_base_url "https://risapi3.komuna.net/web/"
  @service "ris-zugang"
  @touch_id_reason "RIS-Tagesordnung lesen"
  @timeout_ms 5_000
  # Ein Sitzungstag hat viele TOPs; die Frist gilt fuer den ganzen Lauf —
  # aber erst ab der Freigabe: Die Wartezeit auf Touch ID gehoert nicht ins
  # Lese-Budget.
  @budget_ms 120_000

  # Alles, was nach der Dekodierung noch einer Entity-Syntax entspricht,
  # ist ungeloest: unbekannter Name oder ungueltiger Codepunkt.
  @unresolved ~r/&(#\d{1,7}|#x[0-9a-fA-F]{1,6}|[a-zA-Z][a-zA-Z0-9]*);/

  @usage "Aufruf: mix run priv/ris_tagesordnung.exs -- --datum <YYYY-MM-DD> " <>
           "[--anmelden] [--base-url <url>] [--tresor <programm>]"

  # --- CLI -------------------------------------------------------------------

  @doc false
  @spec parse_cli([String.t()]) :: {:ok, map()} | {:error, String.t()}
  def parse_cli(argv) do
    {anmelden, argv} = split_flag(drop_separator(argv), "--anmelden")

    case RisHttp.parse_flags(argv, datum: :string, base_url: :string, tresor: :string) do
      {:ok, flags} -> with_datum(flags, anmelden)
      :error -> {:error, "ris_tagesordnung: " <> @usage}
    end
  end

  # mix run gibt das Trennzeichen selbst mit: `mix run skript -- --flag`
  # liefert ["--", "--flag", ...]. Die Familien-Skripte ohne App-Code starten
  # per elixir und sehen es nie; dieses hier laeuft per mix run.
  defp drop_separator(["--" | rest]), do: rest
  defp drop_separator(argv), do: argv

  # --anmelden traegt keinen Wert: Es wird herausgetrennt, bevor
  # parse_flags jedes Flag mit Wert erwartet.
  defp split_flag(argv, flag) do
    if flag in argv,
      do: {true, Enum.reject(argv, &(&1 == flag))},
      else: {false, argv}
  end

  defp with_datum(flags, anmelden) do
    case flags[:datum] do
      nil ->
        {:error, "ris_tagesordnung: " <> @usage}

      raw ->
        case Date.from_iso8601(raw) do
          {:ok, datum} ->
            {:ok,
             %{
               datum: datum,
               anmelden: anmelden,
               base_url: Keyword.get(flags, :base_url, @default_base_url),
               tresor: Keyword.get(flags, :tresor)
             }}

          {:error, _ungueltig} ->
            {:error, "ris_tagesordnung: --datum <YYYY-MM-DD>, nicht #{inspect(raw)}"}
        end
    end
  end

  @doc """
  Befehlszeile abarbeiten: `{exit_code, meldungen}` statt Prozess-Exit —
  Tests laufen ueber diese Funktion, der Einschnitt unten druckt nur.
  `opts` reicht Durchreichen an die Schluesselbund- und Tresor-Bausteine
  (`:security`, `:tresor`), wie es ris_cassettes vorlebt: Die echte
  Keychain und die echte Enclave bleiben draussen.
  """
  @spec run([String.t()], keyword()) :: {non_neg_integer(), [{:out | :err, String.t()}]}
  def run(argv, opts \\ []) do
    case parse_cli(argv) do
      {:ok, request} -> bericht(request, opts)
      {:error, usage} -> {2, [{:err, usage}]}
    end
  end

  # --- Bericht -----------------------------------------------------------------

  defp bericht(%{anmelden: anmelden} = request, opts) do
    case sitzungen(request, opts) do
      {:ok, {lines, unresolved, fehler}} ->
        gast =
          if anmelden,
            do: [],
            else: ["Gast-Modus: ohne --anmelden fehlen die Textblöcke meist; ungelöste Entities sagen dann nichts über die Dekodierung."]

        lesefehler = if fehler > 0, do: ["Lesefehler: #{fehler}"], else: []

        meldungen =
          gast ++ lines ++ lesefehler ++ ["Texte mit ungelösten HTML-Entities: #{unresolved}"]

        {if(unresolved == 0 and fehler == 0, do: 0, else: 1), Enum.map(meldungen, &{:out, &1})}

      {:error, message} ->
        {1, [{:err, "ris_tagesordnung: " <> message}]}
    end
  end

  # Alle Sitzungen des Tages, mit Anmeldung die Texte je oeffentlichem TOP.
  defp sitzungen(%{datum: datum, base_url: base_url} = request, opts) do
    with {:ok, cfg} <- start(base_url),
         {:ok, cfg} <- anmelden(cfg, request, opts),
         {:ok, meetings} <- Api.meetings(cfg, Date.add(datum, -1), Date.add(datum, 1)) do
      tag = Date.to_iso8601(datum)

      case Enum.filter(meetings, &sitzt_am?(&1, tag)) do
        [] ->
          {:error, "keine öffentliche Sitzung am #{tag}"}

        sitzungen ->
          {lines, unresolved, fehler} =
            Enum.reduce(sitzungen, {[], 0, 0}, fn meeting, {lines, unresolved, fehler} ->
              {meeting_lines, n, m} = bericht_sitzung(meeting, cfg)
              {lines ++ meeting_lines, unresolved + n, fehler + m}
            end)

          {:ok, {lines, unresolved, fehler}}
      end
    else
      {:error, _code, message} -> {:error, message}
      {:error, message} -> {:error, message}
    end
  end

  defp sitzt_am?(meeting, tag) do
    match?(%{"id" => id} when is_integer(id) and id > 0, meeting) and
      Top.date(meeting["meetingdate"]) == tag
  end

  defp start(base_url) do
    case Http.start(nil) do
      :ok -> {:ok, %{base_url: base_url, timeout_ms: @timeout_ms, token: nil}}
      {:error, reason} -> {:error, "HTTP-Start fehlgeschlagen: #{inspect(reason)}"}
    end
  end

  # Gast ohne Flag (Frist ab hier), sonst eine Freigabe per Touch ID fuer
  # das Siegel — und die Frist erst danach.
  defp anmelden(cfg, %{anmelden: false}, _opts), do: {:ok, frist(cfg)}

  defp anmelden(cfg, %{anmelden: true, tresor: tresor}, opts) do
    opts =
      if tresor do
        Keyword.put(opts, :tresor, tresor)
      else
        opts
      end

    with {:ok, sealed} <- tag(:schluesselbund, RisCassettes.kc_fetch(@service, opts)),
         {:ok, zugang} <- tag(:tresor, RisCassettes.tresor_open(sealed, @touch_id_reason, opts)),
         {:ok, login, password} <- parse_zugang(zugang),
         cfg = frist(cfg),
         {:ok, token} <- tag(:anmeldung, Api.login(cfg, login, password)) do
      {:ok, Map.put(cfg, :token, token)}
    else
      {:error, {herkunft, reason}} -> {:error, zugang_text(herkunft, reason)}
    end
  end

  # Fehler behalten ihre Herkunft: gleiche Atome verschiedener Quellen
  # bekommen eigene Meldungen, Api.login liefert seine Fehlerform
  # {code, message} als drittes Element.
  defp tag(_herkunft, {:ok, value}), do: {:ok, value}

  defp tag(herkunft, {:error, code, message}) when is_binary(code) and is_binary(message),
    do: {:error, {herkunft, {code, message}}}

  defp tag(herkunft, {:error, reason}), do: {:error, {herkunft, reason}}

  defp parse_zugang(zugang) do
    case JSON.decode(zugang) do
      {:ok, %{"login" => login, "password" => password}}
      when is_binary(login) and login != "" and is_binary(password) and password != "" ->
        {:ok, login, password}

      _ ->
        {:error,
         {:zugang,
          "Zugangssiegel unvollständig (login und password als JSON); neu setzen mit 'komki secret set ris'"}}
    end
  end

  defp zugang_text(:schluesselbund, :missing),
    do: "Schlüsselbund-Eintrag '#{@service}' fehlt; einmalig 'komki secret set ris'"

  defp zugang_text(:schluesselbund, :timeout), do: "Schlüsselbund-Abfrage nach Timeout abgebrochen"

  defp zugang_text(:schluesselbund, {:failed, code}),
    do: "Schlüsselbund-Befehl mit exit #{code} fehlgeschlagen"

  defp zugang_text(:tresor, :missing_bin), do: "komki-tresor fehlt oder ist nicht ausführbar"
  defp zugang_text(:tresor, :no_enclave), do: "keine Secure Enclave (komki-tresor check)"
  defp zugang_text(:tresor, :refused), do: "Freigabe per Touch ID verweigert"
  defp zugang_text(:tresor, :timeout), do: "Zeitüberschreitung bei der Freigabe"
  defp zugang_text(:tresor, :invalid), do: "Siegel des Eintrags '#{@service}' ist ungültig"

  defp zugang_text(:tresor, {:failed, code}),
    do: "komki-tresor mit exit #{code} fehlgeschlagen"

  defp zugang_text(:anmeldung, {_code, message}), do: message
  defp zugang_text(:zugang, message), do: message

  # --- Sitzung und TOPs ----------------------------------------------------------

  defp frist(cfg), do: Map.put(cfg, :deadline, System.monotonic_time(:millisecond) + @budget_ms)

  defp bericht_sitzung(meeting, cfg) do
    id = meeting["id"]
    name = sitzungsname(meeting, id)

    case Api.meeting(cfg, id) do
      {:ok, detail} ->
        tops = Top.public_items(detail)
        {lines, unresolved, fehler} = tops_text(tops, cfg)

        {
          [
            "Sitzung #{id}: #{name} — #{length(tops)} öffentliche TOPs"
            | Enum.reverse(lines)
          ],
          unresolved,
          fehler
        }

      :not_found ->
        {["Sitzung #{id}: #{name} — vom RIS nicht gefunden (Lesefehler)"], 0, 1}

      {:error, _code, message} ->
        {["Sitzung #{id}: #{name} — Lesen fehlgeschlagen: #{message} (Lesefehler)"], 0, 1}
    end
  end

  defp sitzungsname(meeting, id) do
    case Top.string(meeting["name"]) do
      "" -> "Sitzung #{id}"
      name -> name
    end
  end

  defp tops_text(tops, cfg) do
    Enum.reduce(tops, {[], 0, 0}, fn top, {lines, unresolved, fehler} ->
      case top_text(top, cfg) do
        {:ok, text} ->
          {found, line} = top_line(top, text)
          {[line | lines], unresolved + found, fehler}

        :skipped ->
          {lines, unresolved, fehler}

        :lesefehler ->
          {[lesefehlerzeile(top) | lines], unresolved, fehler + 1}
      end
    end)
  end

  # Derselbe Oeffentlichkeits-Blick wie der Connector: Erst das Detail
  # entscheidet (restricted false), dann zaehlt der Text. Nicht-oeffentliche
  # Details bleiben ohne Fehler ausserhalb der Zaehlung — der Connector
  # wuerde sie ebenfalls nicht zeigen. Nicht lesbar dagegen ist ein
  # Lesefehler: Der Bericht entlastet nur, was er auch gelesen hat. Das
  # gilt auch fuer Textbloecke ueber dem Byte-Budget (#486): Der Connector
  # lehnt sie ab, der Bericht zaehlt sie als Lesefehler.
  defp top_text(top, cfg) do
    case Api.agendaitem(cfg, top["id"]) do
      {:ok, %{"restricted" => false} = detail} ->
        case Top.text(detail, fn -> Api.remaining(cfg) end) do
          {:ok, text} -> {:ok, text}
          {:error, _budget_oder_frist} -> :lesefehler
        end

      {:ok, _detail} -> :skipped
      :not_found -> :lesefehler
      {:error, _code, _message} -> :lesefehler
    end
  end

  defp lesefehlerzeile(top) do
    kopf = "  TOP #{Top.string(top["numbering"])} #{Top.string(top["name"])}"
    "#{kopf}: Text nicht lesbar (Lesefehler)"
  end

  defp top_line(top, text) do
    kopf = "  TOP #{Top.string(top["numbering"])} #{Top.string(top["name"])}"

    case Regex.scan(@unresolved, text) do
      [] ->
        {0, "#{kopf}: #{String.length(text)} Zeichen, keine ungelösten Entities"}

      fundstellen ->
        namen = fundstellen |> Enum.map(&hd/1) |> Enum.uniq() |> Enum.join(", ")
        {1, "#{kopf}: #{String.length(text)} Zeichen, ungelöst: #{namen}"}
    end
  end
end

KomkiConnectorRis.RisHttp.cli(System.argv(), fn argv ->
  {code, meldungen} = KomkiConnectorRis.RisTagesordnung.run(argv)

  Enum.each(meldungen, fn
    {:out, zeile} -> IO.puts(zeile)
    {:err, zeile} -> IO.puts(:stderr, zeile)
  end)

  if code != 0 do
    exit({:shutdown, code})
  end
end)
