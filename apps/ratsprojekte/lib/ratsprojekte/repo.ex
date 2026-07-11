defmodule Ratsprojekte.Repo do
  use Ecto.Repo,
    otp_app: :ratsprojekte,
    adapter: Ecto.Adapters.SQLite3
end
