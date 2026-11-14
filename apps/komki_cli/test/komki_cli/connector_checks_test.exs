defmodule KomkiCli.ConnectorChecksTest do
  @moduledoc "Doctor checks of the sealed credentials; the keychain is the test seam."

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
end
