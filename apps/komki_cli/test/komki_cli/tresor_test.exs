defmodule KomkiCli.TresorTest do
  @moduledoc """
  Tresor und versiegelte Geheimnisse mit Fake-Programmen: die echte Secure
  Enclave (Touch ID) und der echte Schluesselbund werden nie gefragt.
  """

  use ExUnit.Case, async: true

  alias KomkiCli.{Secrets, TestSupport, Tresor}

  @kanarie "kanarienwert-für-tests"
  @entry %{name: "brave", service: "brave-search-api", connector: "web", label: "Brave"}

  defp script!(name, body) do
    path = Path.join(TestSupport.tmp_area!("komki-tresor"), name)
    File.write!(path, "#!/bin/sh\n" <> body <> "\n")
    File.chmod!(path, 0o755)
    path
  end

  # Schluesselbund-Fake, der `value` liefert und jeden Aufruf mitschreibt.
  defp keychain!(value) do
    dir = TestSupport.tmp_area!("komki-kc")
    path = Path.join(dir, "security")

    File.write!(path, """
    #!/bin/sh
    echo "$1" >> #{dir}/calls
    [ -f #{dir}/stored ] || printf '%s' '#{value}' > #{dir}/stored
    case "$1" in
      find-generic-password) cat #{dir}/stored; echo ;;
      -i) read -r line; printf '%s' "${line##* }" > #{dir}/stored ;;
    esac
    """)

    File.chmod!(path, 0o755)
    {path, dir}
  end

  describe "Tresor" do
    test "seal und open: Rundweg, Siegel traegt das Praefix und nicht den Klartext" do
      assert {:ok, sealed} = Tresor.seal(@kanarie)
      assert Tresor.sealed?(sealed)
      refute sealed =~ @kanarie
      assert {:ok, @kanarie} = Tresor.open(sealed, "Test")
    end

    test "Exit-Codes werden zu Gruenden" do
      for {code, error} <- [{3, :no_enclave}, {4, :refused}, {5, :invalid}, {9, {:failed, 9}}] do
        cmd = script!("tresor", "read -r v; exit #{code}")
        assert {:error, ^error} = Tresor.open("ktv1.x", "Test", command: cmd)
      end
    end

    test "Klartext wird nicht als Siegel geoeffnet, das Programm laeuft nicht" do
      cmd = script!("tresor", "touch $0.lief; exit 0")
      assert {:error, :invalid} = Tresor.open(@kanarie, "Test", command: cmd)
      refute File.exists?(cmd <> ".lief")
    end

    test "Klartext und Grund gehen nie ueber argv" do
      dir = TestSupport.tmp_area!("komki-tresor-argv")
      cmd = script!("tresor", ~s(echo "$@" > #{dir}/argv; read -r v; echo ktv1.x))
      assert {:ok, _} = Tresor.seal(@kanarie, command: cmd)
      assert File.read!(Path.join(dir, "argv")) == "seal\n"
    end

    test "Timeout beendet das Programm (keine Freigabe)" do
      cmd = script!("tresor", "exec sleep 30")
      assert {:error, :timeout} = Tresor.open("ktv1.x", "Test", command: cmd, timeout: 300)
    end

    test "leere oder mehrzeilige Werte werden nicht versiegelt" do
      assert {:error, :invalid} = Tresor.seal("")
      assert {:error, :invalid} = Tresor.seal("a\nb")
    end
  end

  describe "Secrets" do
    test "reveal oeffnet ein Siegel aus dem Schluesselbund" do
      {:ok, sealed} = Tresor.seal(@kanarie)
      {cmd, _dir} = keychain!(sealed)
      assert {:ok, @kanarie} = Secrets.reveal("brave-search-api", command_kc(cmd))
    end

    test "reveal benutzt keinen Klartext-Eintrag" do
      {cmd, _dir} = keychain!(@kanarie)
      assert {:error, :unsealed} = Secrets.reveal("brave-search-api", command_kc(cmd))
    end

    test "gekuerztes Siegel ist beschaedigt, nicht versiegelt" do
      {:ok, sealed} = Tresor.seal(@kanarie)
      {kc, _} = keychain!(String.slice(sealed, 0, 40))
      assert Secrets.state(@entry, command: kc) == :damaged
      refute Tresor.well_formed?(String.slice(sealed, 0, 40))
    end

    test "state unterscheidet versiegelt, Klartext und fehlend" do
      {:ok, sealed} = Tresor.seal(@kanarie)
      {kc_sealed, _} = keychain!(sealed)
      {kc_plain, _} = keychain!(@kanarie)

      assert Secrets.state(@entry, command: kc_sealed) == :sealed
      assert Secrets.state(@entry, command: kc_plain) == :unsealed
      assert {:error, :missing} = Secrets.state(@entry, command: script!("security", "exit 44"))
    end

    test "seal_existing ersetzt den Klartext durch das Siegel" do
      {cmd, dir} = keychain!(@kanarie)
      assert :ok = Secrets.seal_existing(@entry, command: cmd)
      stored = File.read!(Path.join(dir, "stored"))
      assert Tresor.sealed?(stored)
      refute stored =~ @kanarie
    end

    test "describe nennt nie einen Wert" do
      for error <- [:unsealed, {:tresor, :refused}, {:tresor, :no_enclave}, :missing] do
        text = Secrets.describe("brave-search-api", error)
        assert text =~ "brave-search-api"
        refute text =~ @kanarie
      end
    end
  end

  # `command` gilt fuer den Schluesselbund; der Tresor kommt aus der
  # Application-Env (Fake aus test_helper.exs).
  defp command_kc(cmd), do: [command: cmd]
end
