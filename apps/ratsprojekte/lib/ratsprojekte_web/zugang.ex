defmodule RatsprojekteWeb.Zugang do
  @moduledoc """
  The gate in front of the interface (ADR 0004). With the lock switched on
  (`config :ratsprojekte, :sperre, true`, the release) a request passes
  only with the session marker of the current unlock, which
  `ZugangController` sets: from the one-time link of `ratsprojekte open`
  or from the „Entsperren“ button on the lock page (Touch ID). Everything
  else sees only the lock page. Every passing request is an action and
  postpones the lock.

  `on_mount/4` does the same for LiveViews (`live_session ...,
  on_mount: RatsprojekteWeb.Zugang`): events count as actions, and a lock
  sends the view back to the gate.
  """

  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [put_view: 2, render: 3]

  alias Ratsprojekte.Sperre

  @doc "Is the lock switched on?"
  @spec aktiv?() :: boolean()
  def aktiv?, do: Application.get_env(:ratsprojekte, :sperre, false)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    cond do
      not aktiv?() ->
        conn

      Sperre.zugang?(get_session(conn, :zugang)) ->
        Sperre.handlung()
        conn

      true ->
        conn |> clear_session() |> gesperrt() |> halt()
    end
  end

  @doc "The lock page for everyone without access; `fehler` says why an unlock failed."
  @spec gesperrt(Plug.Conn.t(), String.t() | nil) :: Plug.Conn.t()
  def gesperrt(conn, fehler \\ nil) do
    conn
    |> put_status(401)
    |> put_view(RatsprojekteWeb.ZugangHTML)
    |> render(:gesperrt, fehler: fehler)
  end

  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(_name, _params, session, socket) do
    cond do
      not aktiv?() ->
        {:cont, socket}

      Sperre.zugang?(session["zugang"]) ->
        if Phoenix.LiveView.connected?(socket),
          do: Phoenix.PubSub.subscribe(Ratsprojekte.PubSub, Sperre.topic())

        {:cont,
         socket
         |> Phoenix.LiveView.attach_hook(:zugang_handlung, :handle_event, fn _event,
                                                                             _params,
                                                                             socket ->
           Sperre.handlung()
           {:cont, socket}
         end)
         |> Phoenix.LiveView.attach_hook(:zugang_sperre, :handle_info, fn
           :gesperrt, socket -> {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
           _other, socket -> {:cont, socket}
         end)}

      true ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
    end
  end
end
