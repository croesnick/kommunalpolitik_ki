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
    * **Mix-Kontext** (dev/test, `Mix` geladen): die App startet als
      No-Op-Supervisor — `mix test`/`mix run` duerfen die VM nicht
      anhalten; CLI-Laufe gehen dort direkt ueber `KomkiCli.CLI.main/1`.
  """

  use Application

  @impl Application
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    if mix_context?() do
      Supervisor.start_link([], strategy: :one_for_one)
    else
      # VM-weites ANSI nach dem Burrito-TTY-Gate richten, bevor irgendwer
      # formatiert — auch Optimus' eigene Fehler-/Usage-Ausgaben folgen
      # sonst dem erzwungenen ansi_enabled (Pilot-Fund, Regression #234).
      KomkiCli.Runtime.sync_ansi!()
      KomkiCli.CLI.main(KomkiCli.Runtime.argv())
    end
  end

  # Mix ist in Releases nicht Teil des Payloads: geladenes Mix-Modul kennzeichnet
  # den dev-/test-Kontext. Im Release ist Code.ensure_loaded?/1 fuer Mix false.
  defp mix_context?, do: Code.ensure_loaded?(Mix)
end
