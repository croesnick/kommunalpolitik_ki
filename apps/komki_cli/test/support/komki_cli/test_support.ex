defmodule KomkiCli.TestSupport do
  @moduledoc """
  Test-Fixtures (nur in `:test` kompiliert; siehe `elixirc_paths` in mix.exs).

  Hermetisch und umgebungsagnostisch: temporäre Bereiche unter `/tmp`
  (sonst `System.tmp_dir!/`) mit Auto-Cleanup über `on_exit/1`, selbstgebaute
  Symlink-Paare und die Kernel-realpath-Referenz. Keine Annahmen über
  `/private` oder das Symlink-Layout des Hosts — die Invarianten gelten
  per Definition auf jedem Dateisystem.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  @doc """
  Einmaliger, existierender temporärer Bereich; nach dem Test automatisch
  entfernt. `unique_integer` wiederholt sich über VM-Neustarts, deshalb
  zusätzlich ein Zeitstempel-Suffix.
  """
  @spec tmp_area!(String.t()) :: String.t()
  def tmp_area!(prefix) do
    dir = Path.join(tmp_root(), prefix <> "-" <> unique_suffix())

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    dir
  end

  # Kurze Wurzel (Ticket #146): Socket-Pfade unter der Basis duerfen 103 Byte
  # nicht ueberschreiten; das macOS-TMPDIR (/var/folders/...) ist dafuer zu
  # lang. /tmp, wo vorhanden, sonst System.tmp_dir!/0.
  defp tmp_root, do: if(File.dir?("/tmp"), do: "/tmp", else: System.tmp_dir!())

  @doc "Symlink-Paar unter `dir`: `%{real: existierendes Verz., link: Symlink darauf}`."
  @spec symlink_pair!(String.t()) :: %{real: String.t(), link: String.t()}
  def symlink_pair!(dir) do
    real = Path.join([dir, "real"])
    File.mkdir_p!(real)

    link = Path.join([dir, "link"])
    File.ln_s!(real, link)

    %{real: real, link: link}
  end

  @doc """
  `readlink(1)`-Referenz: die POSIX-Kernel-Sicht eines Pfads (differenziales
  Orakel, löst auch fehlende Enden auf). Wirft, wenn readlink fehlt — ein
  fehlendes Orakel soll laut auffallen, nicht still bestehen.
  """
  @spec readlink!(String.t()) :: String.t()
  def readlink!(path) do
    {out, 0} = System.cmd("readlink", ["-f", path])
    String.trim_trailing(out)
  end

  @doc """
  Fixtur-cfg mit expliziten Werkzeugpfaden. CI-Runner haben keine dieser
  Werkzeuge — die Profil- und argv-Invarianten brauchen keine echten
  Binaries, nur konsistente Pfade. Die Entdeckung selbst wird in
  config_test geprueft.
  """
  @spec fixture_cfg(String.t()) :: KomkiCli.Config.t()
  def fixture_cfg(base) do
    cfg = KomkiCli.Config.defaults(base)

    %{
      cfg
      | node_bin: "/usr/local/bin/node",
        cli_js: "/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js",
        llama_server_bin: "/usr/local/bin/llama-server",
        fd_bin: "/usr/local/bin/fd",
        rg_bin: "/usr/local/bin/rg"
    }
  end

  @doc "Lauf-eindeutiger Suffix (unique_integer plus Zeitstempel)."
  @spec unique_suffix() :: String.t()
  def unique_suffix do
    Integer.to_string(System.unique_integer([:positive])) <>
      "-" <> Integer.to_string(System.system_time(:millisecond))
  end

  @doc """
  Startet einen Attrappen-Prozess, dessen ps-Kommandozeile `marker` und
  `anchor` (Wort) trägt; mit `open_file: pfad` hält er zusätzlich `pfad` als
  stdout offen (Egress-Anker). Compound-Kommando, damit die Zeile erhalten
  bleibt. Liefert die OS-pid; der Aufrufer beendet ihn (`Proc.kill_checked/3`
  oder `kill_fake/1`).
  """
  @spec spawn_fake(String.t(), String.t() | nil, keyword()) :: pos_integer()
  def spawn_fake(marker, anchor \\ nil, opts \\ []) do
    redirect =
      case Keyword.get(opts, :open_file) do
        nil -> ""
        path -> "exec 1>>'" <> path <> "'; "
      end

    cmd = redirect <> "while :; do sleep 1; done # " <> marker <> " " <> (anchor || "")
    port = Port.open({:spawn_executable, "/bin/sh"}, args: ["-c", cmd])
    {:os_pid, pid} = Port.info(port, :os_pid)
    pid
  end

  @doc "Beendet eine Attrappe unbedingt (ohne Identitätscheck)."
  @spec kill_fake(pos_integer()) :: term()
  def kill_fake(pid),
    do: System.cmd("/bin/kill", ["-KILL", Integer.to_string(pid)], stderr_to_stdout: true)
end
