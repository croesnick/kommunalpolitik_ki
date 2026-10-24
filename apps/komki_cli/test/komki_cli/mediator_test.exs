defmodule KomkiCli.MediatorTest do
  @moduledoc """
  Hermetische Unit-Tests der Vermittler-Vertragsnaehe (Ticket #102):
  mcp.json-Aufbau, Spawn-Zeile, healthz-Body-Parsen und vollstaendige
  write_mcp_config. Kein echter Prozess wird gespawnt — der Lifecycle
  (up/down/status) ist wie Llama.up-Laeufe nicht in der Suite (echte
  Binaries, echte Ports).
  """

  use ExUnit.Case, async: true

  alias KomkiCli.{Mediator, TestSupport}

  describe "mcp_config_json/2 (Fassung-Pin auf pi-Seite)" do
    test "Struktur: Server komki, url aus Port, exposure hidden, Fassung-Tools direct" do
      mcp = Mediator.mcp_config_json(49_525, ["ping", "admit_document"])

      # Exakte Gleichheit: keine Extra-Keys, keine zusaetzlichen Server.
      assert mcp == %{
               "mcpServers" => %{
                 "komki" => %{
                   "url" => "http://127.0.0.1:49525/mcp",
                   "exposure" => "hidden",
                   "toolExposure" => %{"ping" => "direct", "admit_document" => "direct"}
                 }
               }
             }
    end

    test "Tool-Liste wird 1:1 abgebildet — jede Eingabe genau ein direct-Eintrag" do
      tools = ["a", "b", "c"]
      exposure = Mediator.mcp_config_json(50_000, tools)["mcpServers"]["komki"]["toolExposure"]

      assert exposure == %{"a" => "direct", "b" => "direct", "c" => "direct"}
      assert Map.keys(exposure) == tools

      # Leere Fassung: kein Tool frei, Server bleibt komplett hidden.
      assert Mediator.mcp_config_json(50_000, [])["mcpServers"]["komki"]["toolExposure"] == %{}
    end

    test "kein Auth-/Header-Feld im Output (Zugangsdaten nur im Vermittler-Prozess)" do
      komki = Mediator.mcp_config_json(49_525, ["ping"])["mcpServers"]["komki"]

      refute Map.has_key?(komki, "headers")
      refute Map.has_key?(komki, "auth")
      refute Map.has_key?(komki, "bearerToken")
    end
  end

  describe "write_mcp_config/2 (pi-Home-Schreibnaht)" do
    test "schreibt die erwartete Struktur unter pi-home/.pi/agent/mcp.json (idempotent)" do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-mediator"))
      tools = ["ping", "admit_document"]

      assert :ok = Mediator.write_mcp_config(cfg, tools)
      assert :ok = Mediator.write_mcp_config(cfg, tools)

      path = Path.join([cfg.pi_home, ".pi", "agent", "mcp.json"])
      assert File.exists?(path)

      assert JSON.decode!(File.read!(path)) ==
               Mediator.mcp_config_json(cfg.mediator_port, tools)
    end
  end

  describe "spawn_line/1 (Spawn-Maschine, rein)" do
    test "enthaelt Binary, --base, --port, Log-Umleitung und pid-Ausgabe" do
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
      assert String.contains?(line, "'--port' '" <> to_string(cfg.mediator_port) <> "'")
      assert String.contains?(line, "'--connectors-dir' '" <> cfg.base_dir <> "/run/connectors'")
      assert String.contains?(line, "< /dev/null > ")
      assert String.contains?(line, Path.join([base, "tmp", "mediator.log"]))
      assert String.ends_with?(line, "2>&1 & echo $!")
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

    test "Vertrag verletzt: nicht-ok status, fehlende/ungueltige tools, kaputtes JSON" do
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

  describe "http_get/1 (echter Loopback-Socket — Smoke-Regression, Ticket #102)" do
    # Der erste reale up-Lauf starb in der recv-Schleife: der Akkumulator
    # wurde als Deadline weitergereicht (binary-Arithmetik) und der Body bei
    # Verbindungschluss weggeworfen. Dieser Test bedient healthz über einen
    # echten Loopback-Listener — ohne echten Socket ware der Fehler
    # unentdeckt geblieben (reine Funktionstests greifen nicht bis hierher).

    test "liefert Status UND vollstaendigen Body ueber die recv-Schleife" do
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

      {:ok, listen} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false, backlog: 1])
      {:ok, port} = :inet.port(listen)

      server =
        Task.async(fn ->
          {:ok, sock} = :gen_tcp.accept(listen, 5_000)
          {:ok, req} = :gen_tcp.recv(sock, 0, 5_000)
          :ok = :gen_tcp.send(sock, resp)
          :ok = :gen_tcp.close(sock)
          req
        end)

      assert {:ok, "200", got} = Mediator.http_get(port)
      assert got == body

      req = Task.await(server)
      assert String.starts_with?(req, "GET /healthz")

      :gen_tcp.close(listen)
    end

    test "kein Listener am Port: strukturierter Fehler statt Crash" do
      # Port ohne Dienst: connect schlaegt fehl (kein rueckweisungsfreier
      # Ephemeral-Port garantiert — der Fehlerfall ist der erwartete).
      assert {:error, _reason} = Mediator.http_get(1)
    end
  end
end
