# Seatbelt profile of the screenshot tool (#510): the hub dev server and the
# headless browser run together under this one deny-default profile. They
# read the worktree, the Erlang/Elixir runtime, the pinned programs and the
# system libraries, write only their own throwaway places, and reach the
# network only on loopback. Built from the apps/seatbelt layers.

defmodule Screenshot.Profile do
  @moduledoc false

  alias Seatbelt.{Escript, SBPL}

  @doc """
  Profile text for `paths` (all kernel-canonical, see `Seatbelt.canonical/1`):

    * `:erlang_root`, `:elixir_root`, `:mix_archives`: runtime, read-only
    * `:worktree`: read-only
    * `:writable`: build output of the worktree and the scratch directory
    * `:programs`: pinned executables (esbuild, tailwind)
    * `:browser`: package directory of the pinned browser
    * `:dylib_dirs`: libraries the NIFs of the build link against
    * `:logs`: log files the launch shells redirect into
    * `:denied`: places that stay closed even if an allow above covered them
    * `:hub_port`: the one loopback port server and browser may use
  """
  def render(paths), do: SBPL.render(rules(paths))

  def rules(p) do
    SBPL.header([
      "komki screenshot tool (#510): hub dev server and headless browser",
      "Generated per run by scripts/screenshot.exs; deny-default, loopback only"
    ]) ++
      Escript.runtime(p.erlang_root, Path.join(p.elixir_root, "bin/mix")) ++
      elixir(p) ++
      worktree(p) ++
      programs(p) ++
      browser(p) ++
      system() ++
      network(p.hub_port) ++
      Enum.flat_map(p.logs, &Escript.log_rules/1) ++
      denied(p.denied)
  end

  defp elixir(p) do
    [
      "; Elixir runtime and Mix archives (read-only); the elixir launcher resolves itself via readlink",
      "(allow process-exec (subpath " <> SBPL.quote!(p.elixir_root) <> "))",
      SBPL.read_subpath(p.elixir_root),
      SBPL.read_subpath(p.mix_archives),
      ~s{(allow process-exec (literal "/usr/bin/readlink"))},
      ~s{(allow file-read* (literal "/usr/bin/readlink"))}
    ] ++ SBPL.metadata_ancestors([p.elixir_root, p.mix_archives])
  end

  defp worktree(p) do
    ["; Worktree with its deps: read-only; build output and scratch: read-write"] ++
      [SBPL.read_subpath(p.worktree)] ++
      Enum.map(
        p.writable,
        &("(allow file-read* file-write* (subpath " <> SBPL.quote!(&1) <> "))")
      ) ++
      ["; NIF libraries of the build (e.g. SQLCipher, OpenSSL)"] ++
      Enum.map(p.dylib_dirs, &SBPL.read_subpath/1) ++
      SBPL.metadata_ancestors([p.worktree | p.writable] ++ p.dylib_dirs)
  end

  defp programs(p) do
    ["; Pinned asset builders (esbuild, tailwind)"] ++
      Enum.flat_map(p.programs, fn path ->
        [
          "(allow process-exec (literal " <> SBPL.quote!(path) <> "))",
          "(allow file-read* (literal " <> SBPL.quote!(path) <> "))"
        ]
      end) ++ SBPL.metadata_ancestors(p.programs)
  end

  # Chromium runs multi-process: the browser re-executes its own binary for
  # renderer and utility processes and hands them Mach ports through its
  # rendezvous server, which it registers under its own name.
  defp browser(p) do
    [
      "; Headless browser (pinned package, read-only); its own child processes",
      "(allow process-exec (subpath " <> SBPL.quote!(p.browser) <> "))",
      SBPL.read_subpath(p.browser),
      ~s{(allow mach-register (global-name-prefix "org.chromium."))},
      ~s{(allow mach-lookup (global-name-prefix "org.chromium."))},
      "(allow process-info* (target same-sandbox))",
      "(allow signal (target same-sandbox))",
      "(allow ipc-posix-shm)",
      "(allow ipc-posix-sem)"
    ] ++ SBPL.metadata_ancestors([p.browser])
  end

  defp system do
    [
      "; System services the browser needs for fonts and rendering",
      # No user-preference-read: the browser asks for it, but the PNGs come
      # out byte-identical without it (measured, #510).
      "(allow sysctl-read)",
      "(allow iokit-open (iokit-user-client-class \"IOSurfaceRootUserClient\"))",
      SBPL.read_subpath("/Library/Fonts"),
      SBPL.read_subpath("/System/Library"),
      SBPL.read_subpath("/usr/share"),
      SBPL.mach_lookup("com.apple.fonts"),
      SBPL.mach_lookup("com.apple.FontObjectsServer"),
      SBPL.mach_lookup("com.apple.cfprefsd.daemon"),
      SBPL.mach_lookup("com.apple.cfprefsd.agent"),
      SBPL.mach_lookup("com.apple.system.logger"),
      SBPL.mach_lookup("com.apple.logd")
    ]
  end

  # Only the hub's port: loopback alone would also reach every other local
  # service (a dev server with Tidewave, llama-server, proxies).
  defp network(port) do
    local = SBPL.quote!("localhost:#{port}")

    [
      "; Network: loopback, and there only the hub's port (server listens, browser connects)",
      "(allow network-bind (local ip " <> local <> "))",
      "(allow network-inbound (local ip " <> local <> "))",
      "(allow network-outbound (remote ip " <> local <> "))"
    ]
  end

  # Belt and braces: later rules win, so these deny even reads an allow
  # above would cover.
  defp denied(paths) do
    ["; Places that stay closed (read ban of interactive sessions, #462)"] ++
      Enum.map(paths, &("(deny file-read* file-write* (subpath " <> SBPL.quote!(&1) <> "))"))
  end
end
