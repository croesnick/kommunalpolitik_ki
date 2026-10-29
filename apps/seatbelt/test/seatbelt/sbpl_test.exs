defmodule Seatbelt.SBPLTest do
  @moduledoc """
  Byte-exact emitter contracts, composition helpers, and the
  metadata-ancestor unification (the two pre-library implementations must
  produce the same lines — the expected values below are hand-derived
  from both).
  """

  use ExUnit.Case, async: true

  alias Seatbelt.SBPL

  test "emitters: byte-exact rule lines" do
    assert SBPL.comment("note") == "; note"
    assert SBPL.read_literal("/a/b") == "(allow file-read* (literal \"/a/b\"))"
    assert SBPL.read_subpath("/a") == "(allow file-read* (subpath \"/a\"))"
    assert SBPL.write_literal("/a/b") == "(allow file-write* (literal \"/a/b\"))"
    assert SBPL.write_subpath("/a") == "(allow file-write* (subpath \"/a\"))"

    assert SBPL.read_write_literal("/a/log") ==
             "(allow file-read* file-write* (literal \"/a/log\"))"

    assert SBPL.exec_literal("/bin/sh") == "(allow process-exec (literal \"/bin/sh\"))"
    assert SBPL.exec_star_literal("/bin/sh") == "(allow process-exec* (literal \"/bin/sh\"))"
    assert SBPL.metadata_literal("/var") == "(allow file-read-metadata (literal \"/var\"))"
    assert SBPL.sysctl("hw.ncpu") == "(allow sysctl-read (sysctl-name \"hw.ncpu\"))"
    assert SBPL.sysctl_prefix("hw.") == "(allow sysctl-read (sysctl-name-prefix \"hw.\"))"

    assert SBPL.mach_lookup("com.apple.logd") ==
             "(allow mach-lookup (global-name \"com.apple.logd\"))"

    assert SBPL.ipc_posix_shm("apple.shm.notification_center") ==
             "(allow ipc-posix-shm (ipc-posix-name \"apple.shm.notification_center\"))"
  end

  test "header/1: comments, version, deny default" do
    assert SBPL.header(["one", "two"]) == [
             "; one",
             "; two",
             "(version 1)",
             "(deny default)"
           ]
  end

  test "render/1: deduplicates keeping first occurrence, one trailing newline" do
    assert SBPL.render([
             "(allow file-read* (literal \"/a\"))",
             "(allow file-read* (literal \"/a\"))"
           ]) ==
             "(allow file-read* (literal \"/a\"))\n"
  end

  # Both pre-library implementations (a MapSet variant and an Enum.uniq
  # variant) yield exactly this: every ancestor prefix, sorted, deduped,
  # "/" always included.
  test "metadata_ancestors/1: every ancestor, sorted, deduped, rooted" do
    assert SBPL.metadata_ancestors([
             "/opt/erl/lib/crypto-1.0/priv/lib",
             "/private/var/run/sock",
             "/tmp",
             "/tmp"
           ]) == [
             "(allow file-read-metadata (literal \"/\"))",
             "(allow file-read-metadata (literal \"/opt\"))",
             "(allow file-read-metadata (literal \"/opt/erl\"))",
             "(allow file-read-metadata (literal \"/opt/erl/lib\"))",
             "(allow file-read-metadata (literal \"/opt/erl/lib/crypto-1.0\"))",
             "(allow file-read-metadata (literal \"/opt/erl/lib/crypto-1.0/priv\"))",
             "(allow file-read-metadata (literal \"/opt/erl/lib/crypto-1.0/priv/lib\"))",
             "(allow file-read-metadata (literal \"/private\"))",
             "(allow file-read-metadata (literal \"/private/var\"))",
             "(allow file-read-metadata (literal \"/private/var/run\"))",
             "(allow file-read-metadata (literal \"/private/var/run/sock\"))",
             "(allow file-read-metadata (literal \"/tmp\"))"
           ]
  end

  test "metadata_ancestors/1: root-only input yields just the root" do
    assert SBPL.metadata_ancestors(["/"]) == ["(allow file-read-metadata (literal \"/\"))"]
  end

  # Library policy: every emitted byte is ASCII (English comments included) —
  # profile bytes are part of consumer identity, so no umlauts may creep in.
  test "all emitted library text is ASCII" do
    surfaces = [
      Seatbelt.SBPL.render(Seatbelt.Preset.macos_exec_boot()),
      Seatbelt.SBPL.render(Seatbelt.Preset.escript_boot()),
      Seatbelt.SBPL.render(Seatbelt.Preset.tui()),
      Seatbelt.SBPL.render(Seatbelt.Escript.runtime("/opt/erl", "/opt/app/tool.escript")),
      Seatbelt.SBPL.render(Seatbelt.Escript.log_rules("/opt/log")),
      Seatbelt.SBPL.render(
        Seatbelt.Escript.runtime_for("/opt/erl", "/opt/app/tool.escript", %{
          wrapper: "/opt/app/tool",
          runtime_root: "/opt/app/runtime"
        })
      )
    ]

    for text <- surfaces do
      assert Enum.all?(String.to_charlist(text), &(&1 < 128)), inspect(text)
    end
  end
end
