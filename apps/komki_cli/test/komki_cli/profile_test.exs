defmodule KomkiCli.ProfileTest do
  use ExUnit.Case, async: true

  alias KomkiCli.{Config, Profile, TestSupport}

  setup do
    cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-prof"))
    scratch = Path.join(cfg.base_dir, "runs/run-S")
    {:ok, cfg: cfg, scratch: scratch, text: Profile.generate(cfg, scratch)}
  end

  describe "Basis (deny-default)" do
    test "version + deny default sauber drin", %{text: text} do
      assert String.contains?(text, "(version 1)")
      assert String.contains?(text, "(deny default)")
    end

    test "niemals broad-Formen", %{text: text} do
      refute String.contains?(text, "(allow default)")
      refute String.contains?(text, "localhost:*")
      refute String.contains?(text, "(allow mach-lookup)\n")
    end

    test "emittierte Scratch-Pfade sind kernel-kanonisch", %{cfg: cfg} do
      # Invariante statt Plattform-Guard: Der Scratch-Pfad erscheint im
      # Profil immer in kernel-kanonischer Form (readlink-aufgeloest) —
      # unter macOS also /private/..., wo immer das Dateisystem es sagt.
      # Beweis ueber einen selbstgebauten Symlink: auf jedem Host gleich.
      pair = TestSupport.symlink_pair!(TestSupport.tmp_area!("komki-prof-sym"))

      text = Profile.generate(cfg, pair.link)

      assert String.contains?(text, "(subpath \"" <> Config.canonical(pair.real) <> "\")")
    end
  end

  describe "Port-Exception (eine outbound-TCP-Regel)" do
    test "loopback-Spezifik mit konfiguriertem Port", %{text: text, cfg: cfg} do
      port = to_string(cfg.port)

      assert String.contains?(
               text,
               "(allow network-outbound (remote tcp \"localhost:" <> port <> "\"))"
             )

      tcp_lines =
        text
        |> String.split("\n")
        |> Enum.filter(
          &(String.contains?(&1, "network-outbound") and String.contains?(&1, "tcp"))
        )

      assert tcp_lines == ["(allow network-outbound (remote tcp \"localhost:" <> port <> "\"))"]
    end
  end

  describe "gepinnte Regel-Vertraege aus dem Ticket-#70-Beschluss" do
    @pinned_rules [
      "sysctl-name \"kern.ostype\"",
      "sysctl-name \"machdep.cpu.brand_string\"",
      "(literal \"/dev/autofs_nowait\")",
      "vfs.disk-space",
      "com.apple.system.opendirectoryd.libinfo",
      "apple.shm.notification_center",
      "(literal \"/private/var/select/sh\")",
      ".CFUserTextEncoding",
      "unix-socket (literal \"/private/var/run/syslog\")",
      "(subpath \"/private/var/db/timezone\")",
      "(subpath \"/usr/share/icu\")",
      "/dev/dtracehelper"
    ]

    test "alle Probe-Pins vorhanden", %{text: text, cfg: cfg} do
      Enum.each(@pinned_rules, fn pin ->
        assert String.contains?(text, pin), "missing pinned rule: " <> pin
      end)

      # direkte pi-Kette: node-Binary-Literal (quoted) + pi-Bundle-Paket im Read-Baum
      assert String.contains?(text, "(literal \"" <> cfg.node_bin <> "\"))")
      assert String.contains?(text, "pi-coding-agent")
    end

    test "asdf-Regelschicht: nur bei asdf-gepinntem node", %{
      cfg: cfg,
      scratch: scratch,
      text: text
    } do
      # Generischer node-Pfad (brew/nvm-artig): keine asdf-Schicht — sie ist
      # einzig fuer asdf-gemanagte Installationen gedacht.
      refute String.contains?(text, "sysctl-name \"kern.bootargs\"")

      asdf_node =
        Path.join([System.user_home!(), ".asdf", "installs", "nodejs", "24.11.1", "bin", "node"])

      asdf_text = Profile.generate(%{cfg | node_bin: asdf_node}, scratch)

      assert String.contains?(asdf_text, "sysctl-name \"kern.bootargs\"")
      assert String.contains?(asdf_text, "shims")
    end
  end

  describe "pi-Such-Werkzeuge (fd/rg-Fundus)" do
    test "exec-Literale fuer die agent-bin-Kopien", %{text: text, cfg: cfg} do
      bin = Path.join([cfg.pi_home, ".pi", "agent", "bin"])

      assert String.contains?(
               text,
               "(allow process-exec (literal \"" <> Path.join(bin, "fd") <> "\"))"
             )

      assert String.contains?(
               text,
               "(allow process-exec (literal \"" <> Path.join(bin, "rg") <> "\"))"
             )
    end
  end

  describe "Portabilitaet (Nutzer-Regel: keine hartkodierten Systempfade)" do
    test "Nicht-brew-Konfiguration erzeugt keinerlei /opt/homebrew-Literale", %{
      cfg: cfg,
      scratch: scratch
    } do
      # Fixture: /usr/local-Pfade, kein asdf-node — brew-Pfade duerfen im
      # Profil nur aus entdeckten Werkzeugpfaden entstehen, nie hartkodiert.
      text = Profile.generate(cfg, scratch)

      refute String.contains?(text, "/opt/homebrew")
    end
  end

  describe "Write-Scope-Disziplin" do
    test "file-write-Zeilen nur pi-home/scratch (oder stdio/dev-Fall)", %{
      text: text,
      cfg: cfg,
      scratch: scratch
    } do
      text
      |> String.split("\n")
      |> Enum.filter(&String.contains?(&1, "file-write"))
      |> Enum.each(fn line ->
        in_scope =
          String.contains?(line, cfg.pi_home) or String.contains?(line, scratch) or
            String.contains?(line, "/dev/") or String.contains?(line, "dtracehelper")

        assert in_scope, "file-write line outside scope: " <> line
      end)
    end
  end

  describe "Determinismus" do
    test "feste cfg -> byte-identisch", %{cfg: cfg, scratch: scratch} do
      assert Profile.generate(cfg, scratch) == Profile.generate(cfg, scratch)
    end

    test "Scratch-Wechsel wirkt sich auf Scratch-Zeilen aus, sonst byte-gleich", %{
      cfg: cfg,
      scratch: scratch
    } do
      other = Path.join(Path.dirname(Path.dirname(scratch)), "runs/run-B")
      a = Profile.generate(cfg, scratch)
      b = Profile.generate(cfg, other)

      diff =
        a
        |> String.split("\n")
        |> Enum.zip(String.split(b, "\n"))
        |> Enum.reject(fn {x, y} -> x == y end)

      Enum.each(diff, fn {x, y} ->
        assert String.contains?(x, "run-S") and String.contains?(y, "run-B")
      end)
    end
  end
end
