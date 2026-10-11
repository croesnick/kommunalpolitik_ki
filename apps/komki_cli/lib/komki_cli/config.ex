defmodule KomkiCli.Config do
  @moduledoc """
  Konfiguration für die KomKI-CLI (Ticket #74).

  `config.json` im Basisverzeichnis hält die gepinnte Modellkombination aus dem
  Ticket-#70-Beschluss: Port, GGUF-Pfad samt erwartetem
  SHA256, pi-Home, Node-Interpreter, pi-Bundle, llama-server- und
  sandbox-exec-Pfade; optional die pi-Such-Werkzeuge fd/rg (nil, wenn auf
  dem Host nicht entdeckt).

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
  defstruct @enforce_keys ++ [:profile_path, :fd_bin, :rg_bin]

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
          sandbox_exec: String.t(),
          profile_path: String.t()
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
  # Nutzer-Präferenz «große Kontexte» bei 64 GB RAM: 128K ist derDefault;
  # Gemma 4 hält den KV-Cache via SWA klein.
  @default_ctx 131_072
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
  pi-Bundle-Entdeckung (cli.js): globale node_modules-Wurzeln — zuerst die
  zum entdeckten node gehoerige (asdf/nvm-Layout: `<install>/lib`),
  dann Homebrew ARM und Intel. nil, wenn das Bundle nirgends liegt.
  """
  @spec resolve_cli_js(String.t() | nil) :: String.t() | nil
  def resolve_cli_js(node_bin) do
    roots = install_lib_roots(node_bin) ++ ["/opt/homebrew/lib", "/usr/local/lib"]

    Enum.find_value(roots, fn root ->
      candidate = Path.join(root, @pi_bundle_rel)

      if File.exists?(candidate), do: canonical(candidate), else: nil
    end)
  end

  @doc "llama-server-Entdeckung ueber PATH (Kernel-Realpath). nil, falls fehlt."
  @spec resolve_llama_server() :: String.t() | nil
  def resolve_llama_server, do: resolve_optional_tool("llama-server")

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

  # asdf/nvm-Layout: <install>/bin/node -> <install>/lib liegt der globale
  # npm-Baum. Fremde Layouts liefern [] und die generischen Wurzeln greifen.
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
  """
  @spec canonical(String.t()) :: String.t()
  def canonical(path) when is_binary(path) do
    path
    |> Path.expand()
    |> resolve_realpath()
  end

  # Kernel-Sicht via readlink(1) (kein :file.realpath in diesem OTP).
  # BSD-readlink (macOS) scheitert an fehlenden Pfaden, GNU erlaubt
  # fehlende letzte Komponente — deshalb Fallback: tiefsten existierenden
  # Vorfahren aufloesen und den Rest wieder anfuegen. Ohne readlink
  # degradiert die Aufloesung auf die expandierte Form.
  defp resolve_realpath(expanded) do
    if bin = System.find_executable("readlink") do
      resolve(bin, expanded)
    else
      expanded
    end
  end

  defp resolve(bin, path) do
    case System.cmd(bin, ["-f", path]) do
      {real, 0} -> String.trim_trailing(real)
      {_, _} when path == "/" -> path
      {_, _} -> Path.join(resolve(bin, Path.dirname(path)), Path.basename(path))
    end
  end

  @doc """
  Defaults für eine frische KomKI-CLI-Instanz: Modell-Pins plus die zur
  Laufzeit entdeckten Werkzeugpfade (kanonisch; nil, wenn das Werkzeug
  fehlt — init verweigert dann mit klarer Meldung).
  """
  @spec defaults(String.t(), keyword()) :: t()
  def defaults(base_dir, opts \\ []) when is_binary(base_dir) and is_list(opts) do
    base = canonical(base_dir)
    node_bin = resolve_node_bin()

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
      sandbox_exec: canonical(@default_sandbox_exec),
      profile_path: Path.join([base, "profile", "komki.sb"])
    }
  end

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
  @optional_keys [:fd_bin, :rg_bin]

  @spec from_map(%{String.t() => term()}) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) do
    missing = Enum.reject(@keys, &Map.has_key?(map, Atom.to_string(&1)))

    case missing do
      [] ->
        {:ok, from_complete_map(map)}

      _ ->
        {:error,
         "config.json: missing key(s): " <> Enum.map_join(missing, ", ", &Atom.to_string/1)}
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
      sandbox_exec: map["sandbox_exec"],
      profile_path: map["profile_path"]
    }
  end

  @doc "config.json serialisieren (sortierte Schluessel, genau ein finales Newline beim Speichern)."
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
