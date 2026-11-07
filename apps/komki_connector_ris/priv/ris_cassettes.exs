# Encrypt cassettes: AES-256-GCM per cassette, key only via Touch ID from
# the Secure Enclave (komki-tresor).
#
#     elixir apps/komki_connector_ris/priv/ris_cassettes.exs init
#     elixir apps/komki_connector_ris/priv/ris_cassettes.exs seal <verzeichnis>
#     elixir apps/komki_connector_ris/priv/ris_cassettes.exs unseal <verzeichnis>
#     elixir apps/komki_connector_ris/priv/ris_cassettes.exs status <verzeichnis>
#     elixir apps/komki_connector_ris/priv/ris_cassettes.exs check [verzeichnis]
#
# init (once) generates a 32-byte key and stores it as a komki-tresor seal
# in the macOS keychain (entry 'ris-kassetten'). Only this Mac's Secure
# Enclave opens the seal — no restore on another Mac, no key escrow; if the
# entry is gone, the cassettes are gone. Every encryption and decryption
# needs exactly one release via Touch ID (or the Mac's password). seal
# writes <name>.json.enc per cassette (magic rkt1, nonce, ciphertext, tag;
# fresh nonce per file) and deletes the plaintext from disk only after the
# read-back verification passed.
#
# Threat model: storage is protected — no process (no agent either) reads
# encrypted cassettes without the person at the Mac. Runtime windows are
# not: during recording and during unseal, plaintext sits on disk
# (optional hardening: recorder --out on a RAM disk, see README). Messages
# never name keys, seals or cassette contents, only names and counters.
#
# Encrypted directories belong outside any Git repo, just like plaintext
# cassettes; seal/unseal reject repos (RisHttp.repo_free?, like
# ris_recorder — through symlinks too). Replay and ris_skeleton read
# *.json: unseal first, seal afterwards.
#
# check (#328) scans plaintext cassettes for secrets before sealing: the
# values from .env (RIS_EMAIL, RIS_PASSWORD) and the token file of the
# config directory, in each cassette's raw text and in the Base64-decoded
# bodies. Without a directory it checks the timestamp directories under
# the cassette base. No Touch ID release needed (like status); messages
# name names and counters, never secret values.
#
# OTP only (:crypto, ports), no deps: a script started with `elixir` cannot
# load komki_cli, so the port patterns are duplicated from it instead of
# imported (docking point: tresor core #224).

Code.require_file("./ris_http.exs", __DIR__)

