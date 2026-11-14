defmodule KomkiCli.MediatorTest do
  @moduledoc """
  Hermetische Unit-Tests der Vermittler-Vertragsnaehe (Ticket #102):
  mcp.json-Aufbau (stdio-Relay, Ticket #143), Spawn-Zeile, healthz ueber den
  Unix-Socket und vollstaendige write_mcp_config. Kein echter Prozess wird gespawnt — der Lifecycle
  (up/down/status) ist wie Llama.up-Laeufe nicht in der Suite (echte
  Binaries, echte Ports).
  """

  use ExUnit.Case, async: true

  alias KomkiCli.{Channel, Mediator, TestSupport}

  describe "mcp_config_json/2 (stdio-Relay, Fassung-Pin auf pi-Seite)" do
    test "Struktur: Server komki als stdio-Relay, env nur mit Verweisen, Fassung-Tools direct" do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-mcp"))
      mcp = Mediator.mcp_config_json(cfg, ["ping", "admit_document"])

      # Exakte Gleichheit: keine Extra-Keys, keine zusaetzlichen Server.
      assert mcp == %{
               "mcpServers" => %{
                 "komki" => %{
                   "command" => cfg.node_bin,
                   "args" => [Path.join([cfg.pi_home, ".pi", "agent", "komki-relay.js"])],
                   "env" => %{
                     "KOMKI_MEDIATOR_SOCKET" => Path.join([cfg.base_dir, "run", "mediator.sock"]),
                     "KOMKI_MEDIATOR_TOKEN" => "${KOMKI_MEDIATOR_TOKEN}",
                     "KOMKI_SESSION_ID" => "${KOMKI_SESSION_ID}"
                   },
                   "exposure" => "hidden",
                   "toolExposure" => %{"ping" => "direct", "admit_document" => "direct"}
                 }
               }
             }
    end

    test "Tool-Liste wird 1:1 abgebildet — jede Eingabe genau ein direct-Eintrag" do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-mcp"))
      tools = ["a", "b", "c"]
      exposure = Mediator.mcp_config_json(cfg, tools)["mcpServers"]["komki"]["toolExposure"]

      assert exposure == %{"a" => "direct", "b" => "direct", "c" => "direct"}

      # Leere Fassung: kein Tool frei, Server bleibt komplett hidden.
      assert Mediator.mcp_config_json(cfg, [])["mcpServers"]["komki"]["toolExposure"] == %{}
    end

    test "kein Token, keine URL, kein Auth-/Header-Feld in der Datei" do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-mcp"))
      Channel.write_token!(cfg)
      {:ok, token} = Channel.read_token(cfg)

      :ok = Mediator.write_mcp_config(cfg, ["ping"])
      raw = File.read!(Path.join([cfg.pi_home, ".pi", "agent", "mcp.json"]))
      refute raw =~ token

      komki = Mediator.mcp_config_json(cfg, ["ping"])["mcpServers"]["komki"]

      for key <- ["url", "headers", "auth", "bearerToken"],
          do: refute(Map.has_key?(komki, key))
    end
  end

  describe "write_mcp_config/2 (pi-Home-Schreibnaht)" do
    test "schreibt die erwartete Struktur unter pi-home/.pi/agent/mcp.json (idempotent)" do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-mediator"))
      tools = ["ping", "admit_document"]

      assert :ok = Mediator.write_mcp_config(cfg, tools)
      assert :ok = Mediator.write_mcp_config(cfg, tools)

      path = Path.join([cfg.pi_home, ".pi", "agent", "mcp.json"])
      assert JSON.decode!(File.read!(path)) == Mediator.mcp_config_json(cfg, tools)
    end
  end

  describe "spawn_line/1 (Spawn-Maschine, rein)" do
    test "enthält Binary, --base, --socket, --token-file, Log-Umleitung und pid-Ausgabe" do
      base = TestSupport.tmp_area!("komki-med-spawn")
      cfg = %{TestSupport.fixture_cfg(base) | mediator_bin: "/opt/bin/komki-mediator"}

      line = Mediator.spawn_line(cfg)

      # Ticket #137: Start unter dem eigenen Profil ueber die escript-Laufzeit,
      # Umgebung geleert, stdin /dev/null
      assert String.starts_with?(line, "nohup '/usr/bin/env' '-i' ")
      assert String.contains?(line, "'" <> cfg.sandbox_exec <> "' '-f' '")
      assert String.contains?(line, "/profile/mediator.sb' '")
      assert String.contains?(line, "'/opt/bin/komki-mediator'")
      # basis im Spawn-Kontext kernel-kanonisch (Pfadform-Cave, config.ex)
      assert String.contains?(line, "'--base' '" <> cfg.base_dir <> "'")
      assert String.contains?(line, "'--socket' '" <> Channel.socket_path(cfg) <> "'")
      assert String.contains?(line, "'--token-file' '" <> Channel.token_path(cfg) <> "'")
      assert String.contains?(line, "'--connectors-dir' '" <> cfg.base_dir <> "/run/connectors'")
      refute String.contains?(line, "--port")
      assert String.contains?(line, "< /dev/null > ")
      assert String.contains?(line, Path.join([base, "tmp", "mediator.log"]))
      assert String.ends_with?(line, "2>&1 & echo $!")
    end

    test "das Token selbst steht nie in der Spawn-Zeile" do
      cfg = %{
        TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-med-tok"))
        | mediator_bin: "/opt/bin/komki-mediator"
      }

      Channel.write_token!(cfg)
      {:ok, token} = Channel.read_token(cfg)
      refute Mediator.spawn_line(cfg) =~ token
    end

    test "Pfad-Injection-sicher: Quote im Binary-Namen wird escaped" do
      base = TestSupport.tmp_area!("komki-med-spawn-quote")

      cfg = %{TestSupport.fixture_cfg(base) | mediator_bin: "/weird/'path'/komki-mediator"}

      line = Mediator.spawn_line(cfg)
      assert String.contains?(line, "'/weird/'\\''path'\\''/komki-mediator'")
    end
  end

  describe "parse_healthz/1 (healthz-Body)" do
    test "vertraglicher Body: status ok + String-Tools-Liste wird uebernommen" do
      body =
        JSON.encode!(%{
          "status" => "ok",
          "fassung_id" => "f-1",
          "tools" => ["ping", "admit_document"],
          "registry_id" => "r-1",
          "gamma_hash" => "g-1"
        })

      assert {:ok, health} = Mediator.parse_healthz(body)
      assert health["tools"] == ["ping", "admit_document"]
      assert health["fassung_id"] == "f-1"
    end

    test "Vertrag verletzt: nicht-ok status, fehlende/ungültige tools, kaputtes JSON" do
      assert {:error, _} = Mediator.parse_healthz("kein json{")

      assert {:error, _} =
               Mediator.parse_healthz(
                 JSON.encode!(%{"status" => "degraded", "tools" => ["ping"]})
               )

      assert {:error, _} = Mediator.parse_healthz(JSON.encode!(%{"status" => "ok"}))

      assert {:error, _} =
               Mediator.parse_healthz(JSON.encode!(%{"status" => "ok", "tools" => "ping"}))

      assert {:error, _} =
               Mediator.parse_healthz(JSON.encode!(%{"status" => "ok", "tools" => [1, 2]}))
    end
  end

  describe "http_get/2 (echter Unix-Socket — Smoke-Regression, Tickets #102/#143)" do
    # Der erste reale up-Lauf starb in der recv-Schleife: der Akkumulator
    # wurde als Deadline weitergereicht (binary-Arithmetik) und der Body bei
    # Verbindungschluss weggeworfen. Dieser Test bedient healthz über einen
    # echten Unix-Socket-Listener und prueft zugleich die Anfrage-Header.

    test "liefert Status UND vollstaendigen Body, sendet Host und Bearer-Token" do
      body =
        JSON.encode!(%{
          "status" => "ok",
          "fassung_id" => "f-1",
          "tools" => ["ping"],
          "registry_id" => "r-1",
          "gamma_hash" => "g-1"
        })

      resp =
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n" <> body

      path = short_socket()
      {:ok, listen} = :gen_tcp.listen(0, [:binary, ifaddr: {:local, path}, active: false])

      server =
        Task.async(fn ->
          {:ok, sock} = :gen_tcp.accept(listen, 5_000)
          {:ok, req} = :gen_tcp.recv(sock, 0, 5_000)
          :ok = :gen_tcp.send(sock, resp)
          :ok = :gen_tcp.close(sock)
          req
        end)

      token = String.duplicate("ab", 32)
      assert {:ok, "200", got} = Mediator.http_get(path, token)
      assert got == body

      req = Task.await(server)
      assert String.starts_with?(req, "GET /healthz")
      assert req =~ "\r\nHost: localhost\r\n"
      assert req =~ "\r\nAuthorization: Bearer " <> token <> "\r\n"

      :gen_tcp.close(listen)
      File.rm(path)
    end

    test "kein Listener am Socket: strukturierter Fehler statt Crash" do
      assert {:error, _reason} = Mediator.http_get(short_socket(), String.duplicate("ab", 32))
    end
  end

  # macOS begrenzt Unix-Socket-Pfade auf 103 Byte; System.tmp_dir!/0 ist dort tief.
  defp short_socket do
    "/tmp/kct-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower) <> ".sock"
  end
end
