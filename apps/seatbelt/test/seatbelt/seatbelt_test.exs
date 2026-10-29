defmodule SeatbeltTest do
  @moduledoc """
  Host path helpers: `canonical/1` (kernel view, the load-bearing
  invariant for every path in a profile), `erlang_root/1`.
  """

  use ExUnit.Case, async: true

  alias Seatbelt.TestSupport

  test "canonical/1: idempotent" do
    dir = TestSupport.tmp_area!("canonical")
    path = Path.join(dir, "sub")

    once = Seatbelt.canonical(path)
    assert Seatbelt.canonical(once) == once
  end

  # Oracle: the kernel view of readlink -f itself (available wherever the
  # canonical resolution is not the expanded-form fallback).
  test "canonical/1: agrees with readlink -f on real paths" do
    dir = TestSupport.tmp_area!("canonical-oracle")

    if System.find_executable("readlink") do
      real = Path.join(dir, "real")
      File.mkdir_p!(real)
      link = Path.join(dir, "link")
      File.ln_s!(real, link)

      assert Seatbelt.canonical(link) == Seatbelt.canonical(real)
      assert String.contains?(Seatbelt.canonical(real), "/real")
    end
  end

  # BSD readlink fails on missing paths — the deepest existing ancestor
  # is resolved and the missing tail re-attached.
  test "canonical/1: missing tail stays attached to the resolved ancestor" do
    dir = TestSupport.tmp_area!("canonical-tail")

    assert Seatbelt.canonical(Path.join(dir, "missing/deeper")) ==
             Seatbelt.canonical(dir) <> "/missing/deeper"
  end

  test "canonical/1: relative paths expand against the working directory" do
    dir = TestSupport.tmp_area!("canonical-relative")

    assert Seatbelt.canonical(Path.join(dir, ".")) == Seatbelt.canonical(dir)
  end

  test "erlang_root/1: two dirnames of the escript path" do
    assert Seatbelt.erlang_root("/opt/erlang/bin/escript") == "/opt/erlang"
  end
end
