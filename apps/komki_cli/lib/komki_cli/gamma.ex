defmodule KomkiCli.Gamma do
  @moduledoc """
  Γ aus dem Label-Store (Ticket #208): der Store `<base>/registry.db` ist
  die einzige Quelle; `<base>/mediator/registry.json`, aus dem der
  Vermittler entscheidet, ist sein Export.

  `sync/1` laeuft vor jedem Start des Vermittlers: Es importiert die
  Vorlage des Arbeitsraums (`KomkiMediator.Templates.label_store_seed/0`)
  in den Store und schreibt den Export, wenn er sich geaendert hat. Der
  Import ist ein Merge: eigene Bindungen aus `komki label import` bleiben,
  ein identischer Re-Import aendert nichts, eine abweichend registrierte
  Bindung bricht ab (Bindungen sind unveraenderlich, R.2.1). Validiert wird
  ueber `KomkiPolicy.Registry.compile/1` im Export.

  `migrate_outdated_store/1` (Ticket #513) laeuft in `komki up`/`setup`
  vor dem Start: Ein Store, der nur eine fruehere Vorlage enthaelt (keine
  Objekte, keine Entscheidungen, keine eigenen Bindungen), wird durch die
  aktuelle Vorlage ersetzt — mit Sicherung des alten Store und einer Zeile
  in der Ausgabe. Ein Store mit eigenen Inhalten bleibt unberuehrt; dann
  nennt die Sync-Meldung den naechsten Schritt.
  """

  alias KomkiCli.{Config, LabelStore}

  @doc "Pfad des Label-Store der Instanz."
  @spec db_path(Config.t()) :: Path.t()
  def db_path(%Config{base_dir: base}), do: Path.join(base, "registry.db")

  @doc "Pfad der Vermittler-Registry (Export)."
  @spec registry_path(Config.t()) :: Path.t()
  def registry_path(%Config{base_dir: base}), do: Path.join([base, "mediator", "registry.json"])

  @doc """
  Seed importieren, Export schreiben. `:unchanged`, wenn `registry.json`
  schon dem Export entspricht, sonst `:written`.
  """
  @spec sync(Config.t()) :: :unchanged | :written | {:error, String.t()}
  def sync(%Config{} = cfg) do
    db = db_path(cfg)
    path = registry_path(cfg)

    with :ok <- harden_base(cfg),
         {:ok, _counts} <-
           LabelStore.import_registry(db, KomkiMediator.Templates.label_store_seed()),
         {:ok, export} <- LabelStore.export(db),
         {:ok, term} <- parse(export) do
      # Kanonische Form wie die Vorlagen des Vermittlers: so erkennt dessen
      # Migration (SHA-256) den Export der Vorlage als aktuell.
      json = KomkiPolicy.JSON.canonical(term)

      if File.read(path) == {:ok, json} do
        :unchanged
      else
        write_export(path, json)
        :written
      end
    else
      {:error, reason} -> {:error, "Γ aus dem Label-Store: " <> next_step(reason, cfg)}
    end
  end

  # Export und Vermittler-Verzeichnis wie run/ und die Token-Datei
  # haerten (Ticket #485, Fund F13): Der Export traegt Bindungen und
  # Beobachterkreis des Sicherheitsmodells. Bei der Neuanlage steht der
  # Modus VOR dem Inhalt, vorhandene Exporte werden korrigiert.
  defp write_export(path, json) do
    dir = Path.dirname(path)
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)

    unless File.exists?(path) do
      File.write!(path, "")
    end

    File.chmod!(path, 0o600)
    File.write!(path, json)
  end

  # Die Instanzbasis haerten wie mediator/ (Ticket #500, Fund: „consider
  # 0700 for <base>“): Der Store-Unterbau haertet nur Dateien und nie
  # Verzeichnisse — --db ist eine freie Pfadnaht —, deshalb sitzt die
  # Basis-Haertung hier, wo die Instanz gemeint ist. Korrigierend wie
  # write_export: vorhandene 0755-Basen heilen beim naechsten Lauf.
  defp harden_base(%Config{base_dir: base}) do
    case File.chmod(base, 0o700) do
      :ok -> :ok
      # Ohne Basis legt der Import sie an; die naechste Sync haertet sie.
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, "chmod " <> base <> ": " <> Kernel.inspect(reason)}
    end
  end

  # Abweichende Registrierungen (R.2.1) ohne Migrationsweg brauchen den
  # naechsten Schritt in der Meldung (#513) — sonst bleibt nur ein Abbruch
  # ohne Handlungsanweisung. Trifft auch auf Beobachtertypen und Umgebungen
  # zu: dieselbe Unveranderlichkeit, dieselbe Abhilfe.
  defp next_step(reason, %Config{} = cfg) do
    if String.contains?(reason, "unveränderlich") do
      reason <>
        ". Nächster Schritt: " <>
        db_path(cfg) <>
        " beiseitelegen (nicht löschen) und 'komki setup' erneut ausführen; " <>
        "eigene Inhalte bleiben in der beiseitegelegten Datei erhalten"
    else
      reason
    end
  end

  @doc """
  Ersetzt einen Store, der nur eine fruehere Vorlage enthaelt, durch die
  aktuelle (#513). Vorher geprüft: keine Objekte, keine Entscheidungen,
  keine eigenen Bindungen (`LabelStore.template_only?/2`), registry_id wie
  die Vorlage — und der Import der aktuellen Vorlage scheitert am Store
  (Merge-Sonde auf einer Kopie; R.2.1 als Orakel). Ein Store, der der
  aktuellen Vorlage entspricht oder sich nur ergaenzen liesse, bleibt
  unberuehrt. Der alte Store wird gesichert, nie geloescht.
  """
  @spec migrate_outdated_store(Config.t()) :: :ok | {:replaced, Path.t()} | {:error, String.t()}
  def migrate_outdated_store(%Config{} = cfg) do
    db = db_path(cfg)

    if File.exists?(db) do
      seed = KomkiMediator.Templates.label_store_seed()

      with {:ok, true} <- LabelStore.template_only?(db, seed),
           true <- divergent?(db, seed) do
        replace_store(db, seed)
      else
        {:ok, false} -> :ok
        false -> :ok
        {:error, reason} -> {:error, "Γ-Migration: " <> reason}
      end
    else
      :ok
    end
  end

  # Store beiseitelegen (Sicherung, nie loeschen) und aus der aktuellen
  # Vorlage neu anlegen.
  defp replace_store(db, seed) do
    backup = backup_path(db)
    :ok = set_aside(db, backup)

    case LabelStore.import_registry(db, seed) do
      {:ok, _counts} -> {:replaced, backup}
      {:error, reason} -> {:error, "Γ-Migration: " <> reason}
    end
  end

  # Wuerde der Import der aktuellen Vorlage an diesem Store scheitern?
  # Sonde auf einer Kopie: Der echte Import bleibt unangetastet, R.2.1
  # bleibt die Instanz des Vergleichs. Ein identischer Re-Import (No-op)
  # oder ein nur ergaenzender Import braucht keine Migration.
  defp divergent?(db, seed) do
    probe = db <> ".migrationsprobe"
    File.cp!(db, probe)
    File.chmod!(probe, 0o600)

    for suffix <- ["-wal", "-shm", "-journal"],
        companion = db <> suffix,
        File.exists?(companion) do
      File.cp!(companion, probe <> suffix)
      File.chmod!(probe <> suffix, 0o600)
    end

    diverges =
      case LabelStore.import_registry(probe, seed) do
        {:ok, _counts} -> false
        {:error, _reason} -> true
      end

    for suffix <- ["" | ~w(-wal -shm -journal)] do
      _ = File.rm(probe <> suffix)
    end

    diverges
  end

  # Sicherung mit Zeitstempel: eine zweite Migration ueberschreibt nie eine
  # fruehere Sicherung (rename auf vorhandenes Ziel wuerde still ersetzen).
  defp backup_path(db) do
    stamp =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601(:basic)

    db <> ".sicherung-" <> stamp
  end

  # Den alten Store mitsamt Begleitdateien beiseitelegen (rename, nie
  # loeschen) und die Sicherung auf 0600 haerten — sie traegt weiterhin
  # das komplette Sicherheitsmodell (#500).
  defp set_aside(db, backup) do
    :ok = File.rename(db, backup)
    File.chmod!(backup, 0o600)

    for suffix <- ["-wal", "-shm", "-journal"],
        companion = db <> suffix,
        File.exists?(companion) do
      :ok = File.rename(companion, backup <> suffix)
      File.chmod!(backup <> suffix, 0o600)
    end

    :ok
  end

  defp parse(export) do
    case KomkiPolicy.JSON.parse(export) do
      {:ok, term} -> {:ok, term}
      {:error, err} -> {:error, "Export nicht lesbar: " <> inspect(err)}
    end
  end
end
