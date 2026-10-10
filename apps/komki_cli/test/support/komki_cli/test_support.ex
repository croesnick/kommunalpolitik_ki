defmodule KomkiCli.TestSupport do
  @moduledoc """
  Test-Fixtures (nur in `:test` kompiliert; siehe `elixirc_paths` in mix.exs).

  Hermetisch und umgebungsagnostisch: temporäre Bereiche unter
  `System.tmp_dir!/` mit Auto-Cleanup über `on_exit/1`, selbstgebaute
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
    dir = Path.join(System.tmp_dir!(), prefix <> "-" <> unique_suffix())

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    dir
  end

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
end
