# Fake komki-tresor for tests: speaks the real program's protocol (one line
# on stdin, one line on stdout, exit 0/2/5) with real P-256 ECDH, but without
# a Secure Enclave and without a prompt. The key reference is the private key
# itself, so the fake needs no state. It proves the point of the real program
# as well: it never sees plaintext.

curve = :secp256r1

fail = fn code, message ->
  IO.puts(:stderr, "fake-tresor: " <> message)
  System.halt(code)
end

case System.argv() do
  ["check"] ->
    :ok

  ["recipient"] ->
    {public, private} = :crypto.generate_key(:ecdh, curve)
    IO.puts(Base.encode64(private) <> " " <> Base.encode64(public))

  ["agree", "--reason", reason] when reason != "" ->
    with line when is_binary(line) <- IO.read(:stdio, :line),
         [ref, peer] <- line |> String.trim_trailing() |> String.split(" "),
         {:ok, private} <- Base.decode64(ref),
         {:ok, peer} <- Base.decode64(peer) do
      shared =
        try do
          :crypto.compute_key(:ecdh, peer, private, curve)
        rescue
          ErlangError -> fail.(5, "Schluessel ungueltig")
        end

      IO.puts(Base.encode64(shared))
    else
      _ -> fail.(5, "Schluessel ungueltig")
    end

  _other ->
    fail.(2, "Aufruf: check | recipient | agree --reason <text>")
end
