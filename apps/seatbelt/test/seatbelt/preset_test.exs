defmodule Seatbelt.PresetTest do
  @moduledoc """
  Pinned rule layers: the campaign-validated lines must stay, the
  dangerous broad forms must not appear, and the documented difference
  between the two boot presets must hold.
  """

  use ExUnit.Case, async: true

  alias Seatbelt.Preset

  test "macos_exec_boot/0: campaign-pinned lines stay" do
    rules = Preset.macos_exec_boot()

    assert "(allow sysctl-read (sysctl-name \"security.mac.lockdown_mode_state\"))" in rules
    assert "(allow file-read-data (literal \"/\"))" in rules

    assert "(allow file-read* file-test-existence file-write-data file-ioctl (literal \"/dev/dtracehelper\"))" in rules

    assert "(allow system-info (info-type \"vfs.disk-space\"))" in rules
  end

  test "macos_exec_boot/0: no broad forms, no asdf coupling" do
    rules = Enum.join(Preset.macos_exec_boot(), "\n")

    refute rules =~ "(allow default)"
    refute rules =~ "asdf"
  end

  test "escript_boot/0: adds the BEAM boot extras over macos_exec_boot" do
    escript = Preset.escript_boot()

    # The documented difference (see Preset moduledoc): these lines exist
    # only in the escript campaign layer.
    assert "(allow file-read-metadata (literal \"/System/Volumes/Data\"))" in escript
    assert "(allow file-write* (literal \"/dev/null\"))" in escript
    assert "(allow file-read* (subpath \"/System/Library\"))" in escript

    refute "(allow file-read-metadata (literal \"/System/Volumes/Data\"))" in Preset.macos_exec_boot()
    refute "(allow file-write* (literal \"/dev/null\"))" in Preset.macos_exec_boot()
  end

  test "escript_boot/0: both boot layers share the dtracehelper grant" do
    grant =
      "(allow file-read* file-test-existence file-write-data file-ioctl (literal \"/dev/dtracehelper\"))"

    assert grant in Preset.macos_exec_boot()
    assert grant in Preset.escript_boot()
  end

  test "tui/0: terminal class rules, scoped" do
    rules = Preset.tui()

    assert "(allow file-ioctl (literal \"/dev/tty\"))" in rules
    assert "(allow pseudo-tty)" in rules
    assert "(allow process-info* (target same-sandbox))" in rules
    assert "(allow signal (target same-sandbox))" in rules
    assert "(allow sysctl-read (sysctl-name-prefix \"hw.\"))" in rules
    assert "(allow sysctl-read (sysctl-name-prefix \"kern.proc.\"))" in rules
  end

  test "tui/0: no unscoped mach-lookup, no network, no allow-default" do
    text = Enum.join(Preset.tui(), "\n")

    refute text =~ "(allow default)"
    refute text =~ "mach-lookup"
    refute text =~ "network-"
    # stdio plumbing of a specific launcher is caller knowledge
    refute text =~ "/dev/fd/0"
  end
end
