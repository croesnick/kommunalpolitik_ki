defmodule KomkiConnectorVault do
  @moduledoc """
  Vault-Connector (Fassung `komki-vault/1`, CONTRACT.md §5): Lesen und
  Suchen in einem lokalen Markdown-Vault, Schreiben nur in den Testordner.

  Sichtbar sind nur Notizen mit gueltigem Frontmatter-Feld `komki_labels`
  (nicht leer, jeder Eintrag in der Form einer Bindungs-ID `kennung@version`).
  Welche Labels gelten, entscheidet der Vermittler gegen Γ (Ticket #211). Alle
  anderen Notizen sind unsichtbar: nicht in `search`, `read` liefert
  `not-found`. Der Connector liefert oeffentliche und vertrauliche Notizen
  gleichermassen samt Labels — filtern tut der Vermittler (Gate 2).

  Zustand: `%{root: <kanonischer Vault-Root>}`.
  """

  @behaviour KomkiConnector.Server

  alias KomkiConnector.Manifest
  alias KomkiConnectorVault.{Note, Paths, Writer}

  @max_bytes 1_048_576
  @max_results 20

  @impl true
  def manifest_id, do: "vault"

  @impl true
  def init(vault_dir) when is_binary(vault_dir) do
    case Paths.realpath(vault_dir) do
      {:ok, root} ->
        if File.dir?(root),
          do: {:ok, %{root: root}},
          else: {:error, "--vault-dir ist kein Verzeichnis"}

      {:error, _} ->
        {:error, "--vault-dir nicht gefunden"}
    end
  end

  def init(_), do: {:error, "--vault-dir fehlt"}

  @impl true
  def handle_op("search", %{"text" => text}, _context, state), do: search(state.root, text)
  def handle_op("read", %{"note_id" => note_id}, _context, state), do: read(state.root, note_id)

  def handle_op("write_test", params, context, state),
    do: Writer.write(state.root, params, context, &label?/1)

  @doc """
  Form einer Bindungs-ID (`kennung@version`). Ob ein Label gilt, prueft der
  Vermittler gegen Γ (Gate 2, Ticket #211); der Connector kennt Γ nicht.
  """
  @spec label?(term()) :: boolean()
  def label?(label),
    do: is_binary(label) and Regex.match?(~r/\A[a-z0-9]+(?:-[a-z0-9]+)*@[1-9][0-9]*\z/, label)

  # --- search ----------------------------------------------------------------

  defp search(root, text) do
    needle = String.downcase(text)

    results =
      root
      |> walk("")
      |> Stream.flat_map(&visible(root, &1))
      |> Stream.filter(fn {_id, note, _labels} -> matches?(note, needle) end)
      |> Enum.take(@max_results)
      |> Enum.map(fn {id, note, labels} ->
        %{"note_id" => id, "title" => note.title, "labels" => labels}
      end)

    {:ok, %{"results" => results}}
  end

  defp matches?(note, needle) do
    String.contains?(String.downcase(note.title), needle) or
      String.contains?(String.downcase(note.body), needle)
  end

  # Tiefensuche, sortiert, ohne versteckte Eintraege. Symlinks (Dateien wie
  # Verzeichnisse) werden per lstat erkannt und nie verfolgt. Liefert nur
  # note_ids, die das Manifest-Pattern von `read` erfuellen — was die Suche
  # zeigt, ist auch lesbar.
  defp walk(root, rel) do
    case File.ls(Path.join(root, rel)) do
      {:ok, names} ->
        names
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.sort()
        |> Stream.flat_map(&entry(root, join(rel, &1)))

      {:error, _} ->
        []
    end
  end

  defp entry(root, rel) do
    case File.lstat(Path.join(root, rel)) do
      {:ok, %File.Stat{type: :directory}} -> walk(root, rel)
      {:ok, %File.Stat{type: :regular, size: size}} when size <= @max_bytes -> note_id(rel)
      _symlink_or_other -> []
    end
  end

  defp note_id(rel) do
    pattern = Manifest.fetch!("vault").ops["read"].params["note_id"].pattern
    if String.length(rel) <= 200 and Regex.match?(pattern, rel), do: [rel], else: []
  end

  defp join("", name), do: name
  defp join(rel, name), do: rel <> "/" <> name

  # Eine Notiz ist sichtbar, wenn sie sicher aufloesbar ist und gueltige
  # Labels traegt. Dieselbe Pruefung wie `read`.
  defp visible(root, id) do
    case load(root, id) do
      {:ok, note, labels} -> [{id, note, labels}]
      {:error, _code, _detail} -> []
    end
  end

  # --- read ------------------------------------------------------------------

  defp read(root, note_id) do
    with {:ok, note, labels} <- load(root, note_id) do
      {:ok,
       %{"note_id" => note_id, "title" => note.title, "content" => note.body, "labels" => labels}}
    end
  end

  defp load(root, note_id) do
    with {:ok, path, stat} <- Paths.resolve(root, note_id),
         :ok <- small(stat),
         {:ok, text} <- read_text(path) do
      note = Note.parse(text, Path.basename(note_id, ".md"))

      case Note.valid_labels(note.labels, &label?/1) do
        {:ok, labels} -> {:ok, note, labels}
        :error -> not_found()
      end
    end
  end

  # Grosse Dateien sind unsichtbar wie in der Suche.
  defp small(%File.Stat{size: size}) when size <= @max_bytes, do: :ok
  defp small(_stat), do: not_found()

  defp read_text(path) do
    case File.read(path) do
      {:ok, text} -> if String.valid?(text), do: {:ok, text}, else: not_found()
      {:error, _} -> not_found()
    end
  end

  defp not_found, do: {:error, "not-found", "Notiz nicht gefunden"}
end
