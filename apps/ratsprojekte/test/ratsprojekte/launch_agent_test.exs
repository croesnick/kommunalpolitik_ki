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
  test "plist ist gültig für launchd (plutil)" do
    path = Path.join(System.tmp_dir!(), "rp-plist-#{System.unique_integer([:positive])}.plist")
    File.write!(path, LaunchAgent.plist("/opt/rel", [{"PHX_SERVER", "true"}]))
    assert {_, 0} = System.cmd("/usr/bin/plutil", ["-lint", path])
    File.rm!(path)
  end
end
