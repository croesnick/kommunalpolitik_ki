defmodule KomkiPolicy.JSONTest do
  use ExUnit.Case, async: true

  alias KomkiPolicy.JSON

  @fixtures_dir Path.expand("../../priv/fixtures", __DIR__)
  @duplicate_key_fixture Path.join(@fixtures_dir, "invalid/registry_duplicate_key.json")

  @rejections [
    {"{\"a\": 1,}", :trailing_comma},
    {"[1, 2,]", :trailing_comma},
    {"NaN", :invalid_number},
    {"Infinity", :invalid_number},
    {"-Infinity", :invalid_number},
    {"+1", :invalid_number},
    {"01", :invalid_number},
    {~s("abc), :unterminated_literal},
    {"{\"a\": \"abc", :unterminated_literal},
    {"tru", :unterminated_literal},
    {"{\"a\": tru", :unterminated_literal},
    {"{\"a\":", :incomplete_document},
    {"[1, 2", :incomplete_document},
    {"{", :incomplete_document},
    {"", :empty_input},
    {"   \n\t  ", :empty_input},
    {"{\"a\": 1} trailing", :trailing_data},
    {"1 2", :trailing_data}
  ]

  defp valid_fixture_files do
    files = fixture_files(@fixtures_dir)

    Enum.reject(files, fn file ->
      file == @duplicate_key_fixture or String.contains?(file, "/invalid/")
    end)
  end

  defp fixture_files(dir) do
    sorted = Path.wildcard(Path.join(dir, "**/*.json"))
    Enum.sort(sorted)
  end

  describe "Korpus-Akzeptanz" do
    test "alle L1-Fixtures (außer invalid/registry_duplicate_key.json) parsen erfolgreich" do
      files = valid_fixture_files()
      refute files == []

      Enum.each(files, fn file ->
        data = File.read!(file)
        result = JSON.parse(data)

        assert elem(result, 0) == :ok,
               "fixture does not parse: #{Path.relative_to(file, @fixtures_dir)}"
      end)
    end

    test "Korpus ist produktiv: invalid/registry_duplicate_key.json ist die einzige Ausnahme" do
      all_invalid = fixture_files(Path.join(@fixtures_dir, "invalid"))

      invalid_files = Enum.reject(all_invalid, &(&1 == @duplicate_key_fixture))

      Enum.each(invalid_files, fn file ->
        data = File.read!(file)
        result = JSON.parse(data)

        assert elem(result, 0) == :ok,
               "fixture does not parse: #{Path.relative_to(file, @fixtures_dir)}"
      end)
    end

    test "canonical ist byte-stabil und strukturell verlustfrei über den Korpus" do
      Enum.each(valid_fixture_files(), fn file ->
        data = File.read!(file)
        {:ok, term} = JSON.parse(data)
        canonical = JSON.canonical(term)

        # twice canonicalized -> byte-identical
        {:ok, reparsed} = JSON.parse(canonical)

        assert JSON.canonical(reparsed) == canonical,
               "not byte-stable: #{Path.relative_to(file, @fixtures_dir)}"

        # structural round-trip: parse o canonical o parse remote
        assert reparsed == term,
               "not structurally stable: #{Path.relative_to(file, @fixtures_dir)}"
      end)
    end
  end

  describe "Rejektion invalid/registry_duplicate_key.json" do
    test "doppelter Schlüssel wird mit Pfad abgewiesen" do
      assert {:error, %{code: :duplicate_json_key, path: path, detail: detail}} =
               JSON.parse(File.read!(@duplicate_key_fixture))

      assert String.contains?(path, "bindings")
      assert String.contains?(path, "readers")
      assert is_binary(detail) and detail != ""
    end
  end

  describe "UTF-8-Wohlgeformtheit in Strings (MIN-7)" do
    test "ungueltige Multi-Byte-Sequenzen werden abgewiesen" do
      # "x\xC3(" ...
      bad = <<34, "x", 0xC3, 0x28, 34>>
      assert {:error, %{code: :invalid_utf8, path: "$"}} = JSON.parse(bad)

      # Overlong-NUL
      overlong = <<34, 0xC0, 0x80, 34>>
      assert {:error, %{code: :invalid_utf8}} = JSON.parse(overlong)

      # UTF-8 codierte Surrogate nicht erlaubt
      surrogate = <<34, 0xED, 0xA0, 0x80, 34>>
      assert {:error, %{code: :invalid_utf8}} = JSON.parse(surrogate)

      # "äh"
      valid = <<34, 0xC3, 0xA4, "h", 34>>
      assert JSON.parse(valid) == {:ok, "äh"}
    end

    test "Literalfortsetzungen mit Ziffern wie true1 sind unterminated_literal (MIN-7-Kosmetik)" do
      assert {:error, %{code: :unterminated_literal}} = JSON.parse("true1")
    end

    test "U+FE0F (Lead 0xEF) ist valides, druckbares UTF-8 inkl. Canonical-Roundtrip" do
      # Variation Selector-16: Lead 0xEF mit zwei Continuation-Bytes, kein
      # Sonderbereich. Vor dem Gate wurde das fälschlich als invalid_utf8
      # abgewiesen (Lane-B-Befund).
      value = <<0xEF, 0x83, 0x8F>>
      assert JSON.parse(<<34, value::binary, 34>>) == {:ok, value}

      assert JSON.canonical(value) == <<34, value::binary, 34, 10>>
      assert {:ok, ^value} = JSON.parse(JSON.canonical(value))
    end

    test "U+E100 (Lead 0xEE, Private Use Area) ist valides UTF-8 inkl. Canonical-Roundtrip" do
      value = <<0xEE, 0x84, 0x80>>
      assert JSON.parse(<<34, value::binary, 34>>) == {:ok, value}

      assert JSON.canonical(value) == <<34, value::binary, 34, 10>>
      assert {:ok, ^value} = JSON.parse(JSON.canonical(value))
    end
  end

  # ======================================================================
  # Tripwire: kanonisch gepinnte Fixtures sind byte-genau §6-Kanalisierung
  # (MIN-8/9; Befund: Snapshot-/Intent-/Registry-Fixtures sind byte-inhaltlich
  # NICHT kanonisch sortiert und koennen daher nicht Tripwire-teil sein.)
  # ======================================================================

  describe "Korpus-Tripwire (MIN-8)" do
    test "alle expected_decision.json / expected_result.json / proofs-Dateien sind byte-kanonisch" do
      files =
        for file <- Path.wildcard(Path.join(@fixtures_dir, "**/*.json")),
            canonical_byte_pin?(file) do
          file
        end

      refute files == []

      Enum.each(files, fn file ->
        data = File.read!(file)
        {:ok, term} = JSON.parse(data)

        assert JSON.canonical(term) == data,
               "not byte-canonical: #{Path.relative_to(file, @fixtures_dir)}"
      end)
    end

    defp canonical_byte_pin?(path) do
      rel = Path.relative_to(path, @fixtures_dir)

      String.contains?(rel, "expected_decision.json") or
        String.contains?(rel, "expected_result.json") or
        String.contains?(rel, "proof_valid.json") or
        String.contains?(rel, "proof_") or
        rel == "proofs/verify_expectations.json" or
        rel == "expressions/evaluate_expectations.json"
    end
  end

  defp assert_rejected(input, code) do
    assert {:error, %{code: error_code}} = JSON.parse(input)
    assert error_code == code, "expected #{code} for #{input}, got #{error_code}"
  end

  describe "Strenge Rejektionen" do
    test "jeder Verstoß bekommt seinen eigenen Fehlercode" do
      Enum.each(@rejections, fn {input, code} ->
        assert_rejected(input, code)
      end)
    end

    test "Fehlerstruktur ist vollständig: %{code, path, detail} (String)" do
      {:error, error} = JSON.parse(~s({"a": 1, "b": tru))
      assert %{code: :unterminated_literal} = error
      assert is_binary(error.path) and String.starts_with?(error.path, "$")
      assert is_binary(error.detail) and error.detail != ""
    end

    test "Doppelte Schlüssel tief verschachtelt benennen den Pfad" do
      input = "{\"a\": {\"b\": {\"c\": 1, \"c\": 2}}}"
      assert {:error, %{code: :duplicate_json_key, path: path}} = JSON.parse(input)
      assert path == "$.a.b.c"
    end

    test "Surrogat- und Escape-Verstöße werden abgewiesen" do
      assert {:error, %{code: :invalid_string}} = JSON.parse(~s("x\\uDD11"))
      assert {:error, %{code: :invalid_string}} = JSON.parse(~S({"a": ["\uD801"]}))
      assert {:error, %{code: :invalid_string}} = JSON.parse(~s({"a": "\\q"}))
    end

    test "grundlegende Typen nach RFC 8259" do
      assert JSON.parse("true") == {:ok, true}
      assert JSON.parse("false") == {:ok, false}
      assert JSON.parse("null") == {:ok, nil}
      assert JSON.parse("42") == {:ok, 42}
      assert JSON.parse("-7") == {:ok, -7}
      assert JSON.parse("1.5") == {:ok, 1.5}
      assert JSON.parse("2.5e2") == {:ok, 250.0}
      assert JSON.parse("\"hällo\"") == {:ok, "hällo"}
      assert JSON.parse("[1, [2, 3], {\"a\": null}]") == {:ok, [1, [2, 3], %{"a" => nil}]}
    end
  end

  describe "Kanonische Darstellung" do
    test "Schlüssel bytewise aufsteigend, 2-Space, finales Newline" do
      assert JSON.canonical(%{"b" => 1, "a" => 2}) == "{\n  \"a\": 2,\n  \"b\": 1\n}\n"
    end

    test "Sortierung ist bytewise (UTF-8), nicht alphabetisch-ignorant" do
      canonical = JSON.canonical(%{"a" => 1, "Z" => 2, "ä" => 3})

      assert canonical == "{\n  \"Z\": 2,\n  \"a\": 1,\n  \"ä\": 3\n}\n"
    end

    test "Genau ein finales Newline; keine Leerzeilen" do
      canonical = JSON.canonical(%{"a" => 1})
      assert String.ends_with?(canonical, "\n")
      refute String.ends_with?(canonical, "\n\n")
      refute canonical =~ ~r/\n\n/
    end

    test "Verschachtelung ist eingerückt (Arrays\/Objekte)" do
      assert JSON.canonical(%{"xs" => [1, %{"b" => true, "a" => nil}]}) ==
               "{\n  \"xs\": [\n    1,\n    {\n      \"a\": null,\n      \"b\": true\n    }\n  ]\n}\n"
    end

    test "Leere Container bleiben inline" do
      assert JSON.canonical(%{"e" => [], "o" => %{}}) == "{\n  \"e\": [],\n  \"o\": {}\n}\n"
    end

    test "Skalare bekommen ein Newline" do
      assert JSON.canonical(42) == "42\n"
      assert JSON.canonical(true) == "true\n"
    end

    test "Strings werden RFC-8259-gerecht escaped" do
      expected = """
      {
        "k": "a\\"b\\n\\\\\\t"
      }
      """

      assert JSON.canonical(%{"k" => "a\"b\n\\\t"}) == expected
    end

    test "Zahlen dezimal ohne Vorzeichennull" do
      assert JSON.canonical(%{"n" => -0}) == "{\n  \"n\": 0\n}\n"
      assert JSON.canonical(%{"n" => 1_000_000_000_000_000_000_000}) =~ "1000000000000000000000"
    end
  end

  describe "Round-Trip" do
    test "canonical(parse(canonical(parse(x)))) == canonical(parse(x))" do
      Enum.each(valid_fixture_files(), fn file ->
        data = File.read!(file)
        {:ok, term} = JSON.parse(data)
        c1 = JSON.canonical(term)
        {:ok, term2} = JSON.parse(c1)
        c2 = JSON.canonical(term2)

        assert c2 == c1, "round-trip drift: #{Path.relative_to(file, @fixtures_dir)}"
      end)
    end

    test "parse_canonical/1 liefert die Kanonisierung direkt" do
      data = File.read!(Path.join(@fixtures_dir, "registry.json"))
      {:ok, term} = JSON.parse(data)

      assert JSON.parse_canonical(data) == {:ok, JSON.canonical(term)}
    end

    test "parse_canonical/1 reicht Parsefehler transparent durch" do
      assert {:error, %{code: :incomplete_document}} = JSON.parse_canonical("{")
    end
  end
end
