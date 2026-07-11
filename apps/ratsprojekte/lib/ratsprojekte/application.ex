defmodule Ratsprojekte.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RatsprojekteWeb.Telemetry,
      Ratsprojekte.Repo,
      {Phoenix.PubSub, name: Ratsprojekte.PubSub},
      RatsprojekteWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
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
end
