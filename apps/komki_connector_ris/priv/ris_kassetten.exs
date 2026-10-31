# Kassetten verschluesseln: AES-256-GCM je Kassette, Schluessel nur per
# Touch ID aus der Secure Enclave (komki-tresor).
#
#     elixir apps/komki_connector_ris/priv/ris_kassetten.exs init
#     elixir apps/komki_connector_ris/priv/ris_kassetten.exs seal <verzeichnis>
#     elixir apps/komki_connector_ris/priv/ris_kassetten.exs unseal <verzeichnis>
#     elixir apps/komki_connector_ris/priv/ris_kassetten.exs status <verzeichnis>
#
# init (einmalig) erzeugt einen 32-Byte-Schluessel und legt ihn als Siegel
# von komki-tresor im macOS-Schluesselbund ab (Eintrag 'ris-kassetten'). Das
# Siegel oeffnet nur die Secure Enclave dieses Macs — kein Restore auf einem
# anderen Mac, kein Key-Escrow; ist der Eintrag weg, sind die Kassetten weg.
# Jede Ver- und Entschluesselung braucht genau eine Freigabe per Touch ID
# (oder Passwort des Macs). seal schreibt je Kassette <name>.json.enc (Magic
# rkt1, Nonce, Chiffretext, Tag; Nonce frisch je Datei) und loescht den
# Klartext erst nach bestandener Gegenprobe von der Platte.
#
# Bedrohungsmodell: Gesichert ist die Ablage — kein Prozess (auch kein
# Agent) liest versiegelte Kassetten ohne die Person am Mac. Nicht gesichert
# sind Laufzeitfenster: waehrend der Aufzeichnung und waehrend unseal liegt
# Klartext auf der Platte (optionale Haertung: Recorder --out auf eine
# RAM-Disk, siehe README). Meldungen nennen nie Schluessel, Siegel oder
# Kassetteninhalte, nur Namen und Zaehler.
#
# Verschluesselte Verzeichnisse gehoeren ausserhalb jedes Git-Repos wie die
# Klartext-Kassetten auch; seal/unseal lehnen Repos ab (wie ris_recorder).
# Replay und Skelett lesen *.json: vorher unseal, danach seal.
#
# Nur OTP (:crypto, Ports), keine Deps. Die Port-Muster sind aus komki_cli
# dupliziert statt importiert (Unix-Prinzip; Andockpunkt: Tresor-Kern #224).

Code.require_file("./ris_http.exs", __DIR__)

