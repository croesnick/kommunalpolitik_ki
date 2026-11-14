defmodule Ratsprojekte.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        RatsprojekteWeb.Telemetry,
        {Phoenix.PubSub, name: Ratsprojekte.PubSub}
      ] ++
        datenbank(Application.get_env(:ratsprojekte, :sperre, false)) ++
        [RatsprojekteWeb.Endpoint]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ratsprojekte.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Release (#440, ADR 0004): start locked. The repo starts only with the key,
  # under Ratsprojekte.RepoSupervisor, when `ratsprojekte open` unlocks.
  defp datenbank(true) do
    home = Ratsprojekte.Ort.home()
    Ratsprojekte.Ort.anlegen!(home)

    if Application.get_env(:ratsprojekte, :inhaltsfreie_logs, false),
      do: Ratsprojekte.Logfilter.installieren()

    [
      {DynamicSupervisor, name: Ratsprojekte.RepoSupervisor, strategy: :one_for_one},
      {Ratsprojekte.Sperre,
       home: home,
       provider: Ratsprojekte.CLI.provider(),
       sperre_nach: Application.fetch_env!(:ratsprojekte, :sperre_nach)},
      {Ratsprojekte.Verwaltung, pfad: Ratsprojekte.Ort.verwaltung(home)},
      {RatsprojekteWeb.Connector, home: home}
    ]
  end

  # Dev and test: no real data, the repo runs without a key from the start.
  # SQLite creates no parent directories.
  defp datenbank(false) do
    case Ratsprojekte.Repo.config()[:database] do
      nil -> :ok
      path -> path |> Path.dirname() |> File.mkdir_p!()
    end

    [Ratsprojekte.Repo]
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RatsprojekteWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
