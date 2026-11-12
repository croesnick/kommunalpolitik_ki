defmodule RatsprojekteWeb.ZugangTest do
  # Switches the lock on for the whole app, hence not async.
  use RatsprojekteWeb.ConnCase, async: false

  import Ratsprojekte.Betrieb

  alias Ratsprojekte.Sperre

  setup do
    Application.put_env(:ratsprojekte, :sperre, true)
    on_exit(fn -> Application.delete_env(:ratsprojekte, :sperre) end)
    home = home!()
    eingerichtet!(home)
    %{sperre: sperre!(home, name: Sperre)}
  end

  test "ohne Cookie nur „Bitte über ratsprojekte öffnen“", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 401) =~ "Bitte über ratsprojekte öffnen"
  end

  test "einmaliger Link setzt das Cookie, danach ist die Oberfläche offen", %{conn: conn} do
    {:ok, token} = Sperre.oeffnen()

    conn = get(conn, ~p"/zugang/#{token}")
    assert redirected_to(conn) == ~p"/"

    conn = conn |> recycle() |> get(~p"/")
    assert html_response(conn, 200) =~ "Der Hub ist im Aufbau."

    # The link is used up; another browser gets nothing with it.
    assert build_conn() |> get(~p"/zugang/#{token}") |> html_response(401) =~
             "Bitte über ratsprojekte öffnen"
  end

  test "nach dem Sperren hilft das alte Cookie nicht mehr", %{conn: conn} do
    {:ok, token} = Sperre.oeffnen()
    conn = get(conn, ~p"/zugang/#{token}")
    :ok = Sperre.sperren()

    conn = conn |> recycle() |> get(~p"/")
    assert html_response(conn, 401) =~ "Bitte über ratsprojekte öffnen"
  end

  test "Link eines gesperrten Hubs wird nicht eingelöst", %{conn: conn} do
    assert conn |> get(~p"/zugang/ausgedacht") |> html_response(401) =~ "Bitte über"
  end
end