defmodule KomkiConnectorRis.RisCassettes do
  @moduledoc false

  alias KomkiConnectorRis.RisHttp

  # Stored state, not an identifier: the key of every encrypted cassette
  # lives under this keychain entry. Renaming it would orphan them.
  @service "ris-kassetten"
  # Format label of komki-tresor (native/komki-tresor/main.swift): every seal
  # starts with it. Deliberately a different prefix than @magic so seals and
  # cassette containers are never confused.
  @tresor_prefix "ktv1."
  @tresor_program "komki-tresor"
  @seal_timeout_ms 10_000
  # Opening waits for Touch ID or the password.
  @open_timeout_ms 120_000
  @check_timeout_ms 10_000

  @security "/usr/bin/security"
  @security_timeout_ms 5_000
  # security(1): exit 44 = errSecItemNotFound
  @not_found 44

  @magic "rkt1"
  @key_bytes 32
  @nonce_bytes 12
  @tag_bytes 16

  # security -i splits the line itself: only characters without special
  # meaning (rule copied from komki_cli/lib/komki_cli/keychain.ex). A ktv1.
  # seal in standard Base64 satisfies it; check before storing so security
  # does not silently truncate to 128 bytes.
  @word ~r/\A[A-Za-z0-9@._+\/=-]+\z/

  @usage "Aufruf: init | seal <verzeichnis> | unseal <verzeichnis> | status <verzeichnis> | check [verzeichnis] [--tresor <programm>]"

  # check reads plaintext only — config and base directories are
  # overridable for tests (run/2 opts); the terminal call uses the defaults.
  @config_dir "~/.config/kommunalpolitik_ki"
  @cassette_base "~/.local/share/kommunalpolitik_ki/ris-cassettes"
  @secret_env_keys ~w(RIS_EMAIL RIS_PASSWORD)
  # Recorder session directories are named YYYYMMDDTHHMMSSZ.
  @timestamp ~r/\A\d{8}T\d{6}Z\z/

  @type tresor_error ::
          :missing_bin | :no_enclave | :refused | :invalid | :timeout | {:failed, integer()}
  @type kc_error :: :missing | :timeout | :invalid | :not_stored | {:failed, integer()}
  @type message :: {:out | :err, String.t()}

  # --- CLI ------------------------------------------------------------------

  @doc false
  @spec parse_cli([String.t()]) ::
          {:ok, {String.t(), String.t() | nil, keyword()}} | {:error, String.t()}
  def parse_cli([cmd | rest]) when cmd in ~w(init seal unseal status check) do
    case parse_flags(cmd, rest, nil, []) do
      {:ok, dir, opts} -> {:ok, {cmd, dir, opts}}
      :error -> {:error, @usage}
    end
  end

  def parse_cli(_other), do: {:error, @usage}

  # Exactly one path (init: none), flags in any order after it. A token
  # with a -- prefix is never a path: a --tresor without a value would
  # otherwise silently become the path and report a missing directory.
  defp parse_flags(cmd, ["--tresor", value | rest], dir, opts),
    do: parse_flags(cmd, rest, dir, Keyword.put(opts, :tresor, value))

  defp parse_flags(cmd, [dir | rest], nil, opts)
       when cmd in ~w(seal unseal status check) and
              (byte_size(dir) < 2 or binary_part(dir, 0, 2) != "--"),
       do: parse_flags(cmd, rest, dir, opts)

  defp parse_flags("init", [], nil, opts), do: {:ok, nil, opts}
  # check without a directory: the timestamp directories of the base.
  defp parse_flags("check", [], nil, opts), do: {:ok, nil, opts}
  defp parse_flags(_cmd, [], dir, opts) when is_binary(dir), do: {:ok, dir, opts}
  defp parse_flags(_cmd, _other, _dir, _opts), do: :error

  @doc """
  Process the command line and return `{exit_code, messages}` (instead of
  exiting) — tests run through this, the runner only prints.
  """
  @spec run([String.t()], keyword()) :: {non_neg_integer(), [message()]}
  def run(argv, opts \\ []) do
    case parse_cli(argv) do
      {:ok, {"init", nil, flag}} ->
        init(Keyword.merge(opts, flag))

      {:ok, {cmd, dir, flag}} when cmd in ~w(seal unseal status) ->
        opts = Keyword.merge(opts, flag)
        dir = Path.expand(dir)

        case cmd do
          "seal" -> seal(dir, opts)
          "unseal" -> unseal(dir, opts)
          "status" -> status(dir, opts)
        end

      {:ok, {"check", dir, flag}} ->
        opts = Keyword.merge(opts, flag)
        check(if(dir, do: Path.expand(dir)), opts)

      {:error, usage} ->
        {2, [{:err, "ris_cassettes: #{usage}"}]}
    end
  end

  # --- komki-tresor (binary over a pipe) -------------------------------------

  @doc false
  @spec tresor_bin(keyword()) :: String.t() | nil
  def tresor_bin(opts) do
    case Keyword.get(opts, :tresor) do
      nil ->
        System.find_executable(@tresor_program)

      # Typo in the --tresor path: nil instead of an ugly port crash. An
      # existing but non-executable path is only caught at spawn
      # (safe_spawn) and becomes missing_bin as well.
      path ->
        if path |> Path.expand() |> File.exists?(), do: Path.expand(path), else: nil
    end
  end

  @doc """
  Check the program's Secure Enclave (`check` subcommand), with a timeout:
  a hanging program must not block init forever.
  """
  @spec tresor_check(String.t(), keyword()) ::
          :ok | {:error, :no_enclave | :timeout | tresor_error()}
  def tresor_check(command, opts \\ []) do
    case safe_spawn(command, ["check"]) do
      {:ok, port} ->
        timeout = Keyword.get(opts, :check_timeout, @check_timeout_ms)

        port
        |> collect([], System.monotonic_time(:millisecond) + timeout, &tresor_on_exit/2)
        |> case do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      :spawn_failed ->
        {:error, :missing_bin}
    end
  end

  @doc "Seal plaintext. No prompt: sealing only needs the public key."
  @spec tresor_seal(String.t(), keyword()) :: {:ok, String.t()} | {:error, tresor_error()}
  def tresor_seal(value, opts) do
    if one_line?(value) do
      case tresor_call(["seal"], value, Keyword.get(opts, :seal_timeout, @seal_timeout_ms), opts) do
        {:ok, out} ->
          if String.starts_with?(out, @tresor_prefix), do: {:ok, out}, else: {:error, :invalid}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :invalid}
    end
  end

  @doc "Open a seal; macOS asks for Touch ID or the password, showing `reason`."
  @spec tresor_open(String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, tresor_error()}
  def tresor_open(sealed, reason, opts) do
    if String.starts_with?(sealed, @tresor_prefix) and one_line?(sealed) do
      tresor_call(
        ["open", "--reason", reason],
        sealed,
        Keyword.get(opts, :open_timeout, @open_timeout_ms),
        opts
      )
    else
      {:error, :invalid}
    end
  end

  # Plaintext and seals travel only over stdin/stdout, never argv
  # (komki-tresor convention). A failed start (not executable, Gatekeeper)
  # becomes missing_bin instead of a raw exception.
  defp tresor_call(args, input, timeout, opts) do
    case tresor_bin(opts) do
      nil ->
        {:error, :missing_bin}

      bin ->
        case safe_spawn(bin, args) do
          {:ok, port} ->
            Port.command(port, input <> "\n")
            collect(port, [], System.monotonic_time(:millisecond) + timeout, &tresor_on_exit/2)

          :spawn_failed ->
            {:error, :missing_bin}
        end
    end
  end

  defp safe_spawn(bin, args) do
    {:ok, Port.open({:spawn_executable, bin}, [:binary, :exit_status, :use_stdio, args: args])}
  rescue
    _unhandled -> :spawn_failed
  end

  # stderr stays in the terminal (the program's messages, without values);
  # stdout carries exactly one line. Exit codes as in komki-tresor: 3 no
  # enclave, 4 no release, 5 invalid seal.
  defp collect(port, acc, deadline, on_exit) do
    left = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} -> collect(port, [acc, data], deadline, on_exit)
      {^port, {:exit_status, code}} -> on_exit.(code, acc)
    after
      left -> kill(port)
    end
  end

  defp tresor_on_exit(0, acc), do: {:ok, acc |> IO.iodata_to_binary() |> String.trim_trailing()}
  defp tresor_on_exit(3, _acc), do: {:error, :no_enclave}
  defp tresor_on_exit(4, _acc), do: {:error, :refused}
  defp tresor_on_exit(5, _acc), do: {:error, :invalid}
  defp tresor_on_exit(code, _acc), do: {:error, {:failed, code}}

  @doc false
  @spec tresor_text(tresor_error()) :: String.t()
  def tresor_text(:missing_bin),
    do:
      "komki-tresor nicht gefunden oder nicht ausfuehrbar (Installation pruefen oder --tresor <programm>)"

  def tresor_text(:no_enclave), do: "keine Secure Enclave auf diesem Mac"
  def tresor_text(:refused), do: "Freigabe per Touch ID oder Passwort verweigert oder abgebrochen"
  def tresor_text(:invalid), do: "Siegel ungueltig oder von einem anderen Mac"
  def tresor_text(:timeout), do: "keine Freigabe rechtzeitig"
  def tresor_text({:failed, code}), do: "komki-tresor fehlgeschlagen (exit #{code})"

  # Exit codes: 3 tresor/enclave missing, 4 no release, 5 invalid seal,
  # 1 program failed otherwise.
  defp tresor_exit(:missing_bin), do: 3
  defp tresor_exit(:no_enclave), do: 3
  defp tresor_exit(:refused), do: 4
  defp tresor_exit(:timeout), do: 4
  defp tresor_exit(:invalid), do: 5
  defp tresor_exit({:failed, _code}), do: 1

  # Sealing triggers no release: a timeout there is not an aborted
  # release but a hanging program (exit 1, not 4).
  defp tresor_seal_exit(:timeout), do: 1
  defp tresor_seal_exit({:failed, _code}), do: 1
  defp tresor_seal_exit(other), do: tresor_exit(other)

  defp one_line?(value),
    do: is_binary(value) and value != "" and not String.contains?(value, ["\n", "\r"])

  # --- Keychain ---------------------------------------------------------------

  @doc false
  @spec kc_present(String.t(), keyword()) :: :ok | {:error, kc_error()}
  def kc_present(service, opts) do
    case kc_run(["find-generic-password", "-s", service], opts) do
      {:ok, _attributes} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  @spec kc_fetch(String.t(), keyword()) :: {:ok, String.t()} | {:error, kc_error()}
  def kc_fetch(service, opts) do
    case kc_run(["find-generic-password", "-s", service, "-w"], opts) do
      {:ok, out} ->
        case String.trim_trailing(out, "\n") do
          "" -> {:error, :missing}
          value -> {:ok, value}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  CREATE a value as a generic password (init only). The value never appears
  in argv (every process would see it via ps); `add-generic-password -w`
  without a value would truncate it interactively to 128 bytes, so the whole
  command goes as one line to `security -i` (pattern from
  komki_cli/lib/komki_cli/keychain.ex). No `-U`: if the entry exists after
  all (race with a second init), the command fails instead of silently
  replacing — a new key would make every cassette encrypted so far
  unreadable. Read back and compare afterwards.
  """
  @spec kc_put_new(String.t(), String.t(), keyword()) :: :ok | {:error, kc_error()}
  def kc_put_new(service, value, opts) do
    account = System.get_env("USER") || "komki"

    with :ok <- plain_words([service, account, value]),
         {:ok, _} <- kc_interactive(service, account, value, opts) do
      case kc_fetch(service, opts) do
        {:ok, ^value} -> :ok
        {:ok, _other} -> {:error, :not_stored}
        {:error, reason} -> {:error, reason}
      end
    else
      :invalid -> {:error, :invalid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp plain_words(words) do
    if Enum.all?(words, &(&1 =~ @word)), do: :ok, else: :invalid
  end

  # `head -n 1` closes stdin after the one line; `security -i` then exits.
  defp kc_interactive(service, account, value, opts) do
    command = Keyword.get(opts, :security, @security)

    with {:ok, port} <-
           spawn_sh(command, "head -n 1 | exec \"$0\" -i >/dev/null 2>&1") do
      line =
        Enum.join(["add-generic-password", "-s", service, "-a", account, "-w", value], " ")

      Port.command(port, line <> "\n")
      collect(port, [], System.monotonic_time(:millisecond) + timeout(opts), &kc_on_exit/2)
    end
  end

  @doc false
  @spec kc_text(kc_error()) :: String.t()
  def kc_text(:missing), do: "Schluesselbund-Eintrag '#{@service}' fehlt"
  def kc_text(:timeout), do: "Schluesselbund-Abfrage nach Timeout abgebrochen"
  def kc_text(:invalid), do: "Wert unzulaessig fuer den Schluesselbund (leer oder Sonderzeichen)"
  def kc_text(:not_stored), do: "Eintrag enthaelt nach dem Schreiben einen anderen Wert"

  def kc_text({:failed, code}),
    do: "Schluesselbund-Befehl fehlgeschlagen (exit #{code})"

  # A port instead of System.cmd: the only way to stop a hanging security
  # after the timeout. stderr is discarded and never shows up in messages.
  defp kc_run(args, opts) do
    command = Keyword.get(opts, :security, @security)

    with {:ok, port} <- spawn_sh(command, "exec \"$0\" \"$@\" 2>/dev/null </dev/null", args) do
      collect(port, [], System.monotonic_time(:millisecond) + timeout(opts), &kc_on_exit/2)
    end
  end

  defp spawn_sh(command, script, args \\ []) do
    {:ok,
     Port.open({:spawn_executable, "/bin/sh"}, [
       :binary,
       :exit_status,
       :use_stdio,
       args: ["-c", script, command | args]
     ])}
  rescue
    _unhandled -> {:error, {:failed, :spawn}}
  end

  defp timeout(opts), do: Keyword.get(opts, :security_timeout, @security_timeout_ms)

  defp kc_on_exit(0, acc), do: {:ok, IO.iodata_to_binary(acc)}
  defp kc_on_exit(@not_found, _acc), do: {:error, :missing}
  defp kc_on_exit(code, _acc), do: {:error, {:failed, code}}

  # After the timeout the program may still be running. With pipelines
  # (security -i) the children would otherwise be orphaned when the parent
  # dies and keep running — so children first, then the parent. badarg
  # covers a port that is already gone.
  defp kill(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        if File.exists?("/usr/bin/pkill") do
          _ = System.cmd("/usr/bin/pkill", ["-KILL", "-P", to_string(pid)])
        end

        System.cmd("/bin/kill", ["-KILL", to_string(pid)])

      nil ->
        :ok
    end

    Port.close(port)
    {:error, :timeout}
  catch
    :error, :badarg -> {:error, :timeout}
  end

  # --- Crypto -------------------------------------------------------------------

  # AES-256-GCM, fresh nonce per file, magic as AAD binds the container
  # version to the ciphertext. OTP 29: encrypt returns {ciphertext, tag};
  # decrypt reports a mismatch as :error instead of raising. Empty
  # cassettes are allowed too (ciphertext of length 0).
  defp sealed_blob(plain, key) do
    nonce = :crypto.strong_rand_bytes(@nonce_bytes)
    {ct, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, plain, @magic, true)
    [@magic, nonce, ct, tag]
  end

  # {:ok, plaintext} | {:error, :bad_magic | :too_short | :bad_tag}
  defp open_blob(blob, key) do
    cond do
      not String.starts_with?(blob, @magic) ->
        {:error, :bad_magic}

      byte_size(blob) < byte_size(@magic) + @nonce_bytes + @tag_bytes ->
        {:error, :too_short}

      true ->
        nonce = binary_part(blob, byte_size(@magic), @nonce_bytes)
        ct_start = byte_size(@magic) + @nonce_bytes
        tag_start = byte_size(blob) - @tag_bytes

        ct = binary_part(blob, ct_start, tag_start - ct_start)
        tag = binary_part(blob, tag_start, @tag_bytes)

        case :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, ct, @magic, tag, false) do
          plain when is_binary(plain) -> {:ok, plain}
          _corrupt -> {:error, :bad_tag}
        end
    end
  end

  # --- Loading the key ----------------------------------------------------------

  # Exactly ONE release per run: read the seal once, open it once. The
  # tresor is checked first — a missing program is the more fundamental
  # failure and must not hide behind a keychain message. An entry without
  # the ktv1. prefix is plaintext — opening it would be pointless.
  defp load_master_key(reason, opts) do
    case tresor_bin(opts) do
      nil ->
        {:error, {:tresor, :missing_bin}}

      _bin ->
        case kc_fetch(@service, opts) do
          {:ok, sealed} ->
            if String.starts_with?(sealed, @tresor_prefix) do
              case tresor_open(sealed, reason, opts) do
                {:ok, line} -> decode_key(line)
                {:error, reason} -> {:error, {:tresor, reason}}
              end
            else
              {:error, :unsealed}
            end

          {:error, reason} ->
            {:error, {:keychain, reason}}
        end
    end
  end

  defp decode_key(line) do
    with {:ok, key} <- Base.decode64(line),
         true <- byte_size(key) == @key_bytes do
      {:ok, key}
    else
      _ -> {:error, :invalid_key}
    end
  end

  defp master_key_error(:unsealed),
    do: {5, [{:err, "ris_cassettes: Eintrag '#{@service}' ist kein Siegel; init laufen lassen"}]}

  defp master_key_error(:invalid_key),
    do: {5, [{:err, "ris_cassettes: Schluessel im Siegel hat falsche Form"}]}

  defp master_key_error({:keychain, :missing}),
    do: {5, [{:err, "ris_cassettes: Eintrag '#{@service}' fehlt; zuerst init"}]}

  defp master_key_error({:keychain, reason}),
    do: {1, [{:err, "ris_cassettes: #{kc_text(reason)}"}]}

  defp master_key_error({:tresor, reason}),
    do: {tresor_exit(reason), [{:err, "ris_cassettes: #{tresor_text(reason)}"}]}

  # --- Directories ----------------------------------------------------------------

  @doc """
  `:ok` if `dir` lies outside any Git repo — worktrees too (whose `.git` is
  a file) and symlinks leading into one (RisHttp.repo_free? resolves
  existing paths). Encrypted cassettes belong in a repo as little as
  plaintext does.
  """
  @spec check_dir(Path.t()) :: :ok | {:error, {:dir_in_repo, Path.t()}}
  def check_dir(dir) do
    case RisHttp.repo_free?(dir) do
      :ok -> :ok
      {:error, {:in_repo, repo}} -> {:error, {:dir_in_repo, repo}}
    end
  end

  # One listing per run (instead of File.ls! plus one File.exists? per
  # file): counters and collision checks come from the same snapshot.
  # ".json.enc" does not end in ".json" — the sets are disjoint.
  @spec list_dir(Path.t()) ::
          {:ok, %{json: [String.t()], enc: [String.t()], other: [String.t()]}} | {:error, term()}
  defp list_dir(dir) do
    with {:ok, files} <- File.ls(dir) do
      {enc, rest} = Enum.split_with(files, &String.ends_with?(&1, ".json.enc"))
      {json, other} = Enum.split_with(rest, &String.ends_with?(&1, ".json"))

      {:ok, %{json: Enum.sort(json), enc: Enum.sort(enc), other: Enum.sort(other)}}
    end
  end

  defp json_of_enc(name), do: String.replace_suffix(name, ".enc", "")

  # --- Subcommands -------------------------------------------------------------------

  defp init(opts) do
    case kc_present(@service, opts) do
      :ok ->
        {1,
         [
           {:err,
            "ris_cassettes: Eintrag '#{@service}' existiert bereits; bewusst entfernen mit " <>
              "security delete-generic-password -s #{@service} — danach sind alle bisher " <>
              "verschluesselten Kassetten unlesbar"}
         ]}

      {:error, :missing} ->
        init_create(opts)

      {:error, reason} ->
        {1, [{:err, "ris_cassettes: Schluesselbund nicht abfragbar: #{kc_text(reason)}"}]}
    end
  end

  defp init_create(opts) do
    case tresor_bin(opts) do
      nil ->
        {3, [{:err, "ris_cassettes: #{tresor_text(:missing_bin)}"}]}

      bin ->
        case tresor_check(bin, opts) do
          :ok ->
            init_key(opts)

          {:error, :no_enclave} ->
            {3, [{:err, "ris_cassettes: #{tresor_text(:no_enclave)}"}]}

          # Spawn failed (not executable): the same error as a program that
          # was not found.
          {:error, :missing_bin} ->
            {3, [{:err, "ris_cassettes: #{tresor_text(:missing_bin)}"}]}

          {:error, reason} ->
            {1, [{:err, "ris_cassettes: #{tresor_text(reason)}"}]}
        end
    end
  end

  # Sealing needs no release; the ONE release here is the roundtrip test
  # BEFORE storing — no half-finished state is ever persisted.
  defp init_key(opts) do
    line = Base.encode64(:crypto.strong_rand_bytes(@key_bytes))

    case tresor_seal(line, opts) do
      {:ok, sealed} ->
        case tresor_open(sealed, "RIS-Kassetten-Schluessel zur Kontrolle freigeben", opts) do
          {:ok, ^line} ->
            init_store(sealed, opts)

          {:ok, _other} ->
            {5, [{:err, "ris_cassettes: Roundtrip-Test fehlgeschlagen; nichts gespeichert"}]}

          {:error, reason} ->
            {tresor_exit(reason),
             [{:err, "ris_cassettes: Roundtrip-Test: #{tresor_text(reason)}"}]}
        end

      {:error, reason} ->
        {tresor_seal_exit(reason),
         [{:err, "ris_cassettes: Versiegeln des Schluessels: #{tresor_text(reason)}"}]}
    end
  end

  defp init_store(sealed, opts) do
    case kc_put_new(@service, sealed, opts) do
      :ok ->
        {0,
         [
           {:out,
            "ris_cassettes: Schluessel versiegelt im macOS-Schluesselbund (Eintrag '#{@service}')"},
           {:out,
            "ris_cassettes: Das Siegel oeffnet nur die Secure Enclave dieses Macs — kein Backup, " <>
              "kein Restore auf einem anderen Mac; ohne diesen Mac sind verschluesselte Kassetten unwiederbringlich"},
           {:out,
            "ris_cassettes: Naechster Schritt: elixir apps/komki_connector_ris/priv/ris_cassettes.exs seal <kassettenverzeichnis>"}
         ]}

      {:error, reason} ->
        {kc_store_exit(reason),
         [{:err, "ris_cassettes: Speichern im Schluesselbund fehlgeschlagen: #{kc_text(reason)}"}]}
    end
  end

  # A failed environment (timeout, non-zero exit) is not a seal problem; a
  # diverging or unreadable value is.
  defp kc_store_exit(:timeout), do: 1
  defp kc_store_exit({:failed, _code}), do: 1
  defp kc_store_exit(_other), do: 5

  # --- seal -------------------------------------------------------------------------

  # Cheap checks first (directory, repo, listing, collisions): a rejected
  # run must never trigger a release.
  defp seal(dir, opts) do
    with :ok <- require_dir(dir),
         :ok <- require_repo_free(dir),
         {:ok, files} <- list_ok(dir),
         :ok <- require_collision_free(files, :seal) do
      seal_files(files, dir, opts)
    else
      {:error, code, msg} -> {code, [{:err, msg}]}
    end
  end

  defp seal_files(files, dir, opts) do
    if files.json == [] do
      {0, [{:out, "ris_cassettes: keine Kassetten zu verschluesseln (nur *.json), nichts zu tun"}]}
    else
      case load_master_key("RIS-Kassetten verschluesseln", opts) do
        {:ok, key} ->
          {0, messages} = seal_each(files.json, dir, key, 0, [])
          {0, messages ++ other_warning(files)}

        {:error, reason} ->
          master_key_error(reason)
      end
    end
  end

  # Files that are not *.json cassettes stay plaintext, untouched — make
  # that visible instead of pretending they are encrypted.
  defp other_warning(files) do
    if files.other == [] do
      []
    else
      [
        {:err,
         "ris_cassettes: #{length(files.other)} sonstige Datei(en) sind keine *.json-Kassetten " <>
           "und bleiben Klartext: #{Enum.join(files.other, ", ")}"}
      ]
    end
  end

  defp seal_each([], _dir, _key, n, acc) do
    {0,
     [
       {:out,
        "ris_cassettes: #{n} Kassette(n) verschluesselt; der Schluessel war nur fuer diesen Lauf im Speicher"}
       | Enum.reverse(acc)
     ]}
  end

  defp seal_each([name | rest], dir, key, n, acc) do
    case seal_one(Path.join(dir, name), key) do
      :ok ->
        seal_each(rest, dir, key, n + 1, [{:out, "verschluesselt: #{name}"} | acc])

      # Undeletable plaintext is a local problem of this file (flag,
      # permissions): discard our own .enc, skip, carry on — a repeated
      # seal converges.
      {:skip, msg} ->
        seal_each(rest, dir, key, n, [{:err, "uebersprungen: #{name} — #{msg}"} | acc])

      # Verification/write errors are systemic: abort. The state still
      # converges, because our own .enc was discarded and the plaintext
      # stays.
      {:error, msg} ->
        {1,
         [
           {:err,
            "ris_cassettes: abgebrochen bei #{name}: #{msg}; #{n} verschluesselt, " <>
              "#{length(rest) + 1} offen — Stand mit status pruefen, erneutes seal vollendet"}
           | Enum.reverse(acc)
         ]}
    end
  end

  # Encrypt one cassette: write atomically (exclusive, sync, 0600, rename),
  # verify by reading back from disk, only then delete the plaintext.
  defp seal_one(json, key) do
    enc = json <> ".enc"

    with {:ok, plain} <- File.read(json),
         :ok <- write_atomic(enc, sealed_blob(plain, key)),
         {:ok, blob} <- File.read(enc),
         {:ok, ^plain} <- open_blob(blob, key) do
      case File.rm(json) do
        :ok ->
          :ok

        {:error, reason} ->
          _ = File.rm(enc)
          {:skip, "Klartext nicht loeschbar (#{inspect(reason)}); .enc entsorgt"}
      end
    else
      {:ok, _other} -> verify_failed(enc)
      {:error, :bad_tag} -> verify_failed(enc)
      {:error, {:leftover, tmp}} -> {:error, "Restdatei #{Path.basename(tmp)} blockiert"}
      {:error, {:write, reason}} -> {:error, "Schreiben fehlgeschlagen: #{inspect(reason)}"}
      {:error, reason} -> {:error, "Lesen fehlgeschlagen: #{inspect(reason)}"}
    end
  end

  defp verify_failed(enc) do
    _ = File.rm(enc)
    {:error, "Gegenprobe fehlgeschlagen: #{Path.basename(enc)}"}
  end

  # --- unseal ------------------------------------------------------------------------

  defp unseal(dir, opts) do
    with :ok <- require_dir(dir),
         :ok <- require_repo_free(dir),
         {:ok, files} <- list_ok(dir),
         :ok <- require_collision_free(files, :unseal) do
      unseal_files(files, dir, opts)
    else
      {:error, code, msg} -> {code, [{:err, msg}]}
    end
  end

  defp unseal_files(files, dir, opts) do
    if files.enc == [] do
      {0, [{:out, "ris_cassettes: keine verschluesselten Kassetten, nichts zu tun"}]}
    else
      case load_master_key("RIS-Kassetten entschluesseln", opts) do
        {:ok, key} -> unseal_each(files.enc, dir, key, 0, [])
        {:error, reason} -> master_key_error(reason)
      end
    end
  end

  defp unseal_each([], _dir, _key, n, acc) do
    {0,
     [
       {:out,
        "ris_cassettes: #{n} Kassette(n) entschluesselt; der Schluessel war nur fuer diesen Lauf im Speicher"}
       | Enum.reverse(acc)
     ]}
  end

  defp unseal_each([name | rest], dir, key, n, acc) do
    case unseal_one(Path.join(dir, name), key) do
      :ok ->
        unseal_each(rest, dir, key, n + 1, [{:out, "entschluesselt: #{json_of_enc(name)}"} | acc])

      {:skip, msg} ->
        unseal_each(rest, dir, key, n, [
          {:err, "uebersprungen: #{json_of_enc(name)} — #{msg}"} | acc
        ])

      {:error, code, msg} ->
        {code,
         [
           {:err,
            "ris_cassettes: abgebrochen bei #{name}: #{msg}; #{n} entschluesselt, " <>
              "#{length(rest) + 1} verschluesselt — Stand mit status pruefen, erneutes unseal vollendet"}
           | Enum.reverse(acc)
         ]}
    end
  end

  # The GCM tag is the integrity check (decryption verifies itself) — no
  # second verification needed. If the .enc cannot be deleted after
  # writing, our own plaintext file is removed: we never leave a .json AND
  # .enc state behind, a repeated unseal converges.
  defp unseal_one(enc, key) do
    json = json_of_enc(enc)

    with {:ok, blob} <- File.read(enc),
         {:ok, plain} <- open_blob(blob, key),
         :ok <- write_atomic(json, plain) do
      case File.rm(enc) do
        :ok ->
          :ok

        {:error, reason} ->
          _ = File.rm(json)
          {:skip, "verschluesselte Datei nicht loeschbar (#{inspect(reason)}); zurueckgerollt"}
      end
    else
      {:error, :bad_magic} -> {:error, 5, "keine rkt1-Kassette"}
      {:error, :too_short} -> {:error, 5, "zu kurz fuer rkt1"}
      {:error, :bad_tag} -> {:error, 5, "korrumpiert oder mit anderem Schluessel verschluesselt"}
      {:error, {:leftover, tmp}} -> {:error, 1, "Restdatei #{Path.basename(tmp)} blockiert"}
      {:error, {:write, reason}} -> {:error, 1, "Schreiben fehlgeschlagen: #{inspect(reason)}"}
      {:error, reason} -> {:error, 1, "Lesen oder Schreiben fehlgeschlagen: #{inspect(reason)}"}
    end
  end

  # --- status --------------------------------------------------------------------------

  defp status(dir, _opts) do
    with :ok <- require_dir(dir),
         {:ok, files} <- list_ok(dir) do
      others =
        if files.other == [], do: "", else: ", #{length(files.other)} sonstige Datei(en)"

      {0,
       [
         {:out,
          "ris_cassettes: #{length(files.json)} Klartext-Kassette(n), #{length(files.enc)} verschluesselt" <>
            others}
       ]}
    else
      {:error, code, msg} -> {code, [{:err, msg}]}
    end
  end

  # --- check: secrets in plaintext cassettes (#328) ---------------------------------------
  #
  # Scanned are *.json and *.json.new (plaintext leftover of a crashed
  # unseal); ciphertext (*.json.enc, *.json.enc.new) is skipped and
  # reported. Without a directory: the timestamp directories under the
  # cassette base; a directory without own plaintext but with
  # subdirectories counts as a collection directory. With plaintext
  # present but no secret loadable, the run counts as failed — nothing
  # checked is not clean.

  @spec check(Path.t() | nil, keyword()) :: {non_neg_integer(), [message()]}
  defp check(nil, opts) do
    base = Path.expand(Keyword.get(opts, :cassette_base, @cassette_base))

    case timestamp_dirs(base) do
      [] ->
        {0, [{:out, "ris_cassettes: keine Zeitstempel-Verzeichnisse unter #{base}"}]}

      dirs ->
        check_dirs(dirs, opts)
    end
  end

  defp check(dir, opts) do
    with :ok <- require_dir(dir) do
      case plain_files(dir) do
        {:ok, %{plain: []}} ->
          case subdirs(dir) do
            [] -> {0, [{:out, skip_note(dir)}]}
            dirs -> check_dirs(dirs, opts)
          end

        {:ok, _files} ->
          check_dirs([dir], opts)

        {:error, code, msg} ->
          {code, [{:err, msg}]}
      end
    else
      {:error, code, msg} -> {code, [{:err, msg}]}
    end
  end

  # Directories checked together: skip and error lines ride along, the
  # rest keeps converging (like seal on undeletable files). An unreadable
  # file or directory voids the verdict "clean": exit 1 — deliberate
  # extension of #328's exit codes, nothing checked is not clean.
  defp check_dirs(dirs, opts) do
    {skips, scanable, errors} =
      Enum.reduce(dirs, {[], [], []}, fn dir, {sk, acc, err} ->
        case plain_files(dir) do
          {:ok, %{plain: []}} -> {[skip_note(dir) | sk], acc, err}
          {:ok, files} -> {sk, [{dir, files} | acc], err}
          {:error, _code, msg} -> {sk, acc, [msg | err]}
        end
      end)

    error_lines = Enum.map(Enum.reverse(errors), &{:err, &1})
    skip_lines = Enum.map(Enum.reverse(skips), &{:out, &1})

    cond do
      scanable == [] and errors == [] ->
        {0, skip_lines}

      scanable == [] ->
        {1, error_lines ++ skip_lines}

      true ->
        case load_secrets(opts) do
          [] ->
            config = config_dir(opts)

            {1,
             error_lines ++
               skip_lines ++
               [
                 {:out,
                  "ris_cassettes: keine Geheimnisse aus #{config} ladbar" <>
                    " (.env mit #{Enum.join(@secret_env_keys, "/")}, token-Datei)" <>
                    " — #{length(scanable)} Verzeichnis(se) mit Klartext blieben ungeprueft"}
               ]}

          secrets ->
            {findings, checked, unreadable, messages} = scan_dirs(scanable, secrets)
            skipped = length(skips)

            total =
              "ris_cassettes: Gesamt: #{checked} Kassette(n) geprueft, #{findings} Funde" <>
                skip_text(skipped) <> unreadable_text(unreadable)

            exit = if findings > 0 or unreadable > 0 or errors != [], do: 1, else: 0

            {exit, error_lines ++ skip_lines ++ Enum.reverse(messages) ++ [{:out, total}]}
        end
    end
  end

  defp scan_dirs(scanable, secrets) do
    Enum.reduce(scanable, {0, 0, 0, []}, fn {dir, files}, {f, c, u, acc} ->
      {dir_findings, dir_unreadable, dir_messages} = scan_dir(dir, files.plain, secrets)

      findings = f + dir_findings
      checked = c + length(files.plain) - dir_unreadable
      unreadable = u + dir_unreadable

      summary =
        "ris_cassettes: #{Path.basename(dir)}: #{length(files.plain) - dir_unreadable} Kassette(n)" <>
          " geprueft#{unreadable_text(dir_unreadable)}#{encrypted_text(files.sealed)}" <>
          ", #{dir_findings} Funde"

      {findings, checked, unreadable, [{:out, summary} | dir_messages ++ acc]}
    end)
  end

  defp scan_dir(dir, files, secrets) do
    {findings, unreadable, messages} =
      Enum.reduce(files, {0, 0, []}, fn name, {f, u, acc} ->
        case File.read(Path.join(dir, name)) do
          {:ok, raw} ->
            content = raw |> plaintext_parts() |> Enum.uniq()

            hits =
              for {sname, sval} <- secrets,
                  Enum.any?(content, &String.contains?(&1, sval)),
                  do: sname

            finding_lines =
              for sname <- hits,
                  do: {:out, "ris_cassettes: FUND: #{sname} in #{name} (#{Path.basename(dir)})"}

            {f + length(hits), u, finding_lines ++ acc}

          {:error, reason} ->
            {f, u + 1,
             [
               {:err,
                "ris_cassettes: #{name} (#{Path.basename(dir)}) unlesbar — " <>
                  "Pruefung unvollstaendig (#{inspect(reason)})"}
               | acc
             ]}
        end
      end)

    {findings, unreadable, Enum.reverse(messages)}
  end

  # Plaintext parts of a cassette: raw text plus the Base64-decoded
  # request and response bodies. Invalid JSON (a crash leftover, say)
  # falls back to raw text — a secret in plaintext is found either way.
  defp plaintext_parts(raw) do
    case RisHttp.decode_json(raw) do
      {:ok, %{} = cassette} ->
        [raw | Enum.flat_map(["request", "response"], &part_body(cassette, &1))]

      _no_cassette_map ->
        [raw]
    end
  end

  defp part_body(cassette, part) do
    case cassette do
      %{^part => %{} = p} -> body_of(p)
      _ -> []
    end
  end

  # Deliberately not RisHttp.part_body: the leak scan decodes tolerantly
  # (ignore: :whitespace), never falls back to a plaintext "body" field,
  # and yields nothing on invalid Base64 instead of raising — the check
  # must neither crash on odd cassettes nor get more lenient (#328/#331).
  # One caller, so it stays local (lift threshold: three scripts, #333).
  defp body_of(%{"body_b64" => b64}) when is_binary(b64) do
    case Base.decode64(b64, ignore: :whitespace) do
      {:ok, bin} -> [bin]
      :error -> []
    end
  end

  defp body_of(_), do: []

  # Secrets come from the config directory — never from the command line
  # (shell history). Missing files are not errors: without a .env the
  # token stays checkable.
  defp load_secrets(opts) do
    config = config_dir(opts)
    read_env_secrets(Path.join(config, ".env")) ++ read_token(Path.join(config, "token"))
  end

  defp config_dir(opts), do: Path.expand(Keyword.get(opts, :config_dir, @config_dir))

  # .env parsing mirrors Ratsinfo.Config.parse_env exactly: unanchored
  # regex, first occurrence wins, no comment handling. A commented-out or
  # export-prefixed value is one ratsinfo would send — what ratsinfo
  # could send is what check must search for.
  defp read_env_secrets(path) do
    case File.read(path) do
      {:ok, content} ->
        Enum.flat_map(@secret_env_keys, fn key ->
          case Regex.run(~r/#{key}=(.+)/, content, capture: :all_but_first) do
            [value | _] -> [{key, value}]
            nil -> []
          end
        end)

      {:error, _} ->
        []
    end
  end

  # Parity with Ratsinfo.Auth: a token of 10 bytes or less is never sent,
  # so searching for it would only add noise.
  defp read_token(path) do
    case File.read(path) do
      {:ok, token} ->
        token = String.trim(token)
        if byte_size(token) > 10, do: [{"token", token}], else: []

      {:error, _} ->
        []
    end
  end

  # Plaintext cassettes of a directory: *.json plus *.json.new leftovers
  # of a crashed unseal, and the count of skipped ciphertext (*.json.enc,
  # *.json.enc.new — never plaintext). Other files are neither.
  defp plain_files(dir) do
    case list_ok(dir) do
      {:ok, files} ->
        leftovers = Enum.filter(files.other, &String.ends_with?(&1, ".json.new"))
        cipher = Enum.filter(files.other, &String.ends_with?(&1, ".enc.new"))

        {:ok,
         %{plain: Enum.sort(files.json ++ leftovers), sealed: length(files.enc) + length(cipher)}}

      {:error, code, msg} ->
        {:error, code, msg}
    end
  end

  defp subdirs(dir) do
    case File.ls(dir) do
      {:ok, names} ->
        names
        |> Enum.map(&Path.join(dir, &1))
        |> Enum.filter(&File.dir?/1)
        |> Enum.sort()

      {:error, _} ->
        []
    end
  end

  # The recorder creates one timestamp directory per session; the default
  # call (no directory) checks exactly those (#328). Anything else under
  # the base is not a recording session.
  defp timestamp_dirs(base) do
    base
    |> subdirs()
    |> Enum.filter(&(Path.basename(&1) =~ @timestamp))
  end

  defp skip_note(dir),
    do:
      "ris_cassettes: #{Path.basename(dir)}: kein Klartext (verschluesselt oder leer), uebersprungen"

  defp skip_text(0), do: ""
  defp skip_text(n), do: ", #{n} Verzeichnis(se) uebersprungen"

  defp unreadable_text(0), do: ""
  defp unreadable_text(n), do: ", #{n} unlesbar"

  defp encrypted_text(0), do: ""
  defp encrypted_text(n), do: ", #{n} verschluesselt uebersprungen"

  # --- Shared pre-checks --------------------------------------------------------------------

  defp require_dir(dir) do
    if File.dir?(dir), do: :ok, else: {:error, 1, "ris_cassettes: Verzeichnis fehlt: #{dir}"}
  end

  defp require_repo_free(dir) do
    case check_dir(dir) do
      :ok ->
        :ok

      {:error, {:dir_in_repo, repo}} ->
        {:error, 1,
         "ris_cassettes: #{dir} liegt im Git-Repo #{repo}; Kassetten gehoeren ausserhalb jedes Repos"}
    end
  end

  # Listing must not blow up (File.ls!): an unreadable directory deserves a
  # message, for status too — that is exactly where the broken state shows.
  defp list_ok(dir) do
    case list_dir(dir) do
      {:ok, files} ->
        {:ok, files}

      {:error, reason} ->
        {:error, 1, "ris_cassettes: Verzeichnis nicht lesbar: #{dir} (#{inspect(reason)})"}
    end
  end

  # Collisions before the release: seal/unseal never overwrite. The check
  # runs over the one listing, not one File.exists? per file.
  defp require_collision_free(files, :seal) do
    enc_set = MapSet.new(files.enc)

    case Enum.find(files.json, &MapSet.member?(enc_set, &1 <> ".enc")) do
      nil ->
        :ok

      name ->
        {:error, 1, "ris_cassettes: #{name}.enc existiert bereits; erst unseal oder Hand anlegen"}
    end
  end

  defp require_collision_free(files, :unseal) do
    json_set = MapSet.new(files.json)

    case Enum.find(files.enc, &MapSet.member?(json_set, json_of_enc(&1))) do
      nil ->
        :ok

      name ->
        {:error, 1,
         "ris_cassettes: #{json_of_enc(name)} existiert bereits; erst seal oder Hand anlegen"}
    end
  end

  # --- Atomic write ------------------------------------------------------------------------

  # Exclusive (never clobbers a leftover from a crash), sync (the read-back
  # verification must not just hit the page cache), 0600 (plaintext is
  # never readable more widely either), rename within the same directory
  # (atomic). On failure the temp file is cleaned up.
  defp write_atomic(path, content) do
    tmp = path <> ".new"

    case File.open(tmp, [:write, :exclusive]) do
      {:ok, fd} ->
        with :ok <- IO.binwrite(fd, content),
             :ok <- :file.sync(fd),
             :ok <- File.close(fd),
             :ok <- File.chmod(tmp, 0o600),
             :ok <- File.rename(tmp, path) do
          :ok
        else
          {:error, reason} ->
            _ = File.close(fd)
            _ = File.rm(tmp)
            {:error, {:write, reason}}
        end

      {:error, :eexist} ->
        {:error, {:leftover, tmp}}

      {:error, reason} ->
        {:error, {:write, reason}}
    end
  end
end

KomkiConnectorRis.RisHttp.cli(System.argv(), fn argv ->
  {code, messages} = KomkiConnectorRis.RisCassettes.run(argv)

  Enum.each(messages, fn
    {:out, text} -> IO.puts(text)
    {:err, text} -> IO.puts(:stderr, text)
  end)

  if code != 0, do: exit({:shutdown, code})
end)
