defmodule Ratsprojekte.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Die Datenbankdatei liegt außerhalb des Projekts (ADR 0004), und SQLite
    # legt keine Parent-Verzeichnisse an. In Dev sorgt config/dev.exs dafür,
    # hier ist es der Weg für den Release-Boot (#440).
    ensure_database_dir()

    children = [
      RatsprojekteWeb.Telemetry,
      Ratsprojekte.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:ratsprojekte, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:ratsprojekte, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Ratsprojekte.PubSub},
      # Start a worker by calling: Ratsprojekte.Worker.start_link(arg)
      # {Ratsprojekte.Worker, arg},
      # Start to serve requests, typically the last entry
      RatsprojekteWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ratsprojekte.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RatsprojekteWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations? do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end

  defp ensure_database_dir do
    case Ratsprojekte.Repo.config()[:database] do
      nil -> :ok
      path -> path |> Path.dirname() |> File.mkdir_p!()
    end
  end
end
