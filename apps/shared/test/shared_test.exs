defmodule SharedTest do
  use ExUnit.Case, async: true

  alias Shared.{Sitzung, TOP, Gremium, Dokument, Textblock, Abstimmung, Suchergebnis}

  describe "Gremium" do
    test "can be constructed with defaults" do
      g = %Gremium{id: 7632, name: "VG Buchloe Gemeinschaftsversammlung", client_id: 2445}
      assert g.id == 7632
      assert g.name == "VG Buchloe Gemeinschaftsversammlung"
    end
  end

  describe "Sitzung" do
    test "can be constructed with defaults" do
      s = %Sitzung{id: 116_135_092, name: "1. Sitzung der Gemeinschaftsversammlung"}
      assert s.id == 116_135_092
      assert s.tops == nil
    end

    test "can hold TOPs" do
      top = %TOP{id: "116135092-116135132", nummer: "11", titel: "Protokollgenehmigung"}
      s = %Sitzung{id: 116_135_092, tops: [top]}
      assert length(s.tops) == 1
    end
  end

  describe "TOP" do
    test "can hold documents and textblocks" do
      doc = %Dokument{id: "doc-1", name: "protokoll.pdf", fileext: ".pdf"}
      tb = %Textblock{caption: "Sachverhalt", content: "Test"}

      top = %TOP{
        id: "116135092-116135132",
        sitzung_id: 116_135_092,
        nummer: "11",
        titel: "Protokoll",
        dokumente: [doc],
        textbloecke: [tb]
      }

      assert length(top.dokumente) == 1
      assert length(top.textbloecke) == 1
    end
  end

  describe "Abstimmung" do
    test "defaults to nil fields" do
      a = %Abstimmung{}
      assert a.id == nil
      assert a.ergebnis == nil
    end
  end

  describe "Suchergebnis" do
    test "can be constructed" do
      s = %Suchergebnis{id: "116135092-117330010", titel: "Erlass einer Entschädigungssatzung"}
      assert s.id == "116135092-117330010"
      assert s.titel == "Erlass einer Entschädigungssatzung"
    end
  end
end
