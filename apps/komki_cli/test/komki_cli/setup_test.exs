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

  # Fake-Schluesselbund: `-i` liest eine Befehlszeile von stdin (wie
  # security(1) im interaktiven Modus) und merkt sich argv, Zeile und Wert;
  # `find-generic-password -w` liefert den gemerkten Wert.
  defp recording_fake! do
    dir = TestSupport.tmp_area!("komki-setup-rec")

    cmd =
      fake!("""
      case "$1" in
        -i) read -r line; printf '%s\\n' "$*" > "#{dir}/args"; printf '%s' "$line" > "#{dir}/stdin"
            printf '%s' "${line##* }" > "#{dir}/value" ;;
        find-generic-password) [ "$4" = "-w" ] && cat "#{dir}/value" || exit 44 ;;
      esac
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
    test "Wert geht nur über stdin an security -i, nie über argv; ganz, auch über 128 Byte" do
      {cmd, dir} = recording_fake!()
      siegel = "ktv1." <> String.duplicate("A", 1000) <> "+/="

      assert :ok = Keychain.store("brave-search-api", siegel, command: cmd, account: "tester")

      assert File.read!(Path.join(dir, "args")) == "-i\n"

      assert File.read!(Path.join(dir, "stdin")) ==
               "add-generic-password -s brave-search-api -a tester -U -w " <> siegel
    end

    test "leere Werte und Sonderzeichen werden abgelehnt, ohne security zu rufen" do
      cmd = fake!("touch $0.lief; exit 9")

      for value <- ["", "a\nb", "a b", "a;b", "a\"b", @kanarie] do
        assert {:error, :invalid} = Keychain.store("x", value, command: cmd, account: "t")
      end

      refute File.exists?(cmd <> ".lief")
    end

    test "gekuerzter Wert nach dem Schreiben ist ein Fehler" do
      dir = TestSupport.tmp_area!("komki-kurz")

      cmd =
        fake!("""
        case "$1" in
          -i) read -r line ;;
          find-generic-password) echo gekuerzt ;;
        esac
        """)

      _ = dir
      assert {:error, :not_stored} = Keychain.store("x", "ktv1.lang", command: cmd, account: "t")
    end

    test "Fehler von security wird {:failed, code}" do
      assert {:error, {:failed, 51}} =
               Keychain.store("x", "wert", command: fake!("read a; exit 51"), account: "t")
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

      assert message =~ "versiegelt"
      refute message =~ @kanarie
      # In den Schluesselbund geht nur das Siegel, nie der Klartext.
      {:ok, sealed} = KomkiCli.Tresor.seal(@kanarie)
      assert File.read!(Path.join(dir, "value")) == sealed
      refute File.read!(Path.join(dir, "stdin")) =~ @kanarie
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
