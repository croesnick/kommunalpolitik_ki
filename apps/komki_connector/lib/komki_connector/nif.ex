defmodule KomkiConnector.Nif do
  @moduledoc """
  Zweite Programmform: Escript + NIF von der Platte (CONTRACT.md §4,
  Entscheidung #288, ADR 0002).

  Im Escript-Archiv ist `priv/` gezippt, und `dlopen` scheitert mit
  `errno=20` (Probe #278). Ein Connector mit NIF-Anwendung (Manifest-Feld
  `nif`) lädt sie deshalb von der Platte: aus dem Paket (`lib/<app>/`
  neben dem Programm, #180) oder aus dem Build-Baum (`_build/dev/lib/<app>/`,
  `make komki`), so wie komki selbst exqlite lädt (#91). Unter der
  Burrito-Einzeldatei lädt der NIF aus dem entpackten Payload; diese Seite
  ist dort unverwendbar (`:escript.script_name/0` existiert nicht), und
  Profil wie Pin bleiben bei der Einzeldatei.

  Diese eine Seite kennt die Kandidaten; alle Beteiligten — Bootstrap im
  Connector, Profilgenerator, Programm-Pins, Doctor — fragen dieselbe
  Funktion. So lädt der Connector aus genau dem Verzeichnis, das Profil
  und Pin beschreiben, und die erste Fundstelle gewinnt in allen gleich.
  Ohne Fundstelle bleibt alles beim Alten: der Connector startet, jede
  PDF-Lesung scheitert mit `internal` (Grund im Log), und der Doctor
  meldet die fehlenden Dateien.
  """

  alias Seatbelt

  @doc """
  Kandidatenverzeichnisse der NIF-Anwendung `app` neben `program`, in
  Suchreihenfolge: Paket-Layout (#180), Build-Baum des Multicall-Programms
  (`make komki`), Build-Baum des uebergeordneten Ordners (eigenstaendiges
  Connector-Escript im App-Ordner). Alle Pfade kernel-form, ohne `..`:
  eine Fundstelle fliesst woertlich in Profiltext und Pin. `program` wird
  kernel-kanonisiert (`Seatbelt.canonical/1`): Symlinks wie
  `~/.local/bin/komki` loesen sich auf den Build-Baum auf (Muster exqlite,
  Ticket #241), config-Pfade sind kanonisch und bleiben unveraendert.
  """
  @spec app_dirs(Path.t(), atom()) :: [Path.t()]
  def app_dirs(program, app) when is_binary(program) do
    base = program |> Seatbelt.canonical() |> Path.dirname()
    name = to_string(app)
    build = Path.join(["_build", "dev", "lib"])

    [
      Path.join([base, "lib", name]),
      Path.join([base, build, name]),
      Path.join([Path.dirname(base), build, name])
    ]
  end

  @doc """
  Das physische Verzeichnis der NIF-Anwendung: erste Fundstelle mit einem
  ebin-Verzeichnis — die eine Quelle für Profilregel, Programm-Pin und
  Bootstrap. `nil`, wenn es keine gibt.
  """
  @spec app_dir(Path.t(), atom()) :: Path.t() | nil
  def app_dir(program, app),
    do: Enum.find(app_dirs(program, app), &File.dir?(Path.join(&1, "ebin")))

  @doc """
  Bringt das physische ebin der NIF-Anwendung auf den Code-Pfad (zweite
  Programmform, CONTRACT.md §4): `Application.app_dir/2` zeigt dann auf die
  Platte statt ins Escript-Archiv, und die NIF samt ihrer Geschwisterdatei
  (`libpdfium`) lädt. Ohne `program` (Mix-Kontext, Release, Burrito) oder
  ohne Fundstelle ein No-Op.
  """
  @spec bootstrap(Path.t() | nil, atom()) :: :ok
  def bootstrap(nil, _app), do: :ok

  def bootstrap(program, app) do
    case app_dir(program, app) do
      nil -> :ok
      dir -> Code.prepend_path(Path.join(dir, "ebin"))
    end

    :ok
  end
end
