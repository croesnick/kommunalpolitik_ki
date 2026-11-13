# Shot list of the screenshot tool (#510): routes × themes × widths, plus
# navigations captured mid-flight. Shared by scripts/screenshot.exs and the
# dev loop, which checks an implementer's .dev-loop/screenshots.json
# against the same rules before it runs the tool.

defmodule Screenshot.Spec do
  @moduledoc false

  # Local paths only: no scheme, host, query, fragment or `..` segment.
  # Every route is appended to http://127.0.0.1:<port>, so a leading `//`
  # must not pass either.
  @route ~r{\A/(?:[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*)?\z}
  @themes ~w(light dark)
  @min_width 320
  @max_width 1920
  @max_shots 40

  @type t :: %{
          routes: [String.t()],
          navigations: [{String.t(), String.t()}],
          themes: [String.t()],
          widths: [pos_integer()]
        }

  def defaults, do: %{"themes" => @themes, "widths" => [390, 1280]}

  @doc """
  Validates a decoded JSON map:
  `{"routes": [...], "navigations": [{"from": ..., "to": ...}], "themes": [...], "widths": [...]}`.
  Missing themes and widths fall back to `defaults/0`.
  """
  def parse(map) when is_map(map) do
    map = Map.merge(defaults(), map)
    unknown = Map.keys(map) -- ~w(routes navigations themes widths)

    with :ok <- no_unknown(unknown),
         {:ok, routes} <- routes(Map.get(map, "routes", [])),
         {:ok, navs} <- navigations(Map.get(map, "navigations", [])),
         {:ok, themes} <- themes(map["themes"]),
         {:ok, widths} <- widths(map["widths"]),
         spec = %{routes: routes, navigations: navs, themes: themes, widths: widths},
         :ok <- size(spec) do
      {:ok, spec}
    end
  end

  def parse(_), do: {:error, "Die Liste der Aufnahmen muss ein JSON-Objekt sein."}

  @doc "Every shot of the spec, in a stable order."
  def shots(spec) do
    pages = for r <- spec.routes, t <- spec.themes, w <- spec.widths, do: {:page, r, t, w}
    navs = for n <- spec.navigations, t <- spec.themes, w <- spec.widths, do: {:navigate, n, t, w}
    pages ++ navs
  end

  @doc "File name of a shot, without extension."
  def name({:page, route, theme, width}), do: "#{slug(route)}-#{theme}-#{width}"

  def name({:navigate, {from, to}, theme, width}),
    do: "nav-#{slug(from)}-nach-#{slug(to)}-#{theme}-#{width}"

  defp slug("/"), do: "start"
  defp slug(route), do: route |> String.trim_leading("/") |> String.replace("/", "_")

  defp no_unknown([]), do: :ok
  defp no_unknown(keys), do: {:error, "Unbekannte Felder: #{Enum.join(Enum.sort(keys), ", ")}"}

  defp routes(list) when is_list(list) do
    case Enum.reject(list, &route?/1) do
      [] -> {:ok, Enum.uniq(list)}
      bad -> {:error, "Ungültige Route: #{inspect(hd(bad))} (nur lokale Pfade wie /stand)"}
    end
  end

  defp routes(_), do: {:error, "routes muss eine Liste sein."}

  defp navigations(list) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn
      %{"from" => from, "to" => to} = nav, {:ok, acc} when map_size(nav) == 2 ->
        if route?(from) and route?(to),
          do: {:cont, {:ok, acc ++ [{from, to}]}},
          else: {:halt, {:error, "Ungültige Navigation: #{inspect(nav)}"}}

      nav, _ ->
        {:halt, {:error, "Ungültige Navigation: #{inspect(nav)} (erwartet from und to)"}}
    end)
    |> case do
      {:ok, navs} -> {:ok, Enum.uniq(navs)}
      error -> error
    end
  end

  defp navigations(_), do: {:error, "navigations muss eine Liste sein."}

  defp themes(list) when is_list(list) and list != [] do
    if Enum.all?(list, &(&1 in @themes)),
      do: {:ok, Enum.uniq(list)},
      else: {:error, "themes erlaubt nur #{Enum.join(@themes, " und ")}."}
  end

  defp themes(_), do: {:error, "themes muss eine nicht leere Liste sein."}

  defp widths(list) when is_list(list) and list != [] do
    if Enum.all?(list, &(is_integer(&1) and &1 >= @min_width and &1 <= @max_width)),
      do: {:ok, Enum.uniq(list)},
      else: {:error, "widths erlaubt ganze Zahlen von #{@min_width} bis #{@max_width}."}
  end

  defp widths(_), do: {:error, "widths muss eine nicht leere Liste sein."}

  defp size(spec) do
    case length(shots(spec)) do
      0 -> {:error, "Keine Aufnahme angegeben (routes oder navigations)."}
      n when n > @max_shots -> {:error, "#{n} Aufnahmen, höchstens #{@max_shots} erlaubt."}
      _ -> :ok
    end
  end

  defp route?(r), do: is_binary(r) and Regex.match?(@route, r)
end
