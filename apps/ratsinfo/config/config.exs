import Config

config :ratsinfo, Ratsinfo.Repo,
  database: Path.join(System.user_home!(), ".local/share/ratsinfo/ratsinfo.db"),
  pool_size: 1

# exqlite baut im Workspace gegen die SQLCipher-Systembibliothek (#435,
# ADR 0004 „Betrieb‟). ratsinfo nutzt die gleiche NIF wie ratsprojekte —
# der Deps-Baum ist geteilt, also gilt derselbe Build hier von selbst.
# force_build verhindert die vorcompilierten cc_precompiler-Artefakte
# (ungepatchtes SQLite), make_env reicht die Variablen an make durch.
# Die brew-Formel kompiliert FTS5 ein — ratsinfos Volltextsuche läuft
# unverändert weiter. Gleicher Block: apps/ratsprojekte, apps/komki_cli.
# Voraussetzungen: docs/prerequisites.md (SQLCipher).
sqlcipher_prefix =
  System.get_env("SQLCIPHER_PREFIX") ||
    case :os.type() do
      {:unix, :darwin} ->
        (System.get_env("HOMEBREW_PREFIX") || "/opt/homebrew") <> "/opt/sqlcipher"

      {:unix, :linux} ->
        "/usr"
    end

config :exqlite,
  force_build: true,
  make_env: %{
    "EXQLITE_USE_SYSTEM" => "1",
    "EXQLITE_SYSTEM_CFLAGS" => "-I#{sqlcipher_prefix}/include/sqlcipher",
    "EXQLITE_SYSTEM_LDFLAGS" => "-L#{sqlcipher_prefix}/lib -lsqlcipher"
  }
