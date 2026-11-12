defmodule WegwerfHub.Store do
  @moduledoc """
  DURCHSTICH #409 (Wegwerf): Der Bestand des Wegwerf-Hubs — Vorschläge
  mit Teilen und Verlauf, als JSON-Dateien im Hub-Verzeichnis. Kein
  Cache: jede Anfrage liest und schreibt die Dateien, damit die
  Verwaltungs-Befehle des CLI neben dem laufenden Server funktionieren.

  Ein Vorschlag ist das Ereignis aus komki (ADR 0004): Teile sind
  abwählbar, abgewählte Teile werden GELÖSCHT (11.12), der Verlauf
  hält nur fest, dass Teile nicht übernommen wurden. Jeder Teil trägt
  den Prüfstatus „nicht-verifiziert“, den nur ein Mensch im Hub ändert
  (11.9 — der Agent kann ihn nicht setzen).
  """

  alias KomkiPolicy.JSON

  @vorschlaege "vorschlaege.json"
  @verlauf "verlauf.json"
  @anfragen "anfragen.log"

  # -------------------------------------------------------------------------
  # Lesen
  # -------------------------------------------------------------------------

  @doc "Alle Vorschläge, nach Kennung sortiert."
  @spec vorschlaege(Path.t()) :: [map()]
  def vorschlaege(dir) do
    dir
    |> read_map(@vorschlaege)
    |> Map.values()
    |> Enum.sort_by(& &1["id"])
  end

  @doc "Ein Vorschlag nach Kennung."
  @spec vorschlag(Path.t(), String.t()) :: {:ok, map()} | :error
  def vorschlag(dir, id) do
    case Map.fetch(read_map(dir, @vorschlaege), id) do
      {:ok, proposal} -> {:ok, proposal}
      :error -> :error
    end
  end

  @doc "Der Verlauf, älteste Einträge zuerst."
  @spec verlauf(Path.t()) :: [map()]
  def verlauf(dir), do: read_list(dir, @verlauf)

  @doc "Anzahl der Connector-Anfragen an den Hub (aus dem Anfrage-Log)."
  @spec anfragen(Path.t()) :: non_neg_integer()
  def anfragen(dir) do
    path = Path.join(dir, @anfragen)

    case File.read(path) do
      {:ok, ""} -> 0
      {:ok, log} -> log |> String.split("\n", trim: true) |> length()
      {:error, _} -> 0
    end
  end

  # -------------------------------------------------------------------------
  # Schreiben
  # -------------------------------------------------------------------------

  @doc """
  Nimmt einen Vorschlag aus komki auf (die Connector-Operation): nächste
  freie Kennung, alle Teile „offen“ und „nicht-verifiziert“, Status
  „offen“. Gibt die Kennung zurück (sie verlässt den Hub nie Richtung
  komki — die Quittung ist fix).

  Unsichtbare Steuerzeichen entfallen aus jedem Freitextfeld (Szene 13.6,
  „gilt schon im ersten Wurf“): Was die Redaktion sieht, ist alles, was
  gespeichert ist — verdeckte Anweisungen in der unsichtbaren Wortwahl
  bleiben möglich (G2), unsichtbare Anweisungen nicht.
  """
  @spec annehmen(Path.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def annehmen(dir, incoming) do
    with {:ok, id} <-
           write_atomic(dir, @vorschlaege, %{}, fn proposals ->
             id = next_id(map_size(proposals) + 1, proposals)

             proposal =
               %{
                 "id" => id,
                 "titel" => sauber(incoming["titel"]),
                 "projekt_hinweis" => sauber(incoming["projekt_hinweis"]),
                 "labels" => incoming["labels"],
                 "status" => "offen",
                 "eingegangen" => DateTime.to_iso8601(DateTime.utc_now()),
                 "teile" =>
                   Enum.map(incoming["teile"], fn teil ->
                     %{
                       "aussage" => sauber(teil["aussage"]),
                       "quelle" => sauber(teil["quelle"]),
                       "fundstelle" => sauber(teil["fundstelle"]),
                       "pruefstatus" => "nicht-verifiziert"
                     }
                   end)
               }

             {Map.put(proposals, id, proposal), id}
           end) do
      verlauf_eintrag(dir, "Vorschlag aus komki eingegangen: " <> sauber(incoming["titel"]))
      {:ok, id}
    end
  end

  @unsichtbar ~r/[\x{200B}\x{200C}\x{200D}\x{2060}\x{FEFF}\x{00AD}\x{202A}-\x{202E}\x{2066}-\x{2069}]|\p{Cc}/u

  @doc "Entfernt unsichtbare Steuerzeichen (Szene 13.6); nil bleibt nil."
  @spec sauber(String.t() | nil) :: String.t() | nil
  def sauber(nil), do: nil

  def sauber(text) when is_binary(text),
    do: String.replace(text, @unsichtbar, "", global: true)

  @doc """
  Entscheidung der Redaktion (11.12): `teile` sind die 1-basierten Nummern
  der übernommenen Teile. Nicht übernommene Teile werden gelöscht, der
  Verlauf hält nur ihre Anzahl fest.
  """
  @spec entscheiden(Path.t(), String.t(), [pos_integer()]) :: :ok | {:error, String.t()}
  def entscheiden(dir, id, chosen) do
    with {:ok, proposal} <- vorschlag(dir, id),
         :ok <- closed?(proposal),
         :ok <- im_bereich?(chosen, proposal) do
      teile = proposal["teile"]
      kept = for index <- chosen, do: Enum.at(teile, index - 1)
      nicht = length(teile) - length(kept)

      update!(dir, id, fn proposal ->
        %{
          proposal
          | "status" => "angenommen",
            "teile" => kept
        }
      end)

      verlauf_eintrag(dir, uebernommen_text(kept, nicht))
      :ok
    end
  end

  defp im_bereich?(chosen, proposal) do
    count = length(proposal["teile"])

    if Enum.all?(chosen, &(&1 >= 1 and &1 <= count)),
      do: :ok,
      else: {:error, "Teil-Nummern außerhalb des Vorschlags"}
  end

  @doc "Vorschlag ablehnen: alle Teile weg, Status „abgelehnt“."
  @spec ablehnen(Path.t(), String.t()) :: :ok | {:error, String.t()}
  def ablehnen(dir, id) do
    with {:ok, proposal} <- vorschlag(dir, id),
         :ok <- closed?(proposal) do
      update!(dir, id, fn proposal -> %{proposal | "status" => "abgelehnt", "teile" => []} end)
      verlauf_eintrag(dir, "Vorschlag aus komki abgelehnt: " <> proposal["titel"])
      :ok
    end
  end

  @doc "Eine Zeile ins Anfrage-Log (keine Inhalte, nur Methode, Pfad, Status)."
  @spec anfrage_loggen(Path.t(), String.t(), String.t(), pos_integer()) :: :ok
  def anfrage_loggen(dir, method, path, status) do
    File.mkdir_p!(dir)

    line =
      DateTime.to_iso8601(DateTime.utc_now()) <>
        " " <> method <> " " <> path <> " " <> Integer.to_string(status) <> "\n"

    File.write(Path.join(dir, @anfragen), line, [:append])
    :ok
  end

  # Stand lesen (#419, Szene 12): only these fields enter the stand file. A
  # field the store gains later stays invisible until it is listed here
  # (Gegenprobe 12.7). Open and rejected proposals never appear (12.3).
  @stand_vorschlag ~w(titel)
  @stand_teil ~w(aussage fundstelle pruefstatus quelle)

  @doc """
  Gibt den Stand als Datei aus (`<dir>/stand.json`, atomar): die
  angenommenen Vorschläge mit genau den erlaubten Feldern. Der
  ratsprojekte-Connector liest nur diese Datei, der Hub sieht dabei
  keine Anfrage. Wegwerf-Ersatz für „Stand ausgeben“ (#438).
  """
  @spec stand_ausgeben(Path.t()) :: {:ok, Path.t()}
  def stand_ausgeben(dir) do
    vorschlaege =
      for %{"status" => "angenommen"} = proposal <- vorschlaege(dir) do
        proposal
        |> Map.take(@stand_vorschlag)
        |> Map.put("teile", Enum.map(proposal["teile"], &Map.take(&1, @stand_teil)))
      end

    stand = %{
      "schema" => "wegwerf-stand/1",
      "ausgegeben" => DateTime.to_iso8601(DateTime.utc_now()),
      "vorschlaege" => vorschlaege
    }

    write_map(dir, "stand.json", stand)
    {:ok, Path.join(dir, "stand.json")}
  end

  @doc "Alle Vorschläge löschen (für den Zwei-Welten-Vergleich, 11.4)."
  @spec leeren(Path.t()) :: :ok
  def leeren(dir) do
    write_map(dir, @vorschlaege, %{})
    :ok
  end

  # -------------------------------------------------------------------------
  # Bausteine
  # -------------------------------------------------------------------------

  defp closed?(%{"status" => "offen"}), do: :ok
  defp closed?(%{"status" => status}), do: {:error, "Vorschlag ist bereits #{status}"}

  defp kurze_teile([]), do: "—"
  defp kurze_teile(teile), do: Enum.map_join(teile, ", ", &String.slice(&1["aussage"], 0, 40))

  defp uebernommen_text(kept, nicht) do
    text = "Aus komki übernommen: " <> kurze_teile(kept)

    if nicht > 0 do
      text <>
        " · " <>
        Integer.to_string(nicht) <>
        if(nicht > 1, do: " Teile", else: " Teil") <>
        " nicht übernommen"
    else
      text
    end
  end

  defp next_id(candidate, proposals) do
    id = "v-" <> Integer.to_string(candidate)

    if Map.has_key?(proposals, id),
      do: next_id(candidate + 1, proposals),
      else: id
  end

  defp verlauf_eintrag(dir, text) do
    write_atomic(dir, @verlauf, [], fn verlauf ->
      entry = %{
        "text" => text,
        "datum" => DateTime.to_iso8601(DateTime.utc_now())
      }

      {verlauf ++ [entry], :ok}
    end)

    :ok
  end

  # Atomar schreiben mit Vorher-Nachher-Wert: liest die Datei (Default bei
  # Fehlen), wendet fun an, schreibt tmp + rename. Nebenläufigkeit mit dem
  # Server ist über die einzelne Datei grob serialisiert — für den
  # Wegwerf-Hub genügt das.
  defp write_atomic(dir, file, default, fun) do
    File.mkdir_p!(dir)
    path = Path.join(dir, file)
    current = read_oder(dir, file, default)

    case fun.(current) do
      {new, result} ->
        tmp = path <> ".tmp"
        File.write!(tmp, JSON.canonical(new))
        File.rename!(tmp, path)
        {:ok, result}

      other ->
        {:ok, other}
    end
  end

  defp update!(dir, id, fun) do
    write_atomic(dir, @vorschlaege, %{}, fn proposals ->
      proposal = Map.fetch!(proposals, id)
      {Map.put(proposals, id, fun.(proposal)), :ok}
    end)

    :ok
  end

  defp write_map(dir, file, map) do
    File.mkdir_p!(dir)
    path = Path.join(dir, file)
    tmp = path <> ".tmp"
    File.write!(tmp, JSON.canonical(map))
    File.rename!(tmp, path)
  end

  defp read_oder(dir, file, default) do
    case File.read(Path.join(dir, file)) do
      {:ok, content} when content != "" ->
        case JSON.parse(content) do
          {:ok, term} -> term
          _ -> default
        end

      _ ->
        default
    end
  end

  defp read_map(dir, file) do
    case File.read(Path.join(dir, file)) do
      {:ok, content} when content != "" ->
        case JSON.parse(content) do
          {:ok, map} when is_map(map) -> map
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  defp read_list(dir, file) do
    case File.read(Path.join(dir, file)) do
      {:ok, content} when content != "" ->
        case JSON.parse(content) do
          {:ok, list} when is_list(list) -> list
          _ -> []
        end

      _ ->
        []
    end
  end
end
