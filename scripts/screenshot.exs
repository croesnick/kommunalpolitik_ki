# Screenshot tool (#510): evidence for the hub UI checkpoints without loosening
# any agent sandbox. Starts the hub (apps/ratsprojekte) from a worktree on a
# throwaway database, drives a headless browser over the DevTools protocol and
# writes PNGs for routes × themes × widths, plus navigations captured
# mid-flight. Server and browser run together under one deny-default Seatbelt
# profile (scripts/screenshot/profile.exs): read worktree, runtime and pinned
# programs, write only the build output, the scratch directory and their logs,
# network only on loopback. The caller gets the PNGs and a manifest.
#
#     elixir scripts/screenshot.exs --route / --route /stand [--navigate /:/stand]
#            [--theme light,dark] [--width 390,1280] [--worktree PATH] [--out DIR]
#     elixir scripts/screenshot.exs --spec .dev-loop/screenshots.json [--worktree PATH] [--out DIR]
#     elixir scripts/screenshot.exs --probe [--worktree PATH] [--out DIR]
#
# Interactive sessions start exactly this call outside the Claude sandbox
# (.claude/settings.json), so sandbox-exec can apply; the tool then confines
# server and browser itself. The dev loop runs it after the gates.
# Docs: docs/agents/interaktive-sessions.md, docs/agents/dev-loop.md.

Kernel.ParallelCompiler.require(
  [Path.expand("../apps/seatbelt/lib/seatbelt.ex", __DIR__)] ++
    Path.wildcard(Path.expand("../apps/seatbelt/lib/seatbelt/*.ex", __DIR__)) ++
    Enum.map(~w(spec cdp profile), &Path.expand("screenshot/#{&1}.exs", __DIR__)),
  return_diagnostics: true
)

defmodule Screenshot.Error do
  defexception [:message]
end

