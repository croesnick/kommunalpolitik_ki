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

  describe "Netz-Exceptions (llama-Port und Vermittler-Socket, gepinnte Reihenfolge)" do
    test "llama-Port zuerst, Vermittler-Socket danach, sonst kein Netzziel", %{
      text: text,
      cfg: cfg
    } do
      llama_rule =
        "(allow network-outbound (remote tcp \"localhost:" <> to_string(cfg.port) <> "\"))"

      # Ticket #143: der Vermittler lauscht nur auf dem Unix-Socket.
      socket_rule =
        "(allow network-outbound (remote unix-socket (path-literal \"" <>
          Path.join([cfg.base_dir, "run", "mediator.sock"]) <> "\")))"

      syslog_rule =
        "(allow network-outbound (remote unix-socket (literal \"/private/var/run/syslog\")))"

      outbound =
        text
        |> String.split("\n")
        |> Enum.filter(&String.starts_with?(&1, "(allow network-outbound"))

      assert outbound == [syslog_rule, llama_rule, socket_rule]
      assert String.ends_with?(text, llama_rule <> "\n" <> socket_rule <> "\n")
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

  describe "Abhängigkeiten des pi-Pakets (Anzeige-Extension braucht jiti)" do
    @deps "; Abhaengigkeiten des pi-Pakets"

    test "pi unter node: der node-Baum deckt sie ab, keine Zusatzregel", %{text: text} do
      assert String.contains?(
               text,
               "(allow file-read* (subpath \"/usr/local/lib/node_modules\"))"
             )

      refute String.contains?(text, @deps)
    end

    test "pi aus dem komki-Paket: sein flaches node_modules ist lesbar", %{
      cfg: cfg,
      scratch: scratch
    } do
      packaged = "/opt/komki/libexec/lib/node_modules"
      cfg = %{cfg | cli_js: packaged <> "/@earendil-works/pi-coding-agent/dist/bundle/cli.js"}
      text = Profile.generate(cfg, scratch)

      assert String.contains?(text, @deps)
      assert String.contains?(text, "(allow file-read* (subpath \"" <> packaged <> "\"))")
      refute text =~ ~r/file-write\* \(subpath "#{packaged}/
    end
  end

  describe "pi-Such-Werkzeuge (fd/rg-Fundus)" do
    test "exec-Literale für die agent-bin-Kopien", %{text: text, cfg: cfg} do
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

  describe "Portabilität (Nutzer-Regel: keine hartkodierten Systempfade)" do
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

  describe "/dev/fd/0-Redirect (Burrito-Session-Fix, Pilot 2026-10-11)" do
    test "Regeln vorhanden — kontextfrei im Profil, damit die Identität nicht vom Laufkontext abhängt",
         %{text: text} do
      assert String.contains?(text, "(allow file-write* (literal \"/dev/fd/0\"))")
      assert String.contains?(text, "(allow file-read-metadata (literal \"/dev/fd\"))")
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

  describe "llama-server-Profil (Ticket #100)" do
    # Ueberdeckt das :text aus dem globalen Setup (llama-Profiltext statt pi).
    setup %{cfg: cfg} do
      {:ok, text: Profile.generate_llama(cfg)}
    end

    test "deny-default-Basis, keine Broad-Formen", %{text: text} do
      assert String.contains?(text, "(version 1)")
      assert String.contains?(text, "(deny default)")
      refute String.contains?(text, "(allow default)")
      refute String.contains?(text, "localhost:*")
      refute String.contains?(text, "(allow mach-lookup)\n")
    end

    test "API-Key-Datei nur lesend freigegeben (Ticket #136)", %{cfg: cfg, text: text} do
      key = KomkiCli.Llama.key_path(cfg)
      assert String.contains?(text, ~s|(allow file-read* (literal "#{key}"))|)
      refute String.contains?(text, ~s|(allow file-write* (literal "#{key}"))|)
    end

    test "kein network-outbound — Offline wird profilseitig erzwungen", %{text: text} do
      refute String.contains?(text, "network-outbound")
    end

    test "Management-Port: genau eine bind-Regel, loopback+Port gepinnt", %{text: text, cfg: cfg} do
      assert String.contains?(
               text,
               "(allow network-bind (local ip \"localhost:" <> to_string(cfg.port) <> "\"))"
             )

      assert String.contains?(text, "(allow network-inbound (local ip))")

      bind_lines =
        text |> String.split("\n") |> Enum.filter(&String.contains?(&1, "network-bind"))

      assert bind_lines == [
               "(allow network-bind (local ip \"localhost:" <> to_string(cfg.port) <> "\"))"
             ]
    end

    test "exec/read für llama-server, Modell und Log", %{text: text, cfg: cfg} do
      assert String.contains?(
               text,
               "(allow process-exec (literal \"" <> cfg.llama_server_bin <> "\"))"
             )

      assert String.contains?(text, "(allow file-read* (literal \"" <> cfg.gguf_path <> "\"))")

      log = Path.join([cfg.base_dir, "tmp", "llama-server.log"])
      assert String.contains?(text, "(allow file-write* (literal \"" <> log <> "\"))")
    end

    test "Write-Scope-Disziplin: file-write nur Log + dtracehelper", %{text: text, cfg: cfg} do
      log = Path.join([cfg.base_dir, "tmp", "llama-server.log"])

      text
      |> String.split("\n")
      |> Enum.filter(&String.contains?(&1, "file-write"))
      |> Enum.each(fn line ->
        in_scope = String.contains?(line, log) or String.contains?(line, "dtracehelper")
        assert in_scope, "file-write line outside scope: " <> line
      end)
    end

    test "kein pi-Home, keine pi-Regel-Schicht im llama-Profil", %{text: text, cfg: cfg} do
      refute String.contains?(text, cfg.pi_home)
      refute String.contains?(text, "asdf")
    end

    test "Determinismus: feste cfg -> byte-identisch", %{cfg: cfg} do
      assert Profile.generate_llama(cfg) == Profile.generate_llama(cfg)
    end

    test "GPU/Metal-Kette (#111): iokit-Grants, Compiler-Service und Extensions gepinnt", %{
      text: text
    } do
      assert String.contains?(
               text,
               "(allow iokit-open-user-client (iokit-user-client-class \"AGXDeviceUserClient\"))"
             )

      assert String.contains?(
               text,
               "(allow iokit-open-user-client (iokit-user-client-class \"IOSurfaceRootUserClient\"))"
             )

      assert String.contains?(text, "com.apple.MTLCompilerService")
      assert String.contains?(text, "com.apple.windowserver.active")

      assert String.contains?(
               text,
               "(allow file-issue-extension (extension-class \"com.apple.app-sandbox.read\"))"
             )
    end
  end
end
