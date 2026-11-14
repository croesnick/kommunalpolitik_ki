defmodule KomkiConnectorVault.Paths do
  @moduledoc """
  Pfadhaertung fuer den Vault-Connector — die Hauptsache dieses Connectors.

  Lektion aus dem omac-Sidecar: ein Dienst ausserhalb der Sandbox hat auf
  Wunsch des Agenten ueber einen Symlink `~/.ssh/id_rsa` gelesen. Deshalb:

    * `note_id` ist ein relativer Pfad aus normalen Segmenten. Abgelehnt
      werden absolute Pfade, `..`, leere Segmente, NUL und versteckte
      Segmente (Beginn mit `.`, also auch `.` selbst).
    * Jede Komponente unter dem Vault-Root wird per `File.lstat/1`
      geprueft; ein Symlink irgendwo im Pfad ist `forbidden-path`.
      Symlinks werden nie verfolgt.
    * Zusaetzlich muss der kanonische Pfad (`realpath/1`) unter dem
      kanonischen Vault-Root liegen.

  Der Vault-Root selbst darf ueber Symlinks erreicht werden (z. B.
  `/tmp` → `/private/tmp` auf macOS); er wird beim Start einmal
  kanonisiert.
  """

  @max_links 40

  @type error :: {:error, String.t(), String.t()}

  @doc """
  Kanonischer Pfad: absolut, ohne `.`/`..`, alle Symlinks aufgeloest.
  Die Datei selbst muss existieren.
  """
  @spec realpath(Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def realpath(path) do
    ["/" | segments] = path |> Path.absname() |> Path.split()
    walk("/", segments, @max_links)
  end

  defp walk(current, [], _links), do: {:ok, current}
  defp walk(_current, _segments, 0), do: {:error, :eloop}
  defp walk(current, ["." | rest], links), do: walk(current, rest, links)
  defp walk(current, [".." | rest], links), do: walk(Path.dirname(current), rest, links)

  defp walk(current, [segment | rest], links) do
    next = Path.join(current, segment)

    case File.lstat(next) do
      {:ok, %File.Stat{type: :symlink}} ->
        with {:ok, target} <- File.read_link(next) do
          follow(current, Path.split(target), rest, links - 1)
        end

      {:ok, _stat} ->
        walk(next, rest, links)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Symlink-Ziel: absolut ab "/", relativ ab dem Verzeichnis des Links;
  # ".." wird erst beim Gehen aufgeloest, nicht lexikalisch vorab.
  defp follow(_current, ["/" | target], rest, links), do: walk("/", target ++ rest, links)
  defp follow(current, target, rest, links), do: walk(current, target ++ rest, links)

  @doc """
  Prueft die Segmente einer `note_id` (rein syntaktisch, ohne Dateizugriff).
  """
  @spec segments(String.t()) :: {:ok, [String.t()]} | error()
  def segments(note_id) do
    parts = String.split(note_id, "/")

    cond do
      String.contains?(note_id, <<0>>) -> forbidden("NUL im Pfad")
      String.starts_with?(note_id, "/") -> forbidden("absoluter Pfad")
      Enum.any?(parts, &(&1 == "")) -> forbidden("leeres Segment")
      Enum.any?(parts, &String.starts_with?(&1, ".")) -> forbidden("verstecktes Segment oder ..")
      true -> {:ok, parts}
    end
  end

  @doc """
  Loest eine `note_id` unter `root` (kanonisch) auf. Jede Komponente wird
  per `lstat` geprueft: Symlink → `forbidden-path`, fehlend → `not-found`.
  Die letzte Komponente muss eine regulaere Datei sein. Liefert den Pfad
  und den `File.Stat` der Datei.
  """
  @spec resolve(Path.t(), String.t()) :: {:ok, Path.t(), File.Stat.t()} | error()
  def resolve(root, note_id) do
    with {:ok, parts} <- segments(note_id),
         {:ok, path, stat} <- lstat_chain(root, parts),
         :ok <- regular(stat),
         :ok <- under_root(root, path) do
      {:ok, path, stat}
    end
  end

  defp lstat_chain(root, parts) do
    Enum.reduce_while(parts, {:ok, root, nil}, fn part, {:ok, current, _stat} ->
      next = Path.join(current, part)

      case File.lstat(next) do
        {:ok, %File.Stat{type: :symlink}} -> {:halt, forbidden("Symlink im Pfad")}
        {:ok, stat} -> {:cont, {:ok, next, stat}}
        {:error, _} -> {:halt, not_found()}
      end
    end)
  end

  defp regular(%File.Stat{type: :regular}), do: :ok
  defp regular(_stat), do: not_found()

  @doc "Prueft, dass der kanonische Pfad von `path` unter `root` liegt."
  @spec under_root(Path.t(), Path.t()) :: :ok | error()
  def under_root(root, path) do
    case realpath(path) do
      {:ok, real} ->
        if String.starts_with?(real, root <> "/"),
          do: :ok,
          else: forbidden("ausserhalb des Vaults")

      {:error, _} ->
        not_found()
    end
  end

  defp forbidden(detail), do: {:error, "forbidden-path", detail}
  defp not_found, do: {:error, "not-found", "Notiz nicht gefunden"}
end
