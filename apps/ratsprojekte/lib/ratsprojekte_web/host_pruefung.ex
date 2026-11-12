defmodule RatsprojekteWeb.HostPruefung do
  @moduledoc """
  Accept only requests addressed to `localhost` or `127.0.0.1` (ADR 0004).
  A page on another origin cannot reach the hub through DNS rebinding:
  its requests carry a foreign `Host`. The list comes from
  `config :ratsprojekte, :erlaubte_hosts`; `:alle` switches the check off
  (tests, whose connections use `www.example.com`).
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case Application.get_env(:ratsprojekte, :erlaubte_hosts, ["localhost", "127.0.0.1"]) do
      :alle -> conn
      hosts -> if conn.host in hosts, do: conn, else: conn |> send_resp(421, "") |> halt()
    end
  end
end
