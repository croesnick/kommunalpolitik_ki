defmodule Ratsprojekte.Schemas.QuelleTest do
  @moduledoc """
  Strukturierte RIS-Referenz an der Quelle (Ticket #32).

  `ris_sitzung_id`, `ris_top` und `beschluss_nr` sind nur am Quellentyp
  `sitzung` erlaubt — die Referenz ist die Struktur hinter „welcher Beschluss
  gehört zu Projekt X?“ (WF 4).
  """

  use Ratsprojekte.DataCase, async: false

  alias Ratsprojekte.Schemas.Quelle

  describe "ris reference" do
    test "accepts the reference at typ sitzung" do
      changeset =
        Quelle.changeset(%Quelle{}, %{
          typ: :sitzung,
          titel: "Stadtratssitzung 05.11.2026",
          ris_sitzung_id: "4711",
          ris_top: "7",
          beschluss_nr: "2026/034"
        })

      assert changeset.valid?
    end

    test "accepts sitzung without the reference (Rückwärtskompatibilität)" do
      changeset = Quelle.changeset(%Quelle{}, %{typ: :sitzung, titel: "Stadtratssitzung"})
      assert changeset.valid?
    end

    test "rejects the reference at other quellen typs" do
      changeset =
        Quelle.changeset(%Quelle{}, %{
          typ: :foerderprogramm,
          titel: "Städtebauförderungsrichtlinien",
          ris_sitzung_id: "4711"
        })

      assert "RIS-Referenz (ris_sitzung_id/ris_top/beschluss_nr) ist nur für Quellen vom Typ 'sitzung' erlaubt" in errors_on(
               changeset
             ).ris_sitzung_id
    end

    test "rejects a beschluss_nr without typ sitzung too" do
      changeset =
        Quelle.changeset(%Quelle{}, %{
          typ: :zeitungsartikel,
          titel: "AZ: Freibad vor Veränderung",
          beschluss_nr: "2026/034"
        })

      assert errors_on(changeset).ris_sitzung_id != []
    end
  end
end
