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
  def compute(%Config{} = cfg) do
    for {name, path} <- artifacts(cfg), {:ok, hash} <- [hash(path)], into: %{} do
      {name, %{"path" => path, "sha256" => hash}}
    end
  end

  @doc """
  Abweichungen gegenueber `cfg.pins`: `:new` (noch nicht festgehalten oder
  an einem neuen Pfad, etwa nach `brew upgrade`) und `:changed` (gleicher
  Pfad, andere Bytes). Entfallene Programme zaehlen nicht.
  """
  @spec drift(Config.t(), pins()) :: %{new: [String.t()], changed: [String.t()]}
  def drift(%Config{pins: pinned}, current) do
    Enum.reduce(Enum.sort(current), %{new: [], changed: []}, fn
      {name, %{"path" => path} = pin}, acc ->
        case Map.get(pinned, name) do
          ^pin -> acc
          %{"path" => ^path} -> %{acc | changed: acc.changed ++ [name]}
          _ -> %{acc | new: acc.new ++ [name]}
        end
    end)
  end

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

  @doc "SHA-256 einer Datei oder, fuer ein Verzeichnis, ueber den ganzen Baum."
  @spec hash(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def hash(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :directory}} ->
        {:ok, hex(:crypto.hash(:sha256, tree_lines(path, "")))}

      {:ok, %File.Stat{type: :regular}} ->
        {:ok, hex(file_digest(path))}

      {:ok, %File.Stat{type: :symlink}} ->
        hash(Config.canonical(path))

      {:ok, _} ->
        {:error, "weder Datei noch Verzeichnis"}

      {:error, reason} ->
        {:error, List.to_string(:file.format_error(reason))}
    end
  end

  # Eine Zeile je Eintrag, sortiert: Typ, relativer Pfad, Inhalt-Hash bzw.
  # Symlink-Ziel. Umbenennen, Hinzufuegen, Entfernen und Umbiegen eines
  # Links aendern den Baum-Hash ebenso wie geaenderte Bytes.
  defp tree_lines(root, rel) do
    root
    |> Path.join(rel)
    |> File.ls!()
    |> Enum.sort()
    |> Enum.map(fn entry ->
      rel_entry = if rel == "", do: entry, else: Path.join(rel, entry)
      full = Path.join(root, rel_entry)

      case File.lstat!(full) do
        %File.Stat{type: :directory} ->
          ["d\0", rel_entry, "\n", tree_lines(root, rel_entry)]

        %File.Stat{type: :symlink} ->
          {:ok, target} = :file.read_link(full)
          ["l\0", rel_entry, "\0", to_string(target), "\n"]

        %File.Stat{type: :regular} ->
          ["f\0", rel_entry, "\0", hex(file_digest(full)), "\n"]

        _ ->
          ["o\0", rel_entry, "\n"]
      end
    end)
  end

  defp file_digest(path) do
    path
    |> File.stream!(1024 * 1024)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
  end

  defp hex(digest), do: Base.encode16(digest, case: :lower)
end
