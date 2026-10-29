defmodule KomkiCli.Config do
  @moduledoc """
  Konfiguration für die KomKI-CLI (Ticket #74).

  `config.json` im Basisverzeichnis hält die gepinnte Modellkombination aus dem
  Ticket-#70-Beschluss: Port, GGUF-Pfad samt erwartetem
  SHA256, pi-Home, Node-Interpreter, pi-Bundle, llama-server- und
  sandbox-exec-Pfade; optional die pi-Such-Werkzeuge fd/rg und der
  Vermittler-Binary `komki-mediator` (nil, wenn auf dem Host nicht entdeckt —
  Ticket #102). Einen Vermittler-Port gibt es seit Ticket #143 nicht mehr:
  der Vermittler lauscht auf `<base>/run/mediator.sock` (`KomkiCli.Channel`);
  ein `mediator_port` in aelteren config.json wird ignoriert.

  Connectoren und Egress (Ticket #146, CONTRACT.md §2/§4/§9), alle optional
  (aeltere config.json laden mit Defaults):

    * `escript_bin` — aufgeloeste Erlang-`escript`-Laufzeit; jedes komki-Escript
      startet unter Seatbelt als `escript <datei>`.
    * `egress_bin`, `connector_bins` (id → Pfad) — entdeckt wie der Vermittler.
    * `egress_ports` — Loopback-Port je Connector mit Netz (Default ris 49531,
      web 49532).
    * `ris_base_url` — Default die echte RIS-API; `ris_mock_port` schaltet auf
      `http://127.0.0.1:<port>/` ohne Proxy um.
    * `vault_dir` — Default `<base>/vault` (synthetischer Test-Vault); leer
      oder fehlend: Vault-Connector startet nicht.

  Basisverzeichnis: `KOMKI_HOME` (default `~/.local/share/komki`).
  Alle Pfade werden kernel-kanonisiert, bevor sie ins Profil oder die
  Konfiguration geschrieben werden: aufgeloest per `realpath`, wie der
  Kernel den Pfad sieht — unter macOS also `/tmp/...` -> `/private/tmp/...`.
  Das ist die dokumentierte Pfadform-Cave aus der Phase-1-Probe:
  Seatbelt-Regeln in Symlink-Form matchen nicht.
  """

  @enforce_keys [
    :base_dir,
    :port,
    :ctx,
    :gguf_path,
    :gguf_sha256,
    :pi_home,
    :node_bin,
    :cli_js,
    :llama_server_bin,
    :sandbox_exec
  ]
  defstruct @enforce_keys ++
              [
                :profile_path,
                :fd_bin,
                :rg_bin,
                :mediator_bin,
                # Multicall-Programm (Ticket #179): komki selbst, wenn es alle Rollen traegt
                :komki_bin,
                # Burrito-Einzeldatei (Ticket #181): entpackte Laufzeit der Binary
                :runtime_root,
                # Connectoren und Egress (Ticket #146): Laufzeit, Binaries, Netz, Vault
                :escript_bin,
                :egress_bin,
                :ris_mock_port,
                :vault_dir,
                connector_bins: %{},
                egress_ports: %{},
                # Programm-Pins (KomkiCli.Pins): Name -> %{"path", "sha256"}
                pins: %{},
                ris_base_url: nil,
                # Wie Rollen starten (Ticket #181): "escript" (escript <komki> <rolle>)
                # oder "burrito" (<komki-binary> <rolle>)
                launcher: "escript"
              ]

  @type t :: %__MODULE__{
          base_dir: String.t(),
          port: pos_integer(),
          ctx: pos_integer(),
          gguf_path: String.t(),
          gguf_sha256: String.t(),
          pi_home: String.t(),
          node_bin: String.t() | nil,
          cli_js: String.t() | nil,
          llama_server_bin: String.t() | nil,
          fd_bin: String.t() | nil,
          rg_bin: String.t() | nil,
          mediator_bin: String.t() | nil,
          komki_bin: String.t() | nil,
          runtime_root: String.t() | nil,
          launcher: String.t(),
          sandbox_exec: String.t(),
          profile_path: String.t(),
          escript_bin: String.t() | nil,
          egress_bin: String.t() | nil,
          connector_bins: %{String.t() => String.t() | nil},
          egress_ports: %{String.t() => pos_integer()},
          ris_base_url: String.t() | nil,
          ris_mock_port: pos_integer() | nil,
          vault_dir: String.t() | nil,
          pins: %{String.t() => %{String.t() => String.t()}}
        }

  # Felder, deren Werkzeug-Pfade bei init entdeckt wurden (nil, wenn das
  # Werkzeug fehlt — init verweigert dann mit klarer Meldung).
  defguard tools_ready(cfg)
           when is_binary(cfg.node_bin) and is_binary(cfg.cli_js) and
                  is_binary(cfg.llama_server_bin)

  # Modell-Pin (Nutzer-GO 05.10.2026 nach Model-Recherche): Gemma 4 26B-A4B-it
  # als unsloth UD-Q4_K_XL-GGUF — 26B-MoE (3.8B aktiv), 256K nativer Kontext,
  # starke Deutsch-Community-Reports. SHA wird nach Download-Verifikation
  # gepinnt; Quell-Upload: huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF.
  @expected_gguf_sha256 "ef728c8e0c337fd1067b947af006e38a9ef2419e56feced4fd29b4bf0636e30c"
  @model_filename "gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf"

  @default_sandbox_exec "/usr/bin/sandbox-exec"
  @default_port 49_524
  # Nutzer-Präferenz «große Kontexte» bei 64 GB RAM: 128K ist der Default;
  # Gemma 4 hält den KV-Cache via SWA klein.
  @default_ctx 131_072
  # Connectoren (Ticket #146): je Connector mit egress_hosts ein eigener
  # Loopback-Port am Egress-Proxy (CONTRACT.md §9).
  @default_egress_ports %{"ris" => 49_531, "web" => 49_532}
  # Echte RIS-API (dieselbe Basis wie apps/ratsinfo); der Host steht im
  # Manifest als egress_hosts-Eintrag.
  @default_ris_base_url "https://risapi1.komuna.net/web/"
  @pi_bundle_rel "node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js"

  @spec expected_gguf_sha256 :: String.t()
  def expected_gguf_sha256, do: @expected_gguf_sha256

  @spec model_filename :: String.t()
  def model_filename, do: @model_filename

  @doc "Default-GGUF-Quelle: das bereitgestellte Staging-Artefakt (falls vorhanden)."
  @spec default_probe_gguf() :: String.t() | nil
  def default_probe_gguf do
    if File.exists?(staging_gguf_path()), do: staging_gguf_path(), else: nil
  end

  ## ------------------------------------------------------- Werkzeug-Entdeckung

  # Keine hartkodierten Maschinenpfade: init entdeckt die drei Werkzeuge zur
  # Laufzeit und pinnt die aufgeloesten Pfade in die config.json der Instanz.
  # Die Pfade bleiben dadurch Maschinen-unabhaengig und trotzdem gepinnt.

  @doc """
  node-Interpreter-Entdeckung: (a) asdf via `asdf which node` — noetig, weil
  der asdf-Shim ein Shell-Skript ist und unter der Seatbelt-Grenze still
  scheitert; gebraucht wird der echte Installationspfad dahinter. (b) PATH
  mit Kernel-Realpath (Homebrew-Symlink; asdf-Shims ausgeschlossen). (c) der
  neueste nvm-Install. nil, wenn nichts davon existiert.
  """
  @spec resolve_node_bin() :: String.t() | nil
  def resolve_node_bin do
    asdf_which("node") || path_node() || nvm_node()
  end

  @doc """
  pi-Bundle-Entdeckung (cli.js): zuerst das pi, das neben komki liegt
  (Homebrew-Formel, Ticket #180: gepinnte Version in `libexec/lib`), dann
  ein globales pnpm (`pnpm add -g`, unter `$PNPM_HOME` oder `~/Library/pnpm`),
  dann die globalen node_modules-Roots — die zum entdeckten node gehoerige
  (asdf/nvm-Layout: `<install>/lib`), dann Homebrew ARM und Intel. nil,
  wenn das Bundle nirgends liegt.
  """
  @spec resolve_cli_js(String.t() | nil) :: String.t() | nil
  def resolve_cli_js(node_bin) do
    roots =
      bundled_lib_roots() ++
        pnpm_lib_roots() ++
        install_lib_roots(node_bin) ++ ["/opt/homebrew/lib", "/usr/local/lib"]

    Enum.find_value(roots, fn root ->
      candidate = Path.join(root, @pi_bundle_rel)

      if File.exists?(candidate), do: canonical(candidate), else: nil
    end)
  end

  @doc "llama-server-Entdeckung über PATH (Kernel-Realpath). nil, falls fehlt."
  @spec resolve_llama_server() :: String.t() | nil
  def resolve_llama_server, do: resolve_optional_tool("llama-server")

  @doc """
  komki-mediator-Entdeckung (Ticket #102): erst PATH (Kernel-Realpath, wie
  llama-server), dann die instanz-lokale Form `<base>/bin/komki-mediator`
  (BIN-Baum neben config.json). nil, wenn beides fehlt — bewusst OPTIONAL
  wie fd/rg: init verweigert nicht, `up` und `doctor` verantworten die
  Praesenz. Keine ausgedachten Pfade: nur gefundene werden gepinnt.
  """
  @spec resolve_mediator_bin(String.t()) :: String.t() | nil
  def resolve_mediator_bin(base_dir) when is_binary(base_dir),
    do: resolve_escript("komki-mediator", base_dir)

  @doc """
  Entdeckung eines komki-Escripts (Vermittler, Egress, Connectoren; Ticket
  #146): erst PATH (Kernel-Realpath), dann `<base>/bin/<name>`. nil, wenn
  beides fehlt — `up` und `doctor` verantworten die Praesenz.
  """
  @spec resolve_escript(String.t(), String.t()) :: String.t() | nil
  def resolve_escript(name, base_dir) when is_binary(name) and is_binary(base_dir) do
    case resolve_optional_tool(name) do
      nil ->
        candidate = Path.join([base_dir, "bin", name])
        if File.exists?(candidate), do: candidate, else: nil

      path ->
        path
    end
  end

  @doc """
  Erlang-`escript`-Laufzeit (Ticket #146): Unter Seatbelt startet komki
  jedes Escript ueber den aufgeloesten `escript`-Pfad statt ueber den
  Shebang (`/usr/bin/env escript` endete im asdf-Shim, einem Shell-Skript,
  das unter der Sandbox scheitert — dieselbe Klasse wie beim node-Shim).
  asdf zuerst, dann PATH ohne asdf-Shims.
  """
  @spec resolve_escript_bin() :: String.t() | nil
  def resolve_escript_bin do
    running_escript() || asdf_which("escript") ||
      case System.find_executable("escript") do
        nil -> nil
        path -> if String.contains?(path, "/.asdf/shims/"), do: nil, else: canonical(path)
      end
  end

  @doc """
  komki selbst als Multicall-Programm (Ticket #179): der kanonische Pfad
  des laufenden Escripts bzw. der Burrito-Binary, wenn deren Dateiname mit
  `komki` beginnt. Unter `mix` (Tests, `mix run`) ist das laufende Skript
  `mix`; dann nil, und die Bausteine werden wie bisher einzeln gesucht.
  """
  @spec self_komki() :: String.t() | nil
  def self_komki do
    path = KomkiCli.Runtime.self_path()
    if String.starts_with?(Path.basename(path), "komki"), do: canonical(path), else: nil
  rescue
    _ -> nil
  end

  # Die Laufzeit, auf der komki selbst laeuft (Ticket #179): Rollen starten
  # auf derselben Erlang-Installation, auch wenn sie nicht im PATH liegt
  # (etwa Homebrews keg-only `erlang@28`).
  defp running_escript do
    candidate = Path.join([to_string(:code.root_dir()), "bin", "escript"])
    if File.exists?(candidate), do: canonical(candidate), else: nil
  end

  @doc "Erlang-Wurzel zu einem `escript`-Pfad (`<root>/bin/escript`)."
  @spec erlang_root(String.t()) :: String.t()
  def erlang_root(escript_bin), do: Seatbelt.erlang_root(escript_bin)

  @doc "Default der Egress-Ports je Connector (CONTRACT.md §9)."
  @spec default_egress_ports() :: %{String.t() => pos_integer()}
  def default_egress_ports, do: @default_egress_ports

  @doc "Default-Basis der RIS-API (echter Betrieb)."
  @spec default_ris_base_url() :: String.t()
  def default_ris_base_url, do: @default_ris_base_url

  @doc """
  Entdeckung eines optionalen Werkzeugs ueber PATH (Kernel-Realpath). nil,
  falls es fehlt — im Gegensatz zur Kern-Kette (node/cli/llama-server) kein
  init-Gate: fehlt das Werkzeug, bleibt es beim Verzicht (init ueberspringt
  dann nur die zugehoerige Kopie in pi's Bin-Fundus).
  """
  @spec resolve_optional_tool(String.t()) :: String.t() | nil
  def resolve_optional_tool(name) when is_binary(name) do
    case System.find_executable(name) do
      nil -> nil
      path -> canonical(path)
    end
  end

  defp asdf_which(binary) do
    with exec when not is_nil(exec) <- System.find_executable("asdf"),
         {out, 0} <- System.cmd(exec, ["which", binary], stderr_to_stdout: true) do
      path = String.trim(out)

      if path != "" and File.exists?(path), do: canonical(path), else: nil
    else
      _ -> nil
    end
  end

  defp path_node do
    case System.find_executable("node") do
      nil ->
        nil

      path ->
        # asdf-Shims sind Shell-Skripte (unter Seatbelt unbrauchbar): entweder
        # hat asdf_which sie aufgeloest, oder sie taugen nicht als Pfad.
        if String.contains?(path, "/.asdf/shims/"), do: nil, else: canonical(path)
    end
  end

  defp nvm_node do
    base = Path.join(System.user_home!(), ".nvm/versions/node")

    if File.exists?(base) do
      newest_nvm_node(base)
    else
      nil
    end
  end

  # Neueste zuerst: Versionsverzeichnisse sortieren und das erste echte
  # node-Binary nehmen (nvm benennt die Dirs nach der Version).
  defp newest_nvm_node(base) do
    base
    |> File.ls!()
    |> Enum.sort()
    |> Enum.reverse()
    |> Enum.find_value(fn version ->
      candidate = Path.join([base, version, "bin", "node"])

      if File.exists?(candidate), do: canonical(candidate), else: nil
    end)
  end

  # Neben dem laufenden komki (Formel-Layout libexec/komki + libexec/lib).
  defp bundled_lib_roots do
    case self_komki() do
      nil -> []
      komki -> [Path.join(Path.dirname(komki), "lib")]
    end
  end

  # Globales pnpm: bis pnpm 10 liegt der Baum unter global/<n>/node_modules,
  # ab pnpm 11 je Installation unter global/v<n>/<id>/node_modules.
  defp pnpm_lib_roots do
    home =
      System.get_env("PNPM_HOME") || Path.join(System.user_home!(), "Library/pnpm")

    Enum.sort(Path.wildcard(Path.join(home, "global/*"))) ++
      Enum.sort(Path.wildcard(Path.join(home, "global/*/*")))
  end

  # asdf/nvm-Layout: <install>/bin/node -> <install>/lib liegt der globale
  # npm-Baum. Fremde Layouts liefern [] und die generischen Roots greifen.
  defp install_lib_roots(nil), do: []

  defp install_lib_roots(node_bin) when is_binary(node_bin),
    do: [Path.join(node_bin |> Path.dirname() |> Path.dirname(), "lib")]

  @doc """
  Staging-Ort des Modell-Artefakts (Download-Ziel des Pins und init-Quelle;
  die Instanz haelt nur die SHA-verifizierte Kopie).
  """
  @spec staging_gguf_path() :: String.t()
  def staging_gguf_path,
    do:
      Path.join([
        canonical(System.user_home!()),
        ".local",
        "share",
        "komki",
        "models-staging",
        @model_filename
      ])

  @doc "Basisverzeichnis: KOMKI_HOME oder ~/.local/share/komki."
  @spec default_base() :: String.t()
  def default_base do
    case System.get_env("KOMKI_HOME") do
      nil -> Path.join(canonical(System.user_home!()), ".local/share/komki")
      env -> canonical(env)
    end
  end

  @doc """
  Kanonisieren: expandierte Form, aufgeloest so, wie der Kernel den Pfad
  sieht (`realpath` des tiefsten existierenden Vorfahren plus Rest).
  Symlinks werden aufgeloest — unter macOS entsteht so die
  `/private/...`-Form (Pfadform-Cave aus Phase 1: Seatbelt-Regeln in
  Symlink-Form matchen nicht), unter anderen Hosts bleibt z.B. `/tmp/...`
  einfach `/tmp/...`. Die Definition liest das Dateisystem selbst, keine
  Plattform-Weichen. Idempotent.

  Implementierung lebt seit Ticket #226 in der Library (`Seatbelt.canonical/1`);
  dieser Einstieg bleibt als komki-API erhalten.
  """
  @spec canonical(String.t()) :: String.t()
  def canonical(path) when is_binary(path), do: Seatbelt.canonical(path)

  # Burrito-Einzeldatei (Ticket #181): Rollen starten als `<binary> <rolle>`,
  # die Laufzeit liegt entpackt unter :code.root_dir(). Sonst Escript.
  defp launcher(komki) when is_binary(komki) do
    if KomkiCli.Runtime.burrito?(), do: "burrito", else: "escript"
  end

  defp launcher(nil), do: "escript"

  defp runtime_root(komki) when is_binary(komki) do
    if KomkiCli.Runtime.burrito?(), do: canonical(to_string(:code.root_dir())), else: nil
  end

  defp runtime_root(nil), do: nil

  @doc """
  Verzeichnis, das der Burrito-Wrapper per `KOMKI_INSTALL_DIR` bekommt, damit
  er die entpackte Laufzeit findet, obwohl Rollen mit dem HOME der Instanz
  starten: zwei Ebenen ueber `runtime_root`
  (`<dir>/.burrito/komki_erts-<v>_<app>`).
  """
  @spec burrito_install_dir(t()) :: String.t()
  def burrito_install_dir(%__MODULE__{runtime_root: root}) when is_binary(root),
    do: root |> Path.dirname() |> Path.dirname()

  @doc """
  Defaults für eine frische KomKI-CLI-Instanz: Modell-Pins plus die zur
  Laufzeit entdeckten Werkzeugpfade (kanonisch; nil, wenn das Werkzeug
  fehlt — init verweigert dann mit klarer Meldung).
  """
  @spec defaults(String.t(), keyword()) :: t()
  def defaults(base_dir, opts \\ []) when is_binary(base_dir) and is_list(opts) do
    base = canonical(base_dir)
    node_bin = resolve_node_bin()
    komki = Keyword.get_lazy(opts, :komki_bin, &self_komki/0)

    %__MODULE__{
      base_dir: base,
      port: opts[:port] || @default_port,
      ctx: opts[:ctx] || @default_ctx,
      gguf_path: Path.join([base, "models", @model_filename]),
      gguf_sha256: @expected_gguf_sha256,
      pi_home: Path.join(base, "pi-home"),
      node_bin: node_bin,
      cli_js: resolve_cli_js(node_bin),
      llama_server_bin: resolve_llama_server(),
      fd_bin: resolve_optional_tool("fd"),
      rg_bin: resolve_optional_tool("rg"),
      mediator_bin: komki || resolve_mediator_bin(base),
      komki_bin: komki,
      launcher: launcher(komki),
      runtime_root: runtime_root(komki),
      sandbox_exec: canonical(@default_sandbox_exec),
      profile_path: Path.join([base, "profile", "komki.sb"]),
      escript_bin: resolve_escript_bin(),
      egress_bin: komki || resolve_escript("komki-egress", base),
      connector_bins:
        Map.new(
          KomkiConnector.Manifest.all(),
          &{&1.id, komki || resolve_escript(&1.binary, base)}
        ),
      egress_ports: @default_egress_ports,
      ris_base_url: opts[:ris_base_url] || @default_ris_base_url,
      ris_mock_port: opts[:ris_mock_port],
      # Default: synthetischer Test-Vault unter der Basis (init legt ihn an)
      vault_dir: vault_dir_opt(opts[:vault_dir], base)
    }
  end

  defp vault_dir_opt(nil, base), do: Path.join(base, "vault")
  defp vault_dir_opt("", _base), do: nil
  defp vault_dir_opt(dir, _base), do: canonical(dir)

  @doc """
  RIS im Mock-Betrieb (CONTRACT.md §9)? Dann spricht der Connector direkt
  mit `http://127.0.0.1:<ris_mock_port>/` statt ueber den Egress-Proxy.
  """
  @spec ris_mock?(t()) :: boolean()
  def ris_mock?(%__MODULE__{ris_mock_port: port}), do: is_integer(port)

  @doc "Effektive RIS-Basis-URL (Mock-Port gewinnt)."
  @spec ris_url(t()) :: String.t()
  def ris_url(%__MODULE__{ris_mock_port: port}) when is_integer(port),
    do: "http://127.0.0.1:" <> Integer.to_string(port) <> "/"

  def ris_url(%__MODULE__{ris_base_url: url}), do: url || @default_ris_base_url

  @doc "Pfad der config.json für ein Basisverzeichnis."
  @spec config_path(String.t()) :: String.t()
  def config_path(base_dir), do: Path.join(canonical(base_dir), "config.json")

  @doc "config.json lesen; `{:ok, cfg}` oder `{:error, reason}`."
  @spec load(String.t()) :: {:ok, t()} | {:error, String.t()}
  def load(config_path) do
    case File.read(config_path) do
      {:ok, content} ->
        parse(content)

      {:error, posix} ->
        {:error,
         "cannot read " <> config_path <> ": " <> List.to_string(:file.format_error(posix))}
    end
  end

  @doc "config.json lesen; wirft bei Fehler `RuntimeError`."
  @spec load!(String.t()) :: t()
  def load!(config_path) do
    case load(config_path) do
      {:ok, cfg} -> cfg
      {:error, reason} -> raise RuntimeError, message: reason
    end
  end

  @spec parse(String.t()) :: {:ok, t()} | {:error, String.t()}
  defp parse(content) do
    case JSON.decode(content) do
      {:ok, map} when is_map(map) -> from_map(map)
      {:ok, _} -> {:error, "config.json: expected a JSON object"}
      {:error, err} -> {:error, "config.json parse error: " <> Kernel.inspect(err)}
    end
  end

  @keys [
    :base_dir,
    :port,
    :ctx,
    :gguf_path,
    :gguf_sha256,
    :pi_home,
    :node_bin,
    :cli_js,
    :llama_server_bin,
    :sandbox_exec,
    :profile_path
  ]

  # Optionale Felder: fehlen sie in aelteren config.json, wird nil gelesen —
  # kein Breaking-Change fuer bestehende Instanzen.
  @optional_keys [
    :fd_bin,
    :rg_bin,
    :mediator_bin,
    :komki_bin,
    :launcher,
    :runtime_root,
    :escript_bin,
    :egress_bin,
    :connector_bins,
    :egress_ports,
    :ris_base_url,
    :ris_mock_port,
    :vault_dir,
    :pins
  ]

  @spec from_map(%{String.t() => term()}) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) do
    missing = Enum.reject(@keys, &Map.has_key?(map, Atom.to_string(&1)))

    case missing do
      [] ->
        {:ok, from_complete_map(map)}

      _ ->
        # Neuer Pflicht-Key in einer
        # aelteren Instanz: der Recovery-Weg ist direkt im Fehlertext.
        {:error,
         "config.json: missing key(s): " <>
           Enum.map_join(missing, ", ", &Atom.to_string/1) <>
           " — 'komki init --force' erneuert die Instanz"}
    end
  end

  defp from_complete_map(map) do
    %__MODULE__{
      base_dir: map["base_dir"],
      port: require_pos(:port, map["port"]),
      ctx: require_pos(:ctx, map["ctx"]),
      gguf_path: map["gguf_path"],
      gguf_sha256: map["gguf_sha256"],
      pi_home: map["pi_home"],
      node_bin: map["node_bin"],
      cli_js: map["cli_js"],
      llama_server_bin: map["llama_server_bin"],
      fd_bin: Map.get(map, "fd_bin"),
      rg_bin: Map.get(map, "rg_bin"),
      mediator_bin: Map.get(map, "mediator_bin"),
      komki_bin: Map.get(map, "komki_bin"),
      launcher: Map.get(map, "launcher") || "escript",
      runtime_root: Map.get(map, "runtime_root"),
      sandbox_exec: map["sandbox_exec"],
      profile_path: map["profile_path"],
      # Ticket #146: aeltere Instanzen ohne diese Felder laden mit Defaults;
      # ein fehlender oder leerer vault_dir heisst: Vault-Connector startet nicht.
      escript_bin: Map.get(map, "escript_bin"),
      egress_bin: Map.get(map, "egress_bin"),
      connector_bins: Map.get(map, "connector_bins") || %{},
      egress_ports: ports(Map.get(map, "egress_ports", @default_egress_ports)),
      ris_base_url: Map.get(map, "ris_base_url") || @default_ris_base_url,
      ris_mock_port: optional_pos(:ris_mock_port, Map.get(map, "ris_mock_port")),
      vault_dir: blank_to_nil(Map.get(map, "vault_dir")),
      pins: Map.get(map, "pins") || %{}
    }
  end

  defp ports(map) when is_map(map),
    do: Map.new(map, fn {id, port} -> {id, require_pos(:egress_ports, port)} end)

  defp ports(other) do
    raise RuntimeError,
      message: "config.json: egress_ports must be an object, got " <> Kernel.inspect(other)
  end

  defp optional_pos(_key, nil), do: nil
  defp optional_pos(key, value), do: require_pos(key, value)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  @doc "config.json serialisieren (sortierte Schlüssel, genau ein finales Newline beim Speichern)."
  @spec encode(t()) :: String.t()
  def encode(%__MODULE__{} = cfg) do
    (@keys ++ @optional_keys)
    |> Map.new(fn key -> {Atom.to_string(key), Map.fetch!(cfg, key)} end)
    |> JSON.encode!()
  end

  @doc "config.json schreiben (Verzeichnis wird erzeugt)."
  @spec save(t()) :: :ok
  def save(%__MODULE__{} = cfg) do
    path = config_path(cfg.base_dir)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, encode(cfg) <> "\n")
    :ok
  end

  defp require_pos(_key, value) when is_integer(value) and value > 0, do: value

  defp require_pos(key, value) do
    raise RuntimeError,
      message:
        "config.json: " <>
          Atom.to_string(key) <>
          " must be a positive integer, got " <> Kernel.inspect(value)
  end
end
