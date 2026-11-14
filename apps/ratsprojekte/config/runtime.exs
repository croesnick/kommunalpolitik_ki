import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/ratsprojekte start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :ratsprojekte, RatsprojekteWeb.Endpoint, server: true
end

config :ratsprojekte, RatsprojekteWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :ratsprojekte, RatsprojekteWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/ratsprojekte_web/router\.ex$"E,
        ~r"lib/ratsprojekte_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  # Local operation (#440, ADR 0004): the release starts locked. The database
  # lives in its own directory (RATSPROJEKTE_HOME overrides it for throwaway
  # instances); its key arrives only with `ratsprojekte open`
  # (Ratsprojekte.Sperre), never through the environment.
  home =
    System.get_env("RATSPROJEKTE_HOME") ||
      Path.join(System.user_home!(), "Library/Application Support/ratsprojekte")

  config :ratsprojekte, home: home, sperre: true, inhaltsfreie_logs: true

  config :ratsprojekte, Ratsprojekte.Repo,
    database: Path.join(home, "ratsprojekte.db"),
    pool_size: 2

  # A fresh secret per boot: a restart starts locked anyway, and old session
  # cookies must not survive it.
  secret_key_base = 48 |> :crypto.strong_rand_bytes() |> Base.encode64()

  config :ratsprojekte, RatsprojekteWeb.Endpoint,
    url: [host: "localhost", port: 4100, scheme: "http"],
    http: [ip: {127, 0, 0, 1}, port: 4100, thousand_island_options: [num_acceptors: 4]],
    check_origin: ["//localhost", "//127.0.0.1"],
    secret_key_base: secret_key_base
end
