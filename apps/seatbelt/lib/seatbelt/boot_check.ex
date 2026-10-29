defmodule Seatbelt.BootCheck do
  @moduledoc """
  Boot gate: run a probe program under a generated sandbox profile and
  report whether it boots.

  `sandbox-exec` on recent macOS builds has a documented instability
  class for deny-default profiles (sporadic spawn failures without a
  visible Seatbelt denial). The positive control is therefore to execute
  every profile once under `sandbox-exec` *before* the real run — a
  profile that fails to boot its probe is a hard stop, regardless of
  what the denial log says. Silence in the log is not a confinement
  proof; the boot check is.

  The check runs the probe with a minimal environment
  (`PATH=/usr/bin:/bin`) and merges stderr into stdout so probe chatter
  lands in the reason excerpt instead of the caller's output.
  """

  @doc """
  Run `binary args…` under `sandbox_exec -f profile`.

  Options:

    * `:cwd` — working directory for the probe. The probe's working
      directory must be inside the profile's allowed area: a child
      inheriting a denied directory fails its first `getcwd()` and sh
      reports "shell-init: error retrieving current directory". When
      the profile does not allow any directory of the caller's choice,
      pass a directory the profile explicitly allows (e.g. `"/"` when
      the profile allows reading `/`).

  Returns `%{ok: boolean(), reason: String.t()}` — `reason` is `"rc0"`
  on success, `"rc=<code> <excerpt>"` (first 200 chars) on a non-zero
  exit, or `"exec error …"` when `sandbox-exec` could not be run at
  all.
  """
  @spec run(String.t(), String.t(), String.t(), [String.t()], Keyword.t()) :: %{
          ok: boolean(),
          reason: String.t()
        }
  def run(sandbox_exec, profile_path, binary, args, opts \\ []) do
    cmd_opts = [env: %{"PATH" => "/usr/bin:/bin"}, stderr_to_stdout: true]

    # cd: nil would pass an invalid opt to System.cmd; without :cd the
    # probe inherits the caller's working directory (the komki wrapper
    # always passes an allowed cwd).
    cmd_opts =
      case Keyword.get(opts, :cwd) do
        nil -> cmd_opts
        cwd -> Keyword.put(cmd_opts, :cd, cwd)
      end

    {ok, reason} =
      try do
        case System.cmd(sandbox_exec, ["-f", profile_path, "--", binary] ++ args, cmd_opts) do
          {_out, 0} -> {true, "rc0"}
          {out, code} -> {false, rc_reason(code, out)}
        end
      rescue
        e -> {false, "exec error: " <> Exception.message(e)}
      catch
        kind, thrown ->
          {false, "exec error " <> Kernel.inspect(kind) <> ": " <> Kernel.inspect(thrown)}
      end

    %{ok: ok, reason: reason}
  end

  defp rc_reason(code, out) do
    excerpt = out |> String.trim_trailing() |> String.slice(0, 200)
    "rc=" <> to_string(code) <> " " <> excerpt
  end
end
