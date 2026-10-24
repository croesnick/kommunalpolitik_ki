defmodule KomkiConnectorVault.Writer do
  @moduledoc """
  Schreibende Operation `write_test` (CONTRACT.md §6.3).

    * Labels kommen ausschliesslich aus `context.assigned_label` (vom
      Vermittler, = B_W) und muessen eine nicht leere Teilmenge der
      Import-Labels sein, sonst `forbidden-path`.
    * Ziel: `<vault>/komki-test/<YYYY-MM-DD>-<ascii-slug>.md` (UTC-Datum).
      Ist `komki-test` ein Symlink oder keine Verzeichnis → `forbidden-path`.
    * Kein Ueberschreiben: exklusiv anlegen (`O_EXCL`, folgt auch keinem
      Symlink am Ziel); bei Kollision Suffix `-2`, `-3`, ….
    * Frontmatter (`komki_labels`, `title`, `created`) steht vorn, der Body
      dahinter. Der Parser liest nur das Frontmatter am Dateianfang; ein
      `---`-Block im Body ist Inhalt und kann die Labels nicht aendern.
  """

  alias KomkiConnectorVault.Paths

  @dir "komki-test"
  @max_attempts 100

  @doc "Legt die Notiz an; liefert `note_id` und `labels`."
  @spec write(Path.t(), map(), map(), [String.t()]) ::
          {:ok, map()} | {:error, String.t(), String.t()}
  def write(root, %{"title" => title, "body" => body}, context, allowed) do
    with {:ok, labels} <- assigned(context, allowed),
         {:ok, dir} <- test_dir(root) do
      now = DateTime.truncate(DateTime.utc_now(), :second)
      base = Date.to_iso8601(DateTime.to_date(now)) <> "-" <> slug(title)
      content = render(labels, title, now, body)

      with {:ok, name} <- create(dir, base, content, 1) do
        {:ok, %{"note_id" => @dir <> "/" <> name, "labels" => labels}}
      end
    end
  end

  defp assigned(%{"assigned_label" => [_ | _] = labels}, allowed) do
    if Enum.all?(labels, &(is_binary(&1) and &1 in allowed)),
      do: {:ok, labels},
      else: forbidden("assigned_label nicht in den Import-Labels")
  end

  defp assigned(_context, _allowed), do: forbidden("assigned_label fehlt oder ist leer")

  defp test_dir(root) do
    dir = Path.join(root, @dir)

    case File.lstat(dir) do
      {:ok, %File.Stat{type: :directory}} -> checked_dir(root, dir)
      {:ok, _symlink_or_file} -> forbidden("#{@dir} ist kein echtes Verzeichnis")
      {:error, :enoent} -> make_dir(root, dir)
      {:error, reason} -> {:error, "internal", "#{@dir}: #{inspect(reason)}"}
    end
  end

  defp make_dir(root, dir) do
    case File.mkdir(dir) do
      :ok -> checked_dir(root, dir)
      {:error, reason} -> {:error, "internal", "#{@dir} anlegen: #{inspect(reason)}"}
    end
  end

  defp checked_dir(root, dir) do
    with :ok <- Paths.under_root(root, dir), do: {:ok, dir}
  end

  defp create(_dir, _base, _content, attempt) when attempt > @max_attempts,
    do: {:error, "internal", "zu viele Namenskollisionen"}

  defp create(dir, base, content, attempt) do
    name = if attempt == 1, do: base <> ".md", else: "#{base}-#{attempt}.md"

    case File.open(Path.join(dir, name), [:write, :exclusive, :binary]) do
      {:ok, io} ->
        try do
          :ok = IO.binwrite(io, content)
        after
          File.close(io)
        end

        {:ok, name}

      {:error, :eexist} ->
        create(dir, base, content, attempt + 1)

      {:error, reason} ->
        {:error, "internal", "anlegen: #{inspect(reason)}"}
    end
  end

  # Titel als JSON-String (gueltiger YAML-Doppelquote-Skalar); Steuerzeichen
  # werden vorher zu Leerzeichen, damit der Titel keine Zeile einschleust.
  defp render(labels, title, now, body) do
    clean_title = String.replace(title, ~r/[\x00-\x1f\x7f]/, " ")

    IO.iodata_to_binary([
      "---\n",
      "komki_labels: [",
      Enum.join(labels, ", "),
      "]\n",
      "title: ",
      :json.encode(clean_title),
      "\n",
      "created: ",
      DateTime.to_iso8601(now),
      "\n",
      "---\n",
      body
    ])
  end

  @doc "ASCII-Slug: Umlaute als ae/oe/ue/ss, sonst nur `[a-z0-9-]`, max. 60 Zeichen."
  @spec slug(String.t()) :: String.t()
  def slug(title) do
    title
    |> String.downcase()
    |> String.replace(["ä", "ö", "ü", "ß"], fn
      "ä" -> "ae"
      "ö" -> "oe"
      "ü" -> "ue"
      "ß" -> "ss"
    end)
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.slice(0, 60)
    |> String.trim("-")
    |> case do
      "" -> "notiz"
      slug -> slug
    end
  end

  defp forbidden(detail), do: {:error, "forbidden-path", detail}
end
