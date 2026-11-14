defmodule KomkiCli.DemoVault do
  @moduledoc """
  Der erfundene Test-Vault (Buchloe, fiktiv) eingebaut in komki
  (Ticket #176, `komki setup --demo`). Die Dateien stammen aus
  `apps/komki_connector_vault/priv/test-vault` und werden beim Kompilieren
  eingelesen: So funktioniert `--demo` im Escript und im Release gleich,
  ohne Zugriff auf das Repo.
  """

  @source Path.expand("../../../komki_connector_vault/priv/test-vault", __DIR__)

  # Alle Dateien samt versteckter: `.obsidian/Versteckte Notiz.md` prueft,
  # dass der Connector versteckte Ordner meidet.
  @files (for path <- Path.wildcard(Path.join(@source, "**/*"), match_dot: true),
              File.regular?(path) do
            @external_resource path
            {Path.relative_to(path, @source), File.read!(path)}
          end)

  if @files == [], do: raise("Test-Vault nicht gefunden: " <> @source)

  @doc "Anzahl der eingebauten Notizen (Markdown-Dateien)."
  @spec count() :: pos_integer()
  def count, do: Enum.count(@files, fn {rel, _} -> String.ends_with?(rel, ".md") end)

  @doc """
  Legt den Test-Vault in `dir` an. Verweigert, wenn `dir` schon Dateien
  enthaelt: ein vorhandener Vault wird nie ueberschrieben. Leere Ordner
  zaehlen nicht, etwa der Schreibordner `komki-test`, den komki selbst
  anlegt (Ticket #199).
  """
  @spec install(String.t()) :: {:ok, pos_integer()} | {:error, String.t()}
  def install(dir) do
    if empty?(dir) do
      for {rel, content} <- @files do
        path = Path.join(dir, rel)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, content)
      end

      {:ok, count()}
    else
      {:error, "Vault-Ordner ist nicht leer, Test-Vault nicht angelegt: " <> dir}
    end
  end

  @doc """
  Wahr, wenn `dir` fehlt oder nur leere Ordner enthaelt. Alles andere
  zaehlt als Inhalt, auch Symlinks: ueber einen Link koennte der
  Test-Vault sonst ausserhalb von `dir` landen.
  """
  @spec empty?(String.t()) :: boolean()
  def empty?(dir) do
    entries = Path.wildcard(Path.join(dir, "**"), match_dot: true)
    not Enum.any?(entries, &(File.lstat!(&1).type != :directory))
  end
end
