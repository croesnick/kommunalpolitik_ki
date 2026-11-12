defmodule RatsprojekteWeb.ThemeCssTest do
  # Checkpoint "Hub-Oberfläche" from docs/agents/pruefpunkte.md (#461): every
  # page follows light and dark, so fixed colours live only in the two theme
  # blocks and in @media print. Prompted by #459, where the briefing sheet
  # stayed white in dark mode. A new exception needs a GO (pruefpunkte.md).
  use ExUnit.Case, async: true

  @css Path.expand("../../assets/css/app.css", __DIR__)
  @templates Path.expand("../../lib/ratsprojekte_web", __DIR__)

  # CSS named colours (CSS Color Module Level 4), without transparent and currentcolor.
  @named ~w(aliceblue antiquewhite aqua aquamarine azure beige bisque black blanchedalmond
            blue blueviolet brown burlywood cadetblue chartreuse chocolate coral cornflowerblue
            cornsilk crimson cyan darkblue darkcyan darkgoldenrod darkgray darkgreen darkgrey
            darkkhaki darkmagenta darkolivegreen darkorange darkorchid darkred darksalmon
            darkseagreen darkslateblue darkslategray darkslategrey darkturquoise darkviolet
            deeppink deepskyblue dimgray dimgrey dodgerblue firebrick floralwhite forestgreen
            fuchsia gainsboro ghostwhite gold goldenrod gray green greenyellow grey honeydew
            hotpink indianred indigo ivory khaki lavender lavenderblush lawngreen lemonchiffon
            lightblue lightcoral lightcyan lightgoldenrodyellow lightgray lightgreen lightgrey
            lightpink lightsalmon lightseagreen lightskyblue lightslategray lightslategrey
            lightsteelblue lightyellow lime limegreen linen magenta maroon mediumaquamarine
            mediumblue mediumorchid mediumpurple mediumseagreen mediumslateblue
            mediumspringgreen mediumturquoise mediumvioletred midnightblue mintcream mistyrose
            moccasin navajowhite navy oldlace olive olivedrab orange orangered orchid
            palegoldenrod palegreen paleturquoise palevioletred papayawhip peachpuff peru pink
            plum powderblue purple rebeccapurple red rosybrown royalblue saddlebrown salmon
            sandybrown seagreen seashell sienna silver skyblue slateblue slategray slategrey snow
            springgreen steelblue tan teal thistle tomato turquoise violet wheat white whitesmoke
            yellow yellowgreen)

  @colour_literal Regex.compile!(
                    "#[0-9a-fA-F]{3,8}\\b|\\b(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch|color)\\(" <>
                      "|(?<![-\\w])(?:#{Enum.join(@named, "|")})(?![-\\w])",
                    "i"
                  )

  # A shadow may be a faint tint, never a surface: alpha at most 0.3.
  @max_shadow_alpha 0.3

  @palette "(?:white|black|(?:slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|" <>
             "green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-\\d{2,3})"
  @tailwind_palette Regex.compile!(
                      "\\b(?:bg|text|border(?:-[xytrblse])?|from|via|to|fill|stroke|ring|outline|" <>
                        "shadow|divide|decoration|accent|caret|placeholder)-#{@palette}\\b"
                    )
  @arbitrary_value ~r/\b[a-z][-a-z]*-\[([^\]]*)\]/
  @style_attribute ~r/\bstyle=(?:"([^"]*)"|\{"([^"]*)"\})/

  test "app.css has fixed colours only in the theme blocks and in @media print" do
    offenders =
      @css
      |> File.read!()
      |> String.replace(~r{/\*.*?\*/}s, "")
      |> drop_blocks(~r/@plugin\s+"[^"]*daisyui-theme"\s*\{/)
      |> drop_blocks(~r/@media\s+print\s*\{/)
      |> declarations()
      |> Enum.reject(&allowed?/1)
      |> Enum.filter(fn {_selector, _property, value} -> value =~ @colour_literal end)

    assert offenders == [],
           "Feste Farben außerhalb der Themes und @media print: #{inspect(offenders)}"
  end

  test "templates use theme colours, not fixed colour classes or inline colours" do
    offenders =
      for path <- Path.wildcard(Path.join(@templates, "**/*.{ex,heex}")),
          source = File.read!(path),
          finding <- template_findings(source),
          do: {Path.relative_to(path, @templates), finding}

    assert offenders == [], "Feste Farben in Templates: #{inspect(offenders)}"
  end

  test "the checks catch what they are meant to catch" do
    assert "color: red" =~ @colour_literal
    assert "background: color(display-p3 1 0 0)" =~ @colour_literal
    refute "white-space: nowrap" =~ @colour_literal

    refute "background: color-mix(in oklab, var(--color-primary) 8%, transparent)" =~
             @colour_literal

    assert [{".a:hover #cafe", "color", "red"}] = declarations(".a:hover #cafe { color: red }")

    assert [{".a:not(.white)", "color", "inherit"}] =
             declarations(".a:not(.white) { color: inherit }")

    assert allowed?({":root", "--stufe-3", "#cfd5dd"})
    refute allowed?({".a", "--stufe-3", "#fff"})
    refute allowed?({":root", "--stufe-9", "#fff"})
    assert allowed?({".a", "box-shadow", "0 1px 3px rgb(0 0 0 / 0.08)"})
    assert allowed?({".a", "box-shadow", "0 1px 3px rgba(0, 0, 0, .3), 0 0 1px rgb(0 0 0 / 8%)"})
    refute allowed?({".a", "box-shadow", "0 0 0 999px rgb(255 255 255 / .99)"})
    refute allowed?({".a", "box-shadow", "0 0 0 999px #fff"})

    assert [{"&:hover", "color", "red"}, {".a", "color", "#fff"}] =
             declarations(".a { color: #fff; &:hover { color: red } }")

    assert [{"&:hover", "color", "red"}, {".a", "color", "#fff"}] =
             declarations(".a { &:hover { color: red } color: #fff; }")

    assert length(template_findings(~s(class="border-t-gray-200 text-[white] bg-[#fff]"))) == 3

    assert template_findings(~s(<p style="color: #fff">)) == ["color: #fff"]
    assert template_findings(~s(<i style={"flex: \#{n}"}>)) == []
  end

  defp allowed?({":root", "--stufe-" <> step, _value}), do: step in ~w(1 2 3 4 5)

  defp allowed?({_selector, "box-shadow", value}) do
    opaque =
      Regex.replace(~r/\brgba?\(([^()]*)\)/, value, fn colour, args ->
        if faint?(args), do: "", else: colour
      end)

    not (opaque =~ @colour_literal)
  end

  defp allowed?(_declaration), do: false

  # Alpha as `r g b / a` or `r, g, b, a`, either a number or a percentage.
  defp faint?(args) do
    alpha =
      case {String.split(args, "/"), String.split(args, ",")} do
        {[_, alpha], _} -> alpha
        {_, [_, _, _, alpha]} -> alpha
        _ -> nil
      end

    case alpha && Float.parse(String.replace_prefix(String.trim(alpha), ".", "0.")) do
      {value, "%"} -> value / 100 <= @max_shadow_alpha
      {value, ""} -> value <= @max_shadow_alpha
      _ -> false
    end
  end

  defp template_findings(source) do
    classes = for [class] <- Regex.scan(@tailwind_palette, source), do: class

    arbitrary =
      for [class, value] <- Regex.scan(@arbitrary_value, source),
          value =~ @colour_literal,
          do: class

    styles =
      for [_ | groups] <- Regex.scan(@style_attribute, source),
          style = Enum.join(groups),
          style =~ @colour_literal,
          do: style

    classes ++ arbitrary ++ styles
  end

  # Removes every block whose opening matches `opening`, up to its balanced
  # closing brace.
  defp drop_blocks(css, opening) do
    case Regex.run(opening, css, return: :index) do
      nil ->
        css

      [{start, length}] ->
        rest = binary_part(css, start + length, byte_size(css) - start - length)
        drop_blocks(binary_part(css, 0, start) <> skip_to_close(rest, 1), opening)
    end
  end

  defp skip_to_close(rest, 0), do: rest
  defp skip_to_close("{" <> rest, depth), do: skip_to_close(rest, depth + 1)
  defp skip_to_close("}" <> rest, depth), do: skip_to_close(rest, depth - 1)
  defp skip_to_close(<<_, rest::binary>>, depth), do: skip_to_close(rest, depth)

  # Reads the innermost rule, then replaces it with `;`, until no rule is left.
  # A nested rule thus never hides the declarations of its parent, and an
  # @media wrapper never ends up as a selector.
  defp declarations(css, acc \\ []) do
    case Regex.run(~r/([^{};]*)\{([^{}]*)\}/, css, return: :index) do
      nil ->
        acc

      [{start, length}, selector, body] ->
        found =
          for [_, property, value] <-
                Regex.scan(~r/(?:^|;)\s*([-a-zA-Z0-9]+)\s*:\s*([^;]+)/, slice(css, body)),
              do: {String.trim(slice(css, selector)), property, String.trim(value)}

        before = binary_part(css, 0, start)
        rest = binary_part(css, start + length, byte_size(css) - start - length)
        declarations(before <> ";" <> rest, acc ++ found)
    end
  end

  defp slice(css, {start, length}), do: binary_part(css, start, length)
end
