defmodule KomkiCli.ConfigTest do
  use ExUnit.Case, async: true

  alias KomkiCli.{Config, TestSupport}

  describe "canonical/1 (Pfadform-Cave, Phase 1)" do
    # Differenziale Tests gegen readlink(1) als unabhängiges Orakel und
    # selbstgebaute Symlink-Fixtures — umgebungsagnostisch auf jedem Host,
    # keine Plattform-Guards, keine Annahmen über /tmp-Layout.

    test "Invariante: canonical == readlink(1)-Sicht (existierender Pfad)" do
      area = TestSupport.tmp_area!("komki-canonical")
      assert Config.canonical(area) == TestSupport.readlink!(area)
    end

    test "fehlende Enden: Vorfahren aufgeloest, Rest angefuegt" do
      # Komposition statt direktem Orakel: BSD-readlink scheitert an
      # fehlenden Pfaden, GNU erlaubt nur die fehlende LETZTE Komponente —
      # canonical muss beides ueber den Vorfahren-Walk abdecken.
      area = Config.canonical(TestSupport.tmp_area!("komki-canonical"))
      deep = Path.join(area, "x/y")
      assert Config.canonical(deep) == Path.join(area, "x/y")
    end

    test "Symlink-Aufloesung: link wird auf real abgebildet" do
      pair = TestSupport.symlink_pair!(TestSupport.tmp_area!("komki-canonical"))
      assert Config.canonical(pair.link) == Config.canonical(pair.real)
    end

    test "idempotent" do
      once = Config.canonical(TestSupport.tmp_area!("komki-canonical"))
      assert Config.canonical(once) == once
    end

    test "~/-Expansion" do
      home = Config.canonical(System.user_home!())
      assert Config.canonical("~/l") == Path.join(home, "l")
    end
  end

  describe "defaults/2 — gepinnte Werte aus dem Ticket-#70-Beschluss" do
    test "Basiswerte (Modell-Pin: Gemma 4 26B-A4B, Nutzer-GO 05.10.2026)" do
      cfg = Config.defaults(TestSupport.tmp_area!("komki-cfg"))

      base = cfg.base_dir
      assert base == Config.canonical(base)

      assert cfg.base_dir == base
      assert cfg.port == 49_524
      assert cfg.ctx == 131_072
      assert cfg.gguf_path == Path.join([base, "models", "gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf"])
      assert cfg.gguf_sha256 == Config.expected_gguf_sha256()
      assert cfg.pi_home == Path.join(base, "pi-home")
      assert cfg.sandbox_exec == "/usr/bin/sandbox-exec"
      assert cfg.profile_path == Path.join([base, "profile", "komki.sb"])
    end

    test "Werkzeug-Entdeckung: aufgeloeste Pfade oder nil, nie asdf-Shims" do
      cfg = Config.defaults(TestSupport.tmp_area!("komki-cfg"))

      assert cfg.node_bin == Config.resolve_node_bin()
      assert cfg.cli_js == Config.resolve_cli_js(cfg.node_bin)
      assert cfg.llama_server_bin == Config.resolve_llama_server()

      # Entdeckt heisst: vorhanden und echt — der asdf-Shim (Shell-Skript)
      # taugt unter der Seatbelt-Grenze nicht als node-Pfad.
      if is_binary(cfg.node_bin) do
        assert File.exists?(cfg.node_bin)
        refute String.contains?(cfg.node_bin, "/.asdf/shims/")
      end

      if is_binary(cfg.cli_js), do: assert(File.exists?(cfg.cli_js))

      if is_binary(cfg.llama_server_bin), do: assert(File.exists?(cfg.llama_server_bin))
    end

    test "Port/ctx-Overrides" do
      cfg = Config.defaults(TestSupport.tmp_area!("komki-cfg"), port: 49_999, ctx: 4_096)
      assert cfg.port == 49_999
      assert cfg.ctx == 4_096
    end
  end

  describe "save/load-Roundtrip" do
    test "byte-stabil und voll reconstructierbar" do
      cfg = Config.defaults(TestSupport.tmp_area!("komki-cfg"), port: 50_001, ctx: 4_096)
      base = cfg.base_dir
      Config.save(cfg)

      encoded = File.read!(Config.config_path(base))
      assert encoded == Config.encode(cfg) <> "\n"

      {:ok, reloaded} = Config.load(Config.config_path(base))
      assert reloaded == cfg
    end

    test "fehlende config.json ist ein Fehler, kein Crash" do
      assert {:error, reason} = Config.load("/nonexistent/komki/config.json")
      assert reason =~ "cannot read"
    end
  end
end
