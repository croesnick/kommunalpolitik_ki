defmodule RatsprojekteWeb.ZugangTest do
  # Switches the lock on for the whole app, hence not async.
  use RatsprojekteWeb.ConnCase, async: false

  import Ratsprojekte.Betrieb

  alias Ratsprojekte.{Ort, Sperre}

  setup do
    Application.put_env(:ratsprojekte, :sperre, true)
    on_exit(fn -> Application.delete_env(:ratsprojekte, :sperre) end)
    home = home!()
    eingerichtet!(home)
    %{home: home, sperre: sperre!(home, name: Sperre)}
  end

  defp gesperrt?(conn) do
    html = html_response(conn, 401)
    html =~ ~s(id="gesperrt") and html =~ ~s(id="entsperren")
  end

  test "ohne Cookie nur die Sperrseite mit „Entsperren“", %{conn: conn} do
    assert conn |> get(~p"/") |> gesperrt?()
  end

  describe "einmaliger Link (ratsprojekte open)" do
    test "setzt das Cookie, danach ist die Oberfläche offen", %{conn: conn} do
      {:ok, token} = Sperre.oeffnen()

      conn = get(conn, ~p"/zugang/#{token}")
      assert redirected_to(conn) == ~p"/"

      conn = conn |> recycle() |> get(~p"/")
      assert html_response(conn, 200) =~ "Der Hub ist im Aufbau."

      # The link is used up; another browser gets nothing with it.
      assert build_conn() |> get(~p"/zugang/#{token}") |> gesperrt?()
    end

    test "nach dem Sperren hilft das alte Cookie nicht mehr", %{conn: conn} do
      {:ok, token} = Sperre.oeffnen()
      conn = get(conn, ~p"/zugang/#{token}")
      :ok = Sperre.sperren()

      assert conn |> recycle() |> get(~p"/") |> gesperrt?()
    end

    test "Link eines gesperrten Hubs wird nicht eingelöst", %{conn: conn} do
      conn = get(conn, ~p"/zugang/ausgedacht")
      assert gesperrt?(conn)
      assert html_response(conn, 401) =~ "abgelaufen oder schon benutzt"
    end
  end

  describe "Schaltfläche „Entsperren“" do
    test "entsperrt mit Touch ID und öffnet denselben Tab", %{conn: conn} do
      conn = post(conn, ~p"/entsperren")
      assert redirected_to(conn) == ~p"/"
      assert Sperre.status() == :offen

      conn = conn |> recycle() |> get(~p"/")
      assert html_response(conn, 200) =~ "Der Hub ist im Aufbau."
    end

    test "Touch ID abgelehnt oder Schlüssel fehlt: bleibt gesperrt, sagt warum", %{
      conn: conn,
      home: home
    } do
      File.rm!(Ort.schluessel(home))

      conn = post(conn, ~p"/entsperren")
      assert gesperrt?(conn)
      assert html_response(conn, 401) =~ ~s(id="entsperren-fehler")
      assert Sperre.status() == :gesperrt
    end

    # Like a browser: CSRF check on (ConnTest skips it), page reloaded
    # before the click. Regression: the gate cleared the session including
    # the CSRF token, and the click ended in 403.
    test "mit echter CSRF-Prüfung, auch nach Neuladen der Sperrseite", %{conn: conn} do
      conn = get(conn, ~p"/")
      conn = conn |> recycle() |> get(~p"/")
      [_, token] = Regex.run(~r/name="_csrf_token"[^>]*value="([^"]+)"/, html_response(conn, 401))

      conn =
        conn
        |> recycle()
        |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)
        |> post(~p"/entsperren", %{"_csrf_token" => token})

      assert redirected_to(conn) == ~p"/"
      assert Sperre.status() == :offen
    end

    test "zweiter Browser bei offenem Hub: neue Abfrage, gleiche Sitzung", %{conn: conn} do
      {:ok, token} = Sperre.oeffnen()
      {:ok, marker} = Sperre.einloesen(token)

      conn = post(conn, ~p"/entsperren")
      assert get_session(conn, :zugang) == marker
    end
  end
end
