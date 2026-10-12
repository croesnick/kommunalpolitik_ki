defmodule KomkiCli.RuntimeTest do
  # Env-Variablen der Naht (_IS_TTY, __BURRITO_BIN_PATH) sind global:
  # keine parallelen Läufe in diesem Modul.
  use ExUnit.Case, async: false

  alias KomkiCli.Runtime

  describe "self_path/0 (Pane-Einstieg der Session)" do
    test "unter Burrito: Pfad der Standalone-Binary (__BURRITO_BIN_PATH)" do
      System.put_env("__BURRITO_BIN_PATH", "/tmp/komki-artifact")
      on_exit(fn -> System.delete_env("__BURRITO_BIN_PATH") end)

      assert Runtime.self_path() == Path.expand("/tmp/komki-artifact")
    end

    test "ohne Burrito: Escript-Kontext (unter mix test läuft mix selbst als Escript)" do
      System.delete_env("__BURRITO_BIN_PATH")

      # Der Fallback ist :escript.script_name/0 — im Escript-Lauf der eigene
      # Pfad. Unter mix test ist der Laufkontext der mix-Escript selbst,
      # deshalb deckt dieser Fall den Fallback ohne Burrito ab (kein Raise;
      # das Raise mit klarer Meldung greift nur ausserhalb jeden Escript-
      # Kontexts, z.B. elixir -e, und ist dort vom session-Rescue gefasst).
      assert Runtime.self_path() == Path.expand(to_string(:escript.script_name()))
    end
  end

  describe "ansi_enabled?/0 (Burrito-TTY-Gate, Wrapper-Regression #234)" do
    test "_IS_TTY=0 (gepipet unter Burrito): Farben aus" do
      System.put_env("_IS_TTY", "0")
      on_exit(fn -> System.delete_env("_IS_TTY") end)

      refute Runtime.ansi_enabled?()
    end

    test "_IS_TTY=1 (Terminal unter Burrito): Farben an" do
      System.put_env("_IS_TTY", "1")
      on_exit(fn -> System.delete_env("_IS_TTY") end)

      assert Runtime.ansi_enabled?()
    end

    test "ohne _IS_TTY (Escript/mix): IO.ANSI.enabled?/0 als Fallback" do
      System.delete_env("_IS_TTY")

      assert Runtime.ansi_enabled?() == IO.ANSI.enabled?()
    end
  end

  describe "argv/0 (Burrito-argv-Aufruf, Ticket #75 ausgewiesen)" do
    test "ohne Burrito-Kontext: System.argv/0 (Dual-Sicherheit Escript/mix)" do
      assert Runtime.argv() == System.argv()
    end
  end

  # sync_ansi!/0 veraendert das globale :elixir-Env — Ruestung und Restore
  # im setup, keine parallelen Laeufe mit anderen env-basierten Tests.
  describe "sync_ansi!/0 (VM-weites ANSI-Gate, Optimus-Fix aus dem Pilot)" do
    setup do
      original = Application.get_env(:elixir, :ansi_enabled)

      on_exit(fn ->
        case original do
          nil -> Application.delete_env(:elixir, :ansi_enabled)
          value -> Application.put_env(:elixir, :ansi_enabled, value)
        end
      end)

      :ok
    end

    test "_IS_TTY=0: IO.ANSI.enabled?/0 wird false — auch fuer Optimus-Formatierung" do
      System.put_env("_IS_TTY", "0")
      on_exit(fn -> System.delete_env("_IS_TTY") end)

      :ok = Runtime.sync_ansi!()
      refute IO.ANSI.enabled?()
    end

    test "_IS_TTY=1: IO.ANSI.enabled?/0 wird true" do
      System.put_env("_IS_TTY", "1")
      on_exit(fn -> System.delete_env("_IS_TTY") end)

      :ok = Runtime.sync_ansi!()
      assert IO.ANSI.enabled?()
    end

    test "ohne _IS_TTY: No-Op, Default-Detekt bleibt unberuehrt" do
      System.delete_env("_IS_TTY")
      before = Application.get_env(:elixir, :ansi_enabled)

      :ok = Runtime.sync_ansi!()
      assert Application.get_env(:elixir, :ansi_enabled) == before
    end
  end
end
