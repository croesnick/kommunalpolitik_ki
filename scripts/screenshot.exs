# Screenshot tool (#510): evidence for the hub UI checkpoints without loosening
# any agent sandbox. Starts the hub (apps/ratsprojekte) from a worktree on a
# throwaway database, drives a headless browser over the DevTools protocol and
# writes PNGs for routes × themes × widths, plus navigations captured
# mid-flight. Server and browser run together under one deny-default Seatbelt
# profile (scripts/screenshot/profile.exs): read worktree, runtime and pinned
# programs, write only the scratch directory (throwaway build included) and
# their logs, network only on the hub port on loopback. The caller gets the
# PNGs and a manifest.
#
#     elixir scripts/screenshot.exs --route / --route /stand [--navigate /:/stand]
#            [--theme light,dark] [--width 390,1280] [--worktree PATH] [--out DIR]
#     elixir scripts/screenshot.exs --spec .dev-loop/screenshots.json [--worktree PATH] [--out DIR]
#     elixir scripts/screenshot.exs --probe [--worktree PATH] [--out DIR]
#
# Interactive sessions start the copy that `make screenshot-install` puts in
# ~/.local/share/komki-tools/screenshot, outside every worktree, through its
# launcher bin/komki-screenshot (runtime fixed at install), and only that call
# outside the Claude sandbox (.claude/settings.json), so sandbox-exec can
# apply; the tool then confines server and browser itself. The dev loop runs
# the copy of its own checkout after the gates.
#
# The tool itself runs unconfined. The session may write the worktree and
# the output folder, the hub code under the profile its scratch directory
# and logs; the scratch directory lies where the session cannot write
# (scratch!/0). The tool writes into the output folder only through put!/3
# and reads the logs there only through read_log/1, so a planted symlink or hard link neither
# redirects one of its own writes nor leaks a file. Left open: swapping the
# output folder itself for a symlink during a run, and a hard link planted
# on a log during the run, whose target the shells under the profile would
# then append to (docs/agents/interaktive-sessions.md).
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
  # Next to the installed copy: neither the Claude sandbox nor Edit/Write
  # may change it (.claude/settings.json).
  @cache Path.expand("~/.local/share/komki-tools/cache")
  @runs Path.expand("~/.local/share/komki-tools/run")
  @sandbox_exec "/usr/bin/sandbox-exec"
  @marker ".komki-screenshot"
  @logs ~w(server.log browser.log probe.log)
  # Written by `make screenshot-install`: the installed copy has no Git
  # checkout of its own, so it records the repository it came from.
  @origin Path.expand("screenshot/repo", __DIR__)

  # The read ban of interactive sessions (#462): closed in the profile even
  # if an allow covered them.
  @denied [
    "~/Library/Application Support/ratsprojekte",
    "~/Library/Mobile Documents/iCloud~md~obsidian",
    "~/.ssh",
    "~/.config/gh",
    "~/Library/Keychains",
    "~/.claude"
  ]

  @resolver_rule "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"

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
    @resolver_rule,
    # The hub serves HTTPS with a throwaway certificate of this run (see start_hub/1).
    "--ignore-certificate-errors"
  ]

  @usage """
  Aufruf: komki-screenshot --route /stand [--route …] [--navigate /:/stand]
                 [--theme light,dark] [--width 390,1280] [--worktree PFAD] [--out ORDNER]
          komki-screenshot --spec DATEI.json [--worktree PFAD] [--out ORDNER]
          komki-screenshot --probe [--worktree PFAD] [--out ORDNER]
  (komki-screenshot aus make screenshot-install; im Checkout: elixir scripts/screenshot.exs)
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
    sandbox_exec!()

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

  # Inside the Claude sandbox, macOS refuses a second profile.
  defp sandbox_exec! do
    case System.cmd(@sandbox_exec, ["-p", "(version 1)(allow default)", "/usr/bin/true"],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        :ok

      {out, _} ->
        fail("""
        sandbox-exec greift nicht (#{String.trim(out)}).
        Das Werkzeug muss außerhalb der Claude-Sandbox laufen: nur als nackter Aufruf, ohne cd, Pipe oder &&.
        """)
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

    put!(out, "denials.log", Enum.join(lines, "\n") <> "\n")
  end

  # -- inputs --------------------------------------------------------------

  # Only a worktree of this repository: its whole tree becomes readable in
  # the profile, so a path like $HOME must never pass.
  defp worktree!(path) do
    path = Seatbelt.canonical(path)
    common = repo_common_dir()

    cond do
      # The profile reads the whole worktree: no temp directory (other
      # sessions' files) and nothing that holds a place of the read ban.
      Enum.any?(tmp_roots(), &inside?(path, &1)) ->
        fail("#{path} liegt unter einem Temp-Ordner; nur echte Worktrees.")

      Enum.any?(@denied, &inside?(Seatbelt.canonical(&1), path)) ->
        fail("#{path} enthält einen gesperrten Ort.")

      git(path, ~w(rev-parse --show-toplevel)) != {:ok, path} ->
        fail("#{path} ist nicht die Wurzel eines Git-Worktrees.")

      common == nil or git_common_dir(path) != common ->
        fail("#{path} ist kein Worktree dieses Repositorys.")

      not File.exists?(Path.join([path, @app, "mix.exs"])) ->
        fail("#{path} enthält keinen Hub (#{@app}).")

      not File.dir?(Path.join(path, "apps/artifacts/deps")) ->
        fail("Im Worktree fehlen die Deps: erst `mix workspace.run -t deps.get` in #{path}.")

      # Seeds the throwaway build (seed_build!/2); native code such as the
      # SQLCipher NIF does not compile under the profile.
      not File.dir?(Path.join([path, @app, "_build/dev"])) ->
        fail(
          "Im Worktree fehlt der Build des Hubs: erst `mix compile` in #{Path.join(path, @app)}."
        )

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
        unless match?({:ok, %File.Stat{type: :regular}}, File.lstat(marker)),
          do: fail("#{path} ist nicht leer und stammt nicht von diesem Werkzeug.")

      _ ->
        File.mkdir_p!(path)
        File.write!(marker, "", [:exclusive])
    end

    for old <-
          Path.wildcard(Path.join(path, "*.{png,log,sb}")) ++ [Path.join(path, "manifest.json")],
        do: File.rm(old)

    path
  end

  defp roots(worktree), do: Enum.uniq([worktree | tmp_roots()])

  defp tmp_roots, do: Enum.uniq(Enum.map([System.tmp_dir!(), "/tmp"], &Seatbelt.canonical/1))

  # The tool reads the shot list outside any sandbox, and its error messages
  # quote what they reject: only small regular files inside the worktree or
  # /tmp, symlinks resolved. The file read is tied to the checked path by its
  # inode, so a symlink swapped in between does not pass.
  defp read_spec!(file, worktree) do
    fd = open_spec!(file)

    try do
      {:ok, info} = :file.read_file_info(fd)
      path = Seatbelt.canonical(file)

      cond do
        not Enum.any?(roots(worktree), &inside?(path, &1)) or
            Enum.any?(@denied, &inside?(path, Seatbelt.canonical(&1))) ->
          fail("Die Liste der Aufnahmen muss im Worktree oder unter /tmp liegen: #{file}")

        not same_file?(info, File.stat(path)) ->
          fail("#{file} hat sich beim Lesen geändert.")

        elem(info, 2) != :regular or elem(info, 1) > 65_536 ->
          fail("#{file} ist keine Datei bis 64 KB.")

        true ->
          text = with {:ok, text} <- :file.read(fd, 65_536), do: text, else: (_ -> "")
          decode!(text, file)
      end
    after
      File.close(fd)
    end
  end

  defp open_spec!(file) do
    case File.open(file, [:read, :binary]) do
      {:ok, fd} -> fd
      {:error, reason} -> fail("#{file}: #{:file.format_error(reason)}")
    end
  end

  # :file_info of the open handle (fstat): size at 1, type at 2,
  # major_device at 9, inode at 11.
  defp same_file?(info, {:ok, %File.Stat{inode: inode, major_device: dev}}),
    do: elem(info, 11) == inode and elem(info, 9) == dev

  defp same_file?(_, _), do: false

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
      tmp = "#{path}.#{System.unique_integer([:positive])}.part"
      File.write!(tmp, bin, [:exclusive])
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

  # Next to the installed copy, where neither the Claude sandbox nor
  # Edit/Write reaches: the tool writes the build and boot script there
  # unconfined, and the profile lets the hub write all of it. Under $TMPDIR a
  # session could plant the name as a symlink or swap files in between.
  defp scratch! do
    File.mkdir_p!(@runs)
    dir = Path.join(@runs, hex(:crypto.strong_rand_bytes(8)))

    case File.mkdir(dir) do
      :ok -> :ok
      {:error, reason} -> fail("Wegwerf-Ordner #{dir}: #{:file.format_error(reason)}")
    end

    for sub <- ~w(home tmp hex chrome), do: File.mkdir!(Path.join(dir, sub))
    Seatbelt.canonical(dir)
  end

  defp context(worktree, out, scratch, browser, esbuild, tailwind) do
    app = Path.join(worktree, @app)
    build = seed_build!(worktree, app, Path.join(scratch, "build"))
    elixir_root = Seatbelt.canonical(Path.expand("../..", to_string(:code.lib_dir(:elixir))))
    erlang_root = Seatbelt.canonical(to_string(:code.root_dir()))
    mix_home = System.get_env("MIX_HOME") || Path.expand("~/.mix")

    paths = %{
      erlang_root: erlang_root,
      elixir_root: elixir_root,
      mix_archives: Seatbelt.canonical(Path.join(mix_home, "archives")),
      worktree: worktree,
      # The scratch directory with the hub's throwaway build; nothing in
      # the worktree.
      writable: [scratch],
      programs: [esbuild, tailwind],
      browser: browser.dir,
      dylib_dirs: nif_dylib_dirs(build, [erlang_root, worktree, scratch]),
      logs: Enum.map(@logs, &Path.join(out, &1)),
      denied: Enum.map(@denied, &Seatbelt.canonical/1),
      hub_port: free_port()
    }

    # Fresh regular files with a single link: the shells under the profile
    # append to them, so a link planted before the run must not stay.
    Enum.each(@logs, &put!(out, &1, ""))
    # Handed to sandbox-exec as text: no file anyone could swap before launch.
    profile = Profile.render(paths)
    put!(out, "profile.sb", profile)

    %{
      worktree: worktree,
      app: app,
      build: build,
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

  # The hub builds into the scratch directory (MIX_BUILD_PATH), never into
  # the worktree. A copy of the worktree's dev build seeds it, so only what
  # changed compiles in the sandbox. Mix links priv and include relatively;
  # the copy sits elsewhere, so those links point back to their absolute
  # targets.
  # The copy runs outside any sandbox, so neither the build folder nor a
  # link the copy re-points may lead out of the worktree.
  defp seed_build!(worktree, app, build) do
    source = Path.join(app, "_build/dev")

    unless Seatbelt.canonical(source) == source and
             match?({:ok, %File.Stat{type: :directory}}, File.lstat(source)),
           do: fail("#{source} ist kein Ordner im Worktree (Symlink?).")

    case System.cmd("/bin/cp", ["-Rp", source <> "/", build], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {out, _} -> fail("Build des Worktrees nicht kopiert:\n" <> out)
    end

    for dep <- File.ls!(Path.join(build, "lib")), sub <- ~w(priv include) do
      link = Path.join([build, "lib", dep, sub])

      with {:ok, target} <- File.read_link(link) do
        target = Path.expand(target, Path.join([source, "lib", dep]))

        unless inside?(Seatbelt.canonical(target), worktree),
          do: fail("#{link} zeigt aus dem Worktree heraus: #{target}")

        File.rm!(link)
        File.ln_s!(target, link)
      end
    end

    build
  end

  defp nif_dylib_dirs(build, own_roots) do
    dirs =
      Path.join(build, "lib/*/priv/**/*.so")
      |> Path.wildcard()
      |> Enum.flat_map(&Seatbelt.MachODeps.dylib_dirs/1)

    case Profile.dylib_dirs(dirs, own_roots) do
      {:ok, dirs} ->
        dirs

      {:error, dir} ->
        fail("NIF-Bibliothek außerhalb von #{Enum.join(Profile.dylib_roots(), ", ")}: #{dir}")
    end
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
        [@sandbox_exec, "-p", ctx.profile, "/bin/sh", "-c", ~s{exec "$0" "$@" } <> redirect] ++
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
  # Static files come from a copy of priv inside the throwaway build, and the
  # asset builders write there: the worktree stays untouched.
  priv = Path.join(Mix.Project.app_path(), "priv")
  File.rm_rf!(priv)
  File.cp_r!(Path.expand("priv"), priv)
  assets = Path.join(priv, "static/assets")
  File.rm_rf!(assets)
  Enum.each(~w(js css), &File.mkdir_p!(Path.join(assets, &1)))

  retarget = fn app, flag, path ->
    config = Application.fetch_env!(app, :ratsprojekte)

    args =
      Enum.map(config[:args], fn arg ->
        if String.starts_with?(arg, flag), do: flag <> path, else: arg
      end)

    Application.put_env(app, :ratsprojekte, Keyword.put(config, :args, args))
  end

  retarget.(:esbuild, "--outdir=", Path.join(assets, "js"))
  retarget.(:tailwind, "--output=", Path.join(assets, "css/app.css"))
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
    File.write!(boot, @boot, [:exclusive])
    # The boot script removes the copied bundles, so only this run's build counts.
    static = Path.join(ctx.build, "lib/ratsprojekte/priv/static/assets")
    assets = Enum.map(~w(js/app.js css/app.css), &Path.join(static, &1))

    env =
      env(ctx, [
        {"MIX_ENV", "dev"},
        {"MIX_BUILD_PATH", ctx.build},
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

  defp start_browser(ctx, flags \\ @browser_flags, profile_dir \\ "chrome") do
    log = Path.join(ctx.out, "browser.log")
    argv = [ctx.browser, "--user-data-dir=" <> Path.join(ctx.scratch, profile_dir) | flags]
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

        put!(ctx.out, "manifest.json", JSON.encode!(manifest))
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
      capture!(cdp, session, out, file, %{
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
    cdp = capture!(cdp, session, out, file, %{})

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

  defp capture!(cdp, session, out, file, params) do
    {%{"data" => data}, cdp} =
      CDP.call!(cdp, "Page.captureScreenshot", Map.put(params, "format", "png"), session)

    put!(out, file, Base.decode64!(data))
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
  # BEAM and the browser try to read the hub folder and ~/.ssh, to write into
  # the worktree and to reach the network; one loopback connection and one
  # write into the scratch directory are the positive controls.
  @probe """
  [hub, ssh, hub_port, other_port, worktree, app] = System.argv()
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
    {"BEAM verbindet zum Hub-Port auf 127.0.0.1 (Positivkontrolle)", fn -> :gen_tcp.connect({127, 0, 0, 1}, hub_port, [], 3000) end},
    {"BEAM schreibt in den Worktree", fn -> File.write(Path.join(worktree, ".komki-probe"), "") end},
    {"BEAM schreibt in den Build-Ordner des Hubs im Worktree",
     fn -> File.write(Path.join(app, "_build/dev/.komki-probe"), "") end},
    {"BEAM schreibt in die Assets des Hubs im Worktree",
     fn -> File.write(Path.join(app, "priv/static/assets/.komki-probe"), "") end},
    {"BEAM schreibt in den Wegwerf-Ordner (Positivkontrolle)",
     fn -> File.write(Path.join(System.fetch_env!("TMPDIR"), ".komki-probe"), "") end}
  ]

  for {name, fun} <- checks do
    result = try do: fun.(), rescue: (e -> {:error, Exception.message(e)})
    verdict = if result == :ok or match?({:ok, _}, result), do: "erreicht", else: "verweigert"
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
        to_string(other_port),
        ctx.worktree,
        ctx.app
      ])

    receive do: ({^beam, {:exit_status, _}} -> :ok), after: (60_000 -> stop(beam))
    # Should a write have passed, it leaves nothing behind.
    Enum.each(
      [ctx.worktree, Path.join(ctx.app, "_build/dev"), Path.join(ctx.app, "priv/static/assets")],
      &File.rm(Path.join(&1, ".komki-probe"))
    )

    beam_rows =
      for "PROBE\t" <> row <- String.split(read_log(log), "\n") do
        [name, verdict, detail] = String.split(row, "\t", parts: 3)
        {name, verdict, detail}
      end

    browser_rows =
      browse_all(ctx, @browser_flags, "chrome", [
        {"Browser öffnet http://1.1.1.1/", "http://1.1.1.1/"},
        {"Browser öffnet http://example.com/", "http://example.com/"},
        {"Browser öffnet den Hub-Ordner", "file://" <> ctx.hub <> "/"},
        {"Browser öffnet ~/.ssh", "file://" <> ctx.ssh <> "/"},
        {"Browser öffnet einen anderen Port auf 127.0.0.1", "http://127.0.0.1:#{other_port}/"},
        {"Browser öffnet den Hub-Port auf 127.0.0.1 (Positivkontrolle)",
         "http://127.0.0.1:#{ctx.hub_port}/"}
      ]) ++
        browse_all(ctx, @browser_flags -- [@resolver_rule], "chrome-no-resolver", [
          {"Browser ohne Resolver-Regel öffnet http://1.1.1.1/", "http://1.1.1.1/"},
          {"Browser ohne Resolver-Regel öffnet http://example.com/", "http://example.com/"}
        ])

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

    if length(beam_rows) != 11 or Enum.any?(rows, fn {n, v, _} -> v != expected.(n) end) do
      fail("Probe nicht bestanden.\n" <> tail(log))
    end

    IO.puts("Probe bestanden: #{length(rows)} Kontrollen.")
  end

  # The network controls once more without the resolver rule: then only the
  # profile stands between the browser and the internet.
  defp browse_all(ctx, flags, profile_dir, checks) do
    {cdp, session} = start_browser(ctx, flags, profile_dir)

    {rows, cdp} =
      Enum.map_reduce(checks, cdp, fn {name, url}, cdp -> browse(cdp, session, name, url) end)

    close_browser(cdp)
    rows
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

  defp repo_common_dir do
    case File.read(@origin) do
      {:ok, path} -> Seatbelt.canonical(String.trim(path))
      _ -> git_common_dir(Path.expand("..", __DIR__))
    end
  end

  defp git_common_dir(dir) do
    case git(dir, ~w(rev-parse --path-format=absolute --git-common-dir)) do
      {:ok, path} -> Seatbelt.canonical(path)
      _ -> nil
    end
  end

  # The output folder is writable for the session, and the tool writes
  # outside any sandbox: each file is created exclusively under a fresh name
  # (O_EXCL never follows a symlink) and renamed into place, which replaces a
  # planted symlink instead of writing through it.
  defp put!(dir, name, data) do
    tmp = Path.join(dir, ".#{name}.#{System.unique_integer([:positive])}")
    File.write!(tmp, data, [:exclusive])
    File.rename!(tmp, Path.join(dir, name))
  end

  defp inside?(path, root), do: path == root or String.starts_with?(path, root <> "/")

  defp deadline(ms), do: System.monotonic_time(:millisecond) + ms

  defp tail(log), do: log |> read_log() |> String.split("\n") |> Enum.take(-30) |> Enum.join("\n")

  # The logs lie where the session and the hub code under the profile can
  # swap them, and the tool reads them unconfined and prints their tail. It
  # reads only a regular file with a single link whose open handle (fstat)
  # is the very file the path names without following a symlink (lstat):
  # neither a symlink nor a hard link to a protected file passes.
  defp read_log(log) do
    # lstat first: opening a planted FIFO would block.
    with {:ok, %File.Stat{type: :regular}} <- File.lstat(log),
         {:ok, fd} <- File.open(log, [:read, :binary]) do
      try do
        with {:ok, info} <- :file.read_file_info(fd),
             {:ok, %File.Stat{type: :regular} = stat} <- File.lstat(log),
             true <- elem(info, 8) == 1 and same_file?(info, {:ok, stat}),
             {:ok, text} <- :file.read(fd, max(elem(info, 1), 1)) do
          text
        else
          :eof -> ""
          _ -> "(Log nicht lesbar: keine eigene Datei)"
        end
      after
        File.close(fd)
      end
    else
      _ -> "(kein Log)"
    end
  end

  defp hex(digest), do: Base.encode16(digest, case: :lower)

  # Raises instead of halting, so every `after` stops server and browser and
  # removes the scratch directory.
  defp fail(message), do: raise(Screenshot.Error, message)
end

Screenshot.main(System.argv())
