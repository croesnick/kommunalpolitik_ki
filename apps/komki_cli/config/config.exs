# komki_cli hatte bisher keine Config-Datei — diese existiert für den
# exqlite-Build (#435): Die Label-Registry nutzt exqlite direkt, und der
# Workspace baut exqlite gegen die SQLCipher-Systembibliothek (ADR 0004
# „Betrieb‟, gilt auch für ratsinfo und ratsprojekte). force_build
# verhindert die vorcompilierten cc_precompiler-Artefakte (ungepatchtes
# SQLite), make_env reicht die Variablen an den make-Prozess durch —
# komki selbst nutzt die Datenbank ohne Schlüssel, SQLCipher verhält
# sich dann wie normales SQLite. Konsequenz für das Homebrew-Paket: Die
# gepackte exqlite-NIF verlinkt libsqlcipher.dylib, die Formel hängt
# sqlcipher als Abhängigkeit ein. Voraussetzungen: docs/prerequisites.md.
import Config

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
