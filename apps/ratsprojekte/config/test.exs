import Config

config :ratsprojekte, Ratsprojekte.Repo,
  database:
    Path.join(System.tmp_dir!(), "ratsprojekte_test#{System.get_env("MIX_TEST_PARTITION")}.db"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :ratsprojekte, RatsprojekteWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "3WZB3uXIGsf8Faa3bN1N2XaGjy5LCW9Tp7gpnajcxB9kPQFeSJNNHneziG4+0TAe",
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :phoenix,
  sort_verified_routes_query_params: true
