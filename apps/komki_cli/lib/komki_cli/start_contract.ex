defmodule KomkiCli.StartContract do
  @moduledoc """
  Startvertrag des KomKI-Arbeitsraums (Ticket #92, additiv zu
  `komki-mediator-room/1`).

  Der Vertrag lebt als optionaler Top-Level-Block `contract` in
  `<base>/mediator/room.json`. Das Raum-Schema bleibt unveraendert; der
  Vermittler (`KomkiMediator.Room`) ignoriert unbekannte Top-Level-Keys und
  bleibt unberuehrt.

  ```json
  "contract": {
    "bindings": ["ratsarbeit@1"],
    "auftrag": "Sitzungsvorbereitung fuer den Stadtrat",
    "verantwortliche_person": "nutzende-person",
    "eingangsrechte": ["brief-4711@v1"]
  }
  ```

  Regeln:

    * `bindings` ist B_W: sortiert, eindeutig, jede Bindung existiert in der
      Γ der Label-Registry.
    * `eingangsrechte` sind die erlaubten Objektreferenzen OBJ@VER
      (R.4.1). Sie entscheiden `has_object_access_right` je Objekt.
    * `auftrag` und `verantwortliche_person` sind Pflichtangaben. Der Zweck
      wird NICHT dupliziert: autoritativ ist `facts.purpose` aus der
      Auftragsverwaltung; fehlt er, liefert die Engine `indeterminate`
      (`missing_fact`).

  Fehlt der Block, laeuft eine Session ohne Dateien unveraendert; die
  Dateiaufnahme verweigert mit einer Setup-Remedy, die `room.json` und die
  vier Felder nennt.
  """

  alias KomkiPolicy.{JSON, Registry}

  @room_schema "komki-mediator-room/1"
  @contract_fields ["bindings", "auftrag", "verantwortliche_person", "eingangsrechte"]

  @enforce_keys [:path]
  defstruct [
    :path,
    :room,
    :bindings,
    :auftrag,
    :verantwortliche_person,
    :eingangsrechte,
    :contract_hash,
    :registry_id
  ]

  @type t :: %__MODULE__{
          path: String.t(),
          room: map() | nil,
          bindings: [String.t()] | nil,
          auftrag: String.t() | nil,
          verantwortliche_person: String.t() | nil,
          eingangsrechte: [String.t()] | nil,
          contract_hash: String.t() | nil,
          registry_id: String.t() | nil
        }

  @doc "Default-Pfad der Raumaufstellung: `<base>/mediator/room.json`."
  @spec default_path(String.t()) :: String.t()
  def default_path(base_dir) when is_binary(base_dir) do
    Path.join([base_dir, "mediator", "room.json"])
  end

  @doc """
  Laedt und validiert `room.json`. Ist kein `contract`-Block vorhanden,
  liefert das Ergebnis `contract_hash: nil` (Session ohne Dateien laeuft
  weiter). Strukturfehler am Raum oder am Vertrag sind Fehler.
  """
  @spec load(String.t(), Registry.compiled() | nil) :: {:ok, t()} | {:error, String.t()}
  def load(path, compiled \\ nil) when is_binary(path) do
    with {:ok, raw} <- read(path),
         {:ok, term} <- parse(path, raw),
         {:ok, room} <- validate_room(path, term) do
      case Map.get(term, "contract") do
        nil ->
          {:ok, %__MODULE__{path: path, room: room}}

        %{} = contract ->
          validate_contract(path, room, contract, compiled)

        other ->
          {:error,
           "room.json (" <> path <> "): contract ist kein Objekt (got " <> inspect(other) <> ")"}
      end
    end
  end

  @doc """
  Header-Zeilen des Startvertrags. Ohne Vertrag keine: Das ist der
  Normalfall einer Session ohne Dateien, den Raum zeigt pi selbst
  (#242). Wer Dateien mitbringt, bekommt bei fehlendem Vertrag die
  Anleitung aus `setup_remedy/2`.
  """
  @spec header(t()) :: [String.t()]
  def header(%__MODULE__{contract_hash: nil}), do: []

  def header(%__MODULE__{} = contract) do
    [
      "komki session — Startvertrag (sha256:" <> contract.contract_hash <> ")",
      "room: " <> contract.path <> "  registry: " <> value(contract.registry_id),
      "workspace: " <>
        value(contract.room["workspace_id"]) <>
        "  identity: " <>
        value(contract.room["identity"]) <>
        "  verantwortlich: " <> contract.verantwortliche_person,
      "auftrag: " <> contract.auftrag,
      "zweck: " <> zweck_line(contract.room["facts"]),
      "umgebung: " <> value(contract.room["environment"]),
      "B_W: " <> list_line(contract.bindings),
      "eingangsrechte: " <> list_line(contract.eingangsrechte)
    ]
  end

  @doc """
  Setup-Remedy fuer eine verwiegte Dateiaufnahme ohne nutzbaren Vertrag:
  nennt `room.json` und die vier Pflichtfelder.
  """
  @spec setup_remedy(String.t(), String.t()) :: String.t()
  def setup_remedy(path, reason) do
    "Startvertrag fehlt oder ist ungueltig (" <>
      path <>
      "): " <>
      reason <>
      ". Setup: in room.json den Top-Level-Block \"contract\" mit den vier Feldern " <>
      "bindings, auftrag, verantwortliche_person, eingangsrechte anlegen " <>
      "(bindings = B_W sortiert und eindeutig, eingangsrechte = erlaubte OBJ@VER)."
  end

  @doc """
  Zusaetzliche Pflichten fuer die Dateiaufnahme (fail-closed): ein
  Startvertrag ohne `facts.purpose` oder ohne B_W wird nicht als
  „unlabeled room“ interpretiert, sondern verweigert.
  """
  @spec validate_for_intake(t()) :: :ok | {:error, String.t()}
  def validate_for_intake(%__MODULE__{contract_hash: nil} = contract) do
    {:error, "room.json (" <> contract.path <> "): contract-Block fehlt"}
  end

  def validate_for_intake(%__MODULE__{} = contract) do
    with :ok <- require_purpose(contract) do
      require_intake_bindings(contract)
    end
  end

  defp require_purpose(contract) do
    case contract.room["facts"]["purpose"] do
      %{"value" => _value, "source" => source, "source_kind" => source_kind}
      when is_binary(source) and is_binary(source_kind) ->
        :ok

      _ ->
        {:error,
         "room.json (" <>
           contract.path <>
           "): facts.purpose fehlt oder ist unvollstaendig (Dateiaufnahme braucht den " <>
           "autoritativen Zweck aus der Auftragsverwaltung; R.4.1/D.1)"}
    end
  end

  defp require_intake_bindings(%__MODULE__{bindings: []} = contract) do
    {:error,
     "room.json (" <>
       contract.path <>
       "): contract.bindings ist leer; Dateiaufnahme ohne B_W ist nicht zulaessig " <>
       "(kein unlabeled room, R.5.4)"}
  end

  defp require_intake_bindings(%__MODULE__{bindings: bindings}) when is_list(bindings), do: :ok

  defp require_intake_bindings(_contract), do: {:error, "contract.bindings fehlt"}

  @doc "Ist der Objektbezug in `eingangsrechte` enthalten? (R.4.1)"
  @spec object_allowed?(t(), String.t()) :: boolean()
  def object_allowed?(%__MODULE__{eingangsrechte: rechte}, object_ref) when is_list(rechte) do
    object_ref in rechte
  end

  def object_allowed?(_contract, _object_ref), do: false

  # -------------------------------------------------------------------------
  # Laden / Raum
  # -------------------------------------------------------------------------

  defp read(path) do
    case File.read(path) do
      {:ok, raw} ->
        {:ok, raw}

      {:error, posix} ->
        {:error, "room.json nicht lesbar (" <> path <> "): " <> posix_reason(posix)}
    end
  end

  # Strikte Vorpruefung wie KomkiMediator.Room (KomkiPolicy.JSON): doppelte
  # Schluessel, nachgestellte Kommas und Nicht-JSON werden abgewiesen. Der
  # eigentliche Term kommt aus dem stdlib-Decoder; so bleibt die
  # Dialyzer-Typisierung der geschlossenen Feldmuster erreichbar (die
  # Policy-JSON-Spec typisiert Maps als leeres %{}).
  defp parse(path, raw) do
    case JSON.parse(raw) do
      {:ok, _term} ->
        decode_map(path, raw)

      {:error, err} ->
        {:error, parse_error(path, err)}
    end
  end

  defp decode_map(path, raw) do
    case Elixir.JSON.decode(raw) do
      {:ok, %{} = term} -> {:ok, term}
      {:ok, other} -> {:error, "room.json ist kein Objekt (" <> path <> "): " <> inspect(other)}
      {:error, err} -> {:error, "room.json (" <> path <> "): " <> inspect(err)}
    end
  end

  defp validate_room(path, term) do
    with :ok <- require_room_schema(path, term),
         :ok <- require_room_field(path, term, "identity"),
         :ok <- require_room_field(path, term, "workspace_id"),
         :ok <- require_room_field(path, term, "environment"),
         :ok <- require_room_facts(path, term) do
      {:ok, term}
    end
  end

  defp require_room_schema(_path, %{"schema" => @room_schema}), do: :ok

  defp require_room_schema(path, %{"schema" => other}),
    do:
      {:error,
       "room.json (" <> path <> "): schema " <> inspect(other) <> " statt " <> @room_schema}

  defp require_room_schema(path, _term),
    do: {:error, "room.json (" <> path <> "): schema fehlt (" <> @room_schema <> " erwartet)"}

  defp require_room_field(path, term, field) do
    if nonempty_string?(term[field]) do
      :ok
    else
      {:error, "room.json (" <> path <> "): Feld " <> field <> " fehlt oder ist leer"}
    end
  end

  defp require_room_facts(_path, %{"facts" => facts}) when is_map(facts), do: :ok

  defp require_room_facts(path, _term),
    do: {:error, "room.json (" <> path <> "): Feld facts fehlt oder ist kein Objekt"}

  # -------------------------------------------------------------------------
  # Vertrag
  # -------------------------------------------------------------------------

  defp validate_contract(path, room, contract, compiled) do
    with :ok <- closed_contract_fields(path, contract),
         :ok <- require_nonempty(contract, "auftrag", path),
         :ok <- require_nonempty(contract, "verantwortliche_person", path),
         :ok <- require_known_person(contract["verantwortliche_person"], path, compiled),
         {:ok, bindings} <- validate_bindings(contract["bindings"], path, compiled),
         {:ok, rechte} <- validate_eingangsrechte(contract["eingangsrechte"], path) do
      {:ok,
       %__MODULE__{
         path: path,
         room: room,
         bindings: bindings,
         auftrag: contract["auftrag"],
         verantwortliche_person: contract["verantwortliche_person"],
         eingangsrechte: rechte,
         contract_hash: contract_hash(contract, room, compiled),
         registry_id: compiled && compiled.registry_id
       }}
    end
  end

  # Die verantwortliche Person ist die entscheidende Person fuer die
  # automatische Quarantaene (R.2.5) — sie muss im Beobachterraum der Γ
  # existieren, sonst koennte der Store die Attribution nicht pruefen.
  defp require_known_person(_person, _path, nil), do: :ok

  defp require_known_person(person, path, compiled) do
    if person in compiled.observers do
      :ok
    else
      {:error,
       "room.json (" <>
         path <>
         "): contract.verantwortliche_person " <>
         person <> " ist kein Beobachter der Registry (R.2.5)"}
    end
  end

  defp closed_contract_fields(path, contract) do
    missing = Enum.reject(@contract_fields, &Map.has_key?(contract, &1))
    unknown = contract |> Map.keys() |> Enum.reject(&(&1 in @contract_fields)) |> Enum.sort()

    cond do
      missing != [] ->
        {:error,
         "room.json (" <> path <> "): contract-Felder fehlen: " <> Enum.join(missing, ", ")}

      unknown != [] ->
        {:error,
         "room.json (" <> path <> "): unbekannte contract-Felder: " <> Enum.join(unknown, ", ")}

      true ->
        :ok
    end
  end

  defp require_nonempty(contract, field, path) do
    if nonempty_string?(contract[field]) do
      :ok
    else
      {:error, "room.json (" <> path <> "): contract." <> field <> " fehlt oder ist leer"}
    end
  end

  defp validate_bindings(bindings, path, compiled) when is_list(bindings) do
    cond do
      not Enum.all?(bindings, &is_binary/1) ->
        {:error, "room.json (" <> path <> "): contract.bindings muss Strings enthalten"}

      bindings != Enum.sort(Enum.uniq(bindings)) ->
        {:error,
         "room.json (" <> path <> "): contract.bindings muss sortiert und eindeutig sein (B_W)"}

      compiled == nil ->
        {:ok, bindings}

      true ->
        unknown = Enum.reject(bindings, &Map.has_key?(compiled.bindings, &1))

        case unknown do
          [] ->
            {:ok, bindings}

          [first | _] ->
            {:error,
             "room.json (" <>
               path <> "): contract.bindings verweist auf unbekannte Bindung " <> first}
        end
    end
  end

  defp validate_bindings(_other, path, _compiled),
    do: {:error, "room.json (" <> path <> "): contract.bindings muss eine Liste sein"}

  defp validate_eingangsrechte(rechte, path) when is_list(rechte) do
    cond do
      not Enum.all?(rechte, &object_ref?/1) ->
        {:error,
         "room.json (" <> path <> "): contract.eingangsrechte muss OBJ@VER-Strings enthalten"}

      length(rechte) != length(Enum.uniq(rechte)) ->
        {:error, "room.json (" <> path <> "): contract.eingangsrechte enthaelt Duplikate"}

      true ->
        {:ok, rechte}
    end
  end

  defp validate_eingangsrechte(_other, path),
    do: {:error, "room.json (" <> path <> "): contract.eingangsrechte muss eine Liste sein"}

  defp object_ref?(value) when is_binary(value) do
    case String.split(value, "@", parts: 2) do
      [object_id, version] -> Registry.kebab_id?(object_id) and Registry.kebab_id?(version)
      _ -> false
    end
  end

  # Effektive Vertragsflaeche: der contract-Block bindet nur zusammen mit
  # Identitaet, Raum, Umgebung und der Γ, gegen die entschieden wird.
  defp contract_hash(contract, room, compiled) do
    %{
      "contract" => contract,
      "identity" => room["identity"],
      "workspace_id" => room["workspace_id"],
      "environment" => room["environment"],
      "registry_id" => compiled && compiled.registry_id
    }
    |> JSON.canonical()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  # -------------------------------------------------------------------------
  # Darstellung
  # -------------------------------------------------------------------------

  defp zweck_line(%{"purpose" => %{"value" => value} = purpose}) do
    Kernel.inspect(value) <>
      " (quelle: " <>
      value(purpose["source"]) <> ", " <> value(purpose["source_kind"]) <> ")"
  end

  defp zweck_line(_facts),
    do:
      "fehlt (Engine entscheidet je Bindung; nur purpose-pruefende Bindungen liefern " <>
        "indeterminate/missing_fact; Quelle: auftrags-verwaltung)"

  defp list_line([]), do: "(leer)"
  defp list_line(values) when is_list(values), do: Enum.join(values, ", ")
  defp list_line(_other), do: "(unlesbar)"

  defp value(nil), do: "?"
  defp value(value) when is_binary(value) and value != "", do: value
  defp value(other), do: Kernel.inspect(other)

  defp nonempty_string?(value), do: is_binary(value) and value != ""

  defp posix_reason(posix), do: List.to_string(:file.format_error(posix))

  defp parse_error(path, err),
    do: "room.json (" <> path <> "): ungueltiges JSON: " <> Kernel.inspect(err)
end
