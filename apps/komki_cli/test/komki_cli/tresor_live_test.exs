defmodule KomkiCli.TresorLiveTest do
  @moduledoc """
  Live counter-check of the real Touch ID path (ticket #337): seals a canary
  with the real `komki-tresor` and opens it again. Sealing asks nothing, so a
  passing run shows exactly one prompt, the one for opening.

  Tagged `:touch_id` and excluded from every standard run (`test_helper.exs`):
  no `mix test` and no CI run may raise a prompt. Run it on a Mac before a
  release, from a checkout where `mix compile` built `priv/komki-tresor`:

      cd apps/komki_cli && mix test --include touch_id

  The test uses only the program from this checkout's priv directory: neither
  the fake tresor that `test_helper.exs` installs nor a `komki-tresor` on
  PATH. It writes nothing to the keychain: the key exists only inside the
  seal. The list of paths that need real hardware lives in
  `docs/echte-hardware.md`.
  """

  use ExUnit.Case, async: false

  @moduletag :touch_id
  # Leaves room for Touch ID or the password; the program waits two minutes.
  @moduletag timeout: 180_000

  alias KomkiCli.Tresor.Core

  test "seals and opens a canary through the Secure Enclave" do
    command = Path.join(:code.priv_dir(:komki_cli), "komki-tresor")

    assert File.exists?(command),
           "komki-tresor fehlt in apps/komki_cli/priv (mix compile, swiftc prüfen)"

    assert Core.check(command) == :ok

    canary = "komki-live-canary-" <> Base.encode16(:crypto.strong_rand_bytes(8))

    assert {:ok, sealed} = Core.seal(canary, command: command)
    assert Core.sealed?(sealed)
    refute String.contains?(sealed, canary)

    assert {:ok, ^canary} =
             Core.open(sealed, "komki Live-Gegenprobe: Test-Siegel öffnen", command: command)
  end
end
