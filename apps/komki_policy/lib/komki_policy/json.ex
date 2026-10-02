defmodule KomkiPolicy.JSON do
  @moduledoc """
  Strenger JSON-Parser und kanonischer Encoder (CONTRACT.md § 6).

  Der Parser ist stdlib-only und strikt gemäß RFC 8259. Er verwirft u. a.
  doppelte Objektschlüssel, nachgestellte Kommas, `NaN`/`Infinity`,
  führende Pluszeichen und nicht terminierte Literale. Parse-Fehler werden
  als strukturierte Fehler mit `code`, `path` (JSON-Pointer-ähnlich) und
  `detail` geliefert — `parse/1` wirft nie.

  Der Encoder (`canonical/1`) erzeugt eine deterministische, byte-stabile
  Kanonisierung: Objektschlüssel bytewise aufsteigend sortiert (UTF-8),
  2-Space-Einrückung, LF-Zeilenenden, keine Leerzeilen, genau ein finales
  Newline.

  Objekte werden als Maps mit String-Schlüsseln dargestellt, Arrays als
  Listen, `null` als `nil`.
  """

  @type json_value ::
          nil | true | false | integer() | float() | String.t() | [json_value()] | %{}

  @type parse_error :: %{
          required(:code) => atom(),
          required(:path) => String.t(),
          required(:detail) => String.t()
        }

  # Interner Fehler: {code, path, detail}
  @type reason :: {atom(), String.t(), String.t()}

  @whitespace [0x20, 0x09, 0x0A, 0x0D]

  @number_re ~r/\A-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?\z/

  @escape_map %{
    0x22 => "\\\"",
    0x5C => "\\\\",
    0x08 => "\\b",
    0x09 => "\\t",
    0x0A => "\\n",
    0x0C => "\\f",
    0x0D => "\\r"
  }

  # ---------------------------------------------------------------------------
  # Öffentliche API
  # ---------------------------------------------------------------------------

  @doc """
  Parst ein JSON-Dokument strikt.

  Callback-Ausgabe: `{:ok, term}` oder
  `{:error, %{code: atom, path: binary, detail: binary}}`. `path` ist ein
  JSON-Pointer-ähnlicher Pfad (`$.bindings.buergerfall-4711@1.readers`).
  """
  @spec parse(binary()) :: {:ok, json_value()} | {:error, parse_error()}
  def parse(input) when is_binary(input) do
    with {:ok, value, pos} <- parse_root(input),
         :ok <- expect_end(input, pos) do
      {:ok, value}
    else
      {:halt, {code, path, detail}} -> {:error, %{code: code, path: path, detail: detail}}
    end
  end

  @doc """
  Encodiert einen Wert in die kanonische Darstellung (deterministisch,
  byte-stabil; genau ein finales Newline). Nicht-JSON-Terme (z. B. Atome
  oder Maps mit Nicht-String-Schlüsseln) verursachen einen `ArgumentError`.
  """
  @spec canonical(json_value()) :: binary()
  def canonical(value) do
    encoded = [encode_value(value, 0), "\n"]
    IO.iodata_to_binary(encoded)
  end

  @doc "Convenience: `parse/1` gefolgt von `canonical/1`."
  @spec parse_canonical(binary()) :: {:ok, binary()} | {:error, parse_error()}
  def parse_canonical(input) when is_binary(input) do
    case parse(input) do
      {:ok, value} -> {:ok, canonical(value)}
      {:error, _} = error -> error
    end
  end

  # ---------------------------------------------------------------------------
  # Parser: Dokumentrahmen
  # ---------------------------------------------------------------------------

  defp parse_root(input) do
    wpos = skip_ws(input, 0)

    if wpos >= byte_size(input) do
      {:halt, {:empty_input, "$", "no JSON document, only whitespace"}}
    else
      read_value(input, wpos, "$")
    end
  end

  defp expect_end(input, pos) do
    case skip_ws(input, pos) do
      end_pos when end_pos >= byte_size(input) -> :ok
      _end_pos -> {:halt, {:trailing_data, "$", "unexpected byte after the document"}}
    end
  end

  # ---------------------------------------------------------------------------
  # Parser: Wert-Diskriminator
  # ---------------------------------------------------------------------------

  defp read_value(input, pos, path) do
    case next_byte(input, pos) do
      {:eof, _} ->
        {:halt, {:incomplete_document, path, "unexpected end of input, expected a value"}}

      {byte, npos} ->
        dispatch_value(value_kind(byte), byte, npos, input, pos, path)
    end
  end

  defp value_kind(?{), do: :object
  defp value_kind(?[), do: :array
  defp value_kind(?"), do: :string
  defp value_kind(?n), do: :null
  defp value_kind(?t), do: :true_lit
  defp value_kind(?f), do: :false_lit
  defp value_kind(b) when b in ?0..?9 or b == ?-, do: :number
  defp value_kind(b) when b in [?+, ?N, ?I], do: :bare_number_token
  defp value_kind(_byte), do: :unexpected

  defp dispatch_value(:object, _byte, npos, input, _pos, path),
    do: read_object(input, npos, path)

  defp dispatch_value(:array, _byte, npos, input, _pos, path),
    do: read_array(input, npos, path)

  defp dispatch_value(:string, _byte, _npos, input, pos, path),
    do: read_string(input, pos, path)

  defp dispatch_value(:null, _byte, _npos, input, pos, path),
    do: read_keyword(input, pos, path, "null", nil)

  defp dispatch_value(:true_lit, _byte, _npos, input, pos, path),
    do: read_keyword(input, pos, path, "true", true)

  defp dispatch_value(:false_lit, _byte, _npos, input, pos, path),
    do: read_keyword(input, pos, path, "false", false)

  defp dispatch_value(:number, _byte, _npos, input, pos, path),
    do: read_number(input, pos, path)

  defp dispatch_value(:bare_number_token, _byte, _npos, _input, _pos, path),
    do: {:halt, {:invalid_number, path, "not a JSON number"}}

  defp dispatch_value(:unexpected, byte, _npos, _input, _pos, path),
    do: {:halt, {:unexpected_byte, path, "expected value, got byte " <> byte_hex(byte)}}

  defp next_byte(input, pos) when pos >= byte_size(input), do: {:eof, pos}
  defp next_byte(input, pos), do: {:binary.at(input, pos), pos + 1}

  defp byte_hex(byte), do: "0x" <> Integer.to_string(byte, 16)

  defp skip_ws(input, pos) when pos < byte_size(input) do
    case :binary.at(input, pos) do
      byte when byte in @whitespace -> skip_ws(input, pos + 1)
      _ -> pos
    end
  end

  defp skip_ws(_input, pos), do: pos

  # ---------------------------------------------------------------------------
  # Parser: Schlüsselwörter (true | false | null)
  # ---------------------------------------------------------------------------

  defp read_keyword(input, pos, path, keyword, value) do
    len = byte_size(keyword)

    if pos + len <= byte_size(input) and binary_part(input, pos, len) == keyword do
      accept_keyword(input, pos + len, path, keyword, value)
    else
      {:halt, {:unterminated_literal, path, "expected the literal " <> keyword}}
    end
  end

  defp accept_keyword(input, pos, path, keyword, value) do
    case next_byte(input, pos) do
      {byte, _} when byte in ?a..?z or byte in ?A..?Z or byte in ?0..?9 ->
        {:halt, {:unterminated_literal, path, "literal " <> keyword <> " continues unallowed"}}

      _ ->
        {:ok, value, pos}
    end
  end

  # ---------------------------------------------------------------------------
  # Parser: Objekte
  # ---------------------------------------------------------------------------

  defp read_object(input, pos, path) do
    wpos = skip_ws(input, pos)

    case next_byte(input, wpos) do
      {?}, npos} ->
        {:ok, %{}, npos}

      {?", _} ->
        read_entry(input, wpos, path, %{})

      {?,, _} ->
        {:halt, {:unexpected_byte, path, "expected object key, got byte ','"}}

      {:eof, _} ->
        {:halt, {:incomplete_document, path, "unterminated object"}}

      {byte, _} ->
        {:halt, {:unexpected_byte, path, "expected object key, got byte " <> byte_hex(byte)}}
    end
  end

  defp read_entry(input, pos, path, acc) do
    with {:ok, key, kpos} <- read_string(input, pos, path),
         {:ok, colon_pos} <- expect_colon(input, kpos, path),
         {:ok, value, vpos} <- read_value(input, skip_ws(input, colon_pos), path <> "." <> key) do
      store_object_value(input, skip_ws(input, vpos), path, key, value, acc)
    end
  end

  defp store_object_value(input, wpos, path, key, value, acc) do
    if Map.has_key?(acc, key) do
      {:halt, {:duplicate_json_key, path <> "." <> key, "duplicate object key"}}
    else
      continue_object(input, wpos, path, Map.put(acc, key, value))
    end
  end

  defp continue_object(input, wpos, path, acc) do
    case next_byte(input, wpos) do
      {?}, npos} ->
        {:ok, acc, npos}

      {?,, npos} ->
        expect_object_key(input, skip_ws(input, npos), path, acc)

      {:eof, _} ->
        {:halt, {:incomplete_document, path, "unterminated object"}}

      {byte, _} ->
        {:halt, {:unexpected_byte, path, "expected ',' or '}', got byte " <> byte_hex(byte)}}
    end
  end

  defp expect_object_key(input, wpos, path, acc) do
    case next_byte(input, wpos) do
      {?}, _} ->
        {:halt, {:trailing_comma, path, "comma followed by closing brace"}}

      {?", _} ->
        read_entry(input, wpos, path, acc)

      {:eof, _} ->
        {:halt, {:incomplete_document, path, "unterminated object"}}

      {byte, _} ->
        {:halt, {:unexpected_byte, path, "expected object key, got byte " <> byte_hex(byte)}}
    end
  end

  defp expect_colon(input, pos, path) do
    case next_byte(input, skip_ws(input, pos)) do
      {?:, npos} -> {:ok, npos}
      {:eof, _} -> {:halt, {:incomplete_document, path, "unterminated object"}}
      {byte, _} -> {:halt, {:unexpected_byte, path, "expected ':', got byte " <> byte_hex(byte)}}
    end
  end

  # ---------------------------------------------------------------------------
  # Parser: Arrays
  # ---------------------------------------------------------------------------

  defp read_array(input, pos, path) do
    wpos = skip_ws(input, pos)

    case next_byte(input, wpos) do
      {?], npos} -> {:ok, [], npos}
      {?,, _} -> {:halt, {:unexpected_byte, path, "expected array element, got byte ','"}}
      {:eof, _} -> {:halt, {:incomplete_document, path, "unterminated array"}}
      _ -> array_items(input, wpos, path, [])
    end
  end

  defp array_items(input, pos, path, acc) do
    with {:ok, value, vpos} <- read_value(input, pos, path),
         wpos <- skip_ws(input, vpos) do
      array_continuation(input, wpos, path, [value | acc])
    end
  end

  defp array_continuation(input, wpos, path, acc) do
    case next_byte(input, wpos) do
      {?], npos} ->
        {:ok, Enum.reverse(acc), npos}

      {?,, npos} ->
        watch_out_comma(input, skip_ws(input, npos), path, acc)

      {:eof, _} ->
        {:halt, {:incomplete_document, path, "unterminated array"}}

      {byte, _} ->
        {:halt, {:unexpected_byte, path, "expected ',' or ']', got byte " <> byte_hex(byte)}}
    end
  end

  defp watch_out_comma(input, wpos, path, acc) do
    case next_byte(input, wpos) do
      {?], _} ->
        {:halt, {:trailing_comma, path, "comma followed by closing bracket"}}

      {:eof, _} ->
        {:halt, {:incomplete_document, path, "unterminated array"}}

      _ ->
        array_items(input, wpos, path, acc)
    end
  end

  # ---------------------------------------------------------------------------
  # Parser: Strings (RFC 8259, inkl. \u-Escapes und Surrogat-Paaren)
  # ---------------------------------------------------------------------------

  defp read_string(input, pos, path), do: read_string_rest(input, pos + 1, path, [])

  defp read_string_rest(input, pos, path, acc) do
    if pos >= byte_size(input) do
      {:halt, {:unterminated_literal, path, "unterminated string"}}
    else
      read_string_char(input, pos, path, acc)
    end
  end

  defp read_string_char(input, pos, path, acc) do
    case :binary.at(input, pos) do
      0x22 ->
        {:ok, IO.iodata_to_binary(Enum.reverse(acc)), pos + 1}

      0x5C ->
        read_escape(input, pos + 1, path, acc)

      byte when byte < 0x20 ->
        {:halt, {:invalid_string, path, "unescaped control character in string"}}

      byte when byte < 0x80 ->
        read_string_rest(input, pos + 1, path, [byte | acc])

      byte ->
        read_multibyte_sequence(input, pos, path, byte, acc)
    end
  end

  defp read_multibyte_sequence(input, pos, path, lead, acc) do
    case utf8_sequence(input, pos, lead) do
      {:ok, len} ->
        chunk = binary_part(input, pos, len)
        read_string_rest(input, pos + len, path, [chunk | acc])

      :bad ->
        {:halt, {:invalid_utf8, path, "invalid UTF-8 byte sequence in string"}}
    end
  end

  # Multi-Byte-UTF-8 (RFC 3629); Overlong-/Surrogat-Formen bleiben ungueltig.
  defp utf8_sequence(input, pos, lead) do
    available = min(4, byte_size(input) - pos)
    slice = binary_part(input, pos, available)
    utf8_seq(lead, slice)
  end

  defp utf8_seq(lead, <<lead, b, _rest::binary>>) when lead in 0xC2..0xDF and b in 0x80..0xBF,
    do: {:ok, 2}

  defp utf8_seq(lead, <<lead, b, c, _rest::binary>>)
       when lead in 0xE2..0xEC and b in 0x80..0xBF and c in 0x80..0xBF,
       do: {:ok, 3}

  defp utf8_seq(lead, <<lead, b, c, _rest::binary>>)
       when lead == 0xE0 and b in 0xA0..0xBF and c in 0x80..0xBF, do: {:ok, 3}

  defp utf8_seq(lead, <<lead, b, c, _rest::binary>>)
       when lead == 0xE1 and b in 0x80..0xBF and c in 0x80..0xBF, do: {:ok, 3}

  # U+E000 bis U+EFFF und U+F000 bis U+FFFF: RFC 8259 erlaubt jede
  # wohlgeformte UTF-8-Folge; nur Continuation-Bytes pruefen (keine
  # Sonderbereiche).
  defp utf8_seq(lead, <<lead, b, c, _rest::binary>>)
       when lead in 0xEE..0xEF and b in 0x80..0xBF and c in 0x80..0xBF, do: {:ok, 3}

  defp utf8_seq(lead, <<lead, b, c, _rest::binary>>)
       when lead == 0xED and b in 0x80..0x9F and c in 0x80..0xBF, do: {:ok, 3}

  defp utf8_seq(lead, <<lead, b, c, d, _rest::binary>>)
       when lead == 0xF0 and b in 0x90..0xBF and c in 0x80..0xBF and d in 0x80..0xBF,
       do: {:ok, 4}

  defp utf8_seq(lead, <<lead, b, c, d, _rest::binary>>)
       when lead in 0xF1..0xF3 and b in 0x80..0xBF and c in 0x80..0xBF and d in 0x80..0xBF,
       do: {:ok, 4}

  defp utf8_seq(lead, <<lead, b, c, d, _rest::binary>>)
       when lead == 0xF4 and b in 0x80..0x8F and c in 0x80..0xBF and d in 0x80..0xBF,
       do: {:ok, 4}

  defp utf8_seq(_lead, _slice), do: :bad

  defp read_escape(input, pos, path, acc) do
    if pos >= byte_size(input) do
      {:halt, {:unterminated_literal, path, "incomplete string escape"}}
    else
      case :binary.at(input, pos) do
        ?u -> read_unicode_escape(input, pos + 1, path, acc)
        byte -> simple_escape(byte, input, pos + 1, path, acc)
      end
    end
  end

  defp simple_escape(byte, input, npos, path, acc) do
    case escape_decode(byte) do
      :invalid -> {:halt, {:invalid_string, path, "invalid escape character"}}
      char -> read_string_rest(input, npos, path, [char | acc])
    end
  end

  defp escape_decode(0x22), do: 0x22
  defp escape_decode(0x5C), do: 0x5C
  defp escape_decode(?/), do: ?/
  defp escape_decode(?n), do: 0x0A
  defp escape_decode(?r), do: 0x0D
  defp escape_decode(?t), do: 0x09
  defp escape_decode(?b), do: 0x08
  defp escape_decode(?f), do: 0x0C
  defp escape_decode(_byte), do: :invalid

  defp read_unicode_escape(input, hex0, path, acc) do
    with {:ok, high, next} <- hex4(input, hex0, path) do
      cond do
        high in 0xD800..0xDBFF -> require_low_surrogate(input, next, path, acc, high)
        high in 0xDC00..0xDFFF -> {:halt, {:invalid_string, path, "lone surrogate"}}
        true -> read_string_rest(input, next, path, [<<high::utf8>> | acc])
      end
    end
  end

  defp require_low_surrogate(input, next, path, acc, high) do
    if surrogate_pair?(input, next) do
      {:ok, low, lpos} = hex4(input, next + 2, path)
      cp = 0x10000 + (high - 0xD800) * 0x400 + (low - 0xDC00)
      read_string_rest(input, lpos, path, [<<cp::utf8>> | acc])
    else
      {:halt, {:invalid_string, path, "lone or invalid surrogate"}}
    end
  end

  defp surrogate_pair?(input, next) do
    next + 1 < byte_size(input) and :binary.at(input, next) == 0x5C and
      :binary.at(input, next + 1) == ?u and
      match?({:ok, low, _} when low in 0xDC00..0xDFFF, hex4_unsafe(input, next + 2))
  end

  defp hex4_unsafe(input, pos) do
    if pos + 4 <= byte_size(input) do
      hex = binary_part(input, pos, 4)

      if hex?(hex), do: {:ok, String.to_integer(hex, 16), pos + 4}, else: :invalid_hex
    else
      :invalid_hex
    end
  end

  defp hex4(input, pos, path) do
    if pos + 4 > byte_size(input) do
      {:halt, {:unterminated_literal, path, "incomplete unicode escape"}}
    else
      hex = binary_part(input, pos, 4)

      if hex?(hex) do
        {:ok, String.to_integer(hex, 16), pos + 4}
      else
        {:halt, {:invalid_string, path, "invalid unicode escape"}}
      end
    end
  end

  defp hex?(hex), do: Regex.match?(~r/\A[0-9A-Fa-f]{4}\z/, hex)

  # ---------------------------------------------------------------------------
  # Parser: Zahlen (JSON-Grammatik, führende Pluszeichen/NaN/Infinity abgewiesen)
  # ---------------------------------------------------------------------------

  defp read_number(input, pos, path) do
    run_end = scan_number_run(input, pos)
    raw = binary_part(input, pos, run_end - pos)
    decode_number_raw(raw, path, run_end)
  end

  defp scan_number_run(input, pos) do
    size = byte_size(input)
    scan_number_run(input, pos, size, pos)
  end

  defp scan_number_run(input, pos, size, run_end) do
    if pos < size and number_byte?(:binary.at(input, pos)) do
      scan_number_run(input, pos + 1, size, run_end + 1)
    else
      run_end
    end
  end

  defp number_byte?(byte), do: byte in ?0..?9 or byte in [?-, ?+, ?., ?e, ?E]

  defp decode_number_raw(raw, path, end_pos) do
    if Regex.match?(@number_re, raw) do
      decode_number_value(raw, path, end_pos)
    else
      {:halt, {:invalid_number, path, "number does not match the JSON grammar"}}
    end
  end

  defp decode_number_value(raw, path, end_pos) do
    if String.contains?(raw, ".") or String.contains?(raw, ["e", "E"]) do
      make_float(raw, path, end_pos)
    else
      {:ok, String.to_integer(raw), end_pos}
    end
  end

  defp make_float(raw, path, end_pos) do
    case float_of(raw) do
      {:ok, value} -> {:ok, value, end_pos}
      :error -> {:halt, {:invalid_number, path, "invalid or non-finite float"}}
    end
  end

  defp float_of(raw) do
    normalized = normalize_float(raw)

    try do
      {:ok, :erlang.binary_to_float(normalized)}
    rescue
      ArgumentError -> :error
    end
  end

  defp normalize_float(raw) do
    if String.contains?(raw, ".") do
      raw
    else
      lower_e = String.replace(raw, "E", "e")

      case String.split(lower_e, "e", parts: 2) do
        [mantissa, exponent] -> mantissa <> ".0" <> "e" <> exponent
        [mantissa] -> mantissa <> ".0"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Kanonischer Encoder
  # ---------------------------------------------------------------------------

  defp encode_value(nil, _depth), do: "null"
  defp encode_value(true, _depth), do: "true"
  defp encode_value(false, _depth), do: "false"
  defp encode_value(value, _depth) when is_integer(value), do: Integer.to_string(value)
  defp encode_value(value, _depth) when is_float(value), do: Float.to_string(value)
  defp encode_value(value, _depth) when is_binary(value), do: encode_string(value)
  defp encode_value(value, depth) when is_list(value), do: encode_list(value, depth)
  defp encode_value(value, depth) when is_map(value), do: encode_map(value, depth)

  defp encode_list([], _depth), do: "[]"

  defp encode_list(items, depth) do
    ["[\n", encode_items(items, depth + 1), "\n", pad(depth), "]"]
  end

  defp encode_items([item], depth), do: [pad(depth), encode_value(item, depth)]

  defp encode_items([item | rest], depth) do
    [pad(depth), encode_value(item, depth), ",\n", encode_items(rest, depth)]
  end

  defp encode_map(%{} = value, _depth) when map_size(value) == 0, do: "{}"

  defp encode_map(%{} = value, depth) do
    keys = Enum.sort(Map.keys(value))
    entries = canonical_entries(value, keys, depth)

    ["{\n", join_entries(entries, depth + 1), "\n", pad(depth), "}"]
  end

  defp canonical_entries(_value, [], _depth), do: []

  defp canonical_entries(value, [key | rest], depth) when is_binary(key) do
    entry = [encode_string(key), ": ", encode_value(Map.fetch!(value, key), depth + 1)]
    [entry | canonical_entries(value, rest, depth)]
  end

  defp canonical_entries(_value, [key | _rest], _depth) do
    raise ArgumentError, "non-string map key cannot be canonicalized: #{inspect(key)}"
  end

  defp join_entries([entry], depth), do: [pad(depth), entry]

  defp join_entries([entry | rest], depth) do
    [pad(depth), entry, ",\n", join_entries(rest, depth)]
  end

  defp pad(depth), do: List.duplicate("  ", depth)

  defp encode_string(value) when is_binary(value) do
    [?", escaped_bytes(value), ?"]
  end

  defp escaped_bytes(value), do: escaped_bytes(value, [])

  defp escaped_bytes(<<>>, acc), do: acc

  defp escaped_bytes(<<byte, rest::binary>>, acc) do
    case Map.get(@escape_map, byte) do
      nil when byte < 0x20 ->
        hex4 = String.pad_leading(Integer.to_string(byte, 16), 4, "0")
        escaped_bytes(rest, [acc, "\\u", hex4])

      nil ->
        escaped_bytes(rest, [acc, byte])

      escape ->
        escaped_bytes(rest, [acc, escape])
    end
  end
end
