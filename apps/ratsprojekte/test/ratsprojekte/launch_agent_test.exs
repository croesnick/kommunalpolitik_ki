defmodule Ratsprojekte.LaunchAgentTest do
  use ExUnit.Case, async: true

  alias Ratsprojekte.LaunchAgent

  test "plist startet das Release, nach Absturz neu, mit maskierten Werten" do
    plist =
      LaunchAgent.plist("/opt/rel & co", [{"PHX_SERVER", "true"}, {"RATSPROJEKTE_HOME", "/a<b>"}])

    assert plist =~ "<string>ratsprojekte.hub</string>"

    assert plist =~
             "<string>/opt/rel &amp; co/bin/ratsprojekte</string>\n    <string>start</string>"

    assert plist =~ "<key>RATSPROJEKTE_HOME</key>\n    <string>/a&lt;b&gt;</string>"
    assert plist =~ "<key>SuccessfulExit</key>\n    <false/>"
    assert plist =~ LaunchAgent.logdatei()
  end

  # plutil exists only on macOS; the CI runs on Linux.
  @tag :macos
  @tag :tmp_dir
  test "plist ist gültig für launchd (plutil)", %{tmp_dir: dir} do
    path = Path.join(dir, "ratsprojekte.plist")
    File.write!(path, LaunchAgent.plist("/opt/rel", [{"PHX_SERVER", "true"}]))
    assert {_, 0} = System.cmd("/usr/bin/plutil", ["-lint", path])
  end
end
