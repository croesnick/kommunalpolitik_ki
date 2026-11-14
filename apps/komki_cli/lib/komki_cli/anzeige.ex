defmodule KomkiCli.Anzeige do
  @moduledoc """
  Oberfläche der pi-Session, die komki mitbringt (Quelle: `priv/pi/`, zur
  Compile-Zeit eingebettet):

    * `komki-anzeige/`: Extension, die die Tool-Aufrufe des Vermittlers
      lesbar statt als Roh-JSON zeichnet. Sie registriert Renderer und
      ändert weder Entscheidungen noch den Modellkontext. Dazu bricht sie
      `/resume` und `/import` zu einer fremden Session mit einem Hinweis ab
      (Ticket #295); die Grenze dafür zieht das Profil der Session
      (`KomkiCli.Profile`).
    * `komki-vorlagen/`: Prompt-Vorlagen für die Ratsarbeit
      (`/sitzungsmappe`, `/zusammenfassen`, `/quellen`). Reiner Text, den
      die nutzende Person selbst abschickt; keine Befugnis.
    * `komki-themes/`: Farben wie die Doku-Site, hell und dunkel; pi wählt
      nach dem Terminal.
    * `komki-anzeige/raum.json`: das Raumbild (`KomkiCli.Raumbild`), das die
      Extension in Kopfzeile, Fußzeile und `/raum` zeigt. Den Pfad bekommt
      sie über das Flag `--komki-raum`.

  Die Dateien liegen unter `<pi-home>/.pi/agent/` und werden wie das Relay
  vor jedem pi-Start neu geschrieben: Das pi-Home ist für den Agenten
  schreibbar. Eine veränderte Anzeige oder ein verändertes Theme könnte eine
  Ablehnung als Zulassung zeigen, eine veränderte Vorlage dem Modell fremde
  Anweisungen unterschieben.
  """

  alias KomkiCli.{Config, Raumbild}

  @priv Path.expand("../../priv/pi", __DIR__)
  @parts ~w(komki-anzeige komki-vorlagen komki-themes)
  @files for part <- @parts,
             name <- @priv |> Path.join(part) |> File.ls!() |> Enum.sort(),
             path = Path.join([@priv, part, name]),
             do: {Path.join(part, name), File.read!(path)}
  for {rel, _} <- @files, do: @external_resource(Path.join(@priv, rel))

  @themes "komki-hell/komki-dunkel"

  @spec dir(Config.t()) :: String.t()
  def dir(%Config{} = cfg), do: part_dir(cfg, "komki-anzeige")

  @doc "Einstieg für `pi -e`."
  @spec entry(Config.t()) :: String.t()
  def entry(%Config{} = cfg), do: Path.join(dir(cfg), "index.ts")

  @doc "Pfad des Raumbilds, das `write!/2` schreibt."
  @spec raum_path(Config.t()) :: String.t()
  def raum_path(%Config{} = cfg), do: Path.join(dir(cfg), "raum.json")

  @doc "pi-Flags der Session: Extension, Raumbild, Vorlagen, Themes (hell/dunkel nach Terminal)."
  @spec flags(Config.t()) :: [String.t()]
  def flags(%Config{} = cfg) do
    [
      "-e",
      entry(cfg),
      "--komki-raum",
      raum_path(cfg),
      "--prompt-template",
      part_dir(cfg, "komki-vorlagen"),
      "--theme",
      part_dir(cfg, "komki-themes"),
      "--use-theme",
      @themes
    ]
  end

  @doc """
  Schreibt alle Teile frisch ins pi-Home; fremde Dateien in den Ordnern
  verschwinden. Das Raumbild entsteht aus den Instanzdateien
  (`Raumbild.load/1`); Tests geben es vor.
  """
  @spec write!(Config.t(), map() | nil) :: :ok
  def write!(%Config{} = cfg, raumbild \\ nil) do
    for part <- @parts do
      path = part_dir(cfg, part)
      File.rm_rf!(path)
      File.mkdir_p!(path)
    end

    Enum.each(@files, fn {rel, content} ->
      File.write!(Path.join([cfg.pi_home, ".pi", "agent", rel]), content)
    end)

    File.write!(raum_path(cfg), Raumbild.encode(raumbild || Raumbild.load(cfg)))
    quiet_startup!(cfg)
  end

  # pis englische Liste der geladenen Vorlagen und Extensions weicht der
  # komki-Kopfzeile (Ticket #242). `"header"` blendet nur die Liste und die
  # Modellzeile aus; die Kopfzeile ersetzt die Extension. Die übrigen
  # Einstellungen bleiben, wie init und pi sie geschrieben haben.
  defp quiet_startup!(cfg) do
    path = Path.join([cfg.pi_home, ".pi", "agent", "settings.json"])

    settings =
      with {:ok, content} <- File.read(path),
           {:ok, map} when is_map(map) <- JSON.decode(content) do
        map
      else
        _ -> %{}
      end

    File.write!(path, JSON.encode!(Map.put(settings, "quietStartup", "header")) <> "\n")
  end

  @doc "Eingebettete Dateien, Pfad relativ zu `<pi-home>/.pi/agent/` (für Tests)."
  @spec files() :: [{String.t(), String.t()}]
  def files, do: @files

  defp part_dir(cfg, part), do: Path.join([cfg.pi_home, ".pi", "agent", part])
end
