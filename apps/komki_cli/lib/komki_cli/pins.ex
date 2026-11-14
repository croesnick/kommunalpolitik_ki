defmodule KomkiCli.Pins do
  @moduledoc """
  Programm-Pins: SHA-256 jedes Programms, das komki startet.

  Die Sandbox-Profile prueft komki vor jedem Start auf Byte-Gleichheit mit
  dem Generator. Dieselbe Pruefung gilt hier fuer die Programme selbst:
  `komki setup` haelt ihre Hashes in `config.json` fest (`pins`), und
  `komki up` startet nur, wenn jedes Programm noch dieselben Bytes hat.
  Ein Programm, das sich am selben Pfad veraendert hat, uebernimmt
  `komki setup` erst nach ausdruecklicher Bestaetigung. Ein
  Abhaengigkeits-Update ist damit eine bewusste Aenderung und kein stiller
  Austausch.

  Gepinnt werden die Einstiegsprogramme (komki mit seinen Rollen, escript,
  node, llama-server, komki-tresor) und fuer pi das ganze Paketverzeichnis
  (`@earendil-works/pi-coding-agent`, Baum-Hash ueber Pfade, Dateiinhalte
  und Symlink-Ziele). Nicht gepinnt sind die Laufzeit-Baeume hinter den
  Einstiegsprogrammen (Erlang-`lib`, dylibs von llama.cpp, Systembibliotheken).
  """

  alias KomkiCli.{Config, Tresor}

  @type pin :: %{String.t() => String.t()}
  @type pins :: %{String.t() => pin()}
  @type check :: %{name: String.t(), ok: boolean(), reason: String.t()}

  @doc """
  Die zu pinnenden Programme als `[{name, pfad}]`. komki traegt alle
  Rollen; ein Pfad, der schon unter anderem Namen steht, faellt weg.
  """
  @spec artifacts(Config.t()) :: [{String.t(), String.t()}]
  def artifacts(%Config{} = cfg) do
    roles =
      [{"komki", cfg.komki_bin || cfg.mediator_bin}, {"komki-egress", cfg.egress_bin}] ++
        Enum.map(Enum.sort(cfg.connector_bins), fn {id, bin} ->
          {"komki-connector-" <> id, bin}
        end)

    (roles ++
       [
         {"escript", cfg.escript_bin},
         {"node", cfg.node_bin},
         {"pi", pi_package(cfg.cli_js)},
         {"llama-server", cfg.llama_server_bin},
         {"komki-tresor", Tresor.binary()}
       ])
    |> Enum.reject(fn {_name, path} -> is_nil(path) end)
    |> Enum.uniq_by(fn {_name, path} -> path end)
  end

  # cli.js liegt unter <paket>/dist/bundle/cli.js
  defp pi_package(nil), do: nil
  defp pi_package(cli_js), do: cli_js |> Path.dirname() |> Path.dirname() |> Path.dirname()

  @doc "Aktuelle Pins aller Programme."
  @spec compute(Config.t()) :: pins()
  def compute(%Config{} = cfg), do: Seatbelt.Pins.compute(artifacts(cfg))

  @doc """
  Abweichungen gegenueber `cfg.pins`: `:new` (noch nicht festgehalten oder
  an einem neuen Pfad, etwa nach `brew upgrade`) und `:changed` (gleicher
  Pfad, andere Bytes). Entfallene Programme zaehlen nicht.
  """
  @spec drift(Config.t(), pins()) :: %{new: [String.t()], changed: [String.t()]}
  def drift(%Config{pins: pinned}, current), do: Seatbelt.Pins.drift(pinned, current)

  @doc "Doctor- und Start-Checks: jedes Programm muss seinem Pin entsprechen."
  @spec checks(Config.t()) :: [check()]
  def checks(%Config{} = cfg) do
    Enum.map(artifacts(cfg), fn {name, path} -> check(name, path, Map.get(cfg.pins, name)) end)
  end

  defp check(name, path, pin) do
    check = "pin " <> name

    case {pin, hash(path)} do
      {_, {:error, reason}} ->
        %{name: check, ok: false, reason: path <> ": " <> reason}

      {nil, _} ->
        %{name: check, ok: false, reason: "nicht festgehalten — 'komki setup' hält es fest"}

      {%{"path" => pinned}, _} when pinned != path ->
        %{
          name: check,
          ok: false,
          reason: "neuer Pfad " <> path <> " — 'komki setup' hält ihn fest"
        }

      {%{"sha256" => sha}, {:ok, sha}} ->
        %{name: check, ok: true, reason: "sha256 " <> String.slice(sha, 0, 12) <> "…"}

      {_, {:ok, _}} ->
        %{
          name: check,
          ok: false,
          reason:
            "verändert seit dem Festhalten: " <>
              path <> " — prüfen; nach einem gewollten Update 'komki setup' (fragt nach)"
        }
    end
  end

  @doc """
  SHA-256 einer Datei oder, fuer ein Verzeichnis, ueber den ganzen Baum.

  Implementierung lebt seit Ticket #226 in der Library
  (`Seatbelt.Pins.hash/1`); dieser Einstieg bleibt als komki-API.
  """
  @spec hash(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def hash(path), do: Seatbelt.Pins.hash(path)
end
