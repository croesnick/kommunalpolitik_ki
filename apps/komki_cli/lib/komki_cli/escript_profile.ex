defmodule KomkiCli.EscriptProfile do
  @moduledoc """
  Fassade und komki-Adapter fuer die Escript-Grundschicht unter
  deny-default (Ticket #146): Vermittler, Egress-Proxy und Connectoren
  sind Escripts mit Erlang-Runtime.

  Seit Ticket #226 lebt die Grundschicht selbst in der Library
  (`Seatbelt.Escript`: exec-Kette escript -> erl -> erlexec -> beam.smp,
  Boot-Schicht, BEAM-Initialisierung, crypto-NIF-dylibs, Burrito-Schicht;
  Regelsaetze und deren Begruendung siehe dort). Diese Fassade bleibt
  fuer drei komki-Entscheidungen zustaendig:

    * `erlang_root!/1`: welche Erlang-Wurzel zur Instanz gehoert — unter
      der Burrito-Einzeldatei (Ticket #181) die entpackte Laufzeit,
      sonst die Wurzel zu `escript_bin`; ohne beides scheitert die
      Generierung klar (deutscher Fehlertext).
    * Die Burrito-Schicht tritt nur fuer die komki-Binary selbst ein
      (nicht fuer Connector-Escripts): `runtime_for/2` entscheidet das
      anhand von config.json (`launcher`, `komki_bin`, `runtime_root`).
    * Oeffentliche komki-API (Header/Render/Log/Metadaten-Vorfahrn) mit
      stabiler Signatur fuer Vermittler-, Egress- und Connector-Profile.

  Bewusst nicht erlaubt (Library-Entscheidung, weiterhin gueltig): der
  syslog-Unix-Socket (os_log-Fallback, die Denials sind folgenlos),
  `~/.CFUserTextEncoding`, `/dev/tty`.

  Alle Pfade kommen kanonisch aus der config.json; feste Eingaben ergeben
  byte-identischen Text (der Doctor prueft das).
  """

  alias KomkiCli.Config
  alias Seatbelt.{Escript, SBPL}

  @doc """
  Erlang-Wurzel aus der config: unter der Burrito-Einzeldatei (Ticket #181)
  die entpackte Laufzeit (`runtime_root`), sonst die Wurzel zu `escript_bin`;
  fehlt sie, scheitert die Generierung klar.
  """
  @spec erlang_root!(Config.t()) :: String.t()
  def erlang_root!(%Config{launcher: "burrito", runtime_root: root}) when is_binary(root),
    do: root

  def erlang_root!(%Config{escript_bin: bin}) when is_binary(bin), do: Config.erlang_root(bin)

  def erlang_root!(%Config{}),
    do:
      raise(ArgumentError, "escript-Laufzeit nicht entdeckt (Erlang installieren, 'komki setup')")

  @doc "Regeln zu einem Profiltext verbinden (Library-Render: Duplikate entfernt, ein finales Newline)."
  @spec render([String.t()]) :: String.t()
  def render(rules), do: SBPL.render(rules)

  @doc "Kopf: Kommentarzeilen, Version, deny default."
  @spec header([String.t()]) :: [String.t()]
  def header(comments), do: SBPL.header(comments)

  @doc """
  Grundschicht eines Escripts (Library): Runtime unter `erlang_root`,
  die Escript-Datei `escript_file` und die Startsonden.
  """
  @spec runtime(String.t(), String.t()) :: [String.t()]
  def runtime(erlang_root, escript_file), do: Escript.runtime(erlang_root, escript_file)

  @doc """
  Grundschicht fuer die Rolle `binary` nach der Startart der Instanz. Im
  Escript-Betrieb genau `runtime/2` (Profiltext unveraendert); unter der
  Burrito-Einzeldatei (Ticket #181) zusaetzlich das Ausfuehren der Binary,
  die als Wrapper die entpackte Laufzeit unter `runtime_root` startet —
  aber nur, wenn `binary` die komki-Binary selbst ist.
  """
  @spec runtime_for(Config.t(), String.t()) :: [String.t()]
  def runtime_for(%Config{} = cfg, binary),
    do: Escript.runtime_for(erlang_root!(cfg), binary, burrito_opts(cfg, binary))

  # Burrito-Schicht nur fuer die komki-Binary selbst: Connector- und
  # Vermittler-Escripts sind keine Wrapper, ihre Profile bleiben ohne
  # diese Regeln (wie vor dem Umbau).
  defp burrito_opts(%Config{launcher: "burrito", komki_bin: komki, runtime_root: root}, komki)
       when is_binary(root),
       do: %{wrapper: komki, runtime_root: root}

  # Burrito-Startart, aber keine entpackte Laufzeit eingetragen: klar
  # scheitern statt still die Wrapper-Regeln wegzulassen — sonst bootet
  # die Binary spaeter am Boot-Gate mit verwirrendem rc statt hier mit
  # einer klaren Meldung (Vor-Umbau-Verhalten: lauter Crash).
  defp burrito_opts(%Config{launcher: "burrito", komki_bin: komki}, komki),
    do:
      raise(
        ArgumentError,
        "burrito-Instanz ohne runtime_root — config.json prüfen ('komki setup')"
      )

  defp burrito_opts(_cfg, _binary), do: nil

  @doc "Log-Datei (Redirect-Ziel der Spawn-Shell) lesen und schreiben."
  @spec log_rules(String.t()) :: [String.t()]
  def log_rules(log_path), do: Escript.log_rules(log_path)

  @doc """
  `file-read-metadata` fuer alle Vorfahren der Pfade (realpath-Walk von
  dyn_erl und dem Socket-Bind); sortiert, inklusive `/`.
  """
  @spec meta_ancestors([String.t()]) :: [String.t()]
  def meta_ancestors(paths), do: SBPL.metadata_ancestors(paths)
end
