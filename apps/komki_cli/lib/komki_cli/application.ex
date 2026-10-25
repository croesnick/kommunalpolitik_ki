defmodule KomkiCli.Application do
  @moduledoc """
  Release-Einstieg fuer `komki` (mix release / Burrito-Standalone, Ticket #75).

  Dual-Betrieb mit dem Escript (Ticket #74), das keinen Application-Start
  kennt und weiterhin direkt `KomkiCli.CLI.main/1` aufruft:

    * **Release-Kontext** (Burrito-Binary): der Release-Boot startet die App
      ueber `:mod` und landet hier. argv holt `KomkiCli.Runtime.argv/0`
      (Burrito-argv-Aufruf; `System.argv/0` ist zur Boot-Zeit leer),
      `KomkiCli.CLI.main/1` rendert und beendet synchron mit
      `System.halt(exit_code)`. Das synchron-in-start/2-Muster ist der
      dokumentierte Burrito-1.6.0-Weg (examples/cli_example) und gewinnt
      deterministisch gegen `elixir start_cli`, das sonst argv beanspruchen
      und die VM anhalten wuerde (Burrito-Issue #229, offene Regression).
      Exit-Codes 0/2/3/4 reichen durch den Zig-Wrapper bis zur Shell.
    * **Mix- und Escript-Kontext** (kein `__BURRITO`): die App startet als
      No-Op-Supervisor — `mix test`/`mix run` duerfen die VM nicht
      anhalten, und das Escript ruft `KomkiCli.CLI.main/1` nach dem
      App-Start selbst auf.
  """

  use Application

  @impl Application
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    # Nur die Burrito-Binary startet die CLI aus dem App-Start. Unter mix und
    # im Escript ist der Start ein No-Op; das Escript ruft danach
    # `KomkiCli.CLI.main/1` selbst auf. Wichtig fuer die Rollen (Ticket
    # #179): ein Vermittler, der im App-Start liefe, blockierte den
    # Application-Controller und damit seine eigenen Abhaengigkeiten.
    if KomkiCli.Runtime.burrito?() do
      # VM-weites ANSI nach dem Burrito-TTY-Gate richten, bevor irgendwer
      # formatiert — auch Optimus' eigene Fehler-/Usage-Ausgaben folgen
      # sonst dem erzwungenen ansi_enabled (Pilot-Fund, Regression #234).
      KomkiCli.Runtime.sync_ansi!()
      start_burrito(KomkiCli.Runtime.argv())
    else
      Supervisor.start_link([], strategy: :one_for_one)
    end
  end

  # Rollen (Ticket #181) laufen in einem eigenen Prozess: ein Vermittler oder
  # Connector im App-Start selbst blockierte den Application-Controller, und
  # die Rolle koennte ihre eigenen Abhaengigkeiten nicht mehr starten. Der
  # App-Start kehrt sofort zurueck; die Rolle beendet die VM selbst.
  defp start_burrito(argv) do
    case KomkiCli.Roles.dispatch(argv) do
      {module, rest} ->
        Task.start_link(fn ->
          module.main(rest)
          System.halt(0)
        end)

      nil ->
        KomkiCli.CLI.main(argv)
    end
  end
end
