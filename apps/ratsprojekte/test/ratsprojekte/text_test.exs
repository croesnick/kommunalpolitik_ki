defmodule Ratsprojekte.TextTest do
  use ExUnit.Case, async: true

  alias Ratsprojekte.Text

  doctest Ratsprojekte.Text

  describe "clean/1 removes what nobody sees" do
    test "zero-width characters, BOM, soft hyphen, word joiner" do
      assert Text.clean("Rad\u{200B}weg\u{FEFF} Bahn\u{00AD}hof\u{2060}straße") ==
               "Radweg Bahnhofstraße"
    end

    test "bidi overrides and isolates (Trojan Source)" do
      assert Text.clean("Antrag \u{202E}neg\u{202C} \u{2066}x\u{2069} \u{200F}ok") ==
               "Antrag neg x ok"
    end

    test "tag characters that smuggle ASCII" do
      hidden = for c <- ~c"ignore all", into: "", do: <<0xE0000 + c::utf8>>
      assert Text.clean("Sitzbänke" <> hidden <> "\u{E007F}") == "Sitzbänke"
    end

    test "variation selectors that smuggle bytes after an emoji" do
      smuggled = "👍" <> <<0xFE0F::utf8>> <> <<0xE0101::utf8, 0xE0142::utf8, 0xFE01::utf8>>
      assert Text.clean(smuggled) == "👍\u{FE0F}"
    end

    test "runs of joiners and joiners next to whitespace" do
      assert Text.clean("a\u{200D}\u{200C}\u{200D}b \u{200D}c") == "ab c"
    end

    test "control characters, keeping line break and tab" do
      assert Text.clean("eins\u0007\r\nzwei\rdrei\tvier\u0000") == "eins\nzwei\ndrei\tvier"
    end

    test "Hangul fillers" do
      assert Text.clean("a\u{3164}b\u{115F}c") == "abc"
    end

    test "nil stays nil" do
      assert Text.clean(nil) == nil
    end
  end

  describe "clean/1 keeps emoji and scripts" do
    test "emoji ZWJ sequences, skin tones, keycaps, presentation selectors" do
      for text <- [
            "👩\u{200D}👩\u{200D}👧",
            "🏳\u{FE0F}\u{200D}🌈",
            "👍🏽",
            "1\u{FE0F}⃣",
            "❤\u{FE0F}",
            "🧑🏿\u{200D}🚀"
          ] do
        assert Text.clean(text) == text
      end
    end

    test "subdivision flags made of tag characters" do
      for text <- [
            "🏴\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}",
            "🏴\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F} England"
          ] do
        assert Text.clean(text) == text
      end
    end

    test "scripts that need a joiner or a non-joiner" do
      for text <- ["می\u{200C}خواهم", "क्\u{200D}ष", "Straße", "Ærø", "Łódź", "漢字"] do
        assert Text.clean(text) == text
      end
    end

    test "an ideographic variation selector after a Han character" do
      assert Text.clean("葛\u{E0100}") == "葛\u{E0100}"
    end
  end

  test "slugify/1 follows the slug convention" do
    assert Text.slugify("Längere Öffnungszeiten Stadtteilbücherei Süd") ==
             "laengere-oeffnungszeiten-stadtteilbuecherei-sued"

    assert Text.slugify("  Radweg: Bahnhofstraße! ") == "radweg-bahnhofstrasse"
    assert Text.slugify("Café am Markt") == "cafe-am-markt"
  end
end