defmodule KomkiConnectorRis.RisKassetten do
  @moduledoc false

  @service "ris-kassetten"
  # Format-Label von komki-tresor (native/komki-tresor/main.swift): so beginnt
  # ein Siegel. Bewusst ein anderes Praefix als @magic, damit Siegel und
  # Kassetten-Container nie verwechselt werden.
  @tresor_prefix "ktv1."
  @tresor_program "komki-tresor"
  @seal_timeout_ms 10_000
  # Oeffnen wartet auf Touch ID oder Passwort.
  @open_timeout_ms 120_000

  @security "/usr/bin/security"
  @security_timeout_ms 5_000
  # security(1): Exit 44 = errSecItemNotFound
  @not_found 44

  @magic "rkt1"
  @key_bytes 32
  @nonce_bytes 12
  @tag_bytes 16

  # security -i zerlegt die Zeile selbst: nur Zeichen ohne Sonderbedeutung
  # (Regel kopiert aus komki_cli/lib/komki_cli/keychain.ex). Ein ktv1.-Siegel
  # aus Standard-Base64 erfuellt sie; vor dem Speichern pruefen, damit nicht
  # security still auf 128 Byte kuerzt.
  @word ~r/\A[A-Za-z0-9@._+\/=-]+\z/

  @usage "Aufruf: init | seal <verzeichnis> | unseal <verzeichnis> | status <verzeichnis> [--tresor <programm>]"

  @type tresor_error ::
          :missing_bin | :no_enclave | :refused | :invalid | :timeout | {:failed, integer()}
  @type kc_error ::
          :missing | :timeout | :invalid | :not_stored | {:failed, integer()}
  @type meldung :: {:out | :err, String.t()}

  # --- CLI ------------------------------------------------------------------

  @doc false
  @spec parse_cli([String.t()]) ::
          {:ok, {String.t(), String.t() | nil, keyword()}} | {:error, String.t()}
  def parse_cli([cmd | rest]) when cmd in ~w(init seal unseal status) do
    case parse_flags(cmd, rest, nil, []) do
      {:ok, dir, opts} -> {:ok, {cmd, dir, opts}}
      :error -> {:error, @usage}
    end
  end

  def parse_cli(_other), do: {:error, @usage}

  # Genau ein Pfad (init: keiner), Flags in beliebiger Reihenfolge danach.
  defp parse_flags(cmd, ["--tresor", value | rest], dir, opts),
    do: parse_flags(cmd, rest, dir, Keyword.put(opts, :tresor, value))

  defp parse_flags(cmd, [dir | rest], nil, opts) when cmd in ~w(seal unseal status),
    do: parse_flags(cmd, rest, dir, opts)

  defp parse_flags("init", [], nil, opts), do: {:ok, nil, opts}
  defp parse_flags(_cmd, [], dir, opts) when is_binary(dir), do: {:ok, dir, opts}
  defp parse_flags(_cmd, _other, _dir, _opts), do: :error

  @doc """
  Kommandozeile abarbeiten und `{exit_code, meldungen}` liefern (statt selbst
  zu enden) — Tests laufen darueber, der Runner druckt nur noch.
  """
  @spec run([String.t()], keyword()) :: {pos_integer(), [meldung()]}
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

      {:error, usage} ->
        {2, [{:err, "ris_kassetten: #{usage}"}]}
    end
  end

  # --- komki-tresor (Binaer per Pipe) ----------------------------------------

  @doc false
  @spec tresor_bin(keyword()) :: String.t() | nil
  def tresor_bin(opts) do
    case Keyword.get(opts, :tresor) do
      nil -> System.find_executable(@tresor_program)
      # Ein Tippfehler im --tresor-Pfad waere sonst ein haesslicher
      # System.cmd-Crash statt der klaren missing_bin-Meldung.
      path -> if File.exists?(path), do: path, else: nil
    end
  end

  @doc false
  @spec tresor_check(String.t()) :: :ok | {:error, :no_enclave | {:failed, integer()}}
  def tresor_check(command) do
    case System.cmd(command, ["check"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {_, 3} -> {:error, :no_enclave}
      {_, code} -> {:error, {:failed, code}}
    end
  end

  @doc "Klartext versiegeln. Keine Rueckfrage: Versiegeln braucht nur den oeffentlichen Schluessel."
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

  @doc "Siegel oeffnen; macOS fragt mit `reason` nach Touch ID oder Passwort."
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

  # Klartext und Siegel gehen nur ueber stdin/stdout, nie ueber argv
  # (komki-tresor-Konvention).
  defp tresor_call(args, input, timeout, opts) do
    case tresor_bin(opts) do
      nil ->
        {:error, :missing_bin}

      bin ->
        port =
          Port.open({:spawn_executable, bin}, [:binary, :exit_status, :use_stdio, args: args])

        Port.command(port, input <> "\n")
        collect(port, [], System.monotonic_time(:millisecond) + timeout)
    end
  end

  # stderr bleibt im Terminal (Meldungen des Programms, ohne Werte); stdout
  # traegt genau eine Zeile. Exit-Codes wie komki-tresor: 3 keine Enclave,
  # 4 keine Freigabe, 5 ungueltiges Siegel.
  defp collect(port, acc, deadline) do
    left = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} -> collect(port, [acc, data], deadline)
      {^port, {:exit_status, 0}} -> {:ok, acc |> IO.iodata_to_binary() |> String.trim_trailing()}
      {^port, {:exit_status, 3}} -> {:error, :no_enclave}
      {^port, {:exit_status, 4}} -> {:error, :refused}
      {^port, {:exit_status, 5}} -> {:error, :invalid}
      {^port, {:exit_status, code}} -> {:error, {:failed, code}}
    after
      left -> kill(port)
    end
  end

  @doc false
  @spec tresor_text(tresor_error()) :: String.t()
  def tresor_text(:missing_bin),
    do: "komki-tresor nicht gefunden (Installation pruefen oder --tresor <programm>)"

  def tresor_text(:no_enclave), do: "keine Secure Enclave auf diesem Mac"
  def tresor_text(:refused), do: "Freigabe per Touch ID oder Passwort verweigert oder abgebrochen"
  def tresor_text(:invalid), do: "Siegel ungueltig oder von einem anderen Mac"
  def tresor_text(:timeout), do: "keine Freigabe rechtzeitig"
  def tresor_text({:failed, code}), do: "komki-tresor fehlgeschlagen (exit #{code})"

  # Exit-Codes: 3 Tresor/Enclave fehlt, 4 keine Freigabe, 5 Siegel ungueltig,
  # 1 Programm sonstwie gescheitert.
  defp tresor_exit(:missing_bin), do: 3
  defp tresor_exit(:no_enclave), do: 3
  defp tresor_exit(:refused), do: 4
  defp tresor_exit(:timeout), do: 4
  defp tresor_exit(:invalid), do: 5
  defp tresor_exit({:failed, _code}), do: 1

  defp one_line?(value),
    do: is_binary(value) and value != "" and not String.contains?(value, ["\n", "\r"])

  # --- Schluesselbund ---------------------------------------------------------

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
  Wert als generisches Passwort ablegen (nur fuer Siegel). Der Wert steht nie
  in argv (dort saehe ihn jeder Prozess per ps); `add-generic-password -w`
  ohne Wert kuertzte ihn interaktiv auf 128 Byte, deshalb geht der ganze
  Befehl als eine Zeile an `security -i` (Muster aus
  komki_cli/lib/komki_cli/keychain.ex). Danach zuruecklesen und vergleichen.
  """
  @spec kc_store(String.t(), String.t(), keyword()) :: :ok | {:error, kc_error()}
  def kc_store(service, value, opts) do
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

  # `head -n 1` beendet stdin nach der einen Zeile; `security -i` endet dann.
  defp kc_interactive(service, account, value, opts) do
    command = Keyword.get(opts, :security, @security)

    port =
      Port.open({:spawn_executable, "/bin/sh"}, [
        :binary,
        :exit_status,
        :use_stdio,
        args: ["-c", "head -n 1 | exec \"$0\" -i >/dev/null 2>&1", command]
      ])

    line =
      Enum.join(["add-generic-password", "-s", service, "-a", account, "-U", "-w", value], " ")

    Port.command(port, line <> "\n")

    kc_run_collect(port, [], System.monotonic_time(:millisecond) + timeout(opts))
  end

  @doc false
  @spec kc_text(kc_error()) :: String.t()
  def kc_text(:missing), do: "Schluesselbund-Eintrag '#{@service}' fehlt"
  def kc_text(:timeout), do: "Schluesselbund-Abfrage nach Timeout abgebrochen"
  def kc_text(:invalid), do: "Wert unzulaessig fuer den Schluesselbund (leer oder Sonderzeichen)"
  def kc_text(:not_stored), do: "Eintrag enthaelt nach dem Schreiben einen anderen Wert"

  def kc_text({:failed, code}),
    do: "Schluesselbund-Befehl fehlgeschlagen (exit #{code})"

  # Port statt System.cmd: nur so laesst sich ein haengendes security nach dem
  # Timeout beenden. stderr wird verworfen und taucht nie in Meldungen auf.
  defp kc_run(args, opts) do
    command = Keyword.get(opts, :security, @security)

    port =
      Port.open({:spawn_executable, "/bin/sh"}, [
        :binary,
        :exit_status,
        :use_stdio,
        args: ["-c", "exec \"$0\" \"$@\" 2>/dev/null </dev/null", command | args]
      ])

    kc_run_collect(port, [], System.monotonic_time(:millisecond) + timeout(opts))
  end

  defp timeout(opts), do: Keyword.get(opts, :security_timeout, @security_timeout_ms)

  defp kc_run_collect(port, acc, deadline) do
    left = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} -> kc_run_collect(port, [acc, data], deadline)
      {^port, {:exit_status, 0}} -> {:ok, IO.iodata_to_binary(acc)}
      {^port, {:exit_status, @not_found}} -> {:error, :missing}
      {^port, {:exit_status, code}} -> {:error, {:failed, code}}
    after
      left -> kill(port)
    end
  end

  # Nach dem Timeout koennte das Programm noch laufen: Prozess hart beenden,
  # Port schliessen. badarg faengt den Fall, dass der Port schon weg ist.
  defp kill(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} -> System.cmd("/bin/kill", ["-KILL", to_string(pid)])
      nil -> :ok
    end

    Port.close(port)
    {:error, :timeout}
  catch
    :error, :badarg -> {:error, :timeout}
  end

  # --- Krypto -----------------------------------------------------------------

  # AES-256-GCM, frische Nonce je Datei, Magic als AAD bindet die
  # Container-Version an den Chiffretext. OTP 29: Encrypt liefert
  # {chiffretext, tag}; Decrypt meldet Falsches als :error statt zu werfen.
  defp sealed_blob(plain, key) do
    nonce = :crypto.strong_rand_bytes(@nonce_bytes)
    {ct, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, plain, @magic, true)
    @magic <> nonce <> ct <> tag
  end

  # {:ok, klartext} | {:error, :bad_magic | :too_short | :bad_tag}
  defp open_blob(blob, key) do
    cond do
      not String.starts_with?(blob, @magic) ->
        {:error, :bad_magic}

      byte_size(blob) < byte_size(@magic) + @nonce_bytes + @tag_bytes + 1 ->
        {:error, :too_short}

      true ->
        nonce = binary_part(blob, byte_size(@magic), @nonce_bytes)
        ct_start = byte_size(@magic) + @nonce_bytes
        tag_start = byte_size(blob) - @tag_bytes

        ct = binary_part(blob, ct_start, tag_start - ct_start)
        tag = binary_part(blob, tag_start, @tag_bytes)

        case :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, ct, @magic, tag, false) do
          plain when is_binary(plain) -> {:ok, plain}
          _korrupt -> {:error, :bad_tag}
        end
    end
  end

  # --- Schluessel laden --------------------------------------------------------

  # Genau EINE Freigabe je Lauf: Siegel einmal lesen, einmal oeffnen. Der
  # Tresor wird zuerst geprueft — ein fehlendes Programm ist die grundlegendere
  # Stoerung und darf nicht hinter einer Keychain-Meldung versteckt werden.
  # Ein Eintrag ohne ktv1.-Praefix ist Klartext — oeffnen waere sinnlos.
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
    do: {5, [{:err, "ris_kassetten: Eintrag '#{@service}' ist kein Siegel; init laufen lassen"}]}

  defp master_key_error(:invalid_key),
    do: {5, [{:err, "ris_kassetten: Schluessel im Siegel hat falsche Form"}]}

  defp master_key_error({:keychain, :missing}),
    do: {5, [{:err, "ris_kassetten: Eintrag '#{@service}' fehlt; zuerst init"}]}

  defp master_key_error({:keychain, reason}),
    do: {1, [{:err, "ris_kassetten: #{kc_text(reason)}"}]}

  defp master_key_error({:tresor, reason}),
    do: {tresor_exit(reason), [{:err, "ris_kassetten: #{tresor_text(reason)}"}]}

  # --- Schutz und Dateilisten ---------------------------------------------------

  @doc """
  `:ok`, wenn `dir` ausserhalb jedes Git-Repos liegt (auch Worktrees, deren
  `.git` eine Datei ist), sonst `{:error, {:dir_in_repo, repo}}` — wie
  RisRecorder.check_out/1: verschluesselte Kassetten gehoeren genauso wenig
  ins Repo wie Klartext.
  """
  @spec check_dir(Path.t()) :: :ok | {:error, {:dir_in_repo, Path.t()}}
  def check_dir(dir) do
    dir
    |> Path.expand()
    |> ancestors()
    |> Enum.find(&File.exists?(Path.join(&1, ".git")))
    |> case do
      nil -> :ok
      repo -> {:error, {:dir_in_repo, repo}}
    end
  end

  defp ancestors(path) do
    parent = Path.dirname(path)
    if parent == path, do: [path], else: [path | ancestors(parent)]
  end

  # ".json.enc" endet nicht auf ".json" — die beiden Mengen sind disjunkt.
  defp json_files(dir),
    do: dir |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".json")) |> Enum.sort()

  defp enc_files(dir),
    do: dir |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".json.enc")) |> Enum.sort()

  defp enc_path(dir, name), do: Path.join(dir, name <> ".enc")
  defp json_of_enc(name), do: String.replace_suffix(name, ".enc", "")

  # --- Subkommandos ---------------------------------------------------------------

  defp init(opts) do
    case kc_present(@service, opts) do
      :ok ->
        {1,
         [
           {:err,
            "ris_kassetten: Eintrag '#{@service}' existiert bereits; bewusst entfernen mit " <>
              "security delete-generic-password -s #{@service} — danach sind alle bisher " <>
              "verschluesselten Kassetten unlesbar"}
         ]}

      {:error, :missing} ->
        init_create(opts)

      {:error, reason} ->
        {1, [{:err, "ris_kassetten: Schluesselbund nicht abfragbar: #{kc_text(reason)}"}]}
    end
  end

  defp init_create(opts) do
    case tresor_bin(opts) do
      nil ->
        {3, [{:err, "ris_kassetten: #{tresor_text(:missing_bin)}"}]}

      bin ->
        case tresor_check(bin) do
          :ok -> init_key(opts)
          {:error, reason} -> {3, [{:err, "ris_kassetten: #{tresor_text(reason)}"}]}
        end
    end
  end

  # Versiegeln braucht keine Freigabe; die EINE Freigabe hier ist die
  # Rundweg-Kontrolle VOR dem Speichern — kein persistierter Halbfertig-Zustand.
  defp init_key(opts) do
    line = Base.encode64(:crypto.strong_rand_bytes(@key_bytes))

    case tresor_seal(line, opts) do
      {:ok, sealed} ->
        case tresor_open(sealed, "RIS-Kassetten-Schluessel zur Kontrolle freigeben", opts) do
          {:ok, ^line} ->
            init_store(sealed, opts)

          {:ok, _anderer} ->
            {5, [{:err, "ris_kassetten: Rundweg-Kontrolle fehlgeschlagen; nichts gespeichert"}]}

          {:error, reason} ->
            {tresor_exit(reason),
             [{:err, "ris_kassetten: Rundweg-Kontrolle: #{tresor_text(reason)}"}]}
        end

      {:error, reason} ->
        {tresor_exit(reason),
         [{:err, "ris_kassetten: Versiegeln des Schluessels: #{tresor_text(reason)}"}]}
    end
  end

  defp init_store(sealed, opts) do
    case kc_store(@service, sealed, opts) do
      :ok ->
        {0,
         [
           {:out,
            "ris_kassetten: Schluessel versiegelt im macOS-Schluesselbund (Eintrag '#{@service}')"},
           {:out,
            "ris_kassetten: Das Siegel oeffnet nur die Secure Enclave dieses Macs — kein Backup, " <>
              "kein Restore auf einem anderen Mac; ohne diesen Mac sind verschluesselte Kassetten unwiederbringlich"},
           {:out,
            "ris_kassetten: Naechster Schritt: elixir apps/komki_connector_ris/priv/ris_kassetten.exs seal <kassettenverzeichnis>"}
         ]}

      {:error, reason} ->
        {5,
         [{:err, "ris_kassetten: Speichern im Schluesselbund fehlgeschlagen: #{kc_text(reason)}"}]}
    end
  end

  # --- seal -------------------------------------------------------------------------

  # Billige Pruefungen zuerst: ein abgelehnter Lauf darf nie eine Freigabe
  # ausloesen.
  defp seal(dir, opts) do
    case precheck(dir) do
      {:error, code, msg} ->
        {code, [{:err, msg}]}

      :ok ->
        names = json_files(dir)

        cond do
          names == [] ->
            {0,
             [{:out, "ris_kassetten: keine Kassetten zu versiegeln (nur *.json), nichts zu tun"}]}

          true ->
            # Kollisionspruefung vor der Freigabe: seal ueberschreibt nie.
            case Enum.find(names, &File.exists?(enc_path(dir, &1))) do
              nil ->
                case load_master_key("RIS-Kassetten verschluesseln", opts) do
                  {:ok, key} -> seal_each(names, dir, key, [])
                  {:error, reason} -> master_key_error(reason)
                end

              name ->
                {1,
                 [
                   {:err,
                    "ris_kassetten: #{enc_path(dir, name)} existiert bereits; erst unseal oder Hand anlegen"}
                 ]}
            end
        end
    end
  end

  defp seal_each([], _dir, _key, acc) do
    {0,
     [
       {:out,
        "ris_kassetten: #{length(acc)} Kassette(n) versiegelt; der Schluessel war nur fuer diesen Lauf im Speicher"}
       | acc
     ]}
  end

  defp seal_each([name | rest], dir, key, acc) do
    case seal_one(Path.join(dir, name), key) do
      :ok ->
        seal_each(rest, dir, key, [{:out, "versiegelt: #{name}"} | acc])

      {:error, msg} ->
        {1,
         [
           {:err,
            "ris_kassetten: abgebrochen bei #{name}: #{msg}; #{length(acc)} versiegelt, " <>
              "#{length(rest) + 1} offen — Stand mit status pruefen, erneutes seal vollendet"}
           | acc
         ]}
    end
  end

  # Eine Kassette versiegeln: Schreiben ueber Temp-Datei (0600, atomarer
  # rename), Gegenprobe von der Platte, erst dann den Klartext loeschen.
  defp seal_one(json, key) do
    with {:ok, plain} <- File.read(json),
         :ok <- write_enc(json <> ".enc", json <> ".enc.new", plain, key) do
      case File.rm(json) do
        :ok -> :ok
        {:error, reason} -> {:error, "Loeschen fehlgeschlagen: #{inspect(reason)}"}
      end
    else
      {:error, msg} when is_binary(msg) -> {:error, msg}
      {:error, reason} -> {:error, "Lesen fehlgeschlagen: #{inspect(reason)}"}
    end
  end

  # Misserfolg entsorgt nur die eigene .enc — der Klartext bleibt, es entsteht
  # kein .json-UND-.enc-Zustand durch uns.
  defp write_enc(enc, tmp, plain, key) do
    with :ok <- File.write(tmp, sealed_blob(plain, key)),
         :ok <- File.chmod(tmp, 0o600),
         :ok <- File.rename(tmp, enc),
         {:ok, blob} <- File.read(enc),
         {:ok, ^plain} <- open_blob(blob, key) do
      :ok
    else
      {:ok, _anderer_inhalt} ->
        _ = File.rm(enc)
        {:error, "Gegenprobe fehlgeschlagen: #{Path.basename(enc)}"}

      {:error, :bad_tag} ->
        _ = File.rm(enc)
        {:error, "Gegenprobe fehlgeschlagen: #{Path.basename(enc)}"}

      {:error, reason} ->
        _ = File.rm(tmp)
        _ = File.rm(enc)
        {:error, "Schreiben fehlgeschlagen: #{Path.basename(enc)}: #{inspect(reason)}"}
    end
  end

  # --- unseal ------------------------------------------------------------------------

  defp unseal(dir, opts) do
    case precheck(dir) do
      {:error, code, msg} ->
        {code, [{:err, msg}]}

      :ok ->
        names = enc_files(dir)

        cond do
          names == [] ->
            {0, [{:out, "ris_kassetten: keine verschluesselten Kassetten, nichts zu tun"}]}

          true ->
            # Kollisionspruefung vor der Freigabe: unseal ueberschreibt nie.
            case Enum.find(names, &File.exists?(Path.join(dir, json_of_enc(&1)))) do
              nil ->
                case load_master_key("RIS-Kassetten entschluesseln", opts) do
                  {:ok, key} -> unseal_each(names, dir, key, [])
                  {:error, reason} -> master_key_error(reason)
                end

              name ->
                {1,
                 [
                   {:err,
                    "ris_kassetten: #{json_of_enc(name)} existiert bereits; erst seal oder Hand anlegen"}
                 ]}
            end
        end
    end
  end

  defp unseal_each([], _dir, _key, acc) do
    {0,
     [
       {:out,
        "ris_kassetten: #{length(acc)} Kassette(n) entschluesselt; der Schluessel war nur fuer diesen Lauf im Speicher"}
       | acc
     ]}
  end

  defp unseal_each([name | rest], dir, key, acc) do
    case unseal_one(Path.join(dir, name), key) do
      :ok ->
        unseal_each(rest, dir, key, [{:out, "entschluesselt: #{json_of_enc(name)}"} | acc])

      {:error, code, msg} ->
        {code,
         [
           {:err,
            "ris_kassetten: abgebrochen bei #{name}: #{msg}; #{length(acc)} entschluesselt, " <>
              "#{length(rest) + 1} versiegelt — Stand mit status pruefen, erneutes unseal vollendet"}
           | acc
         ]}
    end
  end

  # Der GCM-Tag ist die Integritaeitspruefung (die Entschluesselung verifiziert
  # sich selbst) — keine zweite Gegenprobe noetig.
  defp unseal_one(enc, key) do
    json = String.replace_suffix(enc, ".enc", "")

    with {:ok, blob} <- File.read(enc),
         {:ok, plain} <- open_blob(blob, key),
         :ok <- File.write(json <> ".new", plain),
         :ok <- File.chmod(json <> ".new", 0o600),
         :ok <- File.rename(json <> ".new", json) do
      case File.rm(enc) do
        :ok -> :ok
        {:error, reason} -> {:error, 1, "Loeschen fehlgeschlagen: #{inspect(reason)}"}
      end
    else
      {:error, :bad_magic} -> {:error, 5, "keine rkt1-Kassette"}
      {:error, :too_short} -> {:error, 5, "zu kurz fuer rkt1"}
      {:error, :bad_tag} -> {:error, 5, "korrumpiert oder mit anderem Schluessel verschluesselt"}
      {:error, reason} -> {:error, 1, "Lesen oder Schreiben fehlgeschlagen: #{inspect(reason)}"}
    end
  end

  # --- status --------------------------------------------------------------------------

  defp status(dir, _opts) do
    if File.dir?(dir) do
      {0,
       [
         {:out,
          "ris_kassetten: #{length(json_files(dir))} Klartext-Kassette(n), #{length(enc_files(dir))} versiegelt"}
       ]}
    else
      {1, [{:err, "ris_kassetten: Verzeichnis fehlt: #{dir}"}]}
    end
  end

  # --- gemeinsame Vorpruefung -------------------------------------------------------------

  defp precheck(dir) do
    cond do
      not File.dir?(dir) -> {:error, 1, "ris_kassetten: Verzeichnis fehlt: #{dir}"}
      true -> repo_check(dir)
    end
  end

  defp repo_check(dir) do
    case check_dir(dir) do
      :ok ->
        :ok

      {:error, {:dir_in_repo, repo}} ->
        {:error, 1,
         "ris_kassetten: #{dir} liegt im Git-Repo #{repo}; Kassetten gehoeren ausserhalb jedes Repos"}
    end
  end
end

KomkiConnectorRis.RisHttp.cli(System.argv(), fn argv ->
  {code, meldungen} = KomkiConnectorRis.RisKassetten.run(argv)

  Enum.each(meldungen, fn
    {:out, text} -> IO.puts(text)
    {:err, text} -> IO.puts(:stderr, text)
  end)

  if code != 0, do: exit({:shutdown, code})
end)
