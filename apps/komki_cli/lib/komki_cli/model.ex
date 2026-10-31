defmodule KomkiCli.Model do
  @moduledoc """
  Das gepinnte Modell beschaffen (Ticket #178, Entscheidung „Download ja“
  im Plan `docs/research/2026-10-24-komki-devx-installation.md`, §8) und
  dazu den MTP-Drafter (Ticket #318): dieselbe Disziplin — feste Revision,
  Pruefsumme vor und nach dem Download — fuer die zweite gepinnte Datei.

  Quelle ist eine feste Revision des Hugging-Face-Repos, nicht `main`. Vor
  dem Download vergleicht komki die vom Server gemeldete Pruefsumme
  (`X-Linked-ETag`, bei LFS-Dateien das SHA-256) mit dem Pin; danach prueft
  es die Datei selbst. Nur eine Datei mit passendem SHA-256 wird unter dem
  Staging-Pfad abgelegt, Teil-Downloads liegen daneben als `.part` und
  werden beim naechsten Versuch fortgesetzt.

  Geladen wird mit `/usr/bin/curl` (Teil von macOS): Fortsetzen (`-C -`),
  Weiterleitungen und Fortschrittsbalken ohne eigene HTTP-Logik. curl
  laeuft mit `:nouse_stdio`, damit der Balken direkt im Terminal steht.
  """

  alias KomkiCli.{Config, Steps}

  @repo "unsloth/gemma-4-26B-A4B-it-GGUF"
  @revision "c099eb48e663fd284577b04978a94ffccb261841"
  @size 17_010_980_576
  @license "Apache-2.0 (https://ai.google.dev/gemma/docs/gemma_4_license)"
  @curl "/usr/bin/curl"
  # Reserve fuer das Dateisystem ueber die fehlenden Bytes hinaus
  @headroom 1_000_000_000

  # MTP-Drafter (Ticket #318): gleiche Quelle/Revision wie das Modell, Datei
  # unter dem MTP-Unterordner des Repos; Staging-Name ohne Verzeichnis.
  @drafter_repo_file "MTP/mtp-gemma-4-26B-A4B-it-Q8_0.gguf"
  @drafter_size 461_766_816

  @doc "Download-URL der gepinnten Revision."
  @spec url() :: String.t()
  def url,
    do:
      "https://huggingface.co/" <>
        @repo <> "/resolve/" <> @revision <> "/" <> Config.model_filename()

  @doc "Download-URL des MTP-Drafters (Ticket #318), dieselbe Revision."
  @spec drafter_url() :: String.t()
  def drafter_url,
    do:
      "https://huggingface.co/" <>
        @repo <> "/resolve/" <> @revision <> "/" <> @drafter_repo_file

  @doc "Größe der gepinnten Datei in Byte."
  @spec size() :: pos_integer()
  def size, do: @size

  @doc "Kurzbeschreibung für die Rückfrage vor dem Download."
  @spec summary() :: [String.t()]
  def summary do
    [
      "Modell      " <> Config.model_filename() <> " (" <> gb(@size) <> ")",
      "Quelle      huggingface.co/" <>
        @repo <> " (Revision " <> String.slice(@revision, 0, 8) <> ")",
      "Lizenz      " <> @license
    ]
  end

  @doc "Kurzbeschreibung des MTP-Drafters für die Rückfrage vor dem Download."
  @spec drafter_summary() :: [String.t()]
  def drafter_summary do
    [
      "Drafter     " <> Config.drafter_filename() <> " (" <> gb(@drafter_size) <> ")",
      "Quelle      huggingface.co/" <>
        @repo <> " (Revision " <> String.slice(@revision, 0, 8) <> ")",
      "Lizenz      " <> @license
    ]
  end

  @doc """
  Vergleicht die vom Server gemeldete Pruefsumme mit dem Pin, ohne die
  Datei zu laden. `:unknown`, wenn der Server keine meldet (dann entscheidet
  die Pruefung nach dem Download).
  """
  @spec remote_matches?(keyword()) :: :ok | :unknown | {:error, String.t()}
  def remote_matches?(opts \\ []) do
    command = Keyword.get(opts, :command, curl())
    expected = Keyword.get(opts, :sha256, Config.expected_gguf_sha256())

    case System.cmd(command, ["-sI", "--max-time", "20", Keyword.get(opts, :url, url())],
           stderr_to_stdout: true
         ) do
      {headers, 0} ->
        case Regex.run(~r/^x-linked-etag:\s*"?([0-9a-f]{64})"?/im, headers) do
          [_, ^expected] ->
            :ok

          [_, other] ->
            {:error, "Quelle meldet eine andere Prüfsumme (" <> other <> "); Pin prüfen"}

          nil ->
            :unknown
        end

      {_out, code} ->
        {:error, "Quelle nicht erreichbar (curl exit " <> to_string(code) <> ")"}
    end
  end

  @doc """
  Pruefsummen-Abgleich fuer den MTP-Drafter (Ticket #318): derselbe Mechanismus
  wie beim Modell, nur mit Drafter-URL und Drafter-Pin.
  """
  @spec drafter_remote_matches?(keyword()) :: :ok | :unknown | {:error, String.t()}
  def drafter_remote_matches?(opts \\ []) do
    remote_matches?(
      Keyword.merge([url: drafter_url(), sha256: Config.expected_drafter_sha256()], opts)
    )
  end

  @doc """
  Laedt das Modell nach `dest` (Default: Staging-Pfad). Setzt einen
  vorhandenen Teil-Download fort, prueft Platz und Pruefsumme und legt die
  Datei erst bei passendem SHA-256 unter `dest` ab.
  """
  @spec download(keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def download(opts \\ []) do
    dest = Keyword.get(opts, :dest, Config.staging_gguf_path())
    part = dest <> ".part"
    size = Keyword.get(opts, :size, @size)
    expected = Keyword.get(opts, :sha256, Config.expected_gguf_sha256())
    File.mkdir_p!(Path.dirname(dest))

    with :ok <- enough_space(Path.dirname(dest), size - current_size(part)),
         :ok <- fetch(Keyword.get(opts, :url, url()), part, Keyword.get(opts, :command, curl())),
         :ok <- verify(part, expected) do
      File.rename!(part, dest)
      {:ok, dest}
    end
  end

  @doc """
  Laedt den MTP-Drafter nach Staging (Ticket #318): dieselbe Kaskade wie
  `download/1` — Platz pruefen, fortsetzbar laden, SHA-256 verifizieren,
  erst dann unter dem Staging-Pfad ablegen.
  """
  @spec drafter_download(keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def drafter_download(opts \\ []) do
    download(
      Keyword.merge(
        [
          dest: Config.staging_drafter_path(),
          size: @drafter_size,
          sha256: Config.expected_drafter_sha256(),
          url: drafter_url()
        ],
        opts
      )
    )
  end

  defp curl, do: Application.get_env(:komki_cli, :curl, @curl)

  defp current_size(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> size
      {:error, _} -> 0
    end
  end

  defp enough_space(dir, missing) do
    case System.cmd("/bin/df", ["-k", dir], stderr_to_stdout: true) do
      {out, 0} ->
        free =
          out |> String.split("\n", trim: true) |> List.last() |> String.split() |> Enum.at(3)

        case Integer.parse(to_string(free)) do
          {kb, _} when kb * 1024 >= missing + @headroom ->
            :ok

          {kb, _} ->
            {:error,
             "zu wenig Platz in " <>
               dir <> ": frei " <> gb(kb * 1024) <> ", nötig etwa " <> gb(missing + @headroom)}

          :error ->
            :ok
        end

      _ ->
        :ok
    end
  end

  # curl: -L Weiterleitungen, -C - fortsetzen, --fail HTTP-Fehler als Exit,
  # --progress-bar auf stderr (erbt das Terminal ueber :nouse_stdio).
  defp fetch(url, part, command) do
    port =
      Port.open({:spawn_executable, command}, [
        :nouse_stdio,
        :exit_status,
        args: ["-L", "--fail", "-C", "-", "--progress-bar", "--retry", "3", "-o", part, url]
      ])

    receive do
      {^port, {:exit_status, 0}} ->
        :ok

      {^port, {:exit_status, code}} ->
        {:error,
         "Download abgebrochen (curl exit " <>
           to_string(code) <> "); erneut starten setzt fort: " <> part}
    end
  end

  defp verify(part, expected) do
    case Steps.sha256(part) do
      {:ok, ^expected} ->
        :ok

      {:ok, actual} ->
        File.rm(part)

        {:error,
         "Prüfsumme passt nicht (" <> actual <> " statt " <> expected <> "); Datei verworfen"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp gb(bytes),
    do:
      (bytes / 1.0e9)
      |> :erlang.float_to_binary(decimals: 1)
      |> String.replace(".", ",")
      |> Kernel.<>(" GB")
end
