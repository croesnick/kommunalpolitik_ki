defmodule KomkiCli.LabelStore.ObjectRef do
  @moduledoc """
  Objektreferenz (R.2.1): Objekt-ID und Version bilden ein Paar und reisen
  gemeinsam durch alle Register-Funktionen (`objects`/`decisions` haben
  PRIMARY KEY (object_id, version)). Die CLI nimmt die String-Form OBJ@VER
  entgegen (`parse/1`), Anzeige-/Fehlerformen via String.Chars-Protokoll.
  """

  @enforce_keys [:object_id, :version]
  defstruct [:object_id, :version]

  @type t :: %__MODULE__{object_id: String.t(), version: String.t()}

  @doc """
  Parse der String-Form OBJ@VER. Version ist kebab (z.B. "v42"), NICHT
  numerisch wie bei Bindungs-Versionen (RFC B.3: Objektversionen sind
  kennungsgebunden).
  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, String.t()}
  def parse(ref) when is_binary(ref) do
    case String.split(ref, "@", parts: 2) do
      [object_id, version] -> {:ok, %__MODULE__{object_id: object_id, version: version}}
      _ -> {:error, "Objektreferenz braucht die Form OBJ@VER, got " <> Kernel.inspect(ref)}
    end
  end

  defimpl String.Chars, for: KomkiCli.LabelStore.ObjectRef do
    def to_string(%{object_id: object_id, version: version}), do: object_id <> "@" <> version
  end
end

defmodule KomkiCli.LabelStore do
  @moduledoc """
  SQLite-Registry des Komki-Sicherheitsmodells (Ticket #91): hier leben
  Bindungen, Labels (als Klassifikationsentscheidungen), Objekte,
  Beobachtertypen und der Γ-Export.

  Normative Basis (RFC 0003):

    * R.2.1 — Datenobjekt: Inhalt, Herkunft, Version und
      Klassifikationsentscheidung werden getrennt gespeichert; Objekte sind
      unveraenderlich (neuer Inhalt = neue Objektversion). Labels liegen
      ausserhalb der Schreibhoheit des Agenten: der Default-DB-Pfad liegt am
      Root des Basisverzeichnisses — nicht unter pi-home und nicht
      unter einem Lauf-Scratch, also ausserhalb aller file-write*-Scopes des
      Seatbelt-Profils (deny-default).
    * R.2.2 — Bindung: unveränderliche Kennung mit Version, Bezeichnung,
      Geltungsbereich, verantwortliche Stelle, zulaessiger Empfaengerkreis,
      Operationsbedingungen, Auflagen und Lockerungsbefugnis (ohne Eintrag
      ist keine Lockerung zulaessig). Die Lockerungsbefugnis lebt
      store-seitig als strukturierte Eintraege mit genau den Schluesseln
      {authority, restriction, output} — restriction benennt eine der drei
      R.2.2-Einschraenkungskomponenten (readers, operations, auflagen),
      output eine als Kebab-ID benannte Ausgabe. Der Γ-Export emittiert
      dafuer [] (fail-closed, Ticket #109). Einmal registrierte Inhalte
      sind unveraenderlich (identischer Re-Import = No-op).
    * R.2.5 — Quarantäne: unklassifiziertes Material traegt KEIN reguläres
      Label und wird nicht als leere Bindungsmenge behandelt; die
      Erstklassifikation ist ein menschlicher Akt (decided_by, basis) —
      Entscheiderin ist nur eine Beobachterin vom Typ "person"
      (Store-Zusatzfeld observer_types; eine Verarbeitungsdomaene darf nur
      vorschlagen). Quarantäne-Objekte tragen immer `[]` als Labels — die
      Unterscheidung lebt allein im classification-Feld.
    * Anhang B.3/B.4 — geschlossene, versionierte Schemas; beschränkte
      Policy-Sprache.

  Naht zur Engine (apps/komki_policy/CONTRACT.md, contract-frozen): der
  Import ist `komki-label-store/2` (Obermenge von `komki-registry/2`) und
  wird auf die Engine-Form § 2.1 herabprojiziert und mit
  `KomkiPolicy.Registry.compile/1` geprueft — die Engine ist die einzige
  Schemainstanz (Beobachterraum, B.4-Typen, Kennungsformate); die
  Store-Zusatzfelder (bezeichnung, geltungsbereich, verantwortliche_stelle,
  auflagen, Lockerungsbefugnis-Eintraege, observer_types) prueft dieses
  Modul lokal. Beim Export wird der gebaute Γ-Term (`komki-registry/2`)
  vor der Ausgabe kompiliert (fail-closed; nur bei Store-Korruption
  erreichbar).

  Die `decisions`-Tabelle ist append-only und bildet die Historie der
  Klassifikationsentscheidungen (R.2.1: Entscheidungen bleiben
  nachvollziehbar). Der aktuelle Zustand eines Objekts ist der Eintrag mit
  der hoechsten id. SQLite-Zugriff direkt ueber `Exqlite.Sqlite3` (ohne
  Ecto); der Import laeuft in einer einfachen Transaktion.
  """

  alias Exqlite.Sqlite3
  alias KomkiCli.Config
  alias KomkiCli.LabelStore.ObjectRef
  alias KomkiPolicy.Registry

  @type counts :: %{
          observers: non_neg_integer(),
          fact_fields: non_neg_integer(),
          environments: non_neg_integer(),
          bindings: non_neg_integer()
        }

  @type object_state :: %{
          object: String.t(),
          classification: String.t(),
          labels: [String.t()]
        }

  # Schema steht unten vollständig im Quelltext (Ticket-#91-Vorgabe, 1:1).

  @schema_sql """
  CREATE TABLE IF NOT EXISTS registry_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS observers (id TEXT PRIMARY KEY);
  CREATE TABLE IF NOT EXISTS observer_types (id TEXT PRIMARY KEY, type TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS fact_fields (name TEXT PRIMARY KEY, type TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS environments (
    id TEXT PRIMARY KEY,
    observers TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS bindings (
    id TEXT PRIMARY KEY,
    bezeichnung TEXT NOT NULL,
    geltungsbereich TEXT NOT NULL,
    verantwortliche_stelle TEXT NOT NULL,
    readers TEXT NOT NULL,
    operations TEXT NOT NULL,
    auflagen TEXT NOT NULL,
    relaxation_authorities TEXT NOT NULL,
    registered_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS objects (
    object_id TEXT NOT NULL,
    version TEXT NOT NULL,
    content_ref TEXT NOT NULL,
    origin TEXT NOT NULL,
    PRIMARY KEY (object_id, version)
  );
  CREATE TABLE IF NOT EXISTS decisions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    object_id TEXT NOT NULL,
    version TEXT NOT NULL,
    classification TEXT NOT NULL CHECK (classification IN ('classified','quarantine')),
    labels TEXT NOT NULL,
    decided_by TEXT NOT NULL,
    basis TEXT NOT NULL,
    decided_at TEXT NOT NULL,
    FOREIGN KEY (object_id, version) REFERENCES objects(object_id, version)
  );
  """

  # ========================================================================
  # Öffentliche API
  # ========================================================================

  @doc "Default-Pfad der Registry-DB: <Basis>/registry.db (KOMKI_HOME respektiert)."
  @spec default_path() :: String.t()
  def default_path, do: Path.join(Config.default_base(), "registry.db")

  @doc """
  Registry-Datei (`komki-label-store/2`) in den Store mergen (R.2.1: neue
  Bindungen und Versionen koennen zwischen Entscheidungen registriert
  werden). Einmal registrierter Inhalt ist unveraenderlich:
  kanonisch-identischer Re-Import ist ein No-op, abweichender Inhalt ein
  Fehler. Liefert die Zahl je Tabelle neu eingefuegter Zeilen.
  """
  @spec import_registry(String.t(), term()) :: {:ok, counts()} | {:error, String.t()}
  def import_registry(db_path, term) when is_binary(db_path) do
    with :ok <- validate_import(term) do
      with_conn(db_path, fn conn -> merge(conn, term) end)
    end
  end

  @doc "registry_id aus registry_meta lesen (nil bei uninitialisiertem Store)."
  @spec registry_id(String.t()) :: {:ok, String.t() | nil} | {:error, String.t()}
  def registry_id(db_path) do
    with_conn(db_path, fn conn -> meta_value(conn, "registry_id") end)
  end

  @doc """
  Objekt in Quarantäne (R.2.5): als Eingang eines neuen Materialstands
  (braucht content_ref und origin) oder als Rueckholung eines bestehenden
  Objekts; abweichende Inhaltsangaben sind ein Fehler (neue Inhaltsfassung
  braucht eine neue Objektversion). Quarantäne ist immer auch ein
  Entscheidungsschritt: das Objekt entsteht zusammen mit dem ersten
  decisions-Eintrag; ein Objekt ohne jeden Eintrag existiert nicht.
  """
  @spec quarantine(String.t(), ObjectRef.t(), map()) ::
          {:ok, object_state()} | {:error, String.t()}
  def quarantine(db_path, %ObjectRef{} = ref, opts) when is_binary(db_path) do
    with :ok <- require_object_ref(ref),
         :ok <- require_nonempty(opts.decided_by, "decided_by"),
         :ok <- require_nonempty(opts.basis, "basis") do
      with_conn(db_path, fn conn -> do_quarantine(conn, ref, opts) end)
    end
  end

  @doc """
  Erstklassifikation/Neuklassifikation (R.2.5: menschlicher Akt): haengt
  einen decisions-Eintrag `classified` an. Λ = ∅ ist ein ausdruecklich
  leeres Label (legitimer Engine-Fall, cf. CONTRACT § 8 `case_deny_no_basis`)
  und distinkt zur Quarantäne: die Unterscheidung lebt im classification-
  Feld, nie in den Labels.
  """
  @spec classify(String.t(), ObjectRef.t(), [String.t()], String.t(), String.t()) ::
          {:ok, object_state()} | {:error, String.t()}
  def classify(db_path, %ObjectRef{} = ref, labels, decided_by, basis)
      when is_binary(db_path) and is_list(labels) do
    with :ok <- require_object_ref(ref),
         :ok <- require_nonempty(decided_by, "decided_by"),
         :ok <- require_nonempty(basis, "basis") do
      with_conn(db_path, fn conn ->
        do_classify(conn, ref, labels, decided_by, basis)
      end)
    end
  end

  @doc "Uebersicht: Bindungszusammenfassungen (id, bezeichnung) und Objektstaende."
  @spec list(String.t()) :: {:ok, [map()], [map()]} | {:error, String.t()}
  def list(db_path) do
    with_conn(db_path, fn conn -> do_list(conn) end)
  end

  @doc "Volle Bindungsdefinition (alle R.2.2-Felder)."
  @spec show_binding(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def show_binding(db_path, binding_id) do
    with_conn(db_path, fn conn -> do_show_binding(conn, binding_id) end)
  end

  @doc "Objekt-Metadaten plus Entscheidungshistorie (aktuellster Eintrag zuletzt)."
  @spec show_object(String.t(), ObjectRef.t()) :: {:ok, map()} | {:error, String.t()}
  def show_object(db_path, %ObjectRef{} = ref) do
    with_conn(db_path, fn conn -> do_show_object(conn, ref) end)
  end

  @doc """
  Γ-Export: baut `komki-registry/2` aus dem Store (Mengen sortiert,
  key-deterministisch) und kompiliert den gebauten Term vor der Ausgabe
  (fail-closed). Gleicher Store-Inhalt liefert byte-identische Ausgabe.
  """
  @spec export(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def export(db_path) do
    with_conn(db_path, fn conn ->
      case meta_value(conn, "registry_id") do
        {:ok, nil} ->
          {:error, "Γ-Export: Registry leer (kein Import); erst 'komki label import …'"}

        {:ok, registry_id} ->
          build_export(conn, registry_id)
      end
    end)
  end

  # ========================================================================
  # Import-Validierung (Engine als Schemainstanz + lokale Zusatzpruefung)
  # ========================================================================

  @import_top_fields [
    "schema",
    "registry_id",
    "observers",
    "observer_types",
    "fact_fields",
    "environments",
    "bindings"
  ]

  @nonempty_binding_fields ["bezeichnung", "geltungsbereich", "verantwortliche_stelle"]

  @auflage_fields ["art", "beschreibung", "nachweisart"]

  # Strukturierte Lockerungsbefugnis (R.2.2, Ticket #109, Store-Schicht):
  # Wer (authority) welche Einschränkung (restriction) fuer welche Ausgabe
  # (output) lockern darf. output ist eine regisseurdefinierte kebab-Id
  # und wird bewusst NICHT gegen die Beobachtermenge geprueft.
  @relaxation_entry_fields ["authority", "restriction", "output"]

  @relaxation_restrictions ["readers", "operations", "auflagen"]

  @observer_types ["person", "processing_domain"]

  defp validate_import(term) when is_map(term) do
    with :ok <- require_label_store_schema(term),
         :ok <- closed_top_fields(term),
         {:ok, _compiled} <- validate_engine_projection(term),
         :ok <- validate_observer_types(term) do
      validate_store_bindings(term, term["observers"])
    end
  end

  defp validate_import(other),
    do: {:error, "Import ungueltig: expected an object, got " <> Kernel.inspect(other)}

  defp require_label_store_schema(%{"schema" => "komki-label-store/2"}), do: :ok

  defp require_label_store_schema(%{"schema" => other}),
    do:
      {:error,
       "Import ungueltig: invalid_schema at $.schema (expected \"komki-label-store/2\", got " <>
         Kernel.inspect(other) <> ")"}

  defp require_label_store_schema(_term),
    do: {:error, "Import ungueltig: invalid_schema at $.schema (field \"schema\" fehlt)"}

  defp closed_top_fields(term) do
    unknown = term |> Map.keys() |> Enum.reject(&(&1 in @import_top_fields)) |> Enum.sort()

    case unknown do
      [] ->
        :ok

      [first | _] ->
        {:error,
         "Import ungueltig: unknown_field at $." <>
           first <> " (field not part of the closed schema)"}
    end
  end

  # Die Schluessel-Funktion des Designs (Ticket #91): auf die Engine-Form
  # herabprojizieren und `KomkiPolicy.Registry.compile/1` (CONTRACT.md
  # § 2.1) entscheiden lassen; strukturierte Compile-Fehler
  # (code/path/detail) propagieren.
  defp validate_engine_projection(term) do
    case Registry.compile(engine_projection(term)) do
      {:ok, compiled} ->
        {:ok, compiled}

      {:error, %{code: code, path: path, detail: detail}} ->
        {:error, labeled_engine_error("Import ungueltig", code, path, detail)}
    end
  end

  defp labeled_engine_error(prefix, code, path, detail),
    do: prefix <> ": " <> Kernel.inspect(code) <> " at " <> path <> ": " <> detail

  # Strukturierte Lockerungsbefugnisse sind Store-Schicht; die Engine-Schicht
  # sieht nur [] (fail-closed R.2.2, Granularitaet kann das Γ-Format noch
  # nicht ausdruecken, Ticket #109).
  defp engine_projection(term) do
    %{
      "schema" => "komki-registry/2",
      "registry_id" => term["registry_id"],
      "observers" => term["observers"],
      "fact_fields" => term["fact_fields"],
      "environments" => term["environments"],
      "bindings" =>
        Map.new(term["bindings"], fn {id, binding} ->
          {id,
           %{
             "readers" => binding["readers"],
             "operations" => binding["operations"],
             "relaxation_authorities" => []
           }}
        end)
    }
  end

  # ========================================================================
  # Store-Zusatzfelder (nicht Teil der Engine-Schicht § 2.1)
  # ========================================================================

  @store_binding_fields [
    "bezeichnung",
    "geltungsbereich",
    "verantwortliche_stelle",
    "readers",
    "operations",
    "auflagen",
    "relaxation_authorities"
  ]

  defp validate_store_bindings(term, observers) do
    Enum.reduce_while(Map.to_list(term["bindings"]), :ok, fn {id, spec}, :ok ->
      case validate_store_binding(id, spec, observers) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_store_binding(id, spec, observers) when is_map(spec) do
    with :ok <- closed_store_fields(id, spec),
         :ok <- nonempty_binding_fields(id, spec),
         :ok <- validate_auflagen(id, spec["auflagen"]) do
      validate_relaxation_authorities(id, spec["relaxation_authorities"], observers)
    end
  end

  defp validate_store_binding(id, other, _observers),
    do:
      {:error,
       "Import ungueltig: $.bindings." <>
         id <> " (expected an object, got " <> Kernel.inspect(other) <> ")"}

  # Store-Zusatzfeld observer_types (R.2.5): Typ je Beobachter, nur
  # store-seitig — die Engine-Schicht sieht das Feld nicht.
  defp validate_observer_types(%{"observer_types" => types, "observers" => observers})
       when is_map(types) do
    expected = Enum.sort(observers)
    given = types |> Map.keys() |> Enum.sort()

    case {given -- expected, expected -- given} do
      {[], []} ->
        validate_observer_type_values(types)

      {extra, missing} ->
        {:error,
         "Import ungueltig: $.observer_types (Schluessel muessen exakt der " <>
           "Beobachtermenge entsprechen; zusaetzlich: " <>
           Kernel.inspect(extra) <>
           ", fehlend: " <> Kernel.inspect(missing) <> ")"}
    end
  end

  defp validate_observer_types(other),
    do:
      {:error,
       "Import ungueltig: $.observer_types (erwartet ein Objekt mit einem Typ je Beobachter, got " <>
         Kernel.inspect(other) <> ")"}

  defp validate_observer_type_values(types) do
    Enum.reduce_while(Map.to_list(types), :ok, fn {id, type}, :ok ->
      if type in @observer_types do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          "Import ungueltig: $.observer_types." <>
            id <>
            " (" <>
            ~s(erwartet "person" oder "processing_domain") <>
            ", got " <>
            Kernel.inspect(type) <> ")"}}
      end
    end)
  end

  defp closed_store_fields(id, spec) do
    unknown = spec |> Map.keys() |> Enum.reject(&(&1 in @store_binding_fields)) |> Enum.sort()

    case unknown do
      [] ->
        :ok

      [first | _] ->
        {:error,
         "Import ungueltig: unknown_field at $.bindings." <>
           id <> "." <> first <> " (field not part of the closed schema)"}
    end
  end

  defp nonempty_binding_fields(id, spec) do
    Enum.reduce_while(@nonempty_binding_fields, :ok, fn field, :ok ->
      if nonempty_string?(spec[field]) do
        {:cont, :ok}
      else
        {:halt, nonempty_field_error(id, field, spec[field])}
      end
    end)
  end

  defp nonempty_field_error(id, field, value),
    do:
      "Import ungueltig: $.bindings." <>
        id <>
        "." <>
        field <>
        " (erwartet nichtleeren String, got " <> Kernel.inspect(value) <> ")"

  defp validate_auflagen(_id, auflagen) when is_list(auflagen) do
    Enum.reduce_while(auflagen, :ok, fn auflage, :ok ->
      case validate_auflage(auflage) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_auflagen(_id, other),
    do:
      {:error,
       "Import ungueltig: $.auflagen (expected an array, got " <> Kernel.inspect(other) <> ")"}

  defp validate_auflage(auflage) when is_map(auflage) do
    # String-Klassenvergleich mit sortierten Schluesseln: Map.keys/1
    # liefert interne Reihenfolge — ohne Enum.sort beider Seiten waere der
    # Vergleich reihenfolgeabhaengig.
    closed_keys? =
      Enum.sort(Map.keys(auflage)) == Enum.sort(@auflage_fields)

    values_ok? = closed_keys? and Enum.all?(@auflage_fields, &nonempty_string?(auflage[&1]))

    if values_ok? do
      :ok
    else
      {:error,
       "Import ungueltig: $.auflagen (erwartet Objekte mit genau " <>
         Kernel.inspect(@auflage_fields) <> " und nichtleeren Strings)"}
    end
  end

  defp validate_auflage(other),
    do:
      {:error,
       "Import ungueltig: $.auflagen (erwartet Objekt, got " <> Kernel.inspect(other) <> ")"}

  defp validate_relaxation_authorities(id, authorities, observers) when is_list(authorities) do
    with :ok <- each_relaxation_entry(id, authorities, observers) do
      reject_duplicate_relaxations(id, authorities)
    end
  end

  defp validate_relaxation_authorities(id, other, _observers),
    do:
      {:error,
       "Import ungueltig: $.bindings." <>
         id <>
         ".relaxation_authorities (expected an array, got " <>
         Kernel.inspect(other) <> ")"}

  defp each_relaxation_entry(_id, [], _observers), do: :ok

  defp each_relaxation_entry(id, [entry | rest], observers) do
    with :ok <- validate_relaxation_entry(id, entry, observers) do
      each_relaxation_entry(id, rest, observers)
    end
  end

  defp validate_relaxation_entry(id, entry, observers) when is_map(entry) do
    # String-Klassenvergleich mit sortierten Schluesseln: Map.keys/1
    # liefert interne Reihenfolge — ohne Enum.sort beider Seiten war der
    # Vergleich reihenfolgeabhaengig (Testfund: Schema-Schluessel-Diff).
    closed_keys? =
      Enum.sort(Map.keys(entry)) == Enum.sort(@relaxation_entry_fields)

    strings_ok? =
      closed_keys? and Enum.all?(@relaxation_entry_fields, &nonempty_string?(entry[&1]))

    cond do
      not closed_keys? or not strings_ok? ->
        {:error,
         "Import ungueltig: $.bindings." <>
           id <>
           ".relaxation_authorities (erwartet Objekte mit genau " <>
           Kernel.inspect(@relaxation_entry_fields) <>
           " und nichtleeren Strings, got " <> Kernel.inspect(entry) <> ")"}

      entry["restriction"] not in @relaxation_restrictions ->
        {:error,
         "Import ungueltig: $.bindings." <>
           id <>
           ".relaxation_authorities (restriction erwartet eine aus " <>
           Kernel.inspect(@relaxation_restrictions) <>
           ", got " <> Kernel.inspect(entry["restriction"]) <> ")"}

      not Registry.kebab_id?(entry["authority"]) or not Registry.kebab_id?(entry["output"]) ->
        {:error,
         "Import ungueltig: $.bindings." <>
           id <>
           ".relaxation_authorities (erwartet kebab-Ids, got " <>
           Kernel.inspect(entry) <> ")"}

      entry["authority"] not in observers ->
        {:error,
         "Import ungueltig: $.bindings." <>
           id <>
           ".relaxation_authorities (unbekannter Beobachter: " <>
           entry["authority"] <> "; erst 'komki label import …')"}

      true ->
        :ok
    end
  end

  defp validate_relaxation_entry(id, other, _observers),
    do:
      {:error,
       "Import ungueltig: $.bindings." <>
         id <>
         ".relaxation_authorities (erwartet Objekt, got " <>
         Kernel.inspect(other) <> ")"}

  # Doppelte Eintraege verweigern, nicht stillschweigend vereinzeln.
  defp reject_duplicate_relaxations(id, authorities) do
    uniq = Enum.uniq_by(authorities, &{&1["authority"], &1["restriction"], &1["output"]})

    if length(uniq) == length(authorities) do
      :ok
    else
      {:error,
       "Import ungueltig: $.bindings." <>
         id <>
         ".relaxation_authorities (doppelte Lockerungsbefugnis: " <>
         Kernel.inspect(hd(authorities -- uniq)) <> ")"}
    end
  end

  defp nonempty_string?(value), do: is_binary(value) and value != ""

  # ========================================================================
  # Import-Merge (R.2.1: registrieren zwischen Entscheidungen; Transaktion)
  # ========================================================================

  defp merge(conn, term) do
    :ok = Sqlite3.execute(conn, "BEGIN")

    with {:ok, obs_n} <- merge_observers(conn, term["observers"]),
         :ok <- merge_observer_types(conn, Map.to_list(term["observer_types"])),
         {:ok, ff_n} <- merge_fact_fields(conn, term["fact_fields"]),
         {:ok, env_n} <- merge_environments(conn, term["environments"]),
         {:ok, bind_n} <- merge_bindings(conn, term["bindings"]),
         :ok <-
           put_meta(conn, "registry_id", term["registry_id"]) do
      :ok = Sqlite3.execute(conn, "COMMIT")
      {:ok, %{observers: obs_n, fact_fields: ff_n, environments: env_n, bindings: bind_n}}
    else
      {:error, _reason} = error ->
        # Rollback best-effort: die eigentliche Ursache hat Vorrang.
        _ = Sqlite3.execute(conn, "ROLLBACK")
        error
    end
  end

  defp merge_observers(conn, observers) do
    with {:ok, rows} <- select(conn, "SELECT id FROM observers") do
      insert_each(conn, "INSERT INTO observers (id) VALUES (?)", observers, List.flatten(rows))
    end
  end

  # Beobachtertypen sind unveraenderlich (die Entscheiderfrage R.2.5 darf
  # nachtraeglich nicht umgedeutet werden koennen); identischer Re-Import
  # ist ein No-op.
  defp merge_observer_types(conn, types) do
    Enum.reduce_while(types, :ok, fn {id, type}, :ok ->
      case require_observer_type(conn, id, type) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp require_observer_type(conn, id, type) do
    case fetch_row(conn, "SELECT type FROM observer_types WHERE id = ?", [id]) do
      {:ok, nil} ->
        case insert(conn, "INSERT INTO observer_types (id, type) VALUES (?, ?)", [id, type]) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:ok, [^type]} ->
        :ok

      {:ok, [stored_type]} ->
        {:error,
         "Import ungueltig: Beobachtertyp unveraenderlich: " <>
           id <> " (" <> stored_type <> " != " <> type <> ")"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Einfuege-Schleife: ueberspringt vorhandene Ids, zaehlt nur neue Zeilen.
  defp insert_each(_conn, _sql, [], _existing), do: {:ok, 0}

  defp insert_each(conn, sql, [value | rest], existing) do
    if value in existing do
      insert_each(conn, sql, rest, existing)
    else
      case insert(conn, sql, [value]) do
        :ok -> bump(insert_each(conn, sql, rest, [value | existing]))
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp bump({:ok, n}), do: {:ok, n + 1}
  defp bump({:error, _} = error), do: error

  defp merge_fact_fields(conn, fact_fields) do
    with {:ok, rows} <- select(conn, "SELECT name, type FROM fact_fields") do
      existing = Map.new(rows, fn [name, type] -> {name, type} end)
      merge_fact_entries(conn, existing, Map.to_list(fact_fields), 0)
    end
  end

  defp merge_fact_entries(_conn, _existing, [], count), do: {:ok, count}

  defp merge_fact_entries(conn, existing, [{name, type} | rest], count) do
    case merge_fact_entry(conn, existing, name, type) do
      {:ok, :inserted} -> merge_fact_entries(conn, existing, rest, count + 1)
      {:ok, :noop} -> merge_fact_entries(conn, existing, rest, count)
      {:error, reason} -> {:error, reason}
    end
  end

  defp merge_fact_entry(conn, existing, name, type) do
    case Map.get(existing, name) do
      nil ->
        case insert(conn, "INSERT INTO fact_fields (name, type) VALUES (?, ?)", [name, type]) do
          :ok -> {:ok, :inserted}
          {:error, reason} -> {:error, reason}
        end

      ^type ->
        {:ok, :noop}

      stored_type ->
        {:error,
         "Import ungueltig: fact_field-Konflikt bei " <>
           name <>
           " (" <>
           stored_type <>
           " != " <> type <> ")"}
    end
  end

  # Umgebungen sind unveränderlich (RFC R.3: Umgebungsbeschreibungen sind
  # versioniert; ein neuer Beobachter erscheint nie hinter unveränderter
  # Kennung).
  defp merge_environments(conn, environments) do
    merge_env_entries(conn, Map.to_list(environments), 0)
  end

  defp merge_env_entries(_conn, [], count), do: {:ok, count}

  defp merge_env_entries(conn, [{id, spec} | rest], count) do
    canon = canonical_json(Enum.sort(Enum.uniq(spec["observers"])))

    case merge_env_entry(conn, id, canon) do
      {:ok, :inserted} -> merge_env_entries(conn, rest, count + 1)
      {:ok, :noop} -> merge_env_entries(conn, rest, count)
      {:error, reason} -> {:error, reason}
    end
  end

  defp merge_env_entry(conn, id, canon) do
    case fetch_row(conn, "SELECT observers FROM environments WHERE id = ?", [id]) do
      {:ok, nil} ->
        case insert(conn, "INSERT INTO environments (id, observers) VALUES (?, ?)", [id, canon]) do
          :ok -> {:ok, :inserted}
          {:error, reason} -> {:error, reason}
        end

      {:ok, [^canon]} ->
        {:ok, :noop}

      {:ok, _row} ->
        {:error, "Import ungueltig: Umgebung unveraenderlich: " <> id <> " (Inhalt weicht ab)"}
    end
  end

  defp merge_bindings(conn, bindings) do
    Enum.reduce_while(Map.to_list(bindings), {:ok, 0}, fn {id, spec}, {:ok, n} ->
      case merge_binding(conn, id, spec) do
        {:ok, :inserted} -> {:cont, {:ok, n + 1}}
        {:ok, :noop} -> {:cont, {:ok, n}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @binding_insert_sql """
  INSERT INTO bindings (id, bezeichnung, geltungsbereich, verantwortliche_stelle,
  readers, operations, auflagen, relaxation_authorities, registered_at)
  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  """

  defp merge_binding(conn, id, spec) do
    new_values =
      binding_values(
        spec["bezeichnung"],
        spec["geltungsbereich"],
        spec["verantwortliche_stelle"],
        spec["readers"],
        spec["operations"],
        spec["auflagen"],
        spec["relaxation_authorities"]
      )

    case fetch_row(conn, "SELECT id FROM bindings WHERE id = ?", [id]) do
      {:ok, nil} -> insert_new_binding(conn, id, new_values)
      {:ok, _row} -> compare_binding(conn, id, Tuple.to_list(new_values))
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_new_binding(conn, id, new_values) do
    case insert(conn, @binding_insert_sql, [
           id,
           elem(new_values, 0),
           elem(new_values, 1),
           elem(new_values, 2),
           elem(new_values, 3),
           elem(new_values, 4),
           elem(new_values, 5),
           elem(new_values, 6),
           utc_now()
         ]) do
      :ok -> {:ok, :inserted}
      {:error, reason} -> {:error, reason}
    end
  end

  # Identischer Re-Import = "byte-identical canonical JSON" je Spalte:
  # verglichen wird der 7er-Inhalt (registered_at bleibt beim ersten
  # Import); geschriebene Werte sind kanonisch codiert.
  defp compare_binding(conn, id, new_row) do
    case fetch_row(
           conn,
           "SELECT bezeichnung, geltungsbereich, verantwortliche_stelle, readers,
operations, auflagen, relaxation_authorities FROM bindings WHERE id = ?",
           [id]
         ) do
      {:ok, saved_row} ->
        if new_row == Enum.to_list(saved_row) do
          {:ok, :noop}
        else
          {:error, "Import ungueltig: Bindung unveraenderlich: " <> id <> " (Inhalt weicht ab)"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp binding_values(
         bezeichnung,
         geltungsbereich,
         verantwortliche_stelle,
         readers,
         operations,
         auflagen,
         relaxation_authorities
       ) do
    {
      bezeichnung,
      geltungsbereich,
      verantwortliche_stelle,
      canonical_json(Enum.sort(Enum.uniq(readers))),
      canonical_json(operations),
      canonical_json(auflagen),
      canonical_json(Enum.sort_by(relaxation_authorities, &canonical_json/1))
    }
  end

  # ========================================================================
  # Objekte und Entscheidungen (R.2.1/R.2.5; append-only decisions)
  # ========================================================================

  defp do_quarantine(conn, %ObjectRef{} = ref, opts) do
    with :ok <- require_decider(conn, opts.decided_by) do
      case fetch_row(
             conn,
             "SELECT content_ref, origin FROM objects WHERE object_id = ? AND version = ?",
             [
               ref.object_id,
               ref.version
             ]
           ) do
        {:ok, nil} -> quarantine_new(conn, ref, opts)
        {:ok, row} -> quarantine_existing(conn, ref, opts, row)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp quarantine_new(conn, %ObjectRef{} = ref, opts) do
    content_ref = opts.content_ref
    origin = opts.origin

    if nonempty_string?(content_ref) and nonempty_string?(origin) do
      with :ok <-
             insert(
               conn,
               "INSERT INTO objects (object_id, version, content_ref, origin) VALUES (?, ?, ?, ?)",
               [
                 ref.object_id,
                 ref.version,
                 content_ref,
                 origin
               ]
             ),
           :ok <-
             insert_decision(conn, ref, "quarantine", opts.decided_by, opts.basis, []) do
        {:ok, state(ref, "quarantine", [])}
      end
    else
      {:error, "neues Objekt braucht --content-ref und --origin: " <> Kernel.to_string(ref)}
    end
  end

  defp quarantine_existing(conn, %ObjectRef{} = ref, opts, [stored_content_ref, stored_origin]) do
    mismatch =
      (nonempty_string?(opts.content_ref) and opts.content_ref != stored_content_ref) or
        (nonempty_string?(opts.origin) and opts.origin != stored_origin)

    if mismatch do
      {:error,
       "neue Inhaltsfassung braucht neue Objektversion: " <>
         Kernel.to_string(ref) <> " (Objektinhaltsangabe weicht vom Store ab, R.2.1)"}
    else
      with :ok <-
             insert_decision(conn, ref, "quarantine", opts.decided_by, opts.basis, []) do
        {:ok, state(ref, "quarantine", [])}
      end
    end
  end

  defp do_classify(conn, %ObjectRef{} = ref, labels, decided_by, basis) do
    with :ok <- require_object(conn, ref),
         :ok <- require_decider(conn, decided_by),
         {:ok, stored_labels} <- classify_labels(conn, labels),
         :ok <-
           insert_decision(conn, ref, "classified", decided_by, basis, stored_labels) do
      {:ok, state(ref, "classified", stored_labels)}
    else
      {:error, _} = error -> error
    end
  end

  defp require_object(conn, %ObjectRef{} = ref) do
    case object_exists?(conn, ref.object_id, ref.version) do
      {:ok, true} -> :ok
      {:ok, false} -> {:error, unknown_object_error(Kernel.to_string(ref))}
      {:error, reason} -> {:error, reason}
    end
  end

  defp require_decider(conn, id) do
    case observer_decision_power(conn, id) do
      {:ok, :person} ->
        :ok

      {:ok, :processing_domain} ->
        {:error,
         "R.2.5: nur eine berechtigte Person entscheidet; " <>
           id <> " ist eine Verarbeitungsdomaene und darf nur vorschlagen"}

      {:ok, :untyped} ->
        {:error,
         "R.2.5: ohne Beobachtertyp entscheidet niemand (Store ohne observer_types); " <>
           id <> "; erst 'komki label import …'"}

      {:ok, :unknown} ->
        {:error, unknown_observer_error(id)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # R.2.5: Eine berechtigte Person entscheidet; Verarbeitungsdomänen
  # beobachten nur. Fail-closed: fehlt der Typ (alter Store-Stand), darf
  # niemand entscheiden.
  defp observer_decision_power(conn, id) do
    case fetch_row(conn, "SELECT id FROM observers WHERE id = ?", [id]) do
      {:ok, nil} ->
        {:ok, :unknown}

      {:ok, _row} ->
        case fetch_row(conn, "SELECT type FROM observer_types WHERE id = ?", [id]) do
          {:ok, ["person"]} -> {:ok, :person}
          {:ok, ["processing_domain"]} -> {:ok, :processing_domain}
          {:ok, nil} -> {:ok, :untyped}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Labels sortiert+eindeutig speichern; Doppelangaben sind ein Fehler; jede
  # Bindung muss im Store existieren (R.2.1: unbekannte Bindungskennung ist
  # ebenfalls kein leeres Label-Substitut).
  defp classify_labels(conn, labels) do
    uniq = Enum.uniq(labels)

    if length(uniq) != length(labels) do
      {:error, duplicate_label_error(labels -- uniq)}
    else
      resolve_labels(conn, uniq, [])
    end
  end

  defp resolve_labels(_conn, [], acc), do: {:ok, Enum.sort(acc)}

  defp resolve_labels(conn, [label | rest], acc) do
    case binding_exists?(conn, label) do
      {:ok, true} -> resolve_labels(conn, rest, [label | acc])
      {:ok, false} -> {:error, unknown_binding_error(label)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp duplicate_label_error([value | _]),
    do: "doppelte Bindung: " <> value

  defp unknown_binding_error(id),
    do: "unbekannte Bindung: " <> id <> "; erst 'komki label import …'"

  defp unknown_observer_error(id),
    do: "unbekannter Beobachter: " <> id <> "; erst 'komki label import …'"

  defp unknown_object_error(ref),
    do: "unbekanntes Objekt: " <> ref <> "; erst 'komki label quarantine …'"

  defp state(%ObjectRef{} = ref, classification, labels),
    do: %{object: Kernel.to_string(ref), classification: classification, labels: labels}

  # ========================================================================
  # list / show / export
  # ========================================================================

  defp do_list(conn) do
    with {:ok, binding_rows} <-
           select(conn, "SELECT id, bezeichnung FROM bindings ORDER BY id"),
         {:ok, object_rows} <-
           select(
             conn,
             "SELECT object_id, version, content_ref, origin FROM objects ORDER BY object_id, version"
           ) do
      bindings =
        Enum.map(binding_rows, fn [id, bezeichnung] -> %{id: id, bezeichnung: bezeichnung} end)

      with {:ok, objects} <- list_objects(conn, object_rows, []) do
        {:ok, bindings, objects}
      end
    end
  end

  defp list_objects(_conn, [], acc), do: {:ok, Enum.reverse(acc)}

  defp list_objects(conn, [[id, version, content_ref, origin] | rest], acc) do
    with {:ok, current} <- latest_decision_state(conn, id, version),
         summary <- %{object: id <> "@" <> version, content_ref: content_ref, origin: origin} do
      list_objects(conn, rest, [Map.merge(summary, current) | acc])
    else
      {:error, _} = error -> error
    end
  end

  # Aktueller Zustand = der decisions-Eintrag mit der hoechsten id
  # (append-only Historie, R.2.1).
  defp latest_decision_state(conn, object_id, version) do
    case fetch_row(
           conn,
           "SELECT classification, labels FROM decisions WHERE object_id = ? AND version = ? ORDER BY id DESC LIMIT 1",
           [object_id, version]
         ) do
      {:ok, [classification, labels_json]} ->
        {:ok, %{classification: classification, labels: JSON.decode!(labels_json)}}

      {:ok, nil} ->
        {:ok, %{classification: nil, labels: []}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_show_binding(conn, binding_id) do
    if Registry.reference_id?(binding_id) do
      case fetch_row(
             conn,
             "SELECT id, bezeichnung, geltungsbereich, verantwortliche_stelle, readers,
operations, auflagen, relaxation_authorities, registered_at FROM bindings WHERE id = ?",
             [binding_id]
           ) do
        {:ok,
         [
           id,
           bezeichnung,
           geltungsbereich,
           verantwortliche_stelle,
           readers,
           operations,
           auflagen,
           relaxation_authorities,
           registered_at
         ]} ->
          {:ok,
           %{
             id: id,
             bezeichnung: bezeichnung,
             geltungsbereich: geltungsbereich,
             verantwortliche_stelle: verantwortliche_stelle,
             readers: JSON.decode!(readers),
             operations: JSON.decode!(operations),
             auflagen: JSON.decode!(auflagen),
             relaxation_authorities: JSON.decode!(relaxation_authorities),
             registered_at: registered_at
           }}

        {:ok, nil} ->
          {:error, "unbekannte Bindung: " <> binding_id}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, "ungueltige Bindungskennung (Form <kebab>@<int>): " <> Kernel.inspect(binding_id)}
    end
  end

  defp do_show_object(conn, %ObjectRef{} = ref) do
    with :ok <- require_object_ref(ref),
         {:ok, object} <- object_row(conn, ref) do
      show_object_row(conn, object, ref)
    end
  end

  defp show_object_row(_conn, nil, ref),
    do: {:error, unknown_object_error(Kernel.to_string(ref))}

  defp show_object_row(conn, object, %ObjectRef{} = ref) do
    with {:ok, current} <- latest_decision_state(conn, ref.object_id, ref.version),
         {:ok, decisions} <- decisions_for(conn, ref) do
      {:ok, %{object: Map.merge(object, current), decisions: decisions}}
    end
  end

  defp object_row(conn, %ObjectRef{} = ref) do
    sql =
      "SELECT object_id, version, content_ref, origin FROM objects WHERE object_id = ? AND version = ?"

    case select(conn, sql, [ref.object_id, ref.version]) do
      {:ok, [[_object_id, _version, content_ref, origin]]} ->
        {:ok,
         %{
           object_id: ref.object_id,
           version: ref.version,
           content_ref: content_ref,
           origin: origin
         }}

      {:ok, []} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp object_exists?(conn, object_id, version) do
    case fetch_row(conn, "SELECT object_id FROM objects WHERE object_id = ? AND version = ?", [
           object_id,
           version
         ]) do
      {:ok, nil} -> {:ok, false}
      {:ok, _row} -> {:ok, true}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decisions_for(conn, %ObjectRef{} = ref) do
    case select(
           conn,
           "SELECT id, classification, labels, decided_by, basis, decided_at FROM decisions
WHERE object_id = ? AND version = ? ORDER BY id",
           [ref.object_id, ref.version]
         ) do
      {:ok, rows} ->
        {:ok,
         Enum.map(rows, fn [id, classification, labels, decided_by, basis, decided_at] ->
           %{
             id: id,
             classification: classification,
             labels: JSON.decode!(labels),
             decided_by: decided_by,
             basis: basis,
             decided_at: decided_at
           }
         end)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ========================================================================
  # Γ-Export (komki-registry/2, deterministisch, fail-closed)
  # ========================================================================

  defp build_export(conn, registry_id) do
    with {:ok, observer_rows} <- select(conn, "SELECT id FROM observers"),
         {:ok, fact_rows} <- select(conn, "SELECT name, type FROM fact_fields"),
         {:ok, env_rows} <- select(conn, "SELECT id, observers FROM environments"),
         {:ok, binding_rows} <-
           select(conn, "SELECT id, readers, operations FROM bindings") do
      term = %{
        "schema" => "komki-registry/2",
        "registry_id" => registry_id,
        "observers" => Enum.sort(List.flatten(observer_rows)),
        "fact_fields" => Map.new(fact_rows, fn [name, type] -> {name, type} end),
        "environments" =>
          Map.new(env_rows, fn [id, json] ->
            {id, %{"observers" => JSON.decode!(json)}}
          end),
        "bindings" =>
          Map.new(binding_rows, fn [id, readers, operations] ->
            {id,
             %{
               "readers" => Enum.sort(JSON.decode!(readers)),
               "operations" => JSON.decode!(operations),
               "relaxation_authorities" => []
             }}
          end)
      }

      # Fail-closed: der exportierte Γ wird konsumiert von der Engine, die
      # ihn auch wirklich kompilieren können muss (CONTRACT.md § 2.1). Nur
      # bei Store-Korruption erreichbar.
      case Registry.compile(term) do
        {:ok, _compiled} ->
          {:ok, JSON.encode!(term) <> "\n"}

        {:error, %{code: code, path: path, detail: detail}} ->
          {:error, labeled_engine_error("Γ-Export ungueltig", code, path, detail)}
      end
    end
  end

  # ========================================================================
  # SQLite-Unterbau (Exqlite.Sqlite3 direkt, ohne Ecto)
  # ========================================================================

  # Verbindungskontext: Verzeichnis anlegen (mkdir_p am Elternpfad),
  # Schema sicherstellen, fun ausfuehren, Verbindung schliessen. Jede
  # Oeffnung gilt Tabelle + Foreign-Key-PRAGMA neu (per-Connection).
  defp with_conn(db_path, fun) when is_function(fun, 1) do
    File.mkdir_p!(Path.dirname(db_path))

    case Sqlite3.open(db_path) do
      {:ok, conn} ->
        result =
          try do
            with :ok <- Sqlite3.execute(conn, "PRAGMA foreign_keys = ON"),
                 :ok <- Sqlite3.execute(conn, @schema_sql) do
              fun.(conn)
            else
              {:error, reason} -> {:error, db_error(reason)}
            end
          after
            _ = Sqlite3.close(conn)
          end

        result

      {:error, reason} ->
        {:error, "SQLite open " <> db_path <> ": " <> db_error(reason)}
    end
  end

  # SELECT: prepare + bind + step-Schleife; Statement freigeben.
  defp select(conn, sql, args \\ []) do
    with {:ok, stmt} <- Sqlite3.prepare(conn, sql),
         {:ok, rows} <- bound_rows(conn, stmt, args) do
      _ = Sqlite3.release(conn, stmt)
      {:ok, rows}
    else
      {:error, reason} -> {:error, db_error(reason)}
    end
  end

  # Erste Zeile einer SELECT-Abfrage (oder nil bei leerem Resultset).
  defp fetch_row(conn, sql, args) do
    case select(conn, sql, args) do
      {:ok, [row | _]} -> {:ok, row}
      {:ok, []} -> {:ok, nil}
      {:error, _} = error -> error
    end
  end

  # bind/2 liefert per Spec immer :ok (Arity-Abweichung wirft ArgumentError).
  defp bound_rows(conn, stmt, args) do
    _ = Sqlite3.bind(stmt, args)
    all_rows(conn, stmt, [])
  end

  defp all_rows(conn, stmt, acc) do
    case Sqlite3.step(conn, stmt) do
      :done -> {:ok, Enum.reverse(acc)}
      {:row, row} -> all_rows(conn, stmt, [row | acc])
      :busy -> {:error, "database busy"}
      {:error, reason} -> {:error, reason}
    end
  end

  # INSERT (einzel, parameterisiert).
  defp insert(conn, sql, args) do
    with {:ok, stmt} <- Sqlite3.prepare(conn, sql),
         :ok <- Sqlite3.bind(stmt, args),
         :done <- Sqlite3.step(conn, stmt) do
      _ = Sqlite3.release(conn, stmt)
      :ok
    else
      {:error, reason} -> {:error, db_error(reason)}
      :busy -> {:error, "database busy"}
    end
  end

  defp insert_decision(conn, %ObjectRef{} = ref, classification, decided_by, basis, labels) do
    insert(
      conn,
      "INSERT INTO decisions (object_id, version, classification, labels, decided_by, basis, decided_at)
VALUES (?, ?, ?, ?, ?, ?, ?)",
      [
        ref.object_id,
        ref.version,
        classification,
        canonical_json(labels),
        decided_by,
        basis,
        utc_now()
      ]
    )
  end

  defp binding_exists?(conn, id) do
    case fetch_row(conn, "SELECT id FROM bindings WHERE id = ?", [id]) do
      {:ok, nil} -> {:ok, false}
      {:ok, _row} -> {:ok, true}
      {:error, reason} -> {:error, reason}
    end
  end

  defp meta_value(conn, key) do
    case fetch_row(conn, "SELECT value FROM registry_meta WHERE key = ?", [key]) do
      {:ok, nil} -> {:ok, nil}
      {:ok, [value]} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  # registry_id einmal gesetzt, dann fest (mismatch = registry_id_mismatch).
  defp put_meta(conn, key, value) do
    case meta_value(conn, key) do
      {:ok, nil} ->
        insert(conn, "INSERT INTO registry_meta (key, value) VALUES (?, ?)", [key, value])

      {:ok, stored} when stored == value ->
        :ok

      {:ok, stored} ->
        {:error,
         "Import ungueltig: " <>
           key <>
           "_mismatch (Store: " <>
           Kernel.inspect(stored) <>
           ", Import: " <> Kernel.inspect(value) <> ")"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ========================================================================
  # Kleine Helfer
  # ========================================================================

  defp require_kebab(value, label) do
    if Registry.kebab_id?(value) do
      :ok
    else
      {:error,
       "ungueltige " <> label <> ": " <> Kernel.inspect(value) <> " (kebab-case erwartet)"}
    end
  end

  # Objekt-ID und Version sind getrennte Felder, reisen aber als Paar
  # (ObjectRef); beide muessen die kebab-Form tragen.
  defp require_object_ref(%ObjectRef{} = ref) do
    case require_kebab(ref.object_id, "Objekt-ID") do
      :ok -> require_kebab(ref.version, "Version")
      error -> error
    end
  end

  defp require_nonempty(value, label) do
    if nonempty_string?(value) do
      :ok
    else
      {:error, "--" <> label <> " darf nicht leer sein (Pflichtangabe)"}
    end
  end

  # Kanonisches JSON: Objektschluessel sortiert gespeichert, sodass
  # "byte-identical canonical JSON"-Vergleiche zwischen Import-Kandidat
  # und Store greifen (Engine-Ausdrücke werden inhaltlich unveraender
  # uebernommen).
  defp canonical_json(term) when is_map(term) do
    inner =
      term
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join(",", fn {key, value} ->
        JSON.encode!(key) <> ":" <> canonical_json(value)
      end)

    "{" <> inner <> "}"
  end

  defp canonical_json(term) when is_list(term),
    do: "[" <> Enum.map_join(term, ",", &canonical_json/1) <> "]"

  defp canonical_json(term), do: JSON.encode!(term)

  # ISO8601 UTC (Store-Timestamps; der Policy-Kern selbst ist uhrfrei).
  defp utc_now,
    do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp db_error(reason) when is_binary(reason), do: reason
  defp db_error(reason), do: Kernel.inspect(reason)
end
