defmodule RatsprojekteWeb.ZugangController do
  @moduledoc """
  The one-time link `ratsprojekte open` opens in the browser: valid once
  and for two minutes, traded for the session marker (`Sperre.einloesen/2`).
  The session is renewed, so a cookie from before cannot ride along.
  """

  use RatsprojekteWeb, :controller

  alias Ratsprojekte.Sperre
  alias RatsprojekteWeb.Zugang

  def einloesen(conn, %{"token" => token}) do
    if Zugang.aktiv?() do
      case Sperre.einloesen(token) do
        {:ok, marker} ->
          conn
          |> configure_session(renew: true)
          |> put_session(:zugang, marker)
          |> redirect(to: ~p"/")

        :error ->
          Zugang.bitte_oeffnen(conn)
      end
    else
      redirect(conn, to: ~p"/")
    end
  end
end
