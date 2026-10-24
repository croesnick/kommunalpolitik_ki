defmodule KomkiMediator.Room do
  @moduledoc """
  Raum-Zustand: die Einstimmung des Vermittlers auf die Arbeitsumgebung.
  Die Daten stammen aus `room.json` (Schema `"komki-mediator-room/1"`):
  Identitaet, Arbeitsraum, Umfeld, Fakten und die Objektbelegung —
  Objekt-IDs auf Version und Labels abgebildet.

  Optional `workspace_bindings`: B_W fuer Connector-Operationen
  (sortierte Liste, Connector-Vertrag §7). Fehlt das Feld, ist es `nil`,
  und der Raum bietet keine Connector-Operationen an (fail-closed).
  `admit_document` und `ping` nutzen es nicht.
  """

  @schema "komki-mediator-room/1"

  defstruct [
    :dir,
    :identity,
    :workspace_id,
    :environment,
    :facts,
    :objects,
    :documents_dir,
    :workspace_bindings
  ]

  @type t :: %__MODULE__{
          dir: Path.t(),
          identity: String.t(),
          workspace_id: String.t(),
          environment: String.t(),
          facts: %{String.t() => map()},
          objects: %{String.t() => map()},
          documents_dir: Path.t(),
          workspace_bindings: [String.t()] | nil
        }

  # Objektbildung je Toolaufruf: die Basis eines jeden Calls.
  defmodule Object do
    @moduledoc """
    Das aufgerufene Objekt (Objekt-ID, Version, Labels) — die Referenz
    fuer Intent und Snapshot eines Toolaufrufs.
    """

    defstruct [:object_id, :version, :labels]

    @type t :: %__MODULE__{
            object_id: String.t(),
            version: String.t(),
            labels: [String.t()]
          }
  end

  @typedoc "Ladefehler des Raums (POSIX-Grund bei Read, strukturiert bei Parse/Schema)."
  @type load_error ::
          {:room_read, term()}
          | {:room_parse, map()}
          | {:room_schema, map()}

  @doc """
  Laedt `room.json` aus `dir`. Zerlegt fehlerhaftes Parsen oder falsches
  Schema in strukturierte Fehler statt zu crashen: der CLI-Einstieg
  muendet das in eine Zeile JSON auf stderr.
  """
  @spec load(Path.t()) :: {:ok, t()} | {:error, load_error()}
  def load(dir) do
    path = Path.join(dir, "room.json")

    with {:ok, raw} <- read(path),
         {:ok, term} <- parse(raw) do
      validate_shape(dir, term)
    end
  end

  defp read(path) do
    case File.read(path) do
      {:ok, raw} -> {:ok, raw}
      {:error, reason} -> {:error, {:room_read, reason}}
    end
  end

  defp parse(raw) do
    case KomkiPolicy.JSON.parse(raw) do
      {:ok, term} -> {:ok, term}
      {:error, err} -> {:error, {:room_parse, err}}
    end
  end

  # Die Literale-Muster hier sind korrekt; dialyzer stolpert an der
  # vorlaeufigen @specs-Auslegung von KomkiPolicy.JSON.parse (deren
  # json_value-Map-Komponente als leeres %{}) — daher vermerkt.
  @dialyzer {:nowarn_function, validate_shape: 2}
  defp validate_shape(dir, %{"schema" => @schema, "identity" => _} = term) do
    {:ok,
     %__MODULE__{
       dir: dir,
       identity: term["identity"],
       workspace_id: term["workspace_id"],
       environment: term["environment"],
       facts: term["facts"],
       objects: term["objects"],
       documents_dir: Path.join(dir, term["documents_dir"]),
       workspace_bindings: Map.get(term, "workspace_bindings")
     }}
  end

  defp validate_shape(_dir, %{"schema" => other}),
    do: {:error, {:room_schema, %{"expected" => @schema, "got" => other}}}

  defp validate_shape(_dir, term),
    do: {:error, {:room_schema, %{"expected" => @schema, "got" => term}}}

  @doc """
  Objektbildung je Toolaufruf: `"ping"` → das Ping-Objekt,
  `"admit_document"` → das Dokument aus `params["document_id"]`. Ein an
  `room.json` unbekanntes Objekt bleibt ein strukturierter Fehler, nicht
  ein Crash.
  """
  @spec object_for_call(t(), String.t(), %{String.t() => term()}) ::
          {:ok, Object.t()} | {:error, :unknown_object, String.t() | nil}
  def object_for_call(room, "ping", _params), do: entry(room, "mediator-ping")

  def object_for_call(room, "admit_document", params) do
    entry(room, params["document_id"])
  end

  defp entry(room, object_id) do
    case room.objects[object_id] do
      %{"version" => version, "labels" => labels} ->
        {:ok, %Object{object_id: object_id, version: version, labels: labels}}

      _ ->
        {:error, :unknown_object, object_id}
    end
  end

  @doc """
  Loest einen Objekt-Claim aus dem realisierten Payload gegen room.json
  auf: zum Claim eine Objektbelegung (Objekt-ID, Version, Labels).
  """
  @spec object_for_claim(t(), String.t()) ::
          {:ok, Object.t()} | {:error, :unknown_object, String.t()}
  def object_for_claim(room, object_id), do: entry(room, object_id)

  @doc """
  Baut den vollstaendigen komki-Snapshot eines Aufrufs. `workspace.bindings`
  sind GENAU die Objekt-Labels — `checked_label` faellt damit mit den
  Prueflabels zusammen (Bedingung, die `Verify.check` an den Beweis stellt).
  Klassifikation ist fest `"classified"`; die Fakten kommen unveraendert
  aus dem Raum.
  """
  @spec snapshot_for(t(), KomkiMediator.Gamma.t(), Object.t(), String.t()) :: map()
  def snapshot_for(room, gamma, object, digest12) do
    %{
      "schema" => "komki-snapshot/1",
      "snapshot_id" => "snap-" <> digest12,
      "registry_ref" => gamma.registry_id,
      "identity" => room.identity,
      "workspace" => %{
        "workspace_id" => room.workspace_id,
        "bindings" => object.labels,
        "valid" => true,
        "environment" => room.environment
      },
      "object" => %{
        "object_id" => object.object_id,
        "version" => object.version,
        "classification" => "classified",
        "labels" => object.labels
      },
      "facts" => room.facts
    }
  end

  @doc """
  Snapshot eines Connector-Aufrufs (Connector-Vertrag §6): B_W aus
  `workspace_bindings`, Umgebung und Fakten je Gate. Gate 1 (`emit`)
  setzt die Umgebung aus dem Manifest und den Fakt
  `output_content_digest`; Gate 2 (`admit`) nimmt `room.environment` und
  die Raumfakten.
  """
  @spec connector_snapshot(t(), KomkiMediator.Gamma.t(), %{
          snapshot_id: String.t(),
          environment: String.t(),
          object: Object.t(),
          facts: %{String.t() => map()}
        }) :: map()
  def connector_snapshot(room, gamma, spec) do
    %{
      "schema" => "komki-snapshot/1",
      "snapshot_id" => spec.snapshot_id,
      "registry_ref" => gamma.registry_id,
      "identity" => room.identity,
      "workspace" => %{
        "workspace_id" => room.workspace_id,
        "bindings" => room.workspace_bindings,
        "valid" => true,
        "environment" => spec.environment
      },
      "object" => %{
        "object_id" => spec.object.object_id,
        "version" => spec.object.version,
        "classification" => "classified",
        "labels" => spec.object.labels
      },
      "facts" => spec.facts
    }
  end
end
