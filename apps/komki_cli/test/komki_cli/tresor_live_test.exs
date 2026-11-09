defmodule KomkiCli.TresorLiveTest do
  @moduledoc """
  Live counter-check of the real Touch ID path (ticket #337): seals a canary
  with the real `komki-tresor` and opens it again. Sealing asks nothing, so a
  passing run shows exactly one prompt, the one for opening.

  Tagged `:live` and excluded from every standard run (`test_helper.exs`): no
  `mix test` and no CI run may raise a prompt. Run it on a Mac before a
  release, from a checkout where `mix compile` built `priv/komki-tresor`:

      cd apps/komki_cli && mix test --include live

  The test talks to the real program directly and bypasses the fake tresor
  that `test_helper.exs` installs for all other tests. It writes nothing to
  the keychain: the key exists only inside the seal. The list of paths that
  need real hardware lives in `docs/echte-hardware.md`.
  """

  use ExUnit.Case, async: false

  @moduletag :live
  # Leaves room for Touch ID or the password; the program waits two minutes.
  @moduletag timeout: 180_000

  alias KomkiCli.Tresor
  alias KomkiCli.Tresor.Core

  test "seals and opens a canary through the Secure Enclave" do
    command = Core.binary(:komki_cli)

    assert is_binary(command),
           "komki-tresor fehlt in apps/komki_cli/priv (mix compile, swiftc pruefen)"

    assert Core.check(command) == :ok

    canary = "komki-live-canary-" <> Base.encode16(:crypto.strong_rand_bytes(8))

    assert {:ok, sealed} = Tresor.seal(canary, command: command)
    assert Tresor.sealed?(sealed)
    refute String.contains?(sealed, canary)

    assert {:ok, ^canary} =
             Tresor.open(sealed, "komki Live-Gegenprobe: Test-Siegel öffnen", command: command)
  end
end
