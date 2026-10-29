defmodule KomkiCli.ConnectorProfileTest do
  @moduledoc """
  Golden- und Regeltests der generierten Profile (Ticket #146/#137):
  connector-{ris,web,vault}.sb, egress.sb, mediator.sb. Die Fixtur nutzt
  nicht existierende, feste Pfade (`/opt/komki-golden`, `/opt/erl`) — der
  Text haengt damit nicht vom Host ab (keine crypto-dylibs gefunden).

  Golden-Dateien neu schreiben: `KOMKI_UPDATE_GOLDEN=1 mix test <diese Datei>`.
  """

  use ExUnit.Case, async: true

  alias KomkiCli.{Config, ConnectorProfile, MediatorProfile}
  alias KomkiConnector.Manifest

  @golden Path.expand("../fixtures/profiles", __DIR__)
  @base "/opt/komki-golden"

  defp cfg(overrides \\ []) do
    base = %{
      Config.defaults(@base)
      | base_dir: @base,
        profile_path: @base <> "/profile/komki.sb",
        escript_bin: "/opt/erl/bin/escript",
        egress_bin: "/opt/komki/bin/komki-egress",
        mediator_bin: "/opt/komki/bin/komki-mediator",
        connector_bins: %{
          "ris" => "/opt/komki/bin/komki-connector-ris",
          "web" => "/opt/komki/bin/komki-connector-web",
          "vault" => "/opt/komki/bin/komki-connector-vault",
          "documents" => "/opt/komki/bin/komki-connector-documents"
        },
        egress_ports: %{"ris" => 49_531, "web" => 49_532},
        ris_mock_port: nil,
        vault_dir: @base <> "/vault"
    }

    struct!(base, overrides)
  end

  defp profiles(cfg) do
    connectors =
      Map.new(
        Manifest.all(),
        &{"connector-" <> &1.id <> ".sb", ConnectorProfile.connector(cfg, &1)}
      )

    Map.merge(connectors, %{
      "egress.sb" => ConnectorProfile.egress(cfg),
      "mediator.sb" => MediatorProfile.generate(cfg, {:tcp, 49_525}),
      "mediator-unix.sb" =>
        MediatorProfile.generate(cfg, {:unix, MediatorProfile.socket_path(cfg)})
    })
  end

  defp lines(text), do: String.split(text, "\n", trim: true)

  defp rules_with(text, needle), do: Enum.filter(lines(text), &String.contains?(&1, needle))

  describe "Golden (byte-genau)" do
    test "alle Profile stimmen mit den Golden-Dateien überein" do
      for {name, text} <- profiles(cfg()) do
        path = Path.join(@golden, name)

        if System.get_env("KOMKI_UPDATE_GOLDEN") do
          File.mkdir_p!(@golden)
          File.write!(path, text)
        end

        assert File.read!(path) == text, "Golden-Abweichung: " <> name
      end
    end

    test "Determinismus: zweimal generiert ist byte-identisch" do
      assert profiles(cfg()) == profiles(cfg())
    end
  end

  describe "gemeinsame Garantien" do
    test "deny default, nie allow default, kein Home, kein ~/.ssh" do
      home = System.user_home!()

      for {name, text} <- profiles(cfg()) do
        assert "(deny default)" in lines(text), name
        refute text =~ "(allow default)", name
        refute text =~ ".ssh", name
        refute text =~ "(subpath \"" <> home <> "\")", name
        refute text =~ "(allow network*)", name
        refute text =~ "process-exec (subpath \"/\")", name
      end
    end
  end

  describe "Connector-Profile" do
    test "Proxy-Connectoren: genau ein Outbound, localhost:<egress-port>" do
      text = ConnectorProfile.connector(cfg(), Manifest.fetch!("web"))

      assert rules_with(text, "(allow network-outbound") == [
               "(allow network-outbound (remote tcp \"localhost:49532\"))"
             ]

      refute text =~ "*:443"
      assert text =~ "(path-literal \"/opt/komki-golden/run/connectors/web.sock\")"
      assert text =~ "(literal \"/opt/komki-golden/tmp/connector-web.log\")"
    end

    test "RIS-Mock: direkter Mock-Port statt Proxy-Port" do
      text = ConnectorProfile.connector(cfg(ris_mock_port: 4010), Manifest.fetch!("ris"))

      assert rules_with(text, "(allow network-outbound") == [
               "(allow network-outbound (remote tcp \"localhost:4010\"))"
             ]

      refute text =~ "49531"
    end

    test "Vault: kein Netz, {vault_dir} lesen, komki-test schreiben, sonst nichts schreiben" do
      text = ConnectorProfile.connector(cfg(), Manifest.fetch!("vault"))

      assert rules_with(text, "network-outbound") == []
      assert text =~ "(allow file-read* (subpath \"/opt/komki-golden/vault\"))"

      assert text =~
               "(allow file-read* file-write* (subpath \"/opt/komki-golden/vault/komki-test\"))"

      writes = text |> rules_with("file-write") |> Enum.reject(&String.starts_with?(&1, ";"))

      assert writes == [
               "(allow file-write* (literal \"/dev/null\"))",
               "(allow file-read* file-test-existence file-write-data file-ioctl (literal \"/dev/dtracehelper\"))",
               "(allow file-read* file-write* (literal \"/opt/komki-golden/tmp/connector-vault.log\"))",
               "(allow file-read* file-write* (literal \"/opt/komki-golden/run/connectors/vault.sock\"))",
               "(allow file-read* file-write* (subpath \"/opt/komki-golden/vault/komki-test\"))"
             ]
    end

    test "Vault abgeschaltet: Generierung scheitert klar" do
      assert_raise ArgumentError, ~r/vault_dir/, fn ->
        ConnectorProfile.connector(cfg(vault_dir: nil), Manifest.fetch!("vault"))
      end
    end

    # vault_dir kommt aus der config.json: ein Anfuehrungszeichen darf das
    # Literal nicht schliessen und eine eigene Regel anhaengen.
    test "Vault-Pfad mit Anfuehrungszeichen: Generierung scheitert statt Regel-Injection" do
      assert_raise ArgumentError, ~r/unsafe SBPL string/, fn ->
        ConnectorProfile.connector(
          cfg(vault_dir: ~s{/opt/v")) (allow default}),
          Manifest.fetch!("vault")
        )
      end
    end
  end

  describe "Egress-Profil" do
    test "*:443 plus DNS, bind genau auf die Egress-Ports, keine Dateien außer Log" do
      text = ConnectorProfile.egress(cfg())

      assert "(allow network-outbound (remote tcp \"*:443\"))" in lines(text)
      assert text =~ "/private/var/run/mDNSResponder"

      assert rules_with(text, "network-bind") == [
               "(allow network-bind (local ip \"localhost:49531\"))",
               "(allow network-bind (local ip \"localhost:49532\"))"
             ]

      writes = text |> rules_with("file-write") |> Enum.reject(&String.starts_with?(&1, ";"))
      assert Enum.all?(writes, &(&1 =~ "/dev/" or &1 =~ "/tmp/egress.log"))
    end

    test "RIS-Mock: Egress bindet nur noch den Web-Port" do
      text = ConnectorProfile.egress(cfg(ris_mock_port: 4010))

      assert rules_with(text, "network-bind") == [
               "(allow network-bind (local ip \"localhost:49532\"))"
             ]
    end
  end

  describe "Vermittler-Profil (#137)" do
    test "kein Outbound außer den Connector-Sockets" do
      text = MediatorProfile.generate(cfg(), {:tcp, 49_525})

      outbound = rules_with(text, "(allow network-outbound")

      assert outbound ==
               Enum.map(["documents", "ris", "vault", "web"], fn id ->
                 "(allow network-outbound (remote unix-socket (path-literal \"/opt/komki-golden/run/connectors/" <>
                   id <> ".sock\")))"
               end)

      refute text =~ "remote tcp"
      assert "(allow network-bind (local ip \"localhost:49525\"))" in lines(text)
    end

    test "Schreiben nur Journal, Erstprovisionierung, GO-Anfragen und Log" do
      text = MediatorProfile.generate(cfg(), {:tcp, 49_525})

      writes =
        text
        |> rules_with("file-write")
        |> Enum.reject(&(String.starts_with?(&1, ";") or &1 =~ "/dev/"))

      assert writes == [
               "(allow file-read* file-write* (literal \"/opt/komki-golden/tmp/mediator.log\"))",
               "(allow file-write* (subpath \"/opt/komki-golden/mediator/journal\"))",
               "(allow file-write* (literal \"/opt/komki-golden/mediator\") (literal \"/opt/komki-golden/mediator/registry.json\") (literal \"/opt/komki-golden/mediator/room.json\"))",
               "(allow file-write* (subpath \"/opt/komki-golden/mediator/documents\"))",
               "(allow file-write* (subpath \"/opt/komki-golden/mediator/go\"))"
             ]
    end

    test "Unix-Socket des Vermittlers (#143): Socket binden, Token lesen, kein TCP-Bind" do
      cfg = cfg()
      text = MediatorProfile.generate(cfg, {:unix, MediatorProfile.socket_path(cfg)})

      assert text =~
               "(allow network-bind (local unix-socket (path-literal \"/opt/komki-golden/run/mediator.sock\")))"

      assert text =~ "(allow file-read* (literal \"/opt/komki-golden/run/mediator.token\"))"
      refute text =~ "local ip"
    end
  end
end
