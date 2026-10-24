defmodule KomkiCli.ChannelTest do
  @moduledoc """
  Kanal pi → Vermittler (Ticket #143): Laufzeitverzeichnis, Token-Datei,
  Session-ID, Relay und Socket-Pfad-Grenze.
  """

  use ExUnit.Case, async: true

  alias KomkiCli.{Channel, Pi, TestSupport}

  setup do
    {:ok, cfg: TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-chan"))}
  end

  describe "write_token!/1" do
    test "run-Verzeichnis 0700, Token-Datei 0600, 64 Hex-Zeichen", %{cfg: cfg} do
      :ok = Channel.write_token!(cfg)

      assert mode(Channel.run_dir(cfg)) == 0o700
      assert mode(Channel.token_path(cfg)) == 0o600
      assert File.read!(Channel.token_path(cfg)) =~ ~r/\A[0-9a-f]{64}\z/
    end

    test "jedes up schreibt ein neues Token", %{cfg: cfg} do
      :ok = Channel.write_token!(cfg)
      {:ok, first} = Channel.read_token(cfg)
      :ok = Channel.write_token!(cfg)
      {:ok, second} = Channel.read_token(cfg)

      refute first == second
      assert mode(Channel.token_path(cfg)) == 0o600
    end

    test "zu offene Rechte eines vorhandenen run-Verzeichnisses werden korrigiert", %{cfg: cfg} do
      File.mkdir_p!(Channel.run_dir(cfg))
      File.chmod!(Channel.run_dir(cfg), 0o755)
      :ok = Channel.write_token!(cfg)
      assert mode(Channel.run_dir(cfg)) == 0o700
    end
  end

  describe "read_token/1" do
    test "fehlende Datei: Fehler mit Hinweis auf 'komki up'", %{cfg: cfg} do
      assert {:error, reason} = Channel.read_token(cfg)
      assert reason =~ "komki up"
    end

    test "ungueltiger Inhalt: Fehler ohne den Inhalt", %{cfg: cfg} do
      :ok = Channel.write_token!(cfg)
      File.write!(Channel.token_path(cfg), "geheim-aber-falsch")
      assert {:error, reason} = Channel.read_token(cfg)
      refute reason =~ "geheim-aber-falsch"
    end
  end

  describe "prepare_pi/1" do
    test "Token und frische Session-ID in der Umgebung, Relay geschrieben", %{cfg: cfg} do
      :ok = Channel.write_token!(cfg)
      {:ok, token} = Channel.read_token(cfg)

      assert {:ok, %{"KOMKI_MEDIATOR_TOKEN" => ^token, "KOMKI_SESSION_ID" => s1}} =
               Channel.prepare_pi(cfg)

      assert {:ok, %{"KOMKI_SESSION_ID" => s2}} = Channel.prepare_pi(cfg)
      assert s1 =~ ~r/\Ases-[0-9a-f]{16}\z/
      refute s1 == s2

      # Format passt zur Pruefung im Vermittler (^[a-z0-9-]{8,64}$).
      assert s1 =~ ~r/\A[a-z0-9-]{8,64}\z/
      assert File.read!(Channel.relay_path(cfg)) == Channel.relay_js()
    end

    test "ein veraendertes Relay wird vor dem naechsten pi-Start ersetzt", %{cfg: cfg} do
      :ok = Channel.write_token!(cfg)
      {:ok, _} = Channel.prepare_pi(cfg)
      File.write!(Channel.relay_path(cfg), "// manipuliert")
      {:ok, _} = Channel.prepare_pi(cfg)
      assert File.read!(Channel.relay_path(cfg)) == Channel.relay_js()
    end

    test "ohne Token kein pi-Start", %{cfg: cfg} do
      assert {:error, _} = Channel.prepare_pi(cfg)
    end
  end

  describe "Token nie in argv" do
    test "argv von Einmal-Lauf und Session enthaelt das Token nicht", %{cfg: cfg} do
      :ok = Channel.write_token!(cfg)
      {:ok, env} = Channel.prepare_pi(cfg)
      token = env["KOMKI_MEDIATOR_TOKEN"]

      run_argv = Pi.argv_for(cfg, Path.join(cfg.base_dir, "runs/x"), :text, "Hallo")
      session_argv = Pi.argv_session(cfg, false)

      refute Enum.any?(run_argv ++ session_argv, &String.contains?(&1, token))

      # ... sondern in der Umgebung.
      assert {"KOMKI_MEDIATOR_TOKEN", token} in Pi.session_env(cfg, env)
    end
  end

  describe "check_socket_path/1" do
    test "kurze Basis ist ok, zu lange wird abgelehnt", %{cfg: cfg} do
      assert :ok = Channel.check_socket_path(%{cfg | base_dir: "/tmp/k"})

      long = "/tmp/" <> String.duplicate("x", 90)
      assert {:error, reason} = Channel.check_socket_path(%{cfg | base_dir: long})
      assert reason =~ "103"
    end
  end

  test "Relay ist eingebettet und node-syntaktisch plausibel" do
    js = Channel.relay_js()
    assert js =~ "socketPath"
    assert js =~ "X-Komki-Session"
    refute js =~ ~r/stderr\.write\([^)]*TOKEN/
  end

  defp mode(path) do
    {:ok, stat} = File.stat(path)
    Bitwise.band(stat.mode, 0o777)
  end
end
