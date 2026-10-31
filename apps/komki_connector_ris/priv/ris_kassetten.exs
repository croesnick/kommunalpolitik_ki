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
# Klartext-Kassetten auch; seal/unseal lehnen Repos ab (RisHttp.repo_free?,
# wie ris_recorder — auch durch Symlinks hindurch). Replay und Skelett
# lesen *.json: vorher unseal, danach seal.
#
# Nur OTP (:crypto, Ports), keine Deps. Die Port-Muster sind aus komki_cli
# dupliziert statt importiert (Unix-Prinzip; Andockpunkt: Tresor-Kern #224).

Code.require_file("./ris_http.exs", __DIR__)

defmodule KomkiConnectorRis.RisKassetten do
  @moduledoc false

  alias KomkiConnectorRis.RisHttp

  @service "ris-kassetten"
  # Format-Label von komki-tresor (native/komki-tresor/main.swift): so beginnt
  # ein Siegel. Bewusst ein anderes Praefix als @magic, damit Siegel und
  # Kassetten-Container nie verwechselt werden.
  @tresor_prefix "ktv1."
  @tresor_program "komki-tresor"
  @seal_timeout_ms 10_000
  # Oeffnen wartet auf Touch ID oder Passwort.
  @open_timeout_ms 120_000
  @check_timeout_ms 10_000

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
  @type kc_error :: :missing | :timeout | :invalid | :not_stored | {:failed, integer()}
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
  # Ein Token mit --Praefix ist nie ein Pfad: ein --tresor ohne Wert waere
  # sonst still der Pfad und der Aufruf melden ein fehlendes Verzeichnis.
  defp parse_flags(cmd, ["--tresor", value | rest], dir, opts),
    do: parse_flags(cmd, rest, dir, Keyword.put(opts, :tresor, value))

  defp parse_flags(cmd, [dir | rest], nil, opts)
       when cmd in ~w(seal unseal status) and
              (byte_size(dir) < 2 or binary_part(dir, 0, 2) != "--"),
       do: parse_flags(cmd, rest, dir, opts)

  defp parse_flags("init", [], nil, opts), do: {:ok, nil, opts}
  defp parse_flags(_cmd, [], dir, opts) when is_binary(dir), do: {:ok, dir, opts}
  defp parse_flags(_cmd, _other, _dir, _opts), do: :error

  @doc """
  Kommandozeile abarbeiten und `{exit_code, meldungen}` liefern (statt selbst
  zu enden) — Tests laufen darueber, der Runner druckt nur noch.
  """
  @spec run([String.t()], keyword()) :: {non_neg_integer(), [meldung()]}
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
      nil ->
        System.find_executable(@tresor_program)

      # Tippfehler im --tresor-Pfad: nil statt haesslichem Port-Crash. Ein
      # existierender, aber nicht ausfuehrbarer Pfad faengt erst beim Spawn
      # auf (sicher_spawn) und wird ebenso zu missing_bin.
      path ->
        if path |> Path.expand() |> File.exists?(), do: Path.expand(path), else: nil
    end
  end

  @doc """
  Secure Enclave des Programms pruefen (`check`-Subkommando), mit Timeout:
  ein haengendes Programm blockt init nicht fuer immer.
  """
  @spec tresor_check(String.t(), keyword()) ::
          :ok | {:error, :no_enclave | :timeout | tresor_error()}
  def tresor_check(command, opts \\ []) do
    case sicher_spawn(command, ["check"]) do
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
  # (komki-tresor-Konvention). Ein Fehlstart (nicht ausfuehrbar, Gatekeeper)
  # wird zu missing_bin statt zu einer Roh-Exception.
  defp tresor_call(args, input, timeout, opts) do
    case tresor_bin(opts) do
      nil ->
        {:error, :missing_bin}

      bin ->
        case sicher_spawn(bin, args) do
          {:ok, port} ->
            Port.command(port, input <> "\n")
            collect(port, [], System.monotonic_time(:millisecond) + timeout, &tresor_on_exit/2)

          :spawn_failed ->
            {:error, :missing_bin}
        end
    end
  end

  defp sicher_spawn(bin, args) do
    {:ok, Port.open({:spawn_executable, bin}, [:binary, :exit_status, :use_stdio, args: args])}
  rescue
    _unhandled -> :spawn_failed
  end

  # stderr bleibt im Terminal (Meldungen des Programms, ohne Werte); stdout
  # traegt genau eine Zeile. Exit-Codes wie komki-tresor: 3 keine Enclave,
  # 4 keine Freigabe, 5 ungueltiges Siegel.
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

  # Exit-Codes: 3 Tresor/Enclave fehlt, 4 keine Freigabe, 5 Siegel ungueltig,
  # 1 Programm sonstwie gescheitert.
  defp tresor_exit(:missing_bin), do: 3
  defp tresor_exit(:no_enclave), do: 3
  defp tresor_exit(:refused), do: 4
  defp tresor_exit(:timeout), do: 4
  defp tresor_exit(:invalid), do: 5
  defp tresor_exit({:failed, _code}), do: 1

  # Versiegeln loest keine Freigabe aus: ein Timeout ist dort kein
  # Freigabe-Abbruch, sondern ein haengendes Programm (Exit 1, nicht 4).
  defp tresor_seal_exit(:timeout), do: 1
  defp tresor_seal_exit({:failed, _code}), do: 1
  defp tresor_seal_exit(other), do: tresor_exit(other)

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
  Wert als generisches Passwort ANLEGEN (nur init). Der Wert steht nie in argv
  (dort saehe ihn jeder Prozess per ps); `add-generic-password -w` ohne Wert
  kuertzte ihn interaktiv auf 128 Byte, deshalb geht der ganze Befehl als eine
  Zeile an `security -i` (Muster aus komki_cli/lib/komki_cli/keychain.ex).
  Ohne `-U`: existiert der Eintrag inzwischen doch (Rennen mit einem zweiten
  init), scheitert der Befehl, statt still zu ersetzen — ein neuer Schluessel
  wuerde alle bisher verschluesselten Kassetten unlesbar machen. Danach
  zuruecklesen und vergleichen.
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

  # `head -n 1` beendet stdin nach der einen Zeile; `security -i` endet dann.
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

  # Port statt System.cmd: nur so laesst sich ein haengendes security nach dem
  # Timeout beenden. stderr wird verworfen und taucht nie in Meldungen auf.
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

  # Nach dem Timeout koennte das Programm noch laufen. Bei Pipelines
  # (security -i) wuerden die Kinder beim Tod des Parents sonst zu Waisen und
  # weiterlaufen — deshalb zunaechst die Kinder, dann der Parent. badarg
  # faengt den Fall, dass der Port schon weg ist.
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

  # --- Krypto -----------------------------------------------------------------

  # AES-256-GCM, frische Nonce je Datei, Magic als AAD bindet die
  # Container-Version an den Chiffretext. OTP 29: Encrypt liefert
  # {chiffretext, tag}; Decrypt meldet Falsches als :error statt zu werfen.
  # Auch leere Kassetten sind zulaessig (Chiffretext der Laenge 0).
  defp sealed_blob(plain, key) do
    nonce = :crypto.strong_rand_bytes(@nonce_bytes)
    {ct, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, plain, @magic, true)
    [@magic, nonce, ct, tag]
  end

  # {:ok, klartext} | {:error, :bad_magic | :too_short | :bad_tag}
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

  # --- Verzeichnisse -------------------------------------------------------------

  @doc """
  `:ok`, wenn `dir` ausserhalb jedes Git-Repos liegt — auch Worktrees (deren
  `.git` eine Datei ist) und Symlinks, die hineinfuehren (RisHttp.repo_free?
  loest vorhandene Pfade auf). Verschluesselte Kassetten gehoeren genauso
  wenig ins Repo wie Klartext.
  """
  @spec check_dir(Path.t()) :: :ok | {:error, {:dir_in_repo, Path.t()}}
  def check_dir(dir) do
    case RisHttp.repo_free?(dir) do
      :ok -> :ok
      {:error, {:in_repo, repo}} -> {:error, {:dir_in_repo, repo}}
    end
  end

  # Eine Auflistung je Lauf (statt File.ls! plus je Datei ein File.exists?):
  # Zaehler und Kollisionspruefungen stammen aus derselben Aufnahme.
  # ".json.enc" endet nicht auf ".json" — die Mengen sind disjunkt.
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
        case tresor_check(bin, opts) do
          :ok ->
            init_key(opts)

          {:error, :no_enclave} ->
            {3, [{:err, "ris_kassetten: #{tresor_text(:no_enclave)}"}]}

          # Spawn gescheitert (nicht ausfuehrbar): derselbe Fehler wie ein
          # nicht gefundenes Programm.
          {:error, :missing_bin} ->
            {3, [{:err, "ris_kassetten: #{tresor_text(:missing_bin)}"}]}

          {:error, reason} ->
            {1, [{:err, "ris_kassetten: #{tresor_text(reason)}"}]}
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
        {tresor_seal_exit(reason),
         [{:err, "ris_kassetten: Versiegeln des Schluessels: #{tresor_text(reason)}"}]}
    end
  end

  defp init_store(sealed, opts) do
    case kc_put_new(@service, sealed, opts) do
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
        {kc_store_exit(reason),
         [{:err, "ris_kassetten: Speichern im Schluesselbund fehlgeschlagen: #{kc_text(reason)}"}]}
    end
  end

  # Gescheiterte Umgebung (Timeout, Exit ungleich 0) ist keine Siegel-Frage;
  # ein abgewichener oder unlesbarer Wert schon.
  defp kc_store_exit(:timeout), do: 1
  defp kc_store_exit({:failed, _code}), do: 1
  defp kc_store_exit(_other), do: 5

  # --- seal -------------------------------------------------------------------------

  # Billige Pruefungen zuerst (Verzeichnis, Repo, Auflistung, Kollisionen):
  # ein abgelehnter Lauf darf nie eine Freigabe ausloesen.
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
      {0, [{:out, "ris_kassetten: keine Kassetten zu versiegeln (nur *.json), nichts zu tun"}]}
    else
      case load_master_key("RIS-Kassetten verschluesseln", opts) do
        {:ok, key} ->
          {0, meldungen} = seal_each(files.json, dir, key, 0, [])
          {0, meldungen ++ other_warning(files)}

        {:error, reason} ->
          master_key_error(reason)
      end
    end
  end

  # Dateien, die keine *.json-Kassetten sind, bleiben unberuehrt Klartext —
  # sichtbar machen statt einen versiegelten Schein zu erwecken.
  defp other_warning(files) do
    if files.other == [] do
      []
    else
      [
        {:err,
         "ris_kassetten: #{length(files.other)} sonstige Datei(en) sind keine *.json-Kassetten " <>
           "und bleiben Klartext: #{Enum.join(files.other, ", ")}"}
      ]
    end
  end

  defp seal_each([], _dir, _key, n, acc) do
    {0,
     [
       {:out,
        "ris_kassetten: #{n} Kassette(n) versiegelt; der Schluessel war nur fuer diesen Lauf im Speicher"}
       | Enum.reverse(acc)
     ]}
  end

  defp seal_each([name | rest], dir, key, n, acc) do
    case seal_one(Path.join(dir, name), key) do
      :ok ->
        seal_each(rest, dir, key, n + 1, [{:out, "versiegelt: #{name}"} | acc])

      # Nicht loeschbarer Klartext ist ein lokales Problem dieser Datei
      # (Flag, Rechte): eigene .enc entsorgen, ueberspringen, weitermachen —
      # ein erneutes seal konvergiert.
      {:skip, msg} ->
        seal_each(rest, dir, key, n, [{:err, "uebersprungen: #{name} — #{msg}"} | acc])

      # Gegenprobe/Schreib-Fehler sind systemisch: abbrechen. Auch dann ist
      # der Zustand konvergent, weil die eigene .enc entsorgt wurde und der
      # Klartext bleibt.
      {:error, msg} ->
        {1,
         [
           {:err,
            "ris_kassetten: abgebrochen bei #{name}: #{msg}; #{n} versiegelt, " <>
              "#{length(rest) + 1} offen — Stand mit status pruefen, erneutes seal vollendet"}
           | Enum.reverse(acc)
         ]}
    end
  end

  # Eine Kassette versiegeln: atomar schreiben (Exklusiv, sync, 0600, rename),
  # Gegenprobe von der Platte, erst dann den Klartext loeschen.
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
      {:ok, _anderer} -> gegenprobe_fehl(enc)
      {:error, :bad_tag} -> gegenprobe_fehl(enc)
      {:error, {:restdatei, tmp}} -> {:error, "Restdatei #{Path.basename(tmp)} blockiert"}
      {:error, {:write, reason}} -> {:error, "Schreiben fehlgeschlagen: #{inspect(reason)}"}
      {:error, reason} -> {:error, "Lesen fehlgeschlagen: #{inspect(reason)}"}
    end
  end

  defp gegenprobe_fehl(enc) do
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
      {0, [{:out, "ris_kassetten: keine verschluesselten Kassetten, nichts zu tun"}]}
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
        "ris_kassetten: #{n} Kassette(n) entschluesselt; der Schluessel war nur fuer diesen Lauf im Speicher"}
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
            "ris_kassetten: abgebrochen bei #{name}: #{msg}; #{n} entschluesselt, " <>
              "#{length(rest) + 1} versiegelt — Stand mit status pruefen, erneutes unseal vollendet"}
           | Enum.reverse(acc)
         ]}
    end
  end

  # Der GCM-Tag ist die Integritaetspruefung (die Entschluesselung verifiziert
  # sich selbst) — keine zweite Gegenprobe noetig. Laesst sich die .enc nach
  # dem Schreiben nicht loeschen, wird die eigene Klartextdatei entfernt:
  # kein .json-UND-.enc-Zustand durch uns, ein erneutes unseal konvergiert.
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
          {:skip, "versiegelte Datei nicht loeschbar (#{inspect(reason)}); zurueckgerollt"}
      end
    else
      {:error, :bad_magic} -> {:error, 5, "keine rkt1-Kassette"}
      {:error, :too_short} -> {:error, 5, "zu kurz fuer rkt1"}
      {:error, :bad_tag} -> {:error, 5, "korrumpiert oder mit anderem Schluessel verschluesselt"}
      {:error, {:restdatei, tmp}} -> {:error, 1, "Restdatei #{Path.basename(tmp)} blockiert"}
      {:error, {:write, reason}} -> {:error, 1, "Schreiben fehlgeschlagen: #{inspect(reason)}"}
      {:error, reason} -> {:error, 1, "Lesen oder Schreiben fehlgeschlagen: #{inspect(reason)}"}
    end
  end

  # --- status --------------------------------------------------------------------------

  defp status(dir, _opts) do
    with :ok <- require_dir(dir),
         {:ok, files} <- list_ok(dir) do
      sonstige =
        if files.other == [], do: "", else: ", #{length(files.other)} sonstige Datei(en)"

      {0,
       [
         {:out,
          "ris_kassetten: #{length(files.json)} Klartext-Kassette(n), #{length(files.enc)} versiegelt" <>
            sonstige}
       ]}
    else
      {:error, code, msg} -> {code, [{:err, msg}]}
    end
  end

  # --- gemeinsame Vorpruefung -------------------------------------------------------------

  defp require_dir(dir) do
    if File.dir?(dir), do: :ok, else: {:error, 1, "ris_kassetten: Verzeichnis fehlt: #{dir}"}
  end

  defp require_repo_free(dir) do
    case check_dir(dir) do
      :ok ->
        :ok

      {:error, {:dir_in_repo, repo}} ->
        {:error, 1,
         "ris_kassetten: #{dir} liegt im Git-Repo #{repo}; Kassetten gehoeren ausserhalb jedes Repos"}
    end
  end

  # Auflistung darf nicht knallen (File.ls!): ein unlesbares Verzeichnis ist
  # eine Meldung wert, auch fuer status — gerade es zeigt den kaputten Zustand.
  defp list_ok(dir) do
    case list_dir(dir) do
      {:ok, files} ->
        {:ok, files}

      {:error, reason} ->
        {:error, 1, "ris_kassetten: Verzeichnis nicht lesbar: #{dir} (#{inspect(reason)})"}
    end
  end

  # Kollisionen vor der Freigabe: seal/unseal ueberschreiben nie. Die Pruefung
  # laeuft ueber die eine Auflistung, nicht ueber je Datei ein File.exists?.
  defp require_collision_free(files, :seal) do
    enc_set = MapSet.new(files.enc)

    case Enum.find(files.json, &MapSet.member?(enc_set, &1 <> ".enc")) do
      nil ->
        :ok

      name ->
        {:error, 1, "ris_kassetten: #{name}.enc existiert bereits; erst unseal oder Hand anlegen"}
    end
  end

  defp require_collision_free(files, :unseal) do
    json_set = MapSet.new(files.json)

    case Enum.find(files.enc, &MapSet.member?(json_set, json_of_enc(&1))) do
      nil ->
        :ok

      name ->
        {:error, 1,
         "ris_kassetten: #{json_of_enc(name)} existiert bereits; erst seal oder Hand anlegen"}
    end
  end

  # --- atomares Schreiben ------------------------------------------------------------------

  # Exklusiv (clobbert keine Restdatei aus einem Crash), sync (die Gegenprobe
  # liest nicht nur den Seitencache), 0600 (auch Klartext nie breiter lesbar),
  # rename im selben Verzeichnis (atomar). Misserfolg raeumt die Temp-Datei weg.
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
        {:error, {:restdatei, tmp}}

      {:error, reason} ->
        {:error, {:write, reason}}
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
