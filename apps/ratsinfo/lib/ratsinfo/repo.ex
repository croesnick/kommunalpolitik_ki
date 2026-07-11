defmodule Ratsinfo.Repo do
  use Ecto.Repo,
    otp_app: :ratsinfo,
    adapter: Ecto.Adapters.SQLite3

  @doc "Standard-Datenbankpfad"
  def db_path do
    Path.join(System.user_home!(), ".local/share/ratsinfo/ratsinfo.db")
  end

  @doc "Datenbank öffnen (für CLI-Nutzung ohne Application)"
  def open do
    dir = Path.dirname(db_path())
    File.mkdir_p!(dir)

    config = [
      database: db_path(),
      pool_size: 1,
      journal_mode: :wal
    ]

    __MODULE__.start_link(config)
  end
end
