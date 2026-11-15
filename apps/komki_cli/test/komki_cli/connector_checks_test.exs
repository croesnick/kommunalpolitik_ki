defmodule KomkiCli.ConnectorChecksTest do
  @moduledoc """
  Doctor checks of the sealed credentials (keychain is the test seam) and
  the NIF wiring of the second program form (#288).
  """

  use ExUnit.Case, async: true

  alias KomkiCli.{Config, ConnectorChecks, TestSupport}

  defp credential_check(state) do
    cfg = Config.defaults(TestSupport.tmp_area!("komki-checks"))

    cfg
    |> ConnectorChecks.all(fn _service -> state end)
    |> Enum.find(&(&1.name == "credential BRAVE_API_KEY"))
  end

  test "versiegelt: keine Warnung" do
    refute credential_check(:sealed).reason =~ "WARNUNG"
  end

  test "altes Siegel: Warnung mit dem Weg, ohne einen Wert" do
    check = credential_check(:outdated)

    assert check.reason =~ "WARNUNG"
    assert check.reason =~ "ktv1"
    assert check.reason =~ "komki secret set brave"
  end

  describe "NIF-Pruefung (#288)" do
    defp nif_check(cfg) do
      cfg
      |> ConnectorChecks.all(fn _service -> :sealed end)
      |> Enum.find(&(&1.name == "nif documents"))
    end

    # Ohne native Dateien (Fixtur ohne Baum) rot mit der Ursache; nichts
    # wird gestartet. Das Profil existiert, damit die Fundstelle gemeint ist
    # und nicht das fehlende Profil.
    test "ohne native Dateien: rot, Ursache statt Lauf" do
      cfg =
        struct!(Config.defaults(TestSupport.tmp_area!("komki-checks-nif")), %{
          escript_bin: "/opt/erl/bin/escript",
          connector_bins: %{"documents" => "/opt/komki/bin/komki-connector-documents"}
        })

      profile = KomkiCli.Connectors.profile_path(cfg, "documents")
      File.mkdir_p!(Path.dirname(profile))
      File.write!(profile, "(version 1)\n(deny default)\n")

      check = nif_check(cfg)
      refute check.ok
      assert check.reason =~ "Verzeichnis der NIF-Anwendung fehlt"
    end

    test "mit Baum, ohne Profil der Instanz: rot, Hinweis auf setup" do
      dir = TestSupport.tmp_area!("komki-checks-nif-baum")
      program = Path.join([dir, "bin", "komki-connector-documents"])
      File.mkdir_p!(Path.dirname(program))
      File.write!(program, "")
      File.mkdir_p!(Path.join([dir, "bin", "lib", "ex_pdfium", "ebin"]))

      cfg =
        struct!(Config.defaults(TestSupport.tmp_area!("komki-checks-nif2")), %{
          escript_bin: "/opt/erl/bin/escript",
          connector_bins: %{"documents" => program}
        })

      check = nif_check(cfg)
      refute check.ok
      assert check.reason =~ "Profil fehlt"
    end
  end
end
