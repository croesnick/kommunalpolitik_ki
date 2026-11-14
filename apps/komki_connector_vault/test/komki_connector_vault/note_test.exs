defmodule KomkiConnectorVault.NoteTest do
  use ExUnit.Case, async: true

  alias KomkiConnectorVault.{Note, Writer}

  @allowed ["vault-oeffentlich@1", "vault-vertraulich@1"]

  defp labels(text), do: Note.parse(text, "datei").labels

  test "Inline-Liste, Anfuehrungszeichen und Blockliste" do
    assert labels("---\nkomki_labels: [a, b]\n---\n") == ["a", "b"]
    assert labels("---\nkomki_labels: [\"a\", 'b']\n---\n") == ["a", "b"]
    assert labels("---\nkomki_labels:\n  - a\n  - b\nx: 1\n---\n") == ["a", "b"]
    assert labels("---\r\nkomki_labels: [a]\r\n---\r\nText") == ["a"]
  end

  test "fehlend, Skalar, doppelt und unlesbar" do
    assert labels("Text ohne Frontmatter") == :missing
    assert labels("---\ntitle: x\n---\n") == :missing
    assert labels("---\nkomki_labels: a\n---\n") == :invalid
    assert labels("---\nkomki_labels: [a]\nkomki_labels: [b]\n---\n") == :invalid
    assert labels("---\nkomki_labels:\nx: 1\n---\n") == :invalid
    assert labels("---\nkomki_labels: [a, ]\n---\n") == :invalid
    # nicht geschlossenes Frontmatter ist keins
    assert labels("---\nkomki_labels: [a]\n") == :missing
    # Frontmatter nur in der ersten Zeile
    assert labels("\n---\nkomki_labels: [a]\n---\n") == :missing
    assert labels("Text\n---\nkomki_labels: [a]\n---\n") == :missing
  end

  test "eingerueckter Schluessel zaehlt nicht" do
    assert labels("---\nx:\n  komki_labels: [a]\n---\n") == :missing
  end

  # Seit #211 prueft der Connector nur die Form einer Bindungs-ID; welche
  # Labels gelten, entscheidet der Vermittler gegen Γ.
  test "valid_labels: nicht leer, Form einer Bindungs-ID, sortiert ohne Dubletten" do
    label? = &KomkiConnectorVault.label?/1

    assert Note.valid_labels(["vault-vertraulich@1", "vault-oeffentlich@1"], label?) ==
             {:ok, ["vault-oeffentlich@1", "vault-vertraulich@1"]}

    assert Note.valid_labels(["vault-oeffentlich@1", "vault-oeffentlich@1"], label?) ==
             {:ok, ["vault-oeffentlich@1"]}

    assert Note.valid_labels(["vorlage-nichtoeffentlich@1"], label?) ==
             {:ok, ["vorlage-nichtoeffentlich@1"]}

    assert Note.valid_labels([], label?) == :error
    assert Note.valid_labels(["Vault Geheim"], label?) == :error
    assert Note.valid_labels(["vault-geheim"], label?) == :error
  end

  test "Titel: Frontmatter, Ueberschrift, Dateiname" do
    assert Note.parse("---\ntitle: \"Frontmatter\"\n---\n# Kopf\n", "datei").title ==
             "Frontmatter"

    assert Note.parse("---\nkomki_labels: [a]\n---\nText\n# Kopf\n", "datei").title == "Kopf"
    assert Note.parse("Text\n## Nur Ebene zwei\n", "datei").title == "datei"
  end

  # #478 (Audit #467, Fund F6): Angriffsnotiz wie im Zielbild — Frontmatter-
  # Titel, der nach Control-Zeichen-Reinigung durch den Writer leer
  # decodiert, Body-Zeile "# a" + 19995 Leerzeichen + "x". Die alte Regex
  # `^# +(.+?)[ \t]*$` lief darueber quadratisch heiss bis zum vollen
  # Match-Budget und raiserte am Ende SystemLimitError durch jede Suche.
  test "Angriffsnotiz (#478): linearer Lauf, kein Raise, Titel = Angriffszeile" do
    spaces = String.duplicate(" ", 19_995)
    line = "# a" <> spaces <> "x"
    title = "a" <> spaces <> "x"
    text = "---\nkomki_labels: [a]\ntitle: \" \"\n---\n" <> line <> "\n"

    note = Note.parse(text, "datei")

    assert note.title == title
    assert note.labels == ["a"]
    assert note.body == line <> "\n"
  end

  test "Ueberschrift-Semantik wie die alte Regex (#478)" do
    # Mehrfach-Leerzeichen hinter # und Leerzeichen/Tab am Zeilenende:
    # Titel vollstaendig getrimmt, CRLF inklusive.
    assert Note.parse("#   Kopf mit Vorglanz\n", "datei").title == "Kopf mit Vorglanz"
    assert Note.parse("# Kopf \t \nText\n", "datei").title == "Kopf"
    assert Note.parse("---\nkomki_labels: [a]\n---\r\n# Kopf\r\nText", "datei").title == "Kopf"

    # Erst matchende Zeile gewinnt, auch wenn ihr Titel leer wird.
    assert Note.parse("#   \n# Zweite\n", "datei").title == "datei"
    # "# " ohne weiteren Inhalt ist keine Ueberschrift, die naechste passt.
    assert Note.parse("# \n# Zweite\n", "datei").title == "Zweite"
  end

  test "Body beginnt nach dem Frontmatter, spaetere ---Bloecke bleiben Inhalt" do
    text = "---\nkomki_labels: [a]\n---\nA\n---\nkomki_labels: [b]\n---\n"
    note = Note.parse(text, "datei")
    assert note.labels == ["a"]
    assert note.body == "A\n---\nkomki_labels: [b]\n---\n"
  end

  test "slug: ASCII, Umlaute, Laenge, Fallback" do
    assert Writer.slug("Prüfauftrag Ärztehaus Straße") == "pruefauftrag-aerztehaus-strasse"
    assert Writer.slug("../../etc/passwd") == "etc-passwd"
    assert Writer.slug("!!!") == "notiz"
    assert String.length(Writer.slug(String.duplicate("abc ", 40))) <= 60
  end
end
