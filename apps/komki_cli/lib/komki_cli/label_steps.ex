defmodule KomkiCli.LabelSteps do
  @moduledoc """
  Befehls-Orchestrierung fuer `komki label …` (Ticket #91, SQLite-Registry
  und Γ-Export; RFC 0003 R.2.1/R.2.2/R.2.5).

  **CLI-Surface-Isolation (API-Vertrag wie `KomkiCli.Steps`):** alle
  menschlichen Ausgaben rendert ausschliesslich `KomkiCli.CLI`. Diese
  Orchestrierung liefert *strukturierte* Resultate.

  Resultatformen:

    * `{:label_imported, counts}` — Merge ok; `counts` trägt je Tabelle
      (`observers`, `fact_fields`, `environments`, `bindings`) die Zahl der
      neu eingefuegten Zeilen.
    * `{:label_quarantine, state}` / `{:label_classify, state}` —
      Entscheidungsschritt ok; `state` = `%{object: "id@ver",
      classification, labels}` (bei Quarantäne immer Labels `[]`, R.2.5).
    * `{:label_list, bindings, objects}` — Uebersicht; leere Abschnitte
      rendert die CLI als "(keine)".
    * `{:label_show_binding, map}` — volle Bindungsdefinition (R.2.2).
    * `{:label_show_object, object, decisions}` — Metadaten + Historie
      (append-only Klassifikationsentscheide, aktuellster zuletzt).
    * `{:label_export, out_path, json}` — Γ-Export (`komki-registry/1`);
      `out_path` nil heisst stdout.
    * `{:error, reason, exit_code}` — Exit 2 (Usage-/Konfig-/DB-/
      Registrierungs-Fehler).
  """

  alias KomkiCli.LabelStore

  @type label_state :: %{
          object: String.t(),
          classification: String.t(),
          labels: [String.t()]
        }

  @type result ::
          {:label_imported,
           %{
             observers: non_neg_integer(),
             fact_fields: non_neg_integer(),
             environments: non_neg_integer(),
             bindings: non_neg_integer()
           }}
          | {:label_quarantine, label_state()}
          | {:label_classify, label_state()}
          | {:label_list, [map()], [map()]}
          | {:label_show_binding, map()}
          | {:label_show_object, map(), [map()]}
          | {:label_export, String.t() | nil, String.t()}
          | {:error, String.t(), non_neg_integer()}

  # ========================================================================
  # Subcommand-Dispatch (CLI parst argv; hier Zustand/Store orchestrieren)
  # ========================================================================

  @doc "Dispatch der `komki label …`-Subcommands (ohne die show-Zweige)."
  @spec label_command(atom(), %{String.t() => term()}) :: result()
  def label_command(:import, opts), do: label_import(opts)
  def label_command(:quarantine, opts), do: label_quarantine(opts)
  def label_command(:classify, opts), do: label_classify(opts)
  def label_command(:list, opts), do: label_list(opts)
  def label_command(:export, opts), do: label_export(opts)

  @doc "Dispatch der `komki label show …`-Subcommands."
  @spec label_show(atom(), %{String.t() => term()}) :: result()
  def label_show(:binding, opts), do: label_show_binding(opts)
  def label_show(:object, opts), do: label_show_object(opts)

  # ========================================================================
  # import / quarantine / classify / list / show / export
  # ========================================================================

  @spec label_import(%{String.t() => term()}) :: result()
  def label_import(opts) do
    db = Map.fetch!(opts, "db")
    path = Map.fetch!(opts, "file")

    with {:ok, term} <- read_store_file(path),
         {:ok, counts} <- LabelStore.import_registry(db, term) do
      {:label_imported, counts}
    else
      {:error, reason} -> {:error, reason, 2}
    end
  rescue
    e -> {:error, "label import fehlgeschlagen: " <> Exception.message(e), 2}
  end

  @spec label_quarantine(%{String.t() => term()}) :: result()
  def label_quarantine(opts) do
    db = Map.fetch!(opts, "db")

    case object_ref(Map.fetch!(opts, "object")) do
      {:ok, object_id, version} ->
        case LabelStore.quarantine(db, object_id, version, %{
               content_ref: Map.get(opts, "content-ref"),
               origin: Map.get(opts, "origin"),
               decided_by: Map.fetch!(opts, "decided-by"),
               basis: Map.fetch!(opts, "basis")
             }) do
          {:ok, state} -> {:label_quarantine, state}
          {:error, reason} -> {:error, reason, 2}
        end

      {:error, reason} ->
        {:error, reason, 2}
    end
  rescue
    e -> {:error, "label quarantine fehlgeschlagen: " <> Exception.message(e), 2}
  end

  @spec label_classify(%{String.t() => term()}) :: result()
  def label_classify(opts) do
    db = Map.fetch!(opts, "db")

    case object_ref(Map.fetch!(opts, "object")) do
      {:ok, object_id, version} ->
        case LabelStore.classify(
               db,
               object_id,
               version,
               Map.get(opts, "label", []),
               Map.fetch!(opts, "decided-by"),
               Map.fetch!(opts, "basis")
             ) do
          {:ok, state} -> {:label_classify, state}
          {:error, reason} -> {:error, reason, 2}
        end

      {:error, reason} ->
        {:error, reason, 2}
    end
  rescue
    e -> {:error, "label classify fehlgeschlagen: " <> Exception.message(e), 2}
  end

  @spec label_list(%{String.t() => term()}) :: result()
  def label_list(opts) do
    db = Map.fetch!(opts, "db")

    case LabelStore.list(db) do
      {:ok, bindings, objects} -> {:label_list, bindings, objects}
      {:error, reason} -> {:error, reason, 2}
    end
  rescue
    e -> {:error, "label list fehlgeschlagen: " <> Exception.message(e), 2}
  end

  @spec label_show_binding(%{String.t() => term()}) :: result()
  def label_show_binding(opts) do
    db = Map.fetch!(opts, "db")
    binding_id = Map.fetch!(opts, "binding")

    case LabelStore.show_binding(db, binding_id) do
      {:ok, binding} -> {:label_show_binding, binding}
      {:error, reason} -> {:error, reason, 2}
    end
  rescue
    e -> {:error, "label show binding fehlgeschlagen: " <> Exception.message(e), 2}
  end

  @spec label_show_object(%{String.t() => term()}) :: result()
  def label_show_object(opts) do
    db = Map.fetch!(opts, "db")

    case object_ref(Map.fetch!(opts, "object")) do
      {:ok, object_id, version} ->
        case LabelStore.show_object(db, object_id, version) do
          {:ok, %{object: object, decisions: decisions}} ->
            {:label_show_object, object, decisions}

          {:error, reason} ->
            {:error, reason, 2}
        end

      {:error, reason} ->
        {:error, reason, 2}
    end
  rescue
    e -> {:error, "label show object fehlgeschlagen: " <> Exception.message(e), 2}
  end

  @spec label_export(%{String.t() => term()}) :: result()
  def label_export(opts) do
    db = Map.fetch!(opts, "db")
    out = Map.get(opts, "out")

    case LabelStore.export(db) do
      {:ok, json} -> write_export(out, json)
      {:error, reason} -> {:error, reason, 2}
    end
  rescue
    e -> {:error, "label export fehlgeschlagen: " <> Exception.message(e), 2}
  end

  defp write_export(nil, json), do: {:label_export, nil, json}

  defp write_export(path, json) do
    File.write!(path, json)
    {:label_export, path, json}
  end

  # ========================================================================
  # Helfer
  # ========================================================================

  defp read_store_file(path) do
    case File.read(path) do
      {:ok, content} ->
        case JSON.decode(content) do
          {:ok, term} ->
            {:ok, term}

          {:error, reason} ->
            {:error,
             "Registry-Datei ungueltiges JSON (" <> path <> "): " <> Kernel.inspect(reason)}
        end

      {:error, posix} ->
        {:error,
         "Registry-Datei nicht lesbar: " <>
           path <> " (" <> List.to_string(:file.format_error(posix)) <> ")"}
    end
  end

  # OBJ@VER: Version ist kebab (z.B. "v42"), NICHT numerisch wie bei
  # Bindungs-Versionen (RFC B.3: Objektversionen sind kennungsgebunden).
  defp object_ref(ref) do
    case String.split(ref, "@", parts: 2) do
      [object_id, version] -> {:ok, object_id, version}
      _ -> {:error, "Objektreferenz braucht die Form OBJ@VER, got " <> Kernel.inspect(ref)}
    end
  end
end
