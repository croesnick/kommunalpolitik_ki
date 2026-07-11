import Config

config :ratsprojekte,
  ecto_repos: [Ratsprojekte.Repo],
  generators: [timestamp_type: :utc_datetime]

config :ratsprojekte, RatsprojekteWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: RatsprojekteWeb.ErrorHTML, json: RatsprojekteWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Ratsprojekte.PubSub,
  live_view: [signing_salt: "fP3AwSEK"]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
