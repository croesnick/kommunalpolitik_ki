# Fake-komki-tresor fuer die Tests: rundreisefaehig wie das echte Programm
# (eine Zeile stdin, eine Zeile stdout, Exit 0/2/5), aber ohne Secure Enclave
# und ohne Touch ID. Das Siegel ist hier base64(nonce <> chiffretext <> tag)
# desselben hartkodierten AES-256-GCM-Schluessels, den open wieder anwendet —
# verhaltenstreu, nicht formatkompatibel; das genuegt, weil ris_kassetten das
# Praefix ktv1. nur als Label prueft. Aufgerufen nur aus
# ris_kassetten_test.exs ueber einen Shell-Wrapper.

key = :crypto.hash(:sha256, "ris-kassetten-fake")
aad = "rkt1-fake"

read_line = fn ->
  case IO.read(:stdio, :line) do
    line when is_binary(line) -> String.trim_trailing(line)
    :eof -> ""
  end
end

fail = fn code, msg ->
  IO.puts(:stderr, "fake-tresor: #{msg}")
  System.halt(code)
end

seal = fn line ->
  nonce = :crypto.strong_rand_bytes(12)
  {ct, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, line, aad, true)
  IO.puts("ktv1." <> Base.encode64(nonce <> ct <> tag))
end

open = fn text ->
  with "ktv1." <> b64 <- text,
       {:ok, blob} <- Base.decode64(b64),
       true <- byte_size(blob) > 12 + 16 do
    nonce = binary_part(blob, 0, 12)
    tag_start = byte_size(blob) - 16
    ct = binary_part(blob, 12, tag_start - 12)
    tag = binary_part(blob, tag_start, 16)

    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, ct, aad, tag, false) do
      plain when is_binary(plain) -> IO.puts(plain)
      _korrupt -> fail.(5, "Siegel ungueltig")
    end
  else
    _ -> fail.(5, "Siegel ungueltig")
  end
end

case System.argv() do
  ["check"] ->
    :ok

  ["seal"] ->
    line = read_line.()
    if line == "", do: fail.(2, "erwartet genau eine nicht leere Zeile auf stdin")
    seal.(line)

  ["open", "--reason", reason] when reason != "" ->
    line = read_line.()
    open.(line)

  _other ->
    fail.(2, "Aufruf: check | seal | open --reason <text>")
end
