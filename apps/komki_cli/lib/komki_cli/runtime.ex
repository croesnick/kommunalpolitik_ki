defmodule KomkiCli.Runtime do
  @moduledoc """
  Laufkontext-Detektion fuer den Dual-Betrieb Escript + Burrito-Release
  (Ticket #75).

  komki laeuft in zwei Kontexten mit denselben Modulen:

    * **Escript** (`mix escript.build`, Dev-Alltag, Ticket #74): argv kommt
      ueber `System.argv/0`, der Programmpfad ueber `:escript.script_name/0`,
      Farben ueber `IO.ANSI.enabled?/0`.
    * **Burrito-Standalone-Binary** (`MIX_ENV=prod mix release`): der
      Zig-Wrapper startet den BEAM und setzt Laufzeit-Umgebung
      (`__BURRITO`, `__BURRITO_BIN_PATH`, `_IS_TTY`); `System.argv/0` ist
      zur Boot-Zeit leer (Burrito-1.6.0-`start_cli`-Reihenfolge, Issue #229).

  Diese Naht zentralisiert die drei kontextabhaengigen Fragen — argv,
  Programmpfad (Session-Pane), Farb-Gate — hinter kleinen Funktionen, damit
  nur diese Schicht den Packaging-Kontext kennt, nie Steps/Profile/Pi.

  ## Benannte Runtime-Zusaetze (Ticket-#75-Vorgabe)

  `argv/0` und `self_path/0` rufen **`Burrito.Util.Args`** auf — das ist der
  dokumentierte Weg (Burrito-README), und :burrito landet damit als benannter
  Bestandteil im Release-Payload. Beide Aufrufe sind dual-sicher: ohne
  Burrito-Kontext fallen sie auf Escript-/Mix-Verhalten zurueck.

  ## Farb-Gate unter Burrito (Wrapper-Regression #234)

  Der Unix-Wrapper startet den BEAM mit stdout als Pipe und erzwingt
  `ansi_enabled true` — `IO.ANSI.enabled?/0` ist unter der Binary damit
  immer `true`, auch beim Pipen in Dateien. Der Wrapper setzt dafuer ein
  eigenes `_IS_TTY` ("1"/"0"), das `ansi_enabled?/0` hier auswertet.
  Escript/Mix ohne `_IS_TTY` behalten `IO.ANSI.enabled?/0`.
  """

  # Benannte Burrito-Naht (Ticket #75, siehe Moduldoc): argv- und
  # Programmpfad-Aufruf laufen ueber Burrito.Util.Args.
  alias Burrito.Util.Args

  @no_self_path_msg """
  Programmpfad nicht bestimmbar: weder Burrito-Binary (__BURRITO_BIN_PATH) \
  noch Escript-Kontext — 'session' braucht einen der beiden Laufkontexte
  """

  # ===========================================================================
  # argv (Burrito-argv-Aufruf; Ticket #75: als solcher ausgewiesen)
  # ===========================================================================

  @doc """
  argv im jeweiligen Laufkontext: unter Burrito die vom Zig-Wrapper
  durchgereichten Argumente (`:init.get_plain_arguments/0`), sonst
  `System.argv/0` (Escript/mix). Burrito-1.6.0-Hinweis: `System.argv/0` ist
  zur `Application.start/2`-Zeit leer — diese Funktion ist der einzige
  argv-Einstieg der unter Burrito funktioniert.
  """
  @spec argv() :: [String.t()]
  def argv, do: Args.argv()

  # ===========================================================================
  # Programmpfad (Pane-Einstieg der interaktiven Session)
  # ===========================================================================

  @doc """
  Pfad des laufenden Programms: unter Burrito der Pfad der Standalone-Binary
  (so laesst sich die Session-Pane erneut mit der Binary starten), unter
  Escript der Escript-Pfad. Ausserhalb beider Kontexte wirft die Funktion
  mit klarer Meldung (statt spaeter kryptisch in der Pane zu scheitern).
  """
  @spec self_path() :: String.t() | no_return()
  def self_path do
    case Args.get_bin_path() do
      path when is_binary(path) -> Path.expand(path)
      :not_in_burrito -> escript_path()
    end
  end

  defp escript_path do
    Path.expand(to_string(:escript.script_name()))
  rescue
    # reraise haelt den Original-Stacktrace; die klare Meldung ersetzt nur
    # die kryptische (z.B. :escript.script_name/0 ohne Escript-Kontext).
    _ -> reraise %ArgumentError{message: @no_self_path_msg}, __STACKTRACE__
  end

  # ===========================================================================
  # Farb-Gate
  # ===========================================================================

  @doc """
  ANSI-Farben aktiv? Unter Burrito entscheidet das Wrapper-eigene `_IS_TTY`
  ("1" Terminal / "0" gepipet), weil `IO.ANSI.enabled?/0` unter der
  stdout-Pipe des Wrappers nicht mehr zwischen Terminal und Pipe
  unterscheiden kann (Burrito-Issue #234). Ohne `_IS_TTY` (Escript/mix)
  gilt `IO.ANSI.enabled?/0` wie bisher.
  """
  @spec ansi_enabled?() :: boolean()
  def ansi_enabled? do
    case System.get_env("_IS_TTY") do
      "1" -> true
      "0" -> false
      _ -> IO.ANSI.enabled?()
    end
  end

  @doc """
  Richtet das VM-weite ANSI-Verhalten nach dem Burrito-TTY-Gite — einmalig
  beim Release-Start (Aufrufer: `KomkiCli.Application.start/2`).

  Der Zig-Wrapper erzwingt `-elixir ansi_enabled true` (Regression #234):
  `IO.ANSI.enabled?/0` bleibt unter der Binary auch beim Pipen `true` —
  betroffen ist jede Formatierung, die selbst liest, namentlich Optimus'
  eigene Fehler-/Usage-Ausgaben (Pilot-Fund 2026-10-11: `Error: \e[31m...`
  in gepipete Dateien). Diese Funktion synchronisiert `:elixir
  :ansi_enabled` mit `_IS_TTY`; ohne `_IS_TTY` (Escript/mix) bleibt alles
  beim normalen Default-Detekt.
  """
  @spec sync_ansi!() :: :ok
  def sync_ansi! do
    case System.get_env("_IS_TTY") do
      nil -> :ok
      _ -> Application.put_env(:elixir, :ansi_enabled, ansi_enabled?())
    end
  end
end
