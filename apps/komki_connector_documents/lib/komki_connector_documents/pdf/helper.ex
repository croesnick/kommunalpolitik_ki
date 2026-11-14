defmodule KomkiConnectorDocuments.Pdf.Helper do
  @moduledoc """
  Renders a PDF in a separate OS process (ticket #488, audit finding F17).

  `Pdf.render/1` no longer loads the pdfium NIF into the connector VM. It
  spawns a second BEAM — the `erl` of the running runtime, with the
  connector's own code directories on the `-pa` path — that bootstraps
  Elixir, calls `Pdf.render_in_process/1` and prints the marker followed
  by the external term of the result. The child inherits the connector's
  Seatbelt profile: a macOS sandbox applies to a process and everything it
  spawns (nesting `sandbox-exec` is impossible, CONTRACT.md §2), so "under
  the same profile" is what fork/exec already gives.

  Bounds of the child:

    * a wallclock timeout, defaulted below the mediator's 15 s per call
      (CONTRACT.md §3): a killed child becomes a per-request
      `upstream-error`;
    * an rlimit attempt on the address space, applied by the shell wrapper
      before `exec`. The macOS kernel rejects every RLIMIT_AS change with
      EINVAL (measured 2026-11-14: `setrlimit`/`ulimit -v` fails at any
      value; Darwin pins the limit to unlimited), so on this platform the
      attempt stays without effect and the effective bounds are the
      timeout and the crash isolation — kernels that honor RLIMIT_AS get
      the bound for free;
    * crash isolation: a native crash, OOM or timeout kills the child
      alone, never the connector.

  Deliberately open (#488): ex_pdfium has no decompression budget. A page
  whose content stream expands far beyond the file size keeps allocating in
  the child until the wallclock kills it (bomb measurements in the
  ticket); that bound belongs into the external hex package, not here.

  ## Child protocol

  stdout of the child: `@marker` (written before anything else can fail,
  proving this module loaded), then `term_to_binary` of the
  `Pdf.render_in_process/1` result. Exit 0 with a decodable term is the
  only success path. A child that dies with the marker written died inside
  the render (`upstream-error`); without it, it never became runnable
  (`internal`) — for example in an escript context, where the code path is
  the zipped archive and no plain `erl` can load the module (#288).
  """

  alias KomkiConnectorDocuments.Pdf

  # A child result: how the OS process ended and what it wrote.
  @type child :: {:done, non_neg_integer(), binary()} | :timeout | :overflow

  @shell "/bin/sh"

  # The fixed eval of the child; no input is ever interpolated into it.
  @eval "KomkiConnectorDocuments.Pdf.Helper.run()"

  # One byte before anything else: it proves the child loaded this module
  # and tells a death inside the render apart from a child that never
  # became runnable.
  @marker "H"

  @default_timeout_ms 12_000

  # Address space bound for the child in KiB. macOS rejects any change to
  # RLIMIT_AS (see the moduledoc), so this only takes effect on kernels
  # that honor the limit.
  @address_limit_kib 4_194_304

  # Marker plus the external term of at most one frame's payload; more
  # output cannot be a legitimate reply.
  @max_output_bytes Sidecar.Frame.max_bytes() + 128

  @bad_reply "Antwort des PDF-Hilfsprozesses unbrauchbar"

  @doc """
  Renders `path` in a separate OS process and relays the result of
  `Pdf.render_in_process/1`. `timeout_ms` overrides the wallclock budget.
  """
  @spec render(Path.t(), timeout_ms: pos_integer()) :: Pdf.result()
  def render(path, opts \\ []) do
    timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

    path
    |> command()
    |> run_child(timeout)
    |> classify(timeout)
  end

  @doc """
  Maps a child outcome to the connector's reply (pure, for tests): exit 0
  with the marker decodes the relayed result, a death after the marker is a
  crash or OOM inside the render (`upstream-error`, #488), a death without
  it means the child never became runnable (`internal`), and the wallclock
  kill is the per-request `upstream-error` of #488.
  """
  @spec classify(child(), pos_integer()) :: Pdf.result()
  def classify({:done, 0, output}, _timeout), do: relay(output)

  def classify({:done, status, @marker <> _rest}, _timeout),
    do: {:error, "upstream-error", "PDF-Hilfsprozess abgestuerzt (Exit #{status})"}

  def classify({:done, status, _output}, _timeout),
    do: {:error, "internal", "PDF-Hilfsprozess nicht lauffaehig (Exit #{status})"}

  def classify(:timeout, timeout),
    do: {:error, "upstream-error", "PDF-Hilfsprozess nach #{timeout} ms abgebrochen"}

  def classify(:overflow, _timeout),
    do: {:error, "internal", "Antwort des PDF-Hilfsprozesses zu lang"}

  @doc """
  Child entry, evaluated by the spawn command in a plain `erl` — never
  call it from the connector itself. The marker goes out before anything
  can fail, the render result follows as an external term.
  """
  @spec run() :: :ok
  def run do
    # Byte-transparent stdout: the io protocol re-encodes chardata in the
    # device encoding, and in unicode mode every byte above 127 of the
    # external term would grow to two UTF-8 bytes (measured: 131 became
    # 194,131) — the parent could never decode it. Latin-1 keeps the
    # protocol byte-per-byte.
    _ = :io.setopts(Process.group_leader(), encoding: :latin1)

    IO.binwrite(@marker)

    [path] = System.argv()
    IO.binwrite(:erlang.term_to_binary(Pdf.render_in_process(path)))
  end

  @doc """
  The command line for `/bin/sh` (pure, for tests): the wrapper tries the
  address-space rlimit — silently, kernels without RLIMIT_AS reject it —
  and execs the running runtime's `erl` with the fixed eval. The PDF path
  travels as an argument, never inside the eval.
  """
  @spec command(Path.t()) :: [String.t()]
  def command(path) do
    wrapper = "ulimit -v #{@address_limit_kib} 2> /dev/null || :; exec \"$0\" \"$@\""

    ["-c", wrapper, erl_path(), "-noshell", "-env", "ERL_CRASH_DUMP", "/dev/null"] ++
      code_paths() ++ ["-s", "elixir", "start_cli", "-extra", "-e", @eval, "--", to_string(path)]
  end

  # The erl of the running runtime: the init argument `bindir` names the
  # erts bin directory that started this beam. Under a Burrito release
  # that is <root>/erts-<vsn>/bin — a bare <root>/bin/erl does not exist
  # there (found in the throwaway run, ticket #488); the erl script
  # locates its ROOTDIR by walking up from its own path, so it boots the
  # unpacked release, not the build machine's runtime. Without the
  # argument the empty path makes the spawn fail before the marker
  # (`internal`).
  defp erl_path do
    case :init.get_argument(:bindir) do
      {:ok, [[dir | _] | _]} -> Path.join(dir, "erl")
      _ -> ""
    end
  end

  # Only real directories: a plain erl cannot load from an escript archive
  # (#288), so the archive entry of the code path is dropped.
  defp code_paths do
    :code.get_path()
    |> Enum.map(&to_string/1)
    |> Enum.filter(&File.dir?/1)
    |> Enum.uniq()
    |> Enum.flat_map(&["-pa", &1])
  end

  defp run_child(argv, timeout) do
    port = Port.open({:spawn_executable, @shell}, [:binary, :exit_status, {:args, argv}])
    deadline = make_ref()
    timer = Process.send_after(self(), {:pdf_helper_deadline, deadline}, timeout)

    try do
      collect(port, deadline, "")
    after
      Process.cancel_timer(timer)
      purge(port, deadline)
    end
  end

  # Collects stdout until the child exits, the wallclock deadline passes or
  # the output can no longer be a legitimate reply. Port.close kills the OS
  # process; the bounded wait confirms the kill before the caller moves on.
  defp collect(port, deadline, output) do
    if byte_size(output) > @max_output_bytes do
      stop(port)
      :overflow
    else
      receive do
        {^port, {:data, bytes}} ->
          collect(port, deadline, output <> bytes)

        {^port, {:exit_status, status}} ->
          {:done, status, output}

        {:pdf_helper_deadline, ^deadline} ->
          stop(port)
          :timeout
      end
    end
  end

  defp stop(port) do
    Port.close(port)

    receive do
      {^port, {:exit_status, _status}} -> :ok
    after
      1000 -> :ok
    end
  end

  # The caller keeps serving requests: no message of the finished child may
  # linger in its mailbox.
  defp purge(port, deadline) do
    receive do
      {^port, {:data, _bytes}} -> purge(port, deadline)
      {^port, {:exit_status, _status}} -> purge(port, deadline)
      {:pdf_helper_deadline, ^deadline} -> purge(port, deadline)
    after
      0 -> :ok
    end
  end

  # A success reply is the marker followed by exactly the result term. The
  # safe decode refuses new atoms and functions; anything malformed stays
  # internal — no child byte ever reaches the agent context unvetted.
  defp relay(@marker <> bin) do
    case :erlang.binary_to_term(bin, [:safe]) do
      {:ok, content} when is_binary(content) -> {:ok, content}
      {:error, code, detail} when is_binary(code) and is_binary(detail) -> {:error, code, detail}
      _other -> {:error, "internal", @bad_reply}
    end
  rescue
    _exception -> {:error, "internal", @bad_reply}
  end

  defp relay(_output), do: {:error, "internal", @bad_reply}
end
