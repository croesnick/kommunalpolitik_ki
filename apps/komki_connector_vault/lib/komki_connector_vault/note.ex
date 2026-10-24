defmodule KomkiConnectorVault.Note do
  @moduledoc """
  Minimaler Frontmatter-Parser fuer Vault-Notizen (keine YAML-Dep).

  Frontmatter ist nur ein Block, der in der **ersten Zeile** mit `---`
  beginnt und mit einer Zeile `---` endet. Ein `---`-Block weiter unten
  im Text ist Inhalt, kein Frontmatter — so kann ein geschriebener Body
  die Labels nicht ueberschreiben.

  Gelesen werden nur zwei Schluessel:

    * `komki_labels`: Liste, inline (`[a, b]`) oder als Blockliste
      (`- a` je Zeile). Ein Skalar, ein doppelter Schluessel oder eine
      unlesbare Liste ergibt `:invalid` (fail-closed).
    * `title`: Skalar, optional in Anfuehrungszeichen.

  Titel-Reihenfolge: Frontmatter `title`, sonst erste `# `-Ueberschrift,
  sonst der Dateiname ohne `.md`.
  """

  @type labels :: [String.t()] | :missing | :invalid
  @type t :: %{title: String.t(), body: String.t(), labels: labels()}

  @doc "Zerlegt den Dateiinhalt; `fallback_title` ist der Dateiname ohne `.md`."
  @spec parse(binary(), String.t()) :: t()
  def parse(text, fallback_title) do
    {front, body} = split(text)
    title = front_title(front) || heading(body) || fallback_title
    %{title: title, body: body, labels: labels(front)}
  end

  @doc """
  Gueltige Labels: nicht leere Liste, alle Eintraege in `allowed`.
  Liefert die Labels sortiert und ohne Dubletten, sonst `:error`.
  """
  @spec valid_labels(labels(), [String.t()]) :: {:ok, [String.t()]} | :error
  def valid_labels([_ | _] = labels, allowed) do
    if Enum.all?(labels, &(&1 in allowed)),
      do: {:ok, labels |> Enum.uniq() |> Enum.sort()},
      else: :error
  end

  def valid_labels(_labels, _allowed), do: :error

  # --- Frontmatter abtrennen -------------------------------------------------

  defp split(text) do
    case String.split(text, ~r/\r?\n/, parts: 2) do
      ["---", rest] -> close(rest)
      _ -> {nil, text}
    end
  end

  defp close(rest) do
    case Regex.run(~r/\A(.*?)(?:^---[ \t]*(?:\r?\n|\z))/ms, rest) do
      [whole, front] -> {String.split(front, ~r/\r?\n/), binary_part_after(rest, whole)}
      nil -> {nil, "---\n" <> rest}
    end
  end

  defp binary_part_after(rest, prefix),
    do: binary_part(rest, byte_size(prefix), byte_size(rest) - byte_size(prefix))

  # --- Titel -----------------------------------------------------------------

  defp front_title(nil), do: nil

  defp front_title(lines) do
    case values(lines, "title") do
      [value] -> nonempty(scalar(value))
      _ -> nil
    end
  end

  defp heading(body) do
    case Regex.run(~r/^# +(.+?)[ \t]*$/m, body) do
      [_, title] -> nonempty(title)
      nil -> nil
    end
  end

  defp nonempty(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp nonempty(_), do: nil

  # --- Labels ----------------------------------------------------------------

  defp labels(nil), do: :missing

  defp labels(lines) do
    case indexed_values(lines, "komki_labels") do
      [] -> :missing
      [{"", index}] -> block_list(Enum.drop(lines, index + 1))
      [{value, _index}] -> inline_list(value)
      _duplicate -> :invalid
    end
  end

  defp inline_list(value) do
    case Regex.run(~r/\A\[(.*)\]\z/, value) do
      [_, ""] -> []
      [_, inner] -> inner |> String.split(",") |> Enum.map(&scalar/1) |> all_strings()
      nil -> :invalid
    end
  end

  # Blockliste: direkt folgende Zeilen `- eintrag` (Einrueckung erlaubt).
  defp block_list(lines) do
    lines
    |> Enum.take_while(&Regex.match?(~r/\A\s*-\s/, &1))
    |> Enum.map(fn line -> line |> String.replace(~r/\A\s*-\s/, "") |> scalar() end)
    |> case do
      [] -> :invalid
      items -> all_strings(items)
    end
  end

  defp all_strings(items) do
    if Enum.all?(items, &(is_binary(&1) and &1 != "")), do: items, else: :invalid
  end

  # --- Schluessel/Wert-Zeilen ------------------------------------------------

  defp values(lines, key), do: Enum.map(indexed_values(lines, key), &elem(&1, 0))

  # Nur Schluessel am Zeilenanfang (keine Einrueckung) zaehlen.
  defp indexed_values(lines, key) do
    prefix = key <> ":"

    for {line, index} <- Enum.with_index(lines),
        String.starts_with?(line, prefix),
        do: {String.trim(String.replace_prefix(line, prefix, "")), index}
  end

  # Skalar: doppelte Anfuehrungszeichen als JSON-String (so schreibt der
  # Connector selbst), einfache als YAML-Literal, sonst getrimmt.
  defp scalar(raw) do
    case String.trim(raw) do
      "\"" <> _ = quoted -> json_string(quoted)
      "'" <> _ = quoted -> single_quoted(quoted)
      plain -> plain
    end
  end

  defp json_string(quoted) do
    case :json.decode(quoted) do
      value when is_binary(value) -> value
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp single_quoted(quoted) do
    case Regex.run(~r/\A'(.*)'\z/, quoted) do
      [_, inner] -> String.replace(inner, "''", "'")
      nil -> nil
    end
  end
end
