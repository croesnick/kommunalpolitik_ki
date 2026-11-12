defmodule Ratsprojekte.Betrieb do
  @moduledoc """
  Helpers for the tests of local operation (#440): a throwaway home, the
  file test double in place of the Secure Enclave, a running lock.
  """

  import ExUnit.Callbacks

  alias Ratsprojekte.{Schluessel, Sperre}
  alias SealedEnvelope.KeyAgreement.FileTestDouble

  @migrationen Path.expand("../fixtures/migrationen", __DIR__)

  @doc """
  A fresh home; short, because Unix socket paths are limited to 104 bytes
  (so no ExUnit `tmp_dir`). The name is random, not a counter: counters
  restart with every VM and would meet a home a killed run left behind,
  or one a parallel run in another worktree is using (#452). `mkdir!`
  fails rather than reuse a directory that exists.
  """
  def home! do
    suffix = Base.hex_encode32(:crypto.strong_rand_bytes(10), case: :lower, padding: false)
    home = Path.join(System.tmp_dir!(), "rp-" <> suffix)
    File.mkdir!(home)
    Ratsprojekte.Ort.anlegen!(home)
    on_exit(fn -> File.rm_rf!(home) end)
    home
  end

  def provider(home), do: {FileTestDouble, path: Path.join(home, "enclave.key")}

  @doc "Seal a fresh key under `home`, as `ratsprojekte einrichten` does."
  def eingerichtet!(home) do
    key = Schluessel.neu()
    :ok = Schluessel.versiegeln(key, home, provider(home))
    key
  end

  @doc "Migrations dir with the first `n` fixture migrations."
  def migrationen!(home, n) do
    dir = Path.join(home, "migrationen")
    File.mkdir_p!(dir)

    @migrationen
    |> File.ls!()
    |> Enum.sort()
    |> Enum.take(n)
    |> Enum.each(&File.cp!(Path.join(@migrationen, &1), Path.join(dir, &1)))

    dir
  end

  @doc """
  A lock on `home` with its own repo supervisor; returns its pid. `name:`
  registers it (the web layer calls the default name).
  """
  def sperre!(home, opts \\ []) do
    sup = start_supervised!({DynamicSupervisor, strategy: :one_for_one}, id: make_ref())

    start_supervised!(
      {Sperre,
       name: Keyword.get(opts, :name),
       home: home,
       provider: provider(home),
       sperre_nach: Keyword.get(opts, :sperre_nach, 60_000),
       repo: Ratsprojekte.BetriebRepo,
       repo_supervisor: sup,
       migrationen: Keyword.get_lazy(opts, :migrationen, fn -> migrationen!(home, 1) end)},
      id: make_ref()
    )
  end
end
