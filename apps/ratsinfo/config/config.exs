import Config

config :ratsinfo, Ratsinfo.Repo,
  database: Path.join(System.user_home!(), ".local/share/ratsinfo/ratsinfo.db"),
  pool_size: 1
