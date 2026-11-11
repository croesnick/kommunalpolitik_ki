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
  # Eigene Datei unter ~/Library/Application Support/ratsprojekte/ (ADR 0004),
  # DATABASE_PATH überschreibt. Der SQLCipher-Schlüssel kommt über
  # RATSPROJEKTE_DB_KEY — der lokale Betrieb (#440) versiegelt ihn mit
  # sealed_envelope hinter Touch ID (komki-tresor). Ohne Schlüssel verhält
  # sich SQLCipher wie normales SQLite; der Hub mit echten Daten läuft nur
  # im Release (ADR 0004: „mit echten Daten nie im Dev-Modus‟).
  database_path =
    System.get_env("DATABASE_PATH") ||
      Path.join(System.user_home!(), "Library/Application Support/ratsprojekte/ratsprojekte.db")

  repo_config = [
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")
  ]

  repo_config =
    case System.get_env("RATSPROJEKTE_DB_KEY") do
      nil -> repo_config
      key -> Keyword.put(repo_config, :key, key)
    end

  config :ratsprojekte, Ratsprojekte.Repo, repo_config

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :ratsprojekte, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :ratsprojekte, RatsprojekteWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      #
      # TODO #440: Der lokale Hub gehört auf {127, 0, 0, 1} und Port 4100 —
      # das setzt der lokale Betrieb mit LaunchAgent und Socket (ADR 0004:
      # „Die Oberfläche liegt auf 127.0.0.1:4100‟). Bis dahin phx.new-Stand.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :ratsprojekte, RatsprojekteWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :ratsprojekte, RatsprojekteWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
