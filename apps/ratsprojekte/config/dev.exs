import Config

config :ratsprojekte, Ratsprojekte.Repo,
  database: Path.join(System.user_home!(), ".local/share/ratsinfo/ratsinfo.db"),
  pool_size: 10,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  log: :info

config :ratsprojekte, RatsprojekteWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "3LFU+QwhaeI9YcbyXMtBpdEny0Uf2CTeZqdYUdsi2TO+1LW7OlP+zKcc0JDtrDQs",
  watchers: []

config :ratsprojekte, RatsprojekteWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
      ~r"lib/ratsprojekte_web/(controllers|live|components)/.*\.(ex|heex)$"E
    ]
  ]

config :ratsprojekte, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true
