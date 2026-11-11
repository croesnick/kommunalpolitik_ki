# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ratsprojekte,
  ecto_repos: [Ratsprojekte.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :ratsprojekte, RatsprojekteWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: RatsprojekteWeb.ErrorHTML, json: RatsprojekteWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Ratsprojekte.PubSub,
  live_view: [signing_salt: "0Q7eupxg"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# exqlite baut gegen die SQLCipher-Systembibliothek (ADR 0004 „Betrieb‟, #435,
# BSD-Lizenz). force_build verhindert die vorcompilierten NIF-Artefakte von
# cc_precompiler — sie enthalten ein ungepatchtes SQLite und ignorieren die
# Env-Variablen. make_env reicht die Variablen an den make-Prozess durch;
# ohne EXQLITE_USE_SYSTEM kompiliert das Makefile das gebündelte sqlite3.c.
# Ohne Schlüssel verhält sich SQLCipher wie normales SQLite (ADR 0004:
# „ohne Schlüssel verhält sich SQLCipher wie SQLite‟). Der Schreibweg für den
# Schlüssel kommt mit dem lokalen Betrieb (#440). Derselbe Block steht in
# apps/ratsinfo und apps/komki_cli — der Deps-Baum ist im Workspace geteilt,
# exqlite kompiliert pro App gegen dieselbe Systembibliothek.
sqlcipher_prefix =
  System.get_env("SQLCIPHER_PREFIX") ||
    case :os.type() do
      {:unix, :darwin} ->
        (System.get_env("HOMEBREW_PREFIX") || "/opt/homebrew") <> "/opt/sqlcipher"

      {:unix, :linux} ->
        "/usr"
    end

config :exqlite,
  force_build: true,
  make_env: %{
    "EXQLITE_USE_SYSTEM" => "1",
    "EXQLITE_SYSTEM_CFLAGS" => "-I#{sqlcipher_prefix}/include/sqlcipher",
    "EXQLITE_SYSTEM_LDFLAGS" => "-L#{sqlcipher_prefix}/lib -lsqlcipher"
  }

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  ratsprojekte: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    # Workspace-Pattern: Deps liegen geteilt unter apps/artifacts/deps.
    env: %{
      "NODE_PATH" => [Path.expand("../../artifacts/deps", __DIR__), Mix.Project.build_path()]
    }
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  ratsprojekte: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{
      "NODE_PATH" => [Path.expand("../../artifacts/deps", __DIR__), Mix.Project.build_path()]
    }
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
