defmodule KomkiCli.SessionIntake do
  @moduledoc """
  Aufnahme von Dateien in die KomKI-Session (Ticket #92).

  Die Aufnahme ist kein eigener Entscheider: sie baut fuer jede Datei den
  `komki-snapshot/1` und den `komki-intent/1` und stellt die Entscheidung
  ueber `KomkiPolicy.Derive.decide/3`. Die Engine bleibt die einzige
  Instanz fuer Zulaessigkeit und Remedy-Katalog (Single-Sourcing, #115).

  Zwei getrennte Mengen, die nicht verwechselt werden duerfen (R.5.4):

    * `B_W` = `contract.bindings` aus dem Startvertrag (Validierungslabel).
    * `λ(x)` = die Labels des Objekts aus der Label-Registry.

  `has_object_access_right` wird je Objekt aus den `eingangsrechte` des
  Startvertrags gesetzt (`source: "startvertrag"`); ein Objekt ausserhalb
  dieser Rechte ist ein bekannter verbietender Befund
  (`basis_right_false`).

  Nur `permit`-Dateien werden Raumdokumente (Umbau nach #104/#169): Die
  Bytes landen als `<base>/mediator/documents/<objekt>.md` — PDF-Quellen
  als `<objekt>.pdf` (#290, der Dokument-Connector liest sie mit
  Seitenankern und Highlights) —, das Objekt mit Typ `document`, Version
  und λ(x) in `room.json`. Eine Objekt-ID liegt in genau einer Form im
  Raum: Der Connector liest .md zuerst, eine zweite Form derselben ID
  bliebe ungelesen und widerspraeche der eingetragenen Version. pi liest
  sie danach nur ueber `admit_document` und den Dokument-Connector; der
  Vermittler entscheidet jede Aufnahme erneut. Quarantaene-Bytes bleiben
  am Quellort.
  """

  alias KomkiCli.{Config, LabelStore, StartContract}
  alias KomkiCli.LabelStore.ObjectRef
  alias KomkiPolicy.{Derive, Registry}

  @type entry :: %{
          path: String.t(),
          object: String.t(),
          content_ref: String.t(),
          classification: String.t() | nil,
          labels: [String.t()],
          status: String.t(),
          decision: map() | nil,
          checked_label: [String.t()] | nil,
          blockers: [map()] | nil,
          missing_evidence: [map()] | nil,
          remedies: [map()] | nil,
          quarantine_created: boolean(),
          equivalent_cli: String.t() | nil,
          destination: String.t() | nil
        }

  @type intake :: %{
          entries: [entry()],
          staged: [staged()],
          work_dir: String.t(),
          room_path: String.t()
        }

  @type staged :: %{
          source: String.t(),
          destination: String.t(),
          sha256: String.t(),
          object: String.t(),
          labels: [String.t()]
        }

  # ==========================================================================
  # Pfad- und Moduspruefungen (vor dem Doctor; herm-etisch testbar)
  # ==========================================================================

  @doc """
  Kanonisiert die Dateipfade, dedupliziert sie und prueft Existenz,
  Lesbarkeit und verbotene Schreib-/Verwaltungsbereiche. Liefert die
  kanonische Dateiliste in Argumentreihenfolge.
  """
  @spec validate_paths([String.t()], map()) :: {:ok, [String.t()]} | {:error, String.t()}
  def validate_paths(raw_files, context) when is_list(raw_files) and is_map(context) do
    if Enum.all?(raw_files, &is_binary/1) do
      do_validate_paths(raw_files, context)
    else
      {:error, "Dateiliste darf nur Pfad-Strings enthalten: " <> Kernel.inspect(raw_files)}
    end
  end

  def validate_paths(raw_files, _context),
    do: {:error, "Dateiliste erwartet, got " <> Kernel.inspect(raw_files)}

  defp do_validate_paths(raw_files, context) do
    files =
      raw_files
      |> Enum.map(&Config.canonical/1)
      |> Enum.uniq()

    result =
      Enum.reduce_while(files, {:ok, []}, fn path, {:ok, acc} ->
        case validate_path(path, context) do
          :ok -> {:cont, {:ok, [path | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, paths} -> {:ok, Enum.reverse(paths)}
      error -> error
    end
  end

  defp validate_path(path, context) do
    with :ok <- regular_file(path),
         :ok <- readable(path) do
      forbidden_scope(path, context)
    end
  end

  # lstat statt stat: Symlinks werden nicht verfolgt und nicht akzeptiert
  # (sonst liesse sich ein Agenten-Schreibscope ueber einen Symlink
  # umgehen).
  defp regular_file(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular}} ->
        :ok

      {:ok, %File.Stat{type: type}} ->
        {:error, "keine regulaere Datei (" <> type_name(type) <> "): " <> path}

      {:error, posix} ->
        {:error,
         "Datei nicht gefunden oder nicht statbar: " <> path <> " (" <> posix_reason(posix) <> ")"}
    end
  end

  defp readable(path) do
    case File.open(path, [:read]) do
      {:ok, io} ->
        File.close(io)
        :ok

      {:error, posix} ->
        {:error, "Datei nicht lesbar: " <> path <> " (" <> posix_reason(posix) <> ")"}
    end
  end

  # Agenten-Schreibscope und Verwaltungsbereiche: pi-home, mediator,
  # runs sowie die Registry-DB selbst (inklusive SQLite-Begleitdateien).
  # Ein DB-Verzeichnis ist kein pauschaler Sperrbereich: dort koennen
  # legitime Quellen liegen.
  defp forbidden_scope(path, context) do
    base = Config.canonical(Map.fetch!(context, :base_dir))
    pi_home = Config.canonical(Map.fetch!(context, :pi_home))
    db = Config.canonical(Map.fetch!(context, :db))

    cond do
      within?(path, pi_home) ->
        {:error, "Quelle liegt im Agenten-Schreibscope (pi-home): " <> path}

      within?(path, Path.join(base, "mediator")) ->
        {:error, "Quelle liegt im Vermittler-Verzeichnis: " <> path}

      within?(path, Path.join(base, "runs")) ->
        {:error, "Quelle liegt im Lauf-Scratch (runs): " <> path}

      db_artifact?(path, db) ->
        {:error, "Quelle ist die Registry-DB oder eine DB-Begleitdatei: " <> path}

      true ->
        :ok
    end
  end

  defp db_artifact?(path, db) do
    path == db or
      Enum.any?(["-wal", "-shm", "-journal"], fn suffix -> path == db <> suffix end)
  end

  defp within?(path, dir), do: path == dir or String.starts_with?(path, dir <> "/")

  @doc """
  Aufnahme nur bei einem neuen Start: `--continue` plus Dateien ist ein
  Usage-Fehler (Verweis #98).
  """
  @spec guard_new_start([String.t()], map()) :: :ok | {:error, String.t()}
  def guard_new_start([], _opts), do: :ok

  def guard_new_start(_files, opts) do
    if Map.has_key?(opts, "continue") do
      {:error,
       "--continue ist mit Dateiaufnahme nicht erlaubt: Aufnahme nur bei neuem Start (Ticket #98)"}
    else
      :ok
    end
  end

  @doc "Laedt Γ aus dem Store und kompiliert sie (Engine als Schemainstanz)."
  @spec load_registry(String.t()) :: {:ok, Registry.compiled()} | {:error, String.t()}
  def load_registry(db) do
    with {:ok, json} <- LabelStore.export(db),
         {:ok, term} <- decode_export(json),
         {:ok, compiled} <- compile(term) do
      {:ok, compiled}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_export(json) do
    {:ok, JSON.decode!(json)}
  rescue
    e -> {:error, "Γ-Export nicht dekodierbar: " <> Exception.message(e)}
  end

  defp compile(term) do
    case Registry.compile(term) do
      {:ok, compiled} ->
        {:ok, compiled}

      {:error, %{code: code, path: path, detail: detail}} ->
        {:error, engine_error(%{code: code, path: path, detail: detail})}
    end
  end

  # ==========================================================================
  # Aufnahme planen
  # ==========================================================================

  @doc """
  Plant die Aufnahme: Pfadvalidierung, Store-Lookup, ggf. automatische
  Quarantaene, dann Engine-Entscheidung je Datei. Sind alle Dateien
  `permit`, werden Zielpfade und Kollisionen geprueft, aber noch NICHTS
  kopiert; das Staging macht `stage/1` in `Steps.session_start/2` nach der
  Liveness-Pruefung. Sonst bleiben Dokumente und Raum unveraendert und das Ergebnis
  ist `{:refused, entries}`.

  Automatische Quarantaene wird der verantwortlichen Person des
  Startvertrags zugeschrieben (`decided_by`); `--decided-by` kann diese
  Attribution fuer den Intake ueberschreiben. Das ist ein Eingangsschritt,
  keine Klassifikation (R.2.5): die Engine entscheidet danach erneut.
  """
  @spec plan(map()) :: {:ok, intake()} | {:refused, [entry()]} | {:error, String.t()}
  def plan(%{db: db, room: %StartContract{} = contract, compiled: compiled, files: files} = opts)
      when is_list(files) do
    base = Map.fetch!(opts, :base_dir)
    pi_home = Map.get(opts, :pi_home) || Path.join(base, "pi-home")

    with :ok <- StartContract.validate_for_intake(contract),
         {:ok, files} <- validate_paths(files, %{base_dir: base, pi_home: pi_home, db: db}) do
      do_plan(files, db, contract, compiled, base, opts)
    end
  end

  def plan(_opts), do: {:error, "Aufnahme braucht db, room, compiled und eine Dateiliste"}

  defp do_plan(files, db, contract, compiled, base, opts) do
    documents = documents_dir(base)
    File.mkdir_p!(documents)
    decided_by = Map.get(opts, :decided_by) || contract.verantwortliche_person

    with {:ok, resolved} <- resolve_all(files, db, contract, decided_by) do
      case decide_all(resolved, contract, compiled, documents) do
        {:ok, entries} -> finish(entries, documents, contract.path)
        {:refused, entries} -> {:refused, entries}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc "Verzeichnis der Raumdokumente (liest der Dokument-Connector, #169)."
  @spec documents_dir(String.t()) :: String.t()
  def documents_dir(base), do: Path.join([base, "mediator", "documents"])

  @doc """
  Staged die permit-Dateien als Raumdokumente (idempotent; gleiche Bytes
  sind kein Fehler) und traegt sie in `room.json` ein.
  Wird ausschliesslich von `Steps.session_start/2` nach der
  Liveness-Pruefung aufgerufen. Vor dem ersten `File.cp` werden alle Ziele
  vorgeprueft (lstat, kein Symlink, gleiche Bytes); Kopien laufen ueber
  eine Temp-Datei im Zielverzeichnis und ein atomisches Rename.
  """
  @spec stage(%{staged: [staged()], room_path: String.t()}) :: :ok | {:error, String.t()}
  def stage(%{staged: staged, room_path: room_path}) do
    with :ok <- preflight(staged),
         :ok <- stage_all(staged) do
      register_documents(room_path, staged)
    end
  end

  # room.json: je Dokument das Objekt mit Typ, Version und λ(x) (#134); der
  # Vermittler liest den Raum beim (Neu-)Start.
  defp register_documents(room_path, staged) do
    with {:ok, raw} <- File.read(room_path),
         {:ok, room} <- KomkiPolicy.JSON.parse(raw) do
      objects =
        Enum.reduce(staged, Map.get(room, "objects", %{}), fn entry, acc ->
          Map.put(acc, object_id(entry.object), %{
            "type" => "document",
            "version" => version(entry.object),
            "labels" => entry.labels
          })
        end)

      tmp = room_path <> ".tmp"
      File.write!(tmp, KomkiPolicy.JSON.canonical(Map.put(room, "objects", objects)))
      File.rename!(tmp, room_path)
    else
      _ -> {:error, "room.json nicht lesbar: " <> room_path}
    end
  end

  defp stage_all(staged) do
    Enum.reduce_while(staged, :ok, fn entry, :ok ->
      case stage_one(entry) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # ==========================================================================
  # Header
  # ==========================================================================

  @doc "Header-Zeilen der Aufnahme (eine Statuszeile je Datei)."
  @spec header(intake()) :: [String.t()]
  def header(%{entries: entries, work_dir: work_dir}) do
    ["aufnahme:"] ++
      entry_lines(entries) ++
      ["dokumente: " <> work_dir <> " (pi liest sie mit admit_document)"]
  end

  @doc """
  Statuszeilen je Datei (auch fuer die Verweigerung): vier Zeilen pro
  Datei (datei/objekt/status, labels/checked_label, blockers/
  missing_evidence, remedies), bei permit zusaetzlich das Ziel, bei
  automatischer Quarantaene der aequivalente CLI-Befehl.
  """
  @spec entry_lines([entry()]) :: [String.t()]
  def entry_lines(entries), do: Enum.flat_map(entries, &entry_lines_one/1)

  defp entry_lines_one(entry) do
    [
      "  datei: " <>
        entry.path <>
        " -> " <> entry.object <> " " <> entry.status,
      "    labels: " <>
        JSON.encode!(entry.labels) <>
        "  checked_label: " <> JSON.encode!(entry.checked_label || []),
      "    blockers: " <>
        JSON.encode!(entry.blockers) <>
        "  missing_evidence: " <> JSON.encode!(entry.missing_evidence),
      "    remedies: " <> JSON.encode!(entry.remedies)
    ] ++ destination_lines(entry)
  end

  defp destination_lines(%{status: "permit", destination: destination})
       when is_binary(destination),
       do: [
         # document_id ist der Dateiname ohne Endung — .md wie .pdf (#290).
         "    ziel: " <>
           destination <> "  (admit_document " <> Path.rootname(Path.basename(destination)) <> ")"
       ]

  defp destination_lines(%{quarantine_created: true, equivalent_cli: cli}) when is_binary(cli),
    do: ["    quarantaene angelegt; aequivalent: " <> cli]

  defp destination_lines(_entry), do: []

  # ==========================================================================
  # Aufloesung Pfad -> Objekt/Label
  # ==========================================================================

  defp resolve_all(files, db, contract, decided_by) do
    result =
      Enum.reduce_while(files, {:ok, []}, fn path, {:ok, acc} ->
        case resolve(path, db, contract, decided_by) do
          {:ok, info} -> {:cont, {:ok, [info | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, infos} -> {:ok, Enum.reverse(infos)}
      error -> error
    end
  end

  defp resolve(path, db, contract, decided_by) do
    with {:ok, hex} <- sha256(path),
         content_ref = "sha256:" <> hex,
         {:ok, _bindings, objects} <- LabelStore.list(db) do
      case match_objects(objects, path, content_ref) do
        :none ->
          new_quarantine(path, hex, content_ref, objects, db, contract, decided_by)

        {:ok, object} ->
          existing_object(path, content_ref, object)

        {:ambiguous, found} ->
          {:error,
           "Datei " <>
             path <>
             " ist mehrdeutig: " <>
             to_string(length(found)) <>
             " Store-Objekte passen (content_ref oder sha256); keine Aufnahme ohne eindeutige Zuordnung"}

        {:path_without_digest, object} ->
          {:error,
           "Store-Objekt " <>
             object.object <>
             " ist nur unter dem Pfad-content_ref registriert; ohne gespeicherten " <>
             "sha256-Digest ist der Inhalt nicht gebunden. Berechneter Digest: " <>
             content_ref <>
             ". Fix: Objekt mit 'komki label quarantine " <>
             object.object <>
             " --content-ref " <>
             quote_arg(content_ref) <>
             " ...' neu registrieren (neue Objektversion) — R.2.1"}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # B1: Ein Pfad-Match ist KEIN Inhaltsbeleg. Akzeptiert wird nur ein
  # gespeicherter sha256-content_ref, der exakt dem berechneten Digest
  # entspricht. Ein reiner Pfad-Match (Kompatibilitaet #91) verweigert mit
  # Setup-Hinweis, weil die Bytes am Pfad ausgetauscht worden sein koennen.
  defp match_objects(objects, path, content_ref) do
    sha_matches = Enum.filter(objects, &(&1.content_ref == content_ref))
    path_matches = Enum.filter(objects, &(&1.content_ref == path))
    hits = Enum.uniq_by(sha_matches ++ path_matches, & &1.object)

    cond do
      hits == [] -> :none
      length(hits) > 1 -> {:ambiguous, hits}
      sha_matches == [] -> {:path_without_digest, hd(hits)}
      true -> {:ok, hd(hits)}
    end
  end

  defp new_quarantine(path, hex, content_ref, objects, db, contract, decided_by) do
    with {:ok, object_id} <- slug(path),
         :ok <- check_id_collision(objects, object_id, content_ref),
         {:ok, ref} <- ObjectRef.parse(object_id <> "@v1"),
         basis = basis(path, hex),
         origin = "session-intake:" <> contract.room["workspace_id"],
         {:ok, _state} <-
           LabelStore.quarantine(db, ref, %{
             content_ref: content_ref,
             origin: origin,
             decided_by: decided_by,
             basis: basis
           }) do
      {:ok,
       %{
         path: path,
         object: to_string(ref),
         content_ref: content_ref,
         classification: "quarantine",
         labels: [],
         quarantine_created: true,
         equivalent_cli:
           equivalent_cli(object_id <> "@v1", content_ref, origin, decided_by, basis, db)
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp existing_object(path, content_ref, object) do
    classification = object.classification || "quarantine"
    labels = object.labels || []

    {:ok,
     %{
       path: path,
       object: object.object,
       content_ref: content_ref,
       classification: classification,
       labels: labels,
       quarantine_created: false,
       equivalent_cli: nil
     }}
  end

  defp check_id_collision(objects, object_id, content_ref) do
    collision? =
      Enum.any?(objects, fn object ->
        object.object |> String.split("@", parts: 2) |> hd() == object_id and
          object.content_ref != content_ref
      end)

    if collision? do
      {:error,
       "Objekt-ID-Kollision: " <>
         object_id <>
         " existiert bereits mit anderem content_ref; neue Inhaltsfassung braucht eine neue Objektversion (R.2.1)"}
    else
      :ok
    end
  end

  defp slug(path) do
    slug =
      path
      |> Path.basename()
      |> Path.rootname()
      |> String.downcase()
      |> String.replace("ä", "ae")
      |> String.replace("ö", "oe")
      |> String.replace("ü", "ue")
      |> String.replace("ß", "ss")
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")

    case slug do
      "" -> {:error, "aus dem Dateinamen laesst sich keine Objekt-ID bilden: " <> path}
      value -> {:ok, value}
    end
  end

  defp basis(path, hex) do
    "Session-Intake: " <>
      path <>
      " (sha256:" <>
      hex <> "); automatische Quarantaene, Erstklassifikation steht aus (R.2.5)"
  end

  defp equivalent_cli(ref, content_ref, origin, decided_by, basis, db) do
    "komki label quarantine " <>
      ref <>
      " --content-ref " <>
      quote_arg(content_ref) <>
      " --origin " <>
      quote_arg(origin) <>
      " --decided-by " <>
      quote_arg(decided_by) <> " --basis " <> quote_arg(basis) <> " --db " <> quote_arg(db)
  end

  defp quote_arg(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"

  # ==========================================================================
  # Engine-Entscheidung
  # ==========================================================================

  defp decide_all(resolved, contract, compiled, documents) do
    result =
      Enum.reduce_while(resolved, {:ok, []}, fn info, {:ok, acc} ->
        case decide(info, contract, compiled, documents) do
          {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, entries} ->
        entries = Enum.reverse(entries)

        if Enum.all?(entries, &(&1.status == "permit")) do
          {:ok, entries}
        else
          {:refused, entries}
        end

      error ->
        error
    end
  end

  defp decide(info, contract, compiled, documents) do
    case Derive.decide(compiled, snapshot(info, contract, compiled), intent(info, contract)) do
      {:ok, decision} ->
        status = decision["decision"]

        {:ok,
         %{
           path: info.path,
           object: info.object,
           content_ref: info.content_ref,
           classification: info.classification,
           labels: info.labels,
           status: status,
           decision: decision,
           checked_label: decision["checked_label"],
           blockers: decision["blockers"],
           missing_evidence: decision["missing_evidence"],
           remedies: decision["remedies"],
           quarantine_created: info.quarantine_created,
           equivalent_cli: info.equivalent_cli,
           destination: destination(status, info, documents)
         }}

      {:error, err} ->
        {:error, engine_error(err)}

      {:unsupported, info} ->
        {:error, "Engine: unsupported " <> Kernel.inspect(info)}
    end
  end

  # Der Snapshot trennt B_W (workspace.bindings) von λ(x)
  # (object.labels) — genau die R.5.4-Invariante. Identitaet, Umgebung
  # und Fakten kommen aus room.json; has_object_access_right wird
  # autoritativ aus dem Startvertrag gesetzt.
  defp snapshot(info, contract, compiled) do
    room = contract.room
    object_ref = info.object
    digest = digest12(["snapshot", object_ref, info.content_ref, room["workspace_id"]])

    %{
      "schema" => "komki-snapshot/1",
      "snapshot_id" => "snap-intake-" <> digest,
      "registry_ref" => compiled.registry_id,
      "identity" => room["identity"],
      "workspace" => %{
        "workspace_id" => room["workspace_id"],
        "bindings" => contract.bindings,
        "valid" => true,
        "environment" => room["environment"]
      },
      "object" => %{
        "object_id" => object_id(info.object),
        "version" => version(info.object),
        "classification" => info.classification || "quarantine",
        "labels" => info.labels
      },
      "facts" =>
        put_object_access(room["facts"], StartContract.object_allowed?(contract, object_ref))
    }
  end

  defp intent(info, contract) do
    digest = digest12(["intent", info.object, info.content_ref, contract.room["workspace_id"]])

    %{
      "schema" => "komki-intent/1",
      "intent_id" => "intent-intake-" <> digest,
      "operation" => "admit",
      "object" => info.object,
      "workspace" => contract.room["workspace_id"]
    }
  end

  # PDF-Quellen landen mit ihrer Endung (#290); die document_id bleibt die
  # Objekt-ID ohne Endung.
  defp destination("permit", info, documents) do
    suffix = if pdf?(info.path), do: ".pdf", else: ".md"
    Path.join(documents, object_id(info.object) <> suffix)
  end

  defp destination(_status, _info, _documents), do: nil

  defp put_object_access(facts, allowed?) when is_map(facts) do
    Map.put(facts, "has_object_access_right", %{
      "value" => allowed?,
      "source" => "startvertrag",
      "source_kind" => "administered"
    })
  end

  defp put_object_access(_facts, allowed?) do
    %{
      "has_object_access_right" => %{
        "value" => allowed?,
        "source" => "startvertrag",
        "source_kind" => "administered"
      }
    }
  end

  defp object_id(ref), do: ref |> String.split("@", parts: 2) |> hd()
  defp version(ref), do: ref |> String.split("@", parts: 2) |> List.last()

  # ==========================================================================
  # Staging
  # ==========================================================================

  # Planung prueft nur Ziele und Kollisionen; kopiert wird erst in
  # session_start nach Liveness/tmux (S2).
  defp finish(entries, documents, room_path) do
    staged =
      Enum.map(entries, fn entry ->
        %{
          source: entry.path,
          destination: entry.destination,
          sha256: String.replace_prefix(entry.content_ref, "sha256:", ""),
          object: entry.object,
          labels: entry.labels
        }
      end)

    with :ok <- documentable(staged),
         :ok <- unique_destinations(staged),
         :ok <- preflight(staged) do
      {:ok, %{entries: entries, staged: staged, work_dir: documents, room_path: room_path}}
    end
  end

  # Ein Raumdokument ist Text oder PDF (#290): Markdown liest der
  # Dokument-Connector als JSON-String, PDFs rendert er als Text je Seite
  # mit Seitenankern und Highlights. Die Objekt-ID taugt schon als
  # document_id, der Label-Store erzwingt Kebab-Case.
  defp documentable(staged) do
    case Enum.find_value(staged, :ok, fn entry -> unusable(entry) end) do
      :ok -> :ok
      reason -> {:error, reason}
    end
  end

  # nil = brauchbar, sonst der deutsche Fehlertext.
  defp unusable(entry) do
    cond do
      pdf?(entry.source) and not pdf_header?(entry.source) ->
        "kein PDF trotz Endung (%PDF- steht nicht am Dateianfang), als Raumdokument nicht lesbar: " <>
          entry.source

      not pdf?(entry.source) and not String.valid?(File.read!(entry.source)) ->
        "kein UTF-8-Text, als Raumdokument nicht lesbar: " <> entry.source

      true ->
        nil
    end
  end

  # PDF am Dateinamen; der Connector entscheidet die Lesart derselben
  # Objekt-ID danach (.md gewinnt vor .pdf).
  defp pdf?(path), do: path |> Path.extname() |> String.downcase() == ".pdf"

  # %PDF- am Dateianfang (ISO 32000). Bewusst strenger als ex_pdfium, das
  # Bytes vor dem Header verzeiht: Die Aufnahme weist alles schon hier
  # zurueck, was die Lesung im Connector nur scheitern liesse — eine
  # Textdatei, die irgendwo %PDF- erwaehnt, waere sonst ein Pseudo-PDF im
  # Raum (#290). Eine leere Datei liefert :eof aus IO.binread/2.
  defp pdf_header?(path) do
    case File.open(path) do
      {:ok, device} ->
        head = IO.binread(device, 5)
        File.close(device)
        head == "%PDF-"

      {:error, _posix} ->
        false
    end
  end

  # APFS ist case-insensitiv: "Brief.txt" und "brief.txt" kollidieren —
  # und .md wie .pdf derselben Objekt-ID sind zwei Fassungen desselben
  # Raumdokuments, das im Raum nur einmal liegt: verglichen wird darum
  # die Objekt-ID ohne Endung, nicht der volle Zielpfad (#290).
  defp unique_destinations(staged) do
    roots =
      staged
      |> Enum.map(&(&1.destination |> Path.basename() |> Path.rootname() |> String.downcase()))
      |> Enum.sort()

    duplicates = roots -- Enum.uniq(roots)

    if duplicates == [] do
      :ok
    else
      {:error,
       "mehrere Dateien zielen auf dasselbe Raumdokument (case-insensitiv); bitte umbenennen: " <>
         inspect(duplicates)}
    end
  end

  # Eine Objekt-ID liegt im Raum in genau einer Form (.md oder .pdf, #290):
  # Der Connector liest .md zuerst, eine zweite Form bliebe ungelesen und
  # widerspraeche der im Raum eingetragenen Version. Gilt in der Planung
  # wie beim Staging; dieselbe Form mit gleichen Bytes bleibt idempotent
  # (s. preflight_destination/stage_destination).
  defp rendition_conflict(destination) do
    sibling = sibling_rendition(destination)

    if sibling && File.exists?(sibling) do
      {:error,
       "Raumdokument " <>
         Path.rootname(Path.basename(destination)) <>
         " liegt bereits als " <>
         Path.extname(sibling) <>
         " vor (" <>
         sibling <>
         "); der Connector liest nur eine Form je Objekt-ID — alte Fassung entfernen oder unter anderer Objekt-ID aufnehmen"}
    else
      :ok
    end
  end

  defp sibling_rendition(destination) do
    case Path.extname(destination) do
      ".pdf" -> String.replace_suffix(destination, ".pdf", ".md")
      ".md" -> String.replace_suffix(destination, ".md", ".pdf")
      _other -> nil
    end
  end

  # Preflight fuer ALLE Ziele vor dem ersten Kopieren: kein Symlink,
  # keine fremde regulaere Datei, gleiche Bytes sind idempotent.
  defp preflight(staged) do
    Enum.reduce_while(staged, :ok, fn entry, :ok ->
      case preflight_one(entry) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp preflight_one(%{source: source, destination: destination, sha256: expected}) do
    if source == destination do
      verify_source(source, expected)
    else
      with :ok <- rendition_conflict(destination) do
        preflight_destination(destination, expected)
      end
    end
  end

  defp preflight_destination(destination, expected) do
    case File.lstat(destination) do
      {:error, :enoent} ->
        :ok

      {:ok, %File.Stat{type: :symlink}} ->
        {:error,
         "Ziel unter documents ist ein Symlink und wird nicht beschrieben: " <> destination}

      {:ok, %File.Stat{type: :regular}} ->
        verify_existing_destination(destination, expected)

      {:ok, %File.Stat{type: type}} ->
        {:error,
         "Ziel unter documents ist keine regulaere Datei (" <>
           type_name(type) <> "): " <> destination}

      {:error, posix} ->
        {:error,
         "Ziel unter documents nicht pruefbar: " <>
           destination <> " (" <> posix_reason(posix) <> ")"}
    end
  end

  defp verify_source(source, expected) do
    case File.lstat(source) do
      {:ok, %File.Stat{type: :regular}} ->
        verify_source_hash(source, expected)

      {:ok, %File.Stat{type: type}} ->
        {:error, "Quelle ist keine regulaere Datei mehr (" <> type_name(type) <> "): " <> source}

      {:error, posix} ->
        {:error, "Quelle nicht mehr statbar: " <> source <> " (" <> posix_reason(posix) <> ")"}
    end
  end

  defp verify_source_hash(source, expected) do
    case sha256(source) do
      {:ok, ^expected} ->
        :ok

      {:ok, actual} ->
        {:error,
         "Quelle hat sich seit der Planung geaendert: " <>
           source <> " (erwartet sha256:" <> expected <> ", jetzt sha256:" <> actual <> ")"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp verify_existing_destination(destination, expected) do
    case sha256(destination) do
      {:ok, ^expected} ->
        :ok

      {:ok, _actual} ->
        {:error, "Ziel unter documents existiert mit anderen Bytes: " <> destination}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp stage_one(%{source: source, destination: destination, sha256: expected}) do
    if source == destination do
      verify_source(source, expected)
    else
      with :ok <- rendition_conflict(destination) do
        stage_destination(source, destination, expected)
      end
    end
  end

  defp stage_destination(source, destination, expected) do
    case File.lstat(destination) do
      {:ok, %File.Stat{type: :regular}} ->
        verify_existing_destination(destination, expected)

      {:error, :enoent} ->
        copy_via_temp(source, destination, expected)

      {:ok, %File.Stat{type: :symlink}} ->
        {:error,
         "Ziel unter documents ist ein Symlink und wird nicht beschrieben: " <> destination}

      {:ok, %File.Stat{type: type}} ->
        {:error,
         "Ziel unter documents ist keine regulaere Datei (" <>
           type_name(type) <> "): " <> destination}

      {:error, posix} ->
        {:error,
         "Ziel unter documents nicht pruefbar: " <>
           destination <> " (" <> posix_reason(posix) <> ")"}
    end
  end

  defp copy_via_temp(source, destination, expected) do
    with :ok <- verify_source(source, expected) do
      temp = destination <> ".tmp-" <> Integer.to_string(System.unique_integer([:positive]))

      with :ok <- copy_file(source, temp),
           :ok <- verify_temp(temp, expected) do
        move_into_place(temp, destination, expected)
      end
    end
  end

  defp copy_file(source, temp) do
    case File.cp(source, temp) do
      :ok ->
        :ok

      {:error, posix} ->
        _ = File.rm(temp)
        {:error, "Kopieren nach documents fehlgeschlagen: " <> posix_reason(posix)}
    end
  end

  defp verify_temp(temp, expected) do
    case sha256(temp) do
      {:ok, ^expected} ->
        :ok

      {:ok, actual} ->
        _ = File.rm(temp)

        {:error,
         "Temp-Kopie hat falschen Digest (erwartet sha256:" <>
           expected <> ", jetzt sha256:" <> actual <> ")"}

      {:error, reason} ->
        _ = File.rm(temp)
        {:error, reason}
    end
  end

  # Kein blindes Ueberschreiben: zwischen Preflight und Rename kann ein
  # fremder Prozess das Ziel angelegt haben.
  defp move_into_place(temp, destination, expected) do
    case File.lstat(destination) do
      {:error, :enoent} ->
        rename_temp(temp, destination)

      {:ok, %File.Stat{type: :regular}} ->
        _ = File.rm(temp)
        verify_existing_destination(destination, expected)

      {:ok, %File.Stat{type: :symlink}} ->
        _ = File.rm(temp)

        {:error,
         "Ziel unter documents ist ein Symlink und wird nicht beschrieben: " <> destination}

      {:ok, %File.Stat{type: type}} ->
        _ = File.rm(temp)

        {:error,
         "Ziel unter documents ist keine regulaere Datei (" <>
           type_name(type) <> "): " <> destination}

      {:error, posix} ->
        _ = File.rm(temp)

        {:error,
         "Ziel unter documents nicht pruefbar: " <>
           destination <> " (" <> posix_reason(posix) <> ")"}
    end
  end

  defp rename_temp(temp, destination) do
    case File.rename(temp, destination) do
      :ok ->
        :ok

      {:error, posix} ->
        _ = File.rm(temp)
        {:error, "Rename nach documents fehlgeschlagen: " <> posix_reason(posix)}
    end
  end

  # ==========================================================================
  # Helfer
  # ==========================================================================

  @doc false
  @spec sha256(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def sha256(path) do
    digest =
      path
      |> File.stream!(1024 * 1024)
      |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, hash ->
        :crypto.hash_update(hash, chunk)
      end)
      |> :crypto.hash_final()

    {:ok, Base.encode16(digest, case: :lower)}
  rescue
    e -> {:error, "Datei nicht lesbar: " <> path <> " (" <> Exception.message(e) <> ")"}
  end

  defp digest12(parts) do
    parts
    |> Enum.join("|")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end

  defp engine_error(%{code: code, path: path, detail: detail}),
    do: "Engine: " <> Kernel.inspect(code) <> " at " <> path <> ": " <> detail

  defp posix_reason(posix), do: List.to_string(:file.format_error(posix))

  defp type_name(:directory), do: "Verzeichnis"
  defp type_name(:symlink), do: "Symlink"
  defp type_name(other), do: to_string(other)
end
