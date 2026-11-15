defmodule KomkiConnectorDocuments.CliTest do
  @moduledoc """
  CLI der zweiten Programmform (#288): `nif_check/0` lädt pdfium wirklich
  (Phase 0 von ex_pdfium verifiziert Verkettung und Initialisierung) —
  derselbe Aufruf, den `--nif-check` unter dem Profil ausführt.
  """

  use ExUnit.Case, async: true

  alias KomkiConnectorDocuments.CLI

  test "nif_check: pdfium laedt" do
    assert {:ok, version} = CLI.nif_check()
    assert is_binary(version) and version != ""
  end
end
