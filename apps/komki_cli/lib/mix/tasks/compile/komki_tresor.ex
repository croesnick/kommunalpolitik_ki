defmodule Mix.Tasks.Compile.KomkiTresor do
  @shortdoc "Baut komki-tresor (Swift) nach priv/"
  @moduledoc """
  Baut das Secure-Enclave-Hilfsprogramm beim `mix compile` (Ticket #224):
  `swiftc -O native/komki-tresor/main.swift -> priv/komki-tresor`. Ziel ist
  der Quellbaum (`apps/komki_cli/priv`), damit `make komki` es
  MIX_ENV-unabhaengig neben das Escript kopieren kann; `make komki-tresor`
  bewacht das Ergebnis (lauter Fehler, wenn swiftc fehlt).

  Ohne macOS oder swiftc: Info statt Fehler — Linux-CI und Escript-Bau
  laufen weiter, komki meldet `:missing_bin`, wenn das Programm fehlt.
  Mtime-idempotent: ein frisches Ziel baut nicht neu und meldet `:noop`.
  `mix clean` entfernt das gebaute Programm wieder.
  """

  use Mix.Task.Compiler

  @impl true
  def run(_args) do
    if match?({:unix, :darwin}, :os.type()), do: build(), else: skip("kein macOS")
  end

  @impl true
  def clean, do: File.rm(target())

  defp build do
    source = Path.join(root(), "native/komki-tresor/main.swift")
    target = target()

    if fresh?(source, target) do
      {:noop, []}
    else
      kompilieren(source, target)
    end
  end

  defp root, do: Path.dirname(Mix.Project.project_file())
  defp target, do: Path.join(root(), "priv/komki-tresor")

  defp kompilieren(source, target) do
    case System.find_executable("swiftc") do
      nil -> skip("swiftc fehlt (xcode-select --install)")
      swiftc -> swiftc_bauen(swiftc, source, target)
    end
  end

  defp swiftc_bauen(swiftc, source, target) do
    File.mkdir_p!(Path.dirname(target))
    # Eindeutiger Name: Gleichzeitige Laeufe (etwa dev und test) teilen sich
    # keine Datei; das Gitignore-Muster komki-tresor* deckt ihn ab.
    tmp = target <> "." <> Integer.to_string(System.unique_integer([:positive])) <> ".tmp"

    case System.cmd(swiftc, ["-O", "-o", tmp, source], stderr_to_stdout: true) do
      {_, 0} ->
        # Atomar ersetzen: Ein abgebrochener Bau hinterlaesst kein halbfertiges
        # Ziel, das der Mtime-Vergleich spaeter fuer frisch haelt.
        File.rename!(tmp, target)
        {:ok, []}

      {out, _} ->
        File.rm(tmp)
        Mix.raise("swiftc für komki-tresor fehlgeschlagen:\n" <> out)
    end
  end

  # Ziel gilt als frisch, wenn es existiert und nicht aelter ist als die
  # Quelle. mtime ist ein Kalender-Tupel; Tupel vergleichen sich chronologisch.
  defp fresh?(source, target) do
    with {:ok, s} <- File.stat(source),
         {:ok, t} <- File.stat(target) do
      t.mtime >= s.mtime
    else
      _ -> false
    end
  end

  defp skip(reason) do
    Mix.shell().info("komki-tresor: #{reason} — Bau übersprungen")
    {:noop, []}
  end
end
