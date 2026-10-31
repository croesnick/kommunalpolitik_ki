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

    test "Drafter-Pin (Ticket #318): neben dem Modell, Staging ohne MTP/-Pfad" do
      cfg = Config.defaults(TestSupport.tmp_area!("komki-cfg-drafter"))

      assert cfg.drafter_path ==
               Path.join([cfg.base_dir, "models", "mtp-gemma-4-26B-A4B-it-Q8_0.gguf"])

      assert cfg.drafter_sha256 == Config.expected_drafter_sha256()
      assert cfg.drafter_sha256 =~ ~r/^[0-9a-f]{64}$/

      assert Config.staging_drafter_path() =~
               ~r/models-staging\/mtp-gemma-4-26B-A4B-it-Q8_0\.gguf$/
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

    test "Vermittler-Pins (Ticket #102): mediator_bin optional, kein Port mehr (Ticket #143)" do
      cfg = Config.defaults(TestSupport.tmp_area!("komki-cfg-med"))

      # Entdeckung wird durchgereicht (nil bleibt optional — kein init-Gate;
      # die Discovery-Logik selbst deckt config_test nicht ein, wie fd/rg).
      assert cfg.mediator_bin == Config.resolve_mediator_bin(cfg.base_dir)
      refute Map.has_key?(cfg, :mediator_port)
    end

    test "mediator_bin roundtrip; mediator_port aelterer Instanzen wird ignoriert" do
      cfg = Config.defaults(TestSupport.tmp_area!("komki-cfg-med"))
      base = cfg.base_dir

      no_bin = %{cfg | mediator_bin: nil}
      Config.save(no_bin)
      assert {:ok, no_bin} == Config.load(Config.config_path(base))

      with_bin = %{cfg | mediator_bin: "/pfad/zu/komki-mediator"}
      Config.save(with_bin)
      assert {:ok, with_bin} == Config.load(Config.config_path(base))

      legacy =
        base
        |> Config.config_path()
        |> File.read!()
        |> JSON.decode!()
        |> Map.put("mediator_port", 49_525)

      assert {:ok, ^with_bin} = Config.from_map(legacy)
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

  describe "Connector-Felder (Ticket #146)" do
    test "Defaults: Egress-Ports, echte RIS-URL, Test-Vault unter der Basis" do
      cfg = Config.defaults(TestSupport.tmp_area!("komki-cfg-conn"))
      assert cfg.egress_ports == %{"ris" => 49_531, "web" => 49_532}
      assert cfg.ris_base_url == "https://risapi1.komuna.net/web/"
      assert cfg.ris_mock_port == nil
      assert cfg.vault_dir == Path.join(cfg.base_dir, "vault")
      assert Config.ris_url(cfg) == "https://risapi1.komuna.net/web/"
      refute Config.ris_mock?(cfg)
      assert Map.keys(cfg.connector_bins) == ["documents", "ris", "vault", "web"]
    end

    test "Ticket #203: --port verlegt auch die Egress-Ports" do
      cfg = Config.defaults(TestSupport.tmp_area!("komki-cfg-port"), port: 49_800)
      assert cfg.egress_ports == %{"ris" => 49_807, "web" => 49_808}
      assert Config.egress_ports_for(49_524) == Config.default_egress_ports()
    end

    test "Overrides: Mock-Port schaltet die URL um, leerer vault_dir schaltet ab" do
      cfg =
        Config.defaults(TestSupport.tmp_area!("komki-cfg-conn"),
          ris_mock_port: 4010,
          vault_dir: ""
        )

      assert Config.ris_mock?(cfg)
      assert Config.ris_url(cfg) == "http://127.0.0.1:4010/"
      assert cfg.vault_dir == nil
    end

    test "Roundtrip mit allen neuen Feldern" do
      cfg = %{
        Config.defaults(TestSupport.tmp_area!("komki-cfg-conn"), ris_mock_port: 4011)
        | escript_bin: "/opt/erl/bin/escript",
          egress_bin: "/opt/bin/komki-egress",
          connector_bins: %{"ris" => "/opt/bin/r", "vault" => nil, "web" => "/opt/bin/w"},
          egress_ports: %{"ris" => 50_001, "web" => 50_002}
      }

      Config.save(cfg)
      assert {:ok, cfg} == Config.load(Config.config_path(cfg.base_dir))
    end

    test "aeltere config.json ohne die Felder: Defaults, Vault abgeschaltet" do
      cfg = Config.defaults(TestSupport.tmp_area!("komki-cfg-old"))

      old =
        cfg
        |> Config.encode()
        |> JSON.decode!()
        |> Map.drop(
          ~w(escript_bin egress_bin connector_bins egress_ports ris_base_url ris_mock_port vault_dir)
        )

      assert {:ok, loaded} = Config.from_map(old)
      assert loaded.egress_ports == Config.default_egress_ports()
      assert loaded.ris_base_url == Config.default_ris_base_url()
      assert loaded.vault_dir == nil
      assert loaded.connector_bins == %{}
    end

    # Ticket #318 (Config-Migration): aeltere Instanzen kennen drafter_path/
    # drafter_sha256 noch nicht. Laden traegt die Pins nach (Pfad aus base_dir,
    # SHA aus dem Code-Pin) — doctor meldet dann nur noch die fehlende Datei,
    # und die naechste Speicherung persistiert die Felder.
    test "aeltere config.json ohne Drafter-Felder: Laden-Defaults (Ticket #318)" do
      cfg = Config.defaults(TestSupport.tmp_area!("komki-cfg-old-drafter"))

      old =
        cfg
        |> Config.encode()
        |> JSON.decode!()
        |> Map.drop(~w(drafter_path drafter_sha256))

      assert {:ok, loaded} = Config.from_map(old)
      assert loaded.drafter_path == cfg.drafter_path
      assert loaded.drafter_sha256 == Config.expected_drafter_sha256()

      Config.save(loaded)
      assert {:ok, ^loaded} = Config.load(Config.config_path(loaded.base_dir))
    end

    test "ungültiger Egress-Port ist ein Fehler" do
      cfg = Config.defaults(TestSupport.tmp_area!("komki-cfg-bad"))

      map =
        cfg
        |> Config.encode()
        |> JSON.decode!()
        |> Map.put("egress_ports", %{"ris" => 0})

      assert_raise RuntimeError, ~r/egress_ports/, fn -> Config.from_map(map) end
    end

    test "Erlang-Wurzel aus dem escript-Pfad" do
      assert Config.erlang_root("/x/erlang/28/bin/escript") == "/x/erlang/28"
    end
  end
end
