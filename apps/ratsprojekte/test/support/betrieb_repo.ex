defmodule Ratsprojekte.BetriebRepo do
  @moduledoc """
  Repo for the tests of local operation (#440): `Ratsprojekte.Sperre` starts
  and stops it with a key, next to the sandboxed `Ratsprojekte.Repo`.
  """

  use Ecto.Repo, otp_app: :ratsprojekte, adapter: Ecto.Adapters.SQLite3
end
