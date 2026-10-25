defmodule KomkiCli.SetupTest do
  @moduledoc """
  `komki setup` und seine Bausteine (Ticket #176): Werkzeug-Bericht,
  verdeckte Schluesselablage, eingebauter Test-Vault, Geheimnis-Liste.
  `security` wird nie fuer echte Eintraege aufgerufen; Fake-Skripte
  spielen es nach.
  """

  # async: false, weil store/3 ueber die Application-Env das Fake-Kommando
  # bekommt und andere Tests dieselbe Env lesen.
  use ExUnit.Case, async: false

  alias KomkiCli.{Config, DemoVault, Keychain, Secrets, Setup, TestSupport}

  @kanarie "kanarienwert-für-tests"

  defp fake!(body) do
    path = Path.join(TestSupport.tmp_area!("komki-setup"), "security")
    File.write!(path, "#!/bin/sh\n" <> body <> "\n")
    File.chmod!(path, 0o755)
    path
  end

  # Fake fuer add-generic-password: liest wie security(1) zwei Zeilen von
  # stdin und schreibt argv und Eingaben zur Kontrolle in Dateien.
  defp recording_fake! do
    dir = TestSupport.tmp_area!("komki-setup-rec")

    cmd =
      fake!("""
      read a; read b
      printf '%s\\n' "$*" > "#{dir}/args"
      printf '%s|%s' "$a" "$b" > "#{dir}/stdin"
      """)

    {cmd, dir}
  end

  defp ui(secrets) do
    {:ok, agent} = Agent.start_link(fn -> secrets end)

    %{
      secret: fn _question ->
        Agent.get_and_update(agent, fn [next | rest] -> {next, rest} end)
      end
    }
  end

  describe "Keychain.store/3" do
    test "Wert geht nur über stdin, zweimal; argv enthält ihn nie" do
      {cmd, dir} = recording_fake!()

      assert :ok = Keychain.store("brave-search-api", @kanarie, command: cmd, account: "tester")

      args = File.read!(Path.join(dir, "args"))
      assert args =~ "add-generic-password -s brave-search-api -a tester -U -w"
      refute args =~ @kanarie
      assert File.read!(Path.join(dir, "stdin")) == @kanarie <> "|" <> @kanarie
    end

    test "leere Werte und Zeilenumbrueche werden abgelehnt, ohne security zu rufen" do
      cmd = fake!("exit 9")
      assert {:error, :invalid} = Keychain.store("x", "", command: cmd)
      assert {:error, :invalid} = Keychain.store("x", "a\nb", command: cmd)
    end

    test "Fehler von security wird {:failed, code}" do
      assert {:error, {:failed, 51}} =
               Keychain.store("x", "wert", command: fake!("read a; exit 51"))
    end
  end

  describe "Setup.store_secret/2" do
    setup do
      previous = Application.get_env(:komki_cli, :security)
      on_exit(fn -> Application.put_env(:komki_cli, :security, previous) end)
      :ok
    end

    @entry %{name: "brave", service: "brave-search-api", connector: "web", label: "Brave"}

    test "zwei gleiche Eingaben werden gespeichert; die Meldung nennt den Wert nicht" do
      {cmd, dir} = recording_fake!()
      Application.put_env(:komki_cli, :security, cmd)

      message = Setup.store_secret(@entry, ui([{:ok, @kanarie}, {:ok, @kanarie}]))

      assert message =~ "gespeichert"
      refute message =~ @kanarie
      assert File.read!(Path.join(dir, "stdin")) == @kanarie <> "|" <> @kanarie
    end

    test "verschiedene Eingaben: nichts gespeichert" do
      Application.put_env(:komki_cli, :security, fake!("exit 9"))
      message = Setup.store_secret(@entry, ui([{:ok, "a"}, {:ok, "b"}]))
      assert message =~ "stimmen nicht überein"
      refute message =~ "a\""
    end

    test "ohne Terminal: Hinweis auf 'komki secret set'" do
      message = Setup.store_secret(@entry, ui([{:error, :no_tty}]))
      assert message =~ "komki secret set brave"
    end

    test "leere Eingabe: nichts gespeichert" do
      assert Setup.store_secret(@entry, ui([{:error, :empty}])) =~ "leere Eingabe"
    end
  end

  describe "Setup.tool_report/2" do
    test "fehlende Werkzeuge kommen mit Installationshinweis" do
      cfg = %{
        Config.defaults(TestSupport.tmp_area!("komki-setup-cfg"))
        | llama_server_bin: nil,
          cli_js: nil,
          mediator_bin: nil
      }

      %{required: required, tmux: nil} = Setup.tool_report(cfg, nil)
      missing = for {name, nil, hint} <- required, into: %{}, do: {name, hint}

      assert missing["llama-server"] =~ "brew install llama.cpp"
      assert missing["pi"] =~ "pnpm add -g @earendil-works/pi-coding-agent"
      assert missing["komki-mediator"] =~ "make komki"
    end
  end

  describe "DemoVault" do
    test "legt alle Notizen an, auch die versteckte Probe-Notiz" do
      dir = Path.join(TestSupport.tmp_area!("komki-demo"), "vault")

      assert {:ok, count} = DemoVault.install(dir)
      assert count == DemoVault.count()
      assert File.exists?(Path.join(dir, "Projekte/Verkehr/Radverkehrskonzept.md"))
      assert File.exists?(Path.join(dir, ".obsidian/Versteckte Notiz.md"))
    end

    test "ueberschreibt nie einen vorhandenen Vault" do
      dir = TestSupport.tmp_area!("komki-demo-voll")
      File.write!(Path.join(dir, "eigene.md"), "meins")

      assert {:error, reason} = DemoVault.install(dir)
      assert reason =~ "nicht leer"
      assert File.read!(Path.join(dir, "eigene.md")) == "meins"
    end
  end

  describe "Secrets" do
    test "der Brave-Key kommt aus dem Web-Manifest und heisst kurz 'brave'" do
      assert [%{name: "brave", service: "brave-search-api", connector: "web"}] = Secrets.all()
      assert {:ok, %{name: "brave"}} = Secrets.fetch("brave-search-api")
      assert :error = Secrets.fetch("unbekannt")
    end
  end
end
