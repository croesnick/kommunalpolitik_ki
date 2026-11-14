defmodule Ratsprojekte.Text do
  @moduledoc """
  Free text as the hub stores it (ADR 0004, test 13.6 in #410): the hub
  keeps what the person saw. Invisible control characters go before
  anything is saved, so no hidden instruction rides along in a field that
  looked harmless. Pasting stays allowed.

  Removed:

  - control characters (`Cc`) except line break and tab; `\\r\\n` and a
    lone `\\r` become `\\n`
  - format characters (`Cf`): zero-width space, word joiner, BOM, soft
    hyphen, bidi embeddings, overrides and isolates (Trojan Source), tag
    characters (ASCII smuggling), invisible operators
  - Hangul fillers, which render as blanks
  - variation selectors beyond the first after a visible character, and
    ideographic variation selectors outside Han text (emoji smuggling)

  Kept, so emoji and scripts stay intact:

  - a single zero-width joiner or non-joiner between two visible
    characters (emoji ZWJ sequences, Persian, Indic scripts)
  - one variation selector after a visible character (`❤\u{FE0F}`, keycaps)
  - tag sequences of subdivision flags (🏴\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F})
  """

  @flag ~r/\x{1F3F4}[\x{E0030}-\x{E0039}\x{E0061}-\x{E007A}]{1,6}\x{E007F}/u
  @flag_whole ~r/\A\x{1F3F4}[\x{E0030}-\x{E0039}\x{E0061}-\x{E007A}]{1,6}\x{E007F}\z/u

  # A joiner counts only between two visible characters; one next to
  # whitespace, a control or another invisible character goes.
  @stray_joiner ~r/[\x{200C}\x{200D}](?![^\s\p{C}])|(?<![^\s\p{C}])[\x{200C}\x{200D}]/u
  @stray_selector ~r/(?<=[\s\p{C}\x{FE00}-\x{FE0F}\x{E0100}-\x{E01EF}])[\x{FE00}-\x{FE0F}]|\A[\x{FE00}-\x{FE0F}]/u
  @stray_ideographic_selector ~r/(?<!\p{Han})[\x{E0100}-\x{E01EF}]/u
  @invisible ~r/(?![\n\t\x{200C}\x{200D}])[\p{Cc}\p{Cf}\x{115F}\x{1160}\x{3164}\x{FFA0}]/u

  @doc """
  Removes invisible characters from `text` and trims it.

      iex> Ratsprojekte.Text.clean("Bahn\\u200Bhof\\u202Estraße ")
      "Bahnhofstraße"

      iex> Ratsprojekte.Text.clean("👩\u{200D}👩\u{200D}👧 ❤\u{FE0F}")
      "👩\u{200D}👩\u{200D}👧 ❤\u{FE0F}"
  """
  @spec clean(String.t()) :: String.t()
  @spec clean(nil) :: nil
  def clean(nil), do: nil

  def clean(text) when is_binary(text) do
    @flag
    |> Regex.split(text, include_captures: true)
    |> Enum.map_join(fn part ->
      if Regex.match?(@flag_whole, part), do: part, else: clean_part(part)
    end)
    |> String.trim()
  end

  defp clean_part(part) do
    part
    |> String.replace(~r/\r\n?/, "\n")
    |> String.replace(@stray_joiner, "")
    |> String.replace(@stray_selector, "")
    |> String.replace(@stray_ideographic_selector, "")
    |> String.replace(@invisible, "")
  end

  @doc """
  Cleans the given free-text `fields` of a changeset; a field that is
  empty afterwards becomes `nil`, so `validate_required/2` catches text
  that consisted of invisible characters only.
  """
  @spec clean_fields(Ecto.Changeset.t(), [atom()]) :: Ecto.Changeset.t()
  def clean_fields(changeset, fields) do
    Enum.reduce(
      fields,
      changeset,
      &Ecto.Changeset.update_change(&2, &1, fn value -> blank_to_nil(clean(value)) end)
    )
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(text), do: text

  @slug ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/

  @doc "The slug format (AGENTS.md, Slug-Konvention)."
  @spec slug_format() :: Regex.t()
  def slug_format, do: @slug

  @doc """
  The short name („Kurzname“) a title suggests: lowercase ASCII, umlauts
  as ae/oe/ue/ss, at most four words.

      iex> Ratsprojekte.Text.slugify("Sitzbänke am Stadtweiher")
      "sitzbaenke-am-stadtweiher"
  """
  @spec slugify(String.t()) :: String.t()
  def slugify(title) do
    title
    |> String.downcase()
    |> String.replace(["ä", "ö", "ü", "ß"], fn
      "ä" -> "ae"
      "ö" -> "oe"
      "ü" -> "ue"
      "ß" -> "ss"
    end)
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> String.split("-")
    |> Enum.take(4)
    |> Enum.join("-")
  end
end
