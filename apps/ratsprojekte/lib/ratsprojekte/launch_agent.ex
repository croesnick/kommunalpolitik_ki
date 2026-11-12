defmodule Ratsprojekte.LaunchAgent do
  @moduledoc """
  The LaunchAgent that starts the release at login (ADR 0004). It starts
  locked; unlocking stays with `ratsprojekte open`, so no background service
  asks for Touch ID without it being clear who asks. launchd restarts the
  hub after a crash (`KeepAlive` on unsuccessful exit), not after a regular
  stop.
  """

  @label "ratsprojekte.hub"

  @spec label() :: String.t()
  def label, do: @label

  @spec pfad() :: String.t()
  def pfad, do: Path.join(System.user_home!(), "Library/LaunchAgents/#{@label}.plist")

  @spec logdatei() :: String.t()
  def logdatei, do: Path.join(System.user_home!(), "Library/Logs/ratsprojekte/hub.log")

  @doc "The property list for the release at `root`; `env` is passed to the hub."
  @spec plist(String.t(), [{String.t(), String.t()}]) :: String.t()
  def plist(root, env) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>#{@label}</string>
      <key>ProgramArguments</key>
      <array>
        <string>#{xml(Path.join(root, "bin/ratsprojekte"))}</string>
        <string>start</string>
      </array>
      <key>EnvironmentVariables</key>
      <dict>
    #{Enum.map_join(env, "\n", fn {k, v} -> "    <key>#{xml(k)}</key>\n    <string>#{xml(v)}</string>" end)}
      </dict>
      <key>RunAtLoad</key>
      <true/>
      <key>KeepAlive</key>
      <dict>
        <key>SuccessfulExit</key>
        <false/>
      </dict>
      <key>StandardOutPath</key>
      <string>#{xml(logdatei())}</string>
      <key>StandardErrorPath</key>
      <string>#{xml(logdatei())}</string>
    </dict>
    </plist>
    """
  end

  @doc "Write the plist and load it into the user's GUI domain."
  @spec an(String.t(), [{String.t(), String.t()}]) :: :ok | {:error, String.t()}
  def an(root, env) do
    File.mkdir_p!(Path.dirname(logdatei()))
    File.mkdir_p!(Path.dirname(pfad()))
    _ = launchctl(["bootout", domain() <> "/" <> @label])
    weg(40)
    File.write!(pfad(), plist(root, env))
    launchctl(["bootstrap", domain(), pfad()])
  end

  # bootout returns before launchd has removed the service; a bootstrap in
  # that window fails with "Bootstrap failed: 5". Wait until it is gone.
  defp weg(0), do: :ok

  defp weg(n) do
    case launchctl(["print", domain() <> "/" <> @label]) do
      :ok ->
        Process.sleep(250)
        weg(n - 1)

      {:error, _} ->
        :ok
    end
  end

  @doc "Unload and remove the plist."
  @spec aus() :: :ok | {:error, String.t()}
  def aus do
    result = launchctl(["bootout", domain() <> "/" <> @label])
    _ = File.rm(pfad())
    result
  end

  defp domain do
    {uid, 0} = System.cmd("/usr/bin/id", ["-u"])
    "gui/" <> String.trim(uid)
  end

  defp launchctl(args) do
    case System.cmd("/bin/launchctl", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {out, code} -> {:error, "launchctl #{hd(args)} (exit #{code}): #{String.trim(out)}"}
    end
  end

  defp xml(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
