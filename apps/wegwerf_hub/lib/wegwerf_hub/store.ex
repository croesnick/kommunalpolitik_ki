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
  """
  @spec annehmen(Path.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def annehmen(dir, incoming) do
    with {:ok, id} <-
           write_atomic(dir, @vorschlaege, fn proposals ->
             id = next_id(map_size(proposals) + 1, proposals)

             proposal =
               %{
                 "id" => id,
                 "titel" => incoming["titel"],
                 "projekt_hinweis" => incoming["projekt_hinweis"],
                 "labels" => incoming["labels"],
                 "status" => "offen",
                 "eingegangen" => DateTime.to_iso8601(DateTime.utc_now()),
                 "teile" =>
                   Enum.map(incoming["teile"], fn teil ->
                     %{
                       "aussage" => teil["aussage"],
                       "quelle" => teil["quelle"],
                       "fundstelle" => teil["fundstelle"],
                       "pruefstatus" => "nicht-verifiziert"
                     }
                   end)
               }

             {Map.put(proposals, id, proposal), id}
           end) do
      verlauf_eintrag(dir, "Vorschlag aus komki eingegangen: " <> incoming["titel"])
      {:ok, id}
    end
  end

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
    write_atomic(dir, @verlauf, fn verlauf ->
      entry = %{
        "text" => text,
        "datum" => DateTime.to_iso8601(DateTime.utc_now())
      }

      {verlauf ++ [entry], :ok}
    end)

    :ok
  end

  # Atomar schreiben mit Vorher-Nachher-Wert: liest die Datei, wendet fun
  # an, schreibt tmp + rename. Nebenläufigkeit mit dem Server ist über die
  # einzelne Datei grob serialisiert — für den Wegwerf-Hub genügt das.
  defp write_atomic(dir, file, fun) do
    File.mkdir_p!(dir)
    path = Path.join(dir, file)
    current = read_map(dir, file)

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
    write_atomic(dir, @vorschlaege, fn proposals ->
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
