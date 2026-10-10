defmodule KomkiCli.StepsTest do
  # write_pi_home ist die Testnaeht fuer alles, was komki dem pi-home
  # vorgibt: Provider-Modelle, Settings-Global und der Trust-Store. Der
  # Trust-Schluessel ist die Instanz-Wurzel — pi's Trust-Suche laeuft vom
  # Session-cwd (die Arbeitsflaeche) die Elternkette hoch und muss dort
  # wie auch vom pi-home aus faendig werden.
  use ExUnit.Case, async: true

  alias KomkiCli.{Config, Steps, TestSupport}

  describe "write_pi_home/1" do
    test "Trust-Schluessel ist die Instanz-Wurzel (deckt arbeit und pi-home ab)" do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-steps"))

      Steps.write_pi_home(cfg)

      trust = cfg.pi_home |> Path.join(".pi/agent/trust.json") |> read_json()
      assert trust == %{Config.canonical(cfg.base_dir) => true}
    end

    test "Thinking per Default eingeklappt (hideThinkingBlock)" do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-steps"))

      Steps.write_pi_home(cfg)

      settings = cfg.pi_home |> Path.join(".pi/agent/settings.json") |> read_json()
      assert settings == %{"hideThinkingBlock" => true}
    end

    test "models.json zeigt auf den lokalen llama-Server" do
      cfg = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-steps"))

      Steps.write_pi_home(cfg)

      models = cfg.pi_home |> Path.join(".pi/agent/models.json") |> read_json()

      assert %{
               "providers" => %{
                 "pi-local" => %{
                   "baseUrl" => "http://127.0.0.1:" <> _,
                   "models" => [%{"id" => "local-model"}]
                 }
               }
             } = models
    end

    test "fd/rg landen als Kopien im agent-bin-Fundus (nil-tolerant)" do
      base = TestSupport.tmp_area!("komki-steps-tools")
      cfg = TestSupport.fixture_cfg(base)

      src_fd = Path.join(base, "fd-src")
      src_rg = Path.join(base, "rg-src")
      File.write!(src_fd, "fd-dummy")
      File.write!(src_rg, "rg-dummy")

      Steps.write_pi_home(%{cfg | fd_bin: src_fd, rg_bin: src_rg})

      bin = Path.join([cfg.pi_home, ".pi", "agent", "bin"])
      assert File.read!(Path.join(bin, "fd")) == "fd-dummy"
      assert File.read!(Path.join(bin, "rg")) == "rg-dummy"

      # Ueberschreiben trotz write-geschuetzter Altkopie (echte Binaries
      # behalten 555): init --force muss weiterhin funktionieren.
      File.chmod!(Path.join(bin, "fd"), 0o555)
      File.write!(src_fd, "fd-dummy-2")

      Steps.write_pi_home(%{cfg | fd_bin: src_fd, rg_bin: src_rg})

      assert File.read!(Path.join(bin, "fd")) == "fd-dummy-2"

      bare = TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-steps-bare"))
      Steps.write_pi_home(%{bare | fd_bin: nil, rg_bin: nil})

      refute File.exists?(Path.join([bare.pi_home, ".pi", "agent", "bin", "fd"]))
    end
  end

  defp read_json(path), do: path |> File.read!() |> JSON.decode!()
end
