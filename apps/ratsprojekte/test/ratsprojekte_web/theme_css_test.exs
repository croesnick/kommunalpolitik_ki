defmodule RatsprojekteWeb.ThemeCssTest do
  # Checkpoint "Hub-Oberfläche" from docs/agents/pruefpunkte.md (#461): every
  # page follows light and dark, so fixed colours live only in the two theme
  # blocks and in @media print. Anlass: in #459 the briefing sheet stayed white
  # in dark mode.
  use ExUnit.Case, async: true

  @css Path.expand("../../assets/css/app.css", __DIR__)
  @templates Path.expand("../../lib/ratsprojekte_web", __DIR__)

  # Deliberate exceptions, each the same in both themes: the five-step scale of
  # the opinion bars (data, not surface) and the faint shadow under the sheet.
  @allowed_properties ~w(--stufe-1 --stufe-2 --stufe-3 --stufe-4 --stufe-5 box-shadow)

  @colour_literal ~r/#[0-9a-fA-F]{3,8}\b|\b(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch)\(|\b(?:white|black)\b/

  @tailwind_palette ~r/\b(?:bg|text|border|from|via|to|fill|stroke|ring|outline|shadow|divide|decoration|accent|caret)-(?:white|black|(?:slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-\d{2,3}|\[#[0-9a-fA-F]+\])/

  test "app.css has fixed colours only in the theme blocks and in @media print" do
    offenders =
      @css
      |> File.read!()
      |> strip_comments()
      |> drop_blocks(~r/@plugin\s+"[^"]*daisyui-theme"\s*\{/)
      |> drop_blocks(~r/@media\s+print\s*\{/)
      |> declarations()
      |> Enum.reject(fn {property, _value} -> property in @allowed_properties end)
      |> Enum.filter(fn {_property, value} -> value =~ @colour_literal end)

    assert offenders == [],
           "Feste Farben außerhalb der Themes und @media print: #{inspect(offenders)}"
  end

  test "templates use theme colours, not fixed Tailwind palette classes" do
    offenders =
      for path <- Path.wildcard(Path.join(@templates, "**/*.{ex,heex}")),
          [class] <- Regex.scan(@tailwind_palette, File.read!(path)),
          do: {Path.relative_to(path, @templates), class}

    assert offenders == [], "Feste Farbklassen in Templates: #{inspect(offenders)}"
  end

  defp strip_comments(css), do: String.replace(css, ~r{/\*.*?\*/}s, "")

  # Removes every block whose opening matches `opening`, up to its balanced
  # closing brace.
  defp drop_blocks(css, opening) do
    case Regex.run(opening, css, return: :index) do
      nil ->
        css

      [{start, length}] ->
        rest = binary_part(css, start + length, byte_size(css) - start - length)
        after_block = skip_to_close(rest, 1)
        drop_blocks(binary_part(css, 0, start) <> after_block, opening)
    end
  end

  defp skip_to_close(rest, 0), do: rest
  defp skip_to_close("{" <> rest, depth), do: skip_to_close(rest, depth + 1)
  defp skip_to_close("}" <> rest, depth), do: skip_to_close(rest, depth - 1)
  defp skip_to_close(<<_, rest::binary>>, depth), do: skip_to_close(rest, depth)

  defp declarations(css) do
    for [_, property, value] <- Regex.scan(~r/([-a-zA-Z0-9]+)\s*:\s*([^;{}]+)/, css),
        do: {property, String.trim(value)}
  end
end
