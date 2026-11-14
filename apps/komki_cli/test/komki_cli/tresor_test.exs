defmodule KomkiCli.TresorTest do
  @moduledoc """
  Tresor und versiegelte Geheimnisse mit injizierter Schluesselvereinbarung und
  Fake-Programmen: die echte Secure Enclave (Touch ID) und der echte
  Schluesselbund werden nie gefragt.
  """

  use ExUnit.Case, async: true

  alias KomkiCli.{Secrets, TestSupport, Tresor}
  alias KomkiCli.Tresor.Core
  alias SealedEnvelope.KeyAgreement.FileTestDouble

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

  # Wrapper around the fake program: records argv and stdin of every call.
  defp recording_tresor! do
    dir = TestSupport.tmp_area!("komki-tresor-rec")
    fake = Application.fetch_env!(:komki_cli, :tresor)

    cmd =
      script!("tresor", """
      echo "$@" >> #{dir}/argv
      if [ "$1" = agree ]; then
        read -r line; echo "$line" >> #{dir}/stdin
        printf '%s\\n' "$line" | #{fake} "$@"
      else
        exec #{fake} "$@"
      fi
      """)

    {cmd, dir}
  end

  defp provider!, do: {FileTestDouble, path: Path.join(TestSupport.tmp_area!("komki-key"), "key")}

  defmodule Refusing do
    @moduledoc "Provider that hands out a real key but always answers with `opts[:error]`."
    @behaviour SealedEnvelope.KeyAgreement

    @impl true
    def recipient(opts), do: FileTestDouble.recipient(opts)

    @impl true
    def agree(_key_ref, _peer, opts), do: {:error, Keyword.fetch!(opts, :error)}
  end

  describe "Tresor mit injizierter Schluesselvereinbarung" do
    test "bauen und oeffnen: Rundweg im Format ktv2, ohne den Klartext im Siegel" do
      provider = provider!()

      assert {:ok, sealed} = Core.seal(@kanarie, provider: provider)
      assert String.starts_with?(sealed, "ktv2.")
      assert Core.sealed?(sealed) and Core.well_formed?(sealed)
      refute sealed =~ @kanarie
      assert {:ok, @kanarie} = Core.open(sealed, "Test", provider: provider)
    end

    test "fremder Schluessel und verfaelschtes Siegel sind ungueltig" do
      provider = provider!()
      {:ok, sealed} = Core.seal(@kanarie, provider: provider)

      assert {:error, :invalid} = Core.open(sealed, "Test", provider: provider!())
      assert {:error, :invalid} = Core.open(sealed <> "x", "Test", provider: provider)
      assert {:error, :invalid} = Core.open("ktv2.kaputt", "Test", provider: provider)
    end

    test "Fehler der Schluesselvereinbarung kommen als Grund an" do
      {_, opts} = provider = provider!()
      {:ok, sealed} = Core.seal(@kanarie, provider: provider)

      for error <- [:refused, :no_enclave, :timeout, :missing_bin, {:failed, 9}] do
        refusing = {Refusing, [error: error] ++ opts}
        assert {:error, ^error} = Core.open(sealed, "Test", provider: refusing)
      end

      unknown = {Refusing, [error: :enoent] ++ opts}
      assert {:error, :invalid} = Core.open(sealed, "Test", provider: unknown)
    end

    test "ktv1 wird abgelehnt, ohne die Schluesselvereinbarung zu fragen" do
      refusing = {Refusing, error: :darf_nicht_gefragt_werden}

      assert Core.outdated?("ktv1.abc")
      refute Core.sealed?("ktv1.abc")
      assert {:error, :outdated} = Core.open("ktv1.abc", "Test", provider: refusing)
      assert Core.describe(:outdated) =~ "ktv1"
    end

    test "leere oder mehrzeilige Werte werden nicht versiegelt" do
      assert {:error, :invalid} = Core.seal("", provider: provider!())
      assert {:error, :invalid} = Core.seal("a\nb", provider: provider!())
    end
  end

  describe "Tresor ueber das Programm" do
    test "seal und open: Rundweg ueber das Programm-Protokoll" do
      assert {:ok, sealed} = Tresor.seal(@kanarie)
      assert Tresor.sealed?(sealed)
      refute sealed =~ @kanarie
      assert {:ok, @kanarie} = Tresor.open(sealed, "Test")
    end

    test "Klartext und Siegel erreichen das Programm nicht, der Grund geht ueber argv" do
      {cmd, dir} = recording_tresor!()

      assert {:ok, sealed} = Tresor.seal(@kanarie, command: cmd)
      assert {:ok, @kanarie} = Tresor.open(sealed, "Der Grund", command: cmd)

      argv = File.read!(Path.join(dir, "argv"))
      stdin = File.read!(Path.join(dir, "stdin"))
      assert argv == "recipient\nagree --reason Der Grund\n"

      for seen <- [argv, stdin] do
        refute seen =~ @kanarie
        refute seen =~ sealed
      end

      # Genau eine Schluesselvereinbarung: eine Rueckfrage je Oeffnen.
      assert [_one_line] = String.split(stdin, "\n", trim: true)
    end

    test "Exit-Codes werden zu Gruenden" do
      {:ok, sealed} = Tresor.seal(@kanarie)

      for {code, error} <- [{3, :no_enclave}, {4, :refused}, {5, :invalid}, {9, {:failed, 9}}] do
        cmd = script!("tresor", "read -r v; exit #{code}")
        assert {:error, ^error} = Tresor.open(sealed, "Test", command: cmd)
      end

      cmd = script!("tresor", "exit 3")
      assert {:error, :no_enclave} = Tresor.seal(@kanarie, command: cmd)
    end

    test "unbrauchbare Antworten des Programms sind ungueltig" do
      {:ok, sealed} = Tresor.seal(@kanarie)

      for out <- ["kein-base64!", Base.encode64("zu kurz")] do
        cmd = script!("tresor", "read -r v; echo '#{out}'")
        assert {:error, :invalid} = Tresor.open(sealed, "Test", command: cmd)
      end

      assert {:error, :invalid} = Tresor.seal(@kanarie, command: script!("tresor", "echo kaputt"))
    end

    test "Klartext wird nicht als Siegel geoeffnet, das Programm laeuft nicht" do
      cmd = script!("tresor", "touch $0.lief; exit 0")
      assert {:error, :invalid} = Tresor.open(@kanarie, "Test", command: cmd)
      refute File.exists?(cmd <> ".lief")
    end

    test "ktv1 wird abgelehnt, das Programm laeuft nicht" do
      cmd = script!("tresor", "touch $0.lief; exit 0")
      assert {:error, :outdated} = Tresor.open("ktv1.abc", "Test", command: cmd)
      refute File.exists?(cmd <> ".lief")
    end

    test "Timeout beendet das Programm (keine Freigabe)" do
      {:ok, sealed} = Tresor.seal(@kanarie)
      cmd = script!("tresor", "exec sleep 30")
      assert {:error, :timeout} = Tresor.open(sealed, "Test", command: cmd, timeout: 300)
    end

    test "check meldet die Secure-Enclave-Verfuegbarkeit (Exit 0/3/9)" do
      assert :ok = Core.check(script!("tresor", "exit 0"))
      assert {:error, :no_enclave} = Core.check(script!("tresor", "exit 3"))
      assert {:error, {:failed, 9}} = Core.check(script!("tresor", "exit 9"))
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

    test "altes Siegel: Zustand :outdated, reveal und seal_existing lassen es unangetastet" do
      {cmd, dir} = keychain!("ktv1.altes-siegel")

      assert Secrets.state(@entry, command: cmd) == :outdated
      assert {:error, :outdated} = Secrets.reveal("brave-search-api", command_kc(cmd))
      assert {:error, :outdated} = Secrets.seal_existing(@entry, command: cmd)
      assert File.read!(Path.join(dir, "stored")) == "ktv1.altes-siegel"

      text = Secrets.describe("brave-search-api", :outdated)
      assert text =~ "ktv1"
      assert text =~ "komki secret set brave"
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

    test "erzeugen legt ein Siegel ab und liefert nur den SHA-256 des Tokens" do
      {cmd, dir} = keychain!("alter-wert")
      {:ok, hub} = Secrets.fetch("ratsprojekte-hub")

      assert {:ok, hash} = Secrets.erzeugen(hub, command: cmd)
      assert hash =~ ~r/\A[0-9a-f]{64}\z/

      stored = File.read!(Path.join(dir, "stored"))
      assert Tresor.well_formed?(stored)
      assert {:ok, token} = Secrets.reveal("ratsprojekte-hub-token", command_kc(cmd))
      assert {:ok, _} = Base.url_decode64(token, padding: false)
      assert Base.encode16(:crypto.hash(:sha256, token), case: :lower) == hash
      refute stored =~ token

      # A second call replaces the entry with a fresh token.
      assert {:ok, other} = Secrets.erzeugen(hub, command: cmd)
      refute other == hash
    end

    test "erzeugen verweigert Geheimnisse, die von aussen kommen" do
      {cmd, dir} = keychain!(@kanarie)
      assert {:error, :not_generable} = Secrets.erzeugen(@entry, command: cmd)
      refute File.exists?(Path.join(dir, "calls"))
    end

    test "describe nennt nie einen Wert" do
      for error <- [:unsealed, :outdated, {:tresor, :refused}, {:tresor, :no_enclave}, :missing] do
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