defmodule Screenshot do
  @moduledoc false

  alias Screenshot.{CDP, Profile, Spec}

  @app "apps/ratsprojekte"
  @pins Path.expand("screenshot/pins.json", __DIR__)
  @cache Path.expand("~/.cache/komki-screenshot")
  @sandbox_exec "/usr/bin/sandbox-exec"
  @marker ".komki-screenshot"

  # The read ban of interactive sessions (#462): closed in the profile even
  # if an allow covered them.
  @denied [
    "~/Library/Application Support/ratsprojekte",
    "~/Library/Mobile Documents/iCloud~md~obsidian",
    "~/.ssh",
    "~/.config/gh",
    "~/Library/Keychains"
  ]

  # Fixed here, never taken from the caller. --no-sandbox only switches off
  # Chromium's own sandbox: macOS allows no second Seatbelt profile inside
  # ours, which confines the browser instead. The resolver rule keeps it off
  # DNS even before the profile would refuse.
  @browser_flags [
    "--remote-debugging-pipe",
    "--no-sandbox",
    "--disable-gpu",
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-background-networking",
    "--disable-component-update",
    "--disable-sync",
    "--disable-extensions",
    "--disable-breakpad",
    "--hide-scrollbars",
    "--force-color-profile=srgb",
    "--lang=de-DE",
    "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1",
    # The hub serves HTTPS with a throwaway certificate of this run (see start_hub/1).
    "--ignore-certificate-errors"
  ]

  @usage """
  Aufruf: elixir scripts/screenshot.exs --route /stand [--route …] [--navigate /:/stand]
                 [--theme light,dark] [--width 390,1280] [--worktree PFAD] [--out ORDNER]
          elixir scripts/screenshot.exs --spec DATEI.json [--worktree PFAD] [--out ORDNER]
          elixir scripts/screenshot.exs --probe [--worktree PFAD] [--out ORDNER]
  """

  def main(argv) do
    # :ssl reports every refused handshake as a notice; the tool's output
    # stays the list of shots.
    Logger.configure(level: :warning)
    run(argv)
  rescue
    e in Screenshot.Error ->
      IO.puts(:stderr, String.trim_trailing(e.message))
      System.halt(1)
  end

  defp run(argv) do
    {opts, rest, invalid} =
      OptionParser.parse(argv,
        strict: [
          worktree: :string,
          out: :string,
          spec: :string,
          route: :keep,
          navigate: :keep,
          theme: :string,
          width: :string,
          probe: :boolean
        ]
      )

    if rest != [] or invalid != [], do: fail(@usage)

    worktree = worktree!(opts[:worktree] || File.cwd!())
    out = out!(opts[:out] || Path.join(worktree, ".screenshots"), worktree)
    spec = unless opts[:probe], do: spec!(opts, worktree)
    pins = JSON.decode!(File.read!(@pins))
    browser = browser!(pins["chrome-headless-shell"])
    esbuild = program!("esbuild", pins["esbuild"])
    tailwind = program!("tailwind", pins["tailwind"])
    scratch = scratch!()
    started = System.monotonic_time(:second)

    try do
      ctx = context(worktree, out, scratch, browser, esbuild, tailwind)
      if opts[:probe], do: probe(ctx), else: shoot(ctx, spec)
    after
      File.rm_rf(scratch)
      denials(out, System.monotonic_time(:second) - started + 5)
    end
  end

  # What the profile refused during this run, from the unified log: the
  # starting point when a hub change needs a new rule.
  @confined ~w(beam.smp erl_child_setup chrome-headless-shell esbuild tailwind)

  defp denials(out, seconds) do
    args = [
      "show",
      "--last",
      "#{seconds}s",
      "--style",
      "compact",
      "--predicate",
      ~s{sender == "Sandbox"}
    ]

    lines =
      case System.cmd("/usr/bin/log", args, stderr_to_stdout: true) do
        {text, 0} ->
          text
          |> String.split("\n")
          |> Enum.filter(fn line -> Enum.any?(@confined, &String.contains?(line, &1 <> "(")) end)

        {text, _} ->
          ["log show gescheitert: " <> String.trim(text)]
      end

    File.write!(Path.join(out, "denials.log"), Enum.join(lines, "\n") <> "\n")
  end

  # -- inputs --------------------------------------------------------------

  # Only a worktree of this repository: its whole tree becomes readable in
  # the profile, so a path like $HOME must never pass.
  defp worktree!(path) do
    path = Seatbelt.canonical(path)
    common = git_common_dir(Path.expand("..", __DIR__))

    cond do
      git(path, ~w(rev-parse --show-toplevel)) != {:ok, path} ->
        fail("#{path} ist nicht die Wurzel eines Git-Worktrees.")

      common == nil or git_common_dir(path) != common ->
        fail("#{path} ist kein Worktree dieses Repositorys.")

      not File.exists?(Path.join([path, @app, "mix.exs"])) ->
        fail("#{path} enthält keinen Hub (#{@app}).")

      not File.dir?(Path.join(path, "apps/artifacts/deps")) ->
        fail("Im Worktree fehlen die Deps: erst `mix workspace.run -t deps.get` in #{path}.")

      true ->
        path
    end
  end

  # The PNGs land inside the worktree or a temp directory, never in the
  # worktree root itself.
  defp out!(path, worktree) do
    path = Seatbelt.canonical(path)

    unless path not in roots(worktree) and Enum.any?(roots(worktree), &inside?(path, &1)) and
             not inside?(path, Path.join(worktree, ".git")) do
      fail("Ausgabe nur in einem Unterordner des Worktrees oder von /tmp: #{path}")
    end

    # Old results are removed before a run, but only in a folder this tool
    # made: a marker file, or the folder is new or empty.
    marker = Path.join(path, @marker)

    case File.ls(path) do
      {:ok, entries} when entries != [] ->
        unless File.exists?(marker),
          do: fail("#{path} ist nicht leer und stammt nicht von diesem Werkzeug.")

      _ ->
        File.mkdir_p!(path)
    end

    File.write!(marker, "")

    for old <-
          Path.wildcard(Path.join(path, "*.{png,log,sb}")) ++ [Path.join(path, "manifest.json")],
        do: File.rm(old)

    path
  end

  defp roots(worktree),
    do: Enum.uniq([worktree | Enum.map([System.tmp_dir!(), "/tmp"], &Seatbelt.canonical/1)])

  # The tool reads the shot list outside any sandbox, and its error messages
  # quote what they reject: only small regular files inside the worktree or
  # /tmp, symlinks resolved.
  defp read_spec!(file, worktree) do
    path = Seatbelt.canonical(file)

    cond do
      not Enum.any?(roots(worktree), &inside?(path, &1)) ->
        fail("Die Liste der Aufnahmen muss im Worktree oder unter /tmp liegen: #{file}")

      not match?(
        {:ok, %File.Stat{type: :regular, size: size}} when size <= 65_536,
        File.stat(path)
      ) ->
        fail("#{file} ist keine Datei bis 64 KB.")

      true ->
        decode!(File.read!(path), file)
    end
  end

  defp spec!(opts, worktree) do
    map =
      if file = opts[:spec] do
        read_spec!(file, worktree)
      else
        navs =
          for nav <- Keyword.get_values(opts, :navigate) do
            case String.split(nav, ":") do
              [from, to] -> %{"from" => from, "to" => to}
              _ -> fail("--navigate erwartet VON:NACH, etwa /:/stand")
            end
          end

        %{"routes" => Keyword.get_values(opts, :route), "navigations" => navs}
        |> put_list("themes", opts[:theme], & &1)
        |> put_list("widths", opts[:width], &int!/1)
      end

    case Spec.parse(map) do
      {:ok, spec} -> spec
      {:error, message} -> fail(message)
    end
  end

  defp put_list(map, _key, nil, _fun), do: map

  defp put_list(map, key, value, fun),
    do: Map.put(map, key, value |> String.split(",") |> Enum.map(fun))

  defp int!(text) do
    case Integer.parse(text) do
      {n, ""} -> n
      _ -> fail("Keine ganze Zahl: #{text}")
    end
  end

  defp decode!(text, file) do
    case JSON.decode(text) do
      {:ok, map} -> map
      {:error, _} -> fail("#{file} ist kein gültiges JSON.")
    end
  end

  # -- pinned programs -------------------------------------------------------

  defp browser!(%{"path" => path, "sha256" => sha}) do
    dir = Path.expand(path)
    bin = Path.join(dir, "chrome-headless-shell")

    unless File.exists?(bin) do
      fail("""
      Der Browser fehlt: #{dir}
      Installieren: pnpm dlx playwright install --only-shell (Revision aus scripts/screenshot/pins.json, siehe docs/prerequisites.md)
      """)
    end

    case Seatbelt.Pins.hash(dir) do
      {:ok, ^sha} ->
        %{dir: Seatbelt.canonical(dir), bin: Seatbelt.canonical(bin)}

      {:ok, other} ->
        fail("""
        Der Browser weicht von seiner Prüfsumme ab: #{dir}
        erwartet #{sha}
        gefunden #{other}
        Nach Prüfung des Updates die neue Prüfsumme in scripts/screenshot/pins.json eintragen.
        """)
    end
  end

  # esbuild and tailwind for the hub's asset watchers: downloaded once into
  # the cache, checked against the pin on every run (the cache is writable
  # for agents, so a swapped file must not pass).
  defp program!(name, %{"version" => version, "url" => url, "sha256" => sha} = pin) do
    path = Path.join(@cache, "#{name}-#{version}")

    if sha256(path) != sha do
      IO.puts("Lade #{name} #{version} …")
      body = download!(url)
      bin = if member = pin["member"], do: untar!(body, member), else: body

      if hex(:crypto.hash(:sha256, bin)) != sha,
        do: fail("#{name} #{version}: Prüfsumme des Downloads stimmt nicht (#{url}).")

      File.mkdir_p!(@cache)
      tmp = path <> ".part"
      File.write!(tmp, bin)
      File.chmod!(tmp, 0o755)
      File.rename!(tmp, path)
    end

    Seatbelt.canonical(path)
  end

  defp sha256(path) do
    case File.read(path) do
      {:ok, bin} -> hex(:crypto.hash(:sha256, bin))
      _ -> nil
    end
  end

  defp download!(url) do
    {:ok, _} = Application.ensure_all_started([:inets, :ssl])

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    case :httpc.request(:get, {String.to_charlist(url), []}, [ssl: ssl, timeout: 120_000],
           body_format: :binary
         ) do
      {:ok, {{_, 200, _}, _, body}} -> body
      other -> fail("Download gescheitert: #{url}\n#{inspect(other, limit: 5)}")
    end
  end

  defp untar!(tgz, member) do
    case :erl_tar.extract({:binary, tgz}, [
           :compressed,
           :memory,
           files: [String.to_charlist(member)]
         ]) do
      {:ok, [{_, bin}]} -> bin
      other -> fail("#{member} fehlt im Archiv: #{inspect(other, limit: 5)}")
    end
  end

  # -- profile and launch ----------------------------------------------------

  defp scratch! do
    dir = Path.join(System.tmp_dir!(), "komki-screenshot-#{System.unique_integer([:positive])}")
    for sub <- ~w(home tmp hex chrome), do: File.mkdir_p!(Path.join(dir, sub))
    Seatbelt.canonical(dir)
  end

  defp context(worktree, out, scratch, browser, esbuild, tailwind) do
    app = Path.join(worktree, @app)
    elixir_root = Seatbelt.canonical(Path.expand("../..", to_string(:code.lib_dir(:elixir))))
    erlang_root = Seatbelt.canonical(to_string(:code.root_dir()))
    mix_home = System.get_env("MIX_HOME") || Path.expand("~/.mix")

    paths = %{
      erlang_root: erlang_root,
      elixir_root: elixir_root,
      mix_archives: Seatbelt.canonical(Path.join(mix_home, "archives")),
      worktree: worktree,
      # Build output of the hub (gitignored, rebuilt anyway) and the scratch
      # directory; nothing else in the worktree.
      writable: [Path.join(app, "_build/dev"), Path.join(app, "priv/static/assets"), scratch],
      programs: [esbuild, tailwind],
      browser: browser.dir,
      dylib_dirs: nif_dylib_dirs(app, [erlang_root, worktree]),
      logs: Enum.map(~w(server.log browser.log probe.log), &Path.join(out, &1)),
      denied: Enum.map(@denied, &Seatbelt.canonical/1),
      hub_port: free_port()
    }

    profile = Path.join(scratch, "profile.sb")
    File.write!(profile, Profile.render(paths))
    File.cp!(profile, Path.join(out, "profile.sb"))

    %{
      worktree: worktree,
      app: app,
      out: out,
      scratch: scratch,
      profile: profile,
      browser: browser.bin,
      esbuild: esbuild,
      tailwind: tailwind,
      elixir: Path.join(elixir_root, "bin/elixir"),
      mix: Path.join(elixir_root, "bin/mix"),
      path:
        Enum.join(
          [Path.join(elixir_root, "bin"), Path.join(erlang_root, "bin"), "/usr/bin", "/bin"],
          ":"
        ),
      mix_home: Seatbelt.canonical(mix_home),
      hub_port: paths.hub_port,
      hub: Seatbelt.canonical(hd(@denied)),
      ssh: Seatbelt.canonical("~/.ssh")
    }
  end

  defp nif_dylib_dirs(app, own_roots) do
    Path.join(app, "_build/dev/lib/*/priv/**/*.so")
    |> Path.wildcard()
    |> Enum.flat_map(&Seatbelt.MachODeps.dylib_dirs/1)
    |> Enum.reject(fn dir -> Enum.any?(own_roots, &inside?(dir, &1)) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Clean environment: nothing of the caller's (tokens, keys) reaches the
  # sandbox. HOME points into the scratch directory, so the hub's dev config
  # puts its database there.
  defp env(ctx, extra) do
    [
      {"HOME", Path.join(ctx.scratch, "home")},
      {"TMPDIR", Path.join(ctx.scratch, "tmp")},
      {"PATH", ctx.path},
      {"LANG", "en_US.UTF-8"}
    ] ++ extra
  end

  # Starts `argv` under the profile via a shell that redirects its output
  # into `log` and, for the browser, maps the DevTools pipe (fd 3 in, fd 4
  # out) onto the port's stdin and stdout.
  defp launch(ctx, env, log, argv, opts \\ []) do
    redirect =
      if opts[:pipe],
        do: ~s{3<&0 4>&1 </dev/null >>"$LOG" 2>&1},
        else: ~s{</dev/null >>"$LOG" 2>&1}

    args =
      ["-i" | Enum.map([{"LOG", log} | env], fn {k, v} -> "#{k}=#{v}" end)] ++
        [@sandbox_exec, "-f", ctx.profile, "/bin/sh", "-c", ~s{exec "$0" "$@" } <> redirect] ++
        argv

    Port.open({:spawn_executable, "/usr/bin/env"}, [
      :binary,
      :exit_status,
      args: args,
      cd: opts[:cd] || ctx.scratch
    ])
  end

  defp stop(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        System.cmd("kill", ["-TERM", to_string(pid)], stderr_to_stdout: true)
        receive do: ({^port, {:exit_status, _}} -> :ok), after: (10_000 -> kill(pid))

      nil ->
        :ok
    end
  end

  defp kill(pid), do: System.cmd("kill", ["-KILL", to_string(pid)], stderr_to_stdout: true)

  # -- hub server --------------------------------------------------------------

  @boot """
  # Generated by scripts/screenshot.exs: hub on a throwaway database.
  Application.put_env(:esbuild, :path, System.fetch_env!("SCREENSHOT_ESBUILD"))
  Application.put_env(:tailwind, :path, System.fetch_env!("SCREENSHOT_TAILWIND"))
  # HTTPS only: over TLS the server reads and encrypts files itself. Plain HTTP
  # would use the kernel's sendfile, which the profile can only allow with a
  # rule that also lets the hub port reach the internet.
  https = [
    ip: {127, 0, 0, 1},
    port: String.to_integer(System.fetch_env!("SCREENSHOT_PORT")),
    certfile: System.fetch_env!("SCREENSHOT_CERT"),
    keyfile: System.fetch_env!("SCREENSHOT_KEY")
  ]
  # Live reload would exec its FSEvents helper; polling nothing needs no program.
  Application.put_env(:phoenix_live_reload, :backend, :fs_poll)
  Application.put_env(:phoenix_live_reload, :dirs, [])
  # Asset watchers build once: watching needs FSEvents, the profile has none.
  endpoint = Application.fetch_env!(:ratsprojekte, RatsprojekteWeb.Endpoint)

  watchers =
    for {name, {m, f, args}} <- Keyword.get(endpoint, :watchers, []),
        do: {name, {m, f, Enum.map(args, fn a when is_list(a) -> a -- ["--watch"]; a -> a end)}}

  Application.put_env(
    :ratsprojekte,
    RatsprojekteWeb.Endpoint,
    endpoint |> Keyword.merge(watchers: watchers, http: false, https: https, server: true)
  )
  Ecto.Migrator.with_repo(Ratsprojekte.Repo, &Ecto.Migrator.run(&1, :up, all: true, log: false))
  {:ok, _} = Application.ensure_all_started(:ratsprojekte)
  if File.exists?("priv/repo/seeds.exs"), do: Code.eval_file("priv/repo/seeds.exs")
  IO.puts("screenshot: Hub bereit")
  Process.sleep(:infinity)
  """

  defp start_hub(ctx) do
    port = ctx.hub_port
    {cert, key} = certificate!(ctx.scratch)
    boot = Path.join(ctx.scratch, "boot.exs")
    File.write!(boot, @boot)
    # Generated and gitignored; removed so that only this run's build counts
    # (an older bundle could belong to another branch, and the builders skip
    # writing unchanged output).
    assets = Enum.map(~w(js/app.js css/app.css), &Path.join([ctx.app, "priv/static/assets", &1]))
    Enum.each(assets, &File.rm/1)

    env =
      env(ctx, [
        {"MIX_ENV", "dev"},
        {"MIX_HOME", ctx.mix_home},
        {"HEX_HOME", Path.join(ctx.scratch, "hex")},
        {"HEX_OFFLINE", "1"},
        # Mix holds its compile lock over a loopback TCP socket, which the
        # profile does not allow beyond the hub port. Only this server
        # compiles here, so the lock is off.
        {"MIX_OS_CONCURRENCY_LOCK", "false"},
        {"SCREENSHOT_PORT", to_string(port)},
        {"SCREENSHOT_CERT", cert},
        {"SCREENSHOT_KEY", key},
        {"SCREENSHOT_ESBUILD", ctx.esbuild},
        {"SCREENSHOT_TAILWIND", ctx.tailwind}
      ])

    log = Path.join(ctx.out, "server.log")
    argv = [ctx.elixir, ctx.mix, "run", "--no-start", "--no-deps-check", boot]
    server = launch(ctx, env, log, argv, cd: ctx.app)
    IO.puts("Starte den Hub aus #{ctx.worktree} auf 127.0.0.1:#{port} …")
    await_hub(server, port, assets, log, deadline(300_000))
    {server, port}
  end

  # Ready when the start page answers and both asset bundles exist.
  defp await_hub(server, port, assets, log, deadline) do
    receive do
      {^server, {:exit_status, status}} ->
        fail("Der Hub ist beendet (Status #{status}).\n" <> tail(log))
    after
      500 -> :ok
    end

    cond do
      http_status(port, "/") == 200 and Enum.all?(assets, &File.exists?/1) ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        stop(server)
        fail("Der Hub wurde nicht bereit.\n" <> tail(log))

      true ->
        await_hub(server, port, assets, log, deadline)
    end
  end

  # Throwaway self-signed certificate for 127.0.0.1, valid for this run only.
  # (Certificates from :public_key.pkix_test_data/1 fail Chrome's decoder.)
  defp certificate!(scratch) do
    cert = Path.join(scratch, "hub-cert.pem")
    key = Path.join(scratch, "hub-key.pem")

    args =
      ~w(req -x509 -newkey rsa:2048 -nodes -sha256 -days 1 -subj /CN=127.0.0.1) ++
        ["-addext", "subjectAltName=IP:127.0.0.1", "-keyout", key, "-out", cert]

    case System.cmd("/usr/bin/openssl", args, stderr_to_stdout: true) do
      {_, 0} -> {cert, key}
      {out, _} -> fail("Zertifikat für den Hub nicht erzeugt:\n" <> out)
    end
  end

  defp http_status(port, path) do
    {:ok, _} = Application.ensure_all_started([:inets, :ssl])
    url = String.to_charlist("https://127.0.0.1:#{port}#{path}")

    case :httpc.request(:get, {url, []}, [timeout: 5_000, ssl: [verify: :verify_none]], []) do
      {:ok, {{_, status, _}, _, _}} -> status
      _ -> nil
    end
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  # -- browser ---------------------------------------------------------------

  defp start_browser(ctx) do
    log = Path.join(ctx.out, "browser.log")
    argv = [ctx.browser, "--user-data-dir=" <> Path.join(ctx.scratch, "chrome") | @browser_flags]
    port = launch(ctx, env(ctx, []), log, argv, pipe: true)
    cdp = CDP.new(port)

    case CDP.call(cdp, "Target.createTarget", %{"url" => "about:blank"}, nil, 30_000) do
      {:ok, %{"targetId" => target}, cdp} ->
        {%{"sessionId" => session}, cdp} =
          CDP.call!(cdp, "Target.attachToTarget", %{"targetId" => target, "flatten" => true})

        {_, cdp} = CDP.call!(cdp, "Page.enable", %{}, session)
        {_, cdp} = CDP.call!(cdp, "Runtime.enable", %{}, session)
        {cdp, session}

      {:error, message, _} ->
        fail("Der Browser startet nicht: #{message}\n" <> tail(log))
    end
  end

  defp close_browser(cdp) do
    CDP.call(cdp, "Browser.close", %{}, nil, 5_000)
    stop(cdp.port)
  end

  # -- shots -----------------------------------------------------------------

  defp shoot(ctx, spec) do
    commit = git(ctx.worktree, ~w(rev-parse HEAD)) |> elem(1)
    {server, port} = start_hub(ctx)

    try do
      {cdp, session} = start_browser(ctx)

      try do
        {records, cdp} =
          Enum.map_reduce(Spec.shots(spec), cdp, fn shot, cdp ->
            shot(cdp, session, port, ctx.out, shot)
          end)

        manifest = %{
          "worktree" => ctx.worktree,
          "commit" => commit,
          "created_at" =>
            DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
          "profile" => "profile.sb",
          "shots" => records
        }

        File.write!(Path.join(ctx.out, "manifest.json"), JSON.encode!(manifest))
        close_browser(cdp)
        IO.puts("#{length(records)} Aufnahmen in #{ctx.out} (manifest.json)")
      rescue
        e ->
          close_browser(cdp)
          reraise e, __STACKTRACE__
      end
    after
      stop(server)
    end
  end

  defp viewport(cdp, session, theme, width) do
    {_, cdp} =
      CDP.call!(
        cdp,
        "Emulation.setDeviceMetricsOverride",
        %{
          "width" => width,
          "height" => if(width < 768, do: 844, else: 800),
          "deviceScaleFactor" => 1,
          "mobile" => width < 768
        },
        session
      )

    {_, cdp} =
      CDP.call!(
        cdp,
        "Emulation.setEmulatedMedia",
        %{"features" => [%{"name" => "prefers-color-scheme", "value" => theme}]},
        session
      )

    cdp
  end

  defp shot(cdp, session, port, out, {:page, route, theme, width} = shot) do
    cdp = viewport(cdp, session, theme, width)
    url = "https://127.0.0.1:#{port}#{route}"
    cdp = open!(cdp, session, url)
    {height, cdp} = CDP.eval!(cdp, session, "Math.ceil(document.documentElement.scrollHeight)")
    height = min(height, 10_000)

    clip = %{"x" => 0, "y" => 0, "width" => width, "height" => height, "scale" => 1}
    file = Spec.name(shot) <> ".png"

    cdp =
      capture!(cdp, session, Path.join(out, file), %{
        "captureBeyondViewport" => true,
        "clip" => clip
      })

    {data_theme, cdp} = CDP.eval!(cdp, session, "document.documentElement.dataset.theme || null")
    IO.puts("  #{file}")

    {%{
       "file" => file,
       "kind" => "page",
       "url" => url,
       "theme" => theme,
       "data_theme" => data_theme,
       "width" => width,
       "height" => height
     }, cdp}
  end

  # A live navigation slowed down by LiveView's latency simulator: the same
  # link a `<.link navigate>` renders, captured while the request is still in
  # flight (the loading bar shows after 300 ms), then awaited to the end.
  defp shot(cdp, session, port, out, {:navigate, {from, to}, theme, width} = shot) do
    cdp = viewport(cdp, session, theme, width)
    url = "https://127.0.0.1:#{port}#{from}"
    cdp = open!(cdp, session, url)

    {_, cdp} =
      CDP.eval!(cdp, session, """
      (() => {
        window.liveSocket.enableLatencySim(2000);
        const a = document.createElement("a");
        a.href = #{JSON.encode!(to)};
        a.dataset.phxLink = "redirect";
        a.dataset.phxLinkState = "push";
        document.body.appendChild(a);
        a.click();
        return true;
      })()
      """)

    Process.sleep(900)
    {path_at_capture, cdp} = CDP.eval!(cdp, session, "location.pathname")
    file = Spec.name(shot) <> ".png"
    cdp = capture!(cdp, session, Path.join(out, file), %{})

    {arrived, cdp} =
      wait_for(
        cdp,
        session,
        "location.pathname === #{JSON.encode!(to)} && #{connected()}",
        15_000
      )

    {_, cdp} = CDP.eval!(cdp, session, "window.liveSocket.disableLatencySim(), true")
    {data_theme, cdp} = CDP.eval!(cdp, session, "document.documentElement.dataset.theme || null")

    unless arrived, do: fail("Navigation #{from} → #{to} kam nicht an.")
    IO.puts("  #{file} (aufgenommen auf #{path_at_capture}, Ziel #{to})")

    {%{
       "file" => file,
       "kind" => "navigation",
       "url" => url,
       "to" => to,
       "theme" => theme,
       "data_theme" => data_theme,
       "width" => width,
       "path_at_capture" => path_at_capture,
       "in_flight" => path_at_capture == from
     }, cdp}
  end

  defp connected, do: ~s{document.querySelector("[data-phx-main].phx-connected") !== null}

  defp open!(cdp, session, url) do
    cdp = CDP.flush(cdp)
    {result, cdp} = CDP.call!(cdp, "Page.navigate", %{"url" => url}, session)
    if error = result["errorText"], do: fail("#{url}: #{error}")

    case CDP.await_event(cdp, "Page.loadEventFired", session, 30_000) do
      {:ok, _, cdp} ->
        {ok, cdp} = wait_for(cdp, session, connected(), 15_000)

        unless ok do
          fail("#{url}: LiveView verbindet sich nicht.\n" <> diagnose(cdp, session))
        end

        {_, cdp} = CDP.eval!(cdp, session, "document.fonts.ready.then(() => true)")
        Process.sleep(300)
        cdp

      {:error, message, _} ->
        fail("#{url}: #{message}")
    end
  end

  # Why a page did not connect: script errors and console output the browser
  # reported, and the state of the LiveView main element.
  defp diagnose(cdp, session) do
    {state, cdp} =
      CDP.eval!(cdp, session, """
      JSON.stringify({liveSocket: typeof window.liveSocket,
        main: document.querySelector("[data-phx-main]")?.className ?? null,
        scripts: [...document.scripts].map(s => s.src || "inline"),
        resources: performance.getEntriesByType("resource").map(e => e.name + " " + e.responseStatus)})
      """)

    messages =
      for %{"method" => m, "params" => p} <- cdp.events,
          m in ["Runtime.exceptionThrown", "Runtime.consoleAPICalled"] do
        get_in(p, ["exceptionDetails", "exception", "description"]) ||
          get_in(p, ["exceptionDetails", "text"]) ||
          Enum.map_join(p["args"] || [], " ", &to_string(&1["value"] || &1["description"]))
      end

    Enum.join([state | Enum.take(messages, -10)], "\n")
  end

  defp capture!(cdp, session, path, params) do
    {%{"data" => data}, cdp} =
      CDP.call!(cdp, "Page.captureScreenshot", Map.put(params, "format", "png"), session)

    File.write!(path, Base.decode64!(data))
    cdp
  end

  defp wait_for(cdp, session, expression, timeout) do
    deadline = deadline(timeout)

    Stream.repeatedly(fn -> :tick end)
    |> Enum.reduce_while(cdp, fn :tick, cdp ->
      {value, cdp} = CDP.eval!(cdp, session, "Boolean(#{expression})")

      cond do
        value ->
          {:halt, {true, cdp}}

        System.monotonic_time(:millisecond) > deadline ->
          {:halt, {false, cdp}}

        true ->
          Process.sleep(100)
          {:cont, cdp}
      end
    end)
  end

  # -- probe -----------------------------------------------------------------

  # Negative controls with the very profile of a real run: from inside, the
  # BEAM and the browser try to read the hub folder and ~/.ssh and to reach
  # the network; one loopback connection is the positive control.
  @probe """
  [hub, ssh, hub_port, other_port] = System.argv()
  hub_port = String.to_integer(hub_port)
  other_port = String.to_integer(other_port)

  checks = [
    {"BEAM liest den Hub-Ordner", fn -> File.ls(hub) end},
    {"BEAM liest ~/.ssh", fn -> File.ls(ssh) end},
    {"BEAM verbindet zu 1.1.1.1:443", fn -> :gen_tcp.connect({1, 1, 1, 1}, 443, [], 3000) end},
    {"BEAM verbindet vom Hub-Port aus zu 1.1.1.1:443",
     fn -> :gen_tcp.connect({1, 1, 1, 1}, 443, [port: hub_port, reuseaddr: true], 3000) end},
    {"BEAM löst example.com auf", fn -> :inet.getaddr(~c"example.com", :inet) end},
    {"BEAM verbindet zu einem anderen Port auf 127.0.0.1",
     fn -> :gen_tcp.connect({127, 0, 0, 1}, other_port, [], 3000) end},
    {"BEAM verbindet zum Hub-Port auf 127.0.0.1 (Positivkontrolle)", fn -> :gen_tcp.connect({127, 0, 0, 1}, hub_port, [], 3000) end}
  ]

  for {name, fun} <- checks do
    result = try do: fun.(), rescue: (e -> {:error, Exception.message(e)})
    verdict = if match?({:ok, _}, result), do: "erreicht", else: "verweigert"
    IO.puts("PROBE\\t\#{name}\\t\#{verdict}\\t\#{inspect(result, limit: 3)}")
  end
  """

  defp probe(ctx) do
    # The responder stands in for the hub on its port (positive control);
    # a second one on another loopback port must stay out of reach.
    opts = [:binary, ip: {127, 0, 0, 1}, active: false, reuseaddr: true]
    {:ok, hub_listen} = :gen_tcp.listen(ctx.hub_port, opts)
    {:ok, other_listen} = :gen_tcp.listen(0, opts)
    {:ok, other_port} = :inet.port(other_listen)
    responders = Enum.map([hub_listen, other_listen], &spawn_link(fn -> respond(&1) end))
    script = Path.join(ctx.scratch, "probe.exs")
    File.write!(script, @probe)

    log = Path.join(ctx.out, "probe.log")

    beam =
      launch(ctx, env(ctx, []), log, [
        ctx.elixir,
        script,
        ctx.hub,
        ctx.ssh,
        to_string(ctx.hub_port),
        to_string(other_port)
      ])

    receive do: ({^beam, {:exit_status, _}} -> :ok), after: (60_000 -> stop(beam))

    beam_rows =
      for "PROBE\t" <> row <- String.split(File.read!(log), "\n") do
        [name, verdict, detail] = String.split(row, "\t", parts: 3)
        {name, verdict, detail}
      end

    {cdp, session} = start_browser(ctx)

    {browser_rows, cdp} =
      Enum.map_reduce(
        [
          {"Browser öffnet http://1.1.1.1/", "http://1.1.1.1/"},
          {"Browser öffnet http://example.com/", "http://example.com/"},
          {"Browser öffnet den Hub-Ordner", "file://" <> ctx.hub <> "/"},
          {"Browser öffnet ~/.ssh", "file://" <> ctx.ssh <> "/"},
          {"Browser öffnet einen anderen Port auf 127.0.0.1", "http://127.0.0.1:#{other_port}/"},
          {"Browser öffnet den Hub-Port auf 127.0.0.1 (Positivkontrolle)",
           "http://127.0.0.1:#{ctx.hub_port}/"}
        ],
        cdp,
        fn {name, url}, cdp -> browse(cdp, session, name, url) end
      )

    close_browser(cdp)

    for pid <- responders do
      Process.unlink(pid)
      Process.exit(pid, :kill)
    end

    rows = beam_rows ++ browser_rows

    expected = fn name ->
      if String.contains?(name, "Positivkontrolle"), do: "erreicht", else: "verweigert"
    end

    for {name, verdict, detail} <- rows do
      mark = if verdict == expected.(name), do: "ok  ", else: "FEHL"
      IO.puts("#{mark} #{name}: #{verdict} (#{String.slice(detail, 0, 100)})")
    end

    if length(beam_rows) != 7 or Enum.any?(rows, fn {n, v, _} -> v != expected.(n) end) do
      fail("Probe nicht bestanden.\n" <> tail(log))
    end

    IO.puts("Probe bestanden: #{length(rows)} Kontrollen.")
  end

  # The browser counts as through only if the page carries the marker of our
  # responder or a directory listing; Chrome renders its own error pages.
  defp browse(cdp, session, name, url) do
    cdp = CDP.flush(cdp)
    {result, cdp} = CDP.call!(cdp, "Page.navigate", %{"url" => url}, session, 20_000)

    case result["errorText"] do
      nil ->
        {_, cdp} = wait_for(cdp, session, ~s{document.readyState === "complete"}, 10_000)

        {text, cdp} =
          CDP.eval!(cdp, session, "document.body ? document.body.innerText.slice(0, 200) : ''")

        listing = String.contains?(text || "", ["Index of", "Inhalt von"])

        verdict =
          if String.contains?(text || "", "komki-probe") or listing,
            do: "erreicht",
            else: "verweigert"

        {{name, verdict, inspect(text)}, cdp}

      error ->
        {{name, "verweigert", error}, cdp}
    end
  end

  defp respond(listen) do
    case :gen_tcp.accept(listen) do
      {:ok, socket} ->
        :gen_tcp.recv(socket, 0, 2_000)
        body = "komki-probe"

        :gen_tcp.send(
          socket,
          "HTTP/1.1 200 OK\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
            body
        )

        :gen_tcp.close(socket)
        respond(listen)

      _ ->
        :ok
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp git(dir, args) do
    case System.cmd("git", ["-C", dir | args], stderr_to_stdout: true) do
      {out, 0} -> {:ok, String.trim(out)}
      {out, _} -> {:error, out}
    end
  end

  defp git_common_dir(dir) do
    case git(dir, ~w(rev-parse --path-format=absolute --git-common-dir)) do
      {:ok, path} -> Seatbelt.canonical(path)
      _ -> nil
    end
  end

  defp inside?(path, root), do: path == root or String.starts_with?(path, root <> "/")

  defp deadline(ms), do: System.monotonic_time(:millisecond) + ms

  defp tail(log) do
    case File.read(log) do
      {:ok, text} -> text |> String.split("\n") |> Enum.take(-30) |> Enum.join("\n")
      _ -> "(kein Log)"
    end
  end

  defp hex(digest), do: Base.encode16(digest, case: :lower)

  # Raises instead of halting, so every `after` stops server and browser and
  # removes the scratch directory.
  defp fail(message), do: raise(Screenshot.Error, message)
end

Screenshot.main(System.argv())
