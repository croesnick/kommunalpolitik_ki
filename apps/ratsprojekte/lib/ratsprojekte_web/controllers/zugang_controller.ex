defmodule RatsprojekteWeb.ZugangController do
  @moduledoc """
  The two ways to the session marker (ADR 0004, Nachtrag #440):

  - `einloesen/2`: the one-time link `ratsprojekte open` opens in the
    browser, valid once and for two minutes.
  - `entsperren/2`: the „Entsperren“ button on the lock page. A POST with
    the CSRF token of that page, so no other website can trigger it; the
    hub then asks for Touch ID exactly as for `ratsprojekte open`.

  Both renew the session, so a cookie from before cannot ride along.
  """

  use RatsprojekteWeb, :controller

  alias Ratsprojekte.{Schluessel, Sperre}
  alias RatsprojekteWeb.Zugang

  def einloesen(conn, %{"token" => token}) do
    if Zugang.aktiv?() do
      case Sperre.einloesen(token) do
        {:ok, marker} -> zulassen(conn, marker)
        :error -> Zugang.gesperrt(conn, "Dieser Link ist abgelaufen oder schon benutzt.")
      end
    else
      redirect(conn, to: ~p"/")
    end
  end

  def entsperren(conn, _params) do
    if Zugang.aktiv?() do
      with {:ok, token} <- Sperre.oeffnen(),
           {:ok, marker} <- Sperre.einloesen(token) do
        zulassen(conn, marker)
      else
        {:error, :datenbank} ->
          Zugang.gesperrt(conn, "Nicht entsperrt: Die Datenbank ließ sich nicht öffnen.")

        {:error, reason} ->
          Zugang.gesperrt(conn, "Nicht entsperrt: " <> Schluessel.beschreiben(reason) <> ".")

        :error ->
          Zugang.gesperrt(conn, "Nicht entsperrt, bitte noch einmal.")
      end
    else
      redirect(conn, to: ~p"/")
    end
  end

  defp zulassen(conn, marker) do
    conn
    |> configure_session(renew: true)
    |> put_session(:zugang, marker)
    |> redirect(to: ~p"/")
  end
end
