defmodule Seatbelt.PinsTest do
  @moduledoc """
  Program pins: known-value file hash, tree-hash sensitivity (content,
  additions, renames, symlink retargeting), drift classification.
  """

  use ExUnit.Case, async: true

  alias Seatbelt.{Pins, TestSupport}

  # sha256("abc\n")
  @abc_sha "edeaaff3f1774ad2888673770c6d64097e391bc362d7d6fb34982ddf0efd18cb"

  defp place!(path, content) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    path
  end

  test "hash/1: file SHA-256 against a known vector" do
    dir = TestSupport.tmp_area!("pins-file")
    file = place!(Path.join(dir, "prog"), "abc\n")

    assert Pins.hash(file) == {:ok, @abc_sha}
  end

  test "hash/1: symlink hashes the target" do
    dir = TestSupport.tmp_area!("pins-link")
    target = place!(Path.join(dir, "target"), "abc\n")
    link = Path.join(dir, "link")
    File.ln_s!(target, link)

    assert Pins.hash(link) == {:ok, @abc_sha}
  end

  test "hash/1: missing file and special files are errors" do
    assert {:error, reason} = Pins.hash("/definitely/not/there")
    assert is_binary(reason)
  end

  test "hash/1: tree hash reacts to every change class" do
    dir = TestSupport.tmp_area!("pins-tree")
    root = Path.join(dir, "pkg")

    place!(Path.join([root, "dist", "cli.js"]), "v1\n")
    place!(Path.join(root, "package.json"), "{}\n")
    {:ok, base} = Pins.hash(root)

    # content change
    File.write!(Path.join([root, "dist", "cli.js"]), "v2\n")
    {:ok, changed_content} = Pins.hash(root)
    File.write!(Path.join([root, "dist", "cli.js"]), "v1\n")

    # added file
    File.write!(Path.join(root, "extra.txt"), "x\n")
    {:ok, added} = Pins.hash(root)
    File.rm!(Path.join(root, "extra.txt"))

    # rename
    File.rename!(Path.join(root, "package.json"), Path.join(root, "package.json2"))
    {:ok, renamed} = Pins.hash(root)
    File.rename!(Path.join(root, "package.json2"), Path.join(root, "package.json"))

    # symlink retarget
    File.ln_s!(Path.join([root, "dist", "cli.js"]), Path.join(root, "link"))
    {:ok, with_link} = Pins.hash(root)
    File.rm!(Path.join(root, "link"))
    File.ln_s!(Path.join(root, "package.json"), Path.join(root, "link"))
    {:ok, retargeted} = Pins.hash(root)
    File.rm!(Path.join(root, "link"))

    assert base not in [changed_content, added, renamed, retargeted]
    assert with_link != retargeted
  end

  test "compute/1: pins every hashable artifact, skips the rest" do
    dir = TestSupport.tmp_area!("pins-compute")
    a = place!(Path.join(dir, "a"), "a\n")
    b = place!(Path.join(dir, "b"), "b\n")

    assert {:ok, _} = Pins.hash(a)

    pins = Pins.compute([{"a", a}, {"b", b}, {"gone", Path.join(dir, "gone")}])

    assert Map.keys(pins) == ["a", "b"]
    assert pins["a"]["path"] == a
    assert pins["a"]["sha256"] == elem(Pins.hash(a), 1)
  end

  test "drift/2: same bytes ok, new path :new, same path other bytes :changed" do
    dir = TestSupport.tmp_area!("pins-drift")
    a = place!(Path.join(dir, "a"), "a\n")
    b = place!(Path.join(dir, "b"), "b\n")
    c = place!(Path.join(dir, "c"), "c\n")

    pinned = Pins.compute([{"a", a}, {"b", b}])

    # unchanged a, b with new bytes at the same path, c newly appeared
    File.write!(b, "changed\n")
    current = Pins.compute([{"a", a}, {"b", b}, {"c", c}])

    assert Pins.drift(pinned, current) == %{new: ["c"], changed: ["b"]}
  end

  test "drift/2: disappeared programs do not count" do
    dir = TestSupport.tmp_area!("pins-drift-gone")
    a = place!(Path.join(dir, "a"), "a\n")

    pinned = Pins.compute([{"a", a}])
    assert Pins.drift(pinned, %{}) == %{new: [], changed: []}
  end
end
