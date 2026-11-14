defmodule KomkiPolicy.Release do
  @moduledoc """
  Freigabe-Datensatz `komki-release/2` (CONTRACT.md § 2.6): eine
  Aktionsfreigabe oder — seit #423 — eine Offenlegungsfreigabe.

  Geschlossene Schema-Validierung plus die verbindliche Call-Hash-Formel
  (R.6.2): ein GO autorisiert ein Ereignis, nicht nur einen Text — die
  Bindung an den exakten Call geschieht ausschließlich über den
  call hash, neu berechnet aus (Inhaltsreferenz, Objekt, Operation,
  Workspace). Kein separater Referenzvergleich; ein abweichender Call
  fällt durch den Hash-Abgleich auf.

  Neu in `komki-release/2` (Ticket #423): eine Offenlegungsfreigabe
  nennt zusätzlich die Ausgabeart und das Ziellabel der Lockerung
  (R.6.1, R.6.2 — Ausgangs- und Ziellabel): `ausgabeart` aus dem
  geschlossenen Vokabular (§ 2.1) und `ziellabel` als sortierte,
  eindeutige Liste existierender Bindungen. Beide Felder sind für
  `kind: offenlegungsfreigabe` Pflicht und für
  `kind: aktionsfreigabe` verboten (eine Aktionsfreigabe lockert keine
  Bindung, § 4.6). `komki-release/1` bleibt für Aktionsfreigaben
  unverändert gültig; das Ziellabel einer Aktionsfreigabe ist immer
  `[]`.

  Die Validierung ist rein und umfasst die geschlossene Feldmenge, die
  `kind`-Menge (`aktionsfreigabe` | `offenlegungsfreigabe`; unbekannte
  Werte sind Eingabefehler), die Operation (unbekannte Werte Eingabefehler;
  entscheidbar sind `emit`, `store` und `transfer` erst im Freigabe-Zweig,
  CONTRACT § 4.6 und § 4.9), Hex-Digest-Formate und das
  Frische-Fenster `valid_from <= valid_until` (logische Ganzzahlen —
  die Engine hat keine Uhr, § 1; die Prüfung gegen `as_of` geschieht im
  Freigabe-Zweig, nicht hier).
  """

  alias KomkiPolicy.{JSON, Registry, Validations}

  @fields [
    "schema",
    "release_id",
    "kind",
    "operation",
    "object",
    "workspace",
    "content_digest",
    "call_hash",
    "scope",
    "authority",
    "valid_from",
    "valid_until",
    "nonce"
  ]
  @offenlegung_fields ["ausgabeart", "ziellabel"]
  @kinds ["aktionsfreigabe", "offenlegungsfreigabe"]
  @known_operations ["start", "admit", "emit", "transfer", "store"]

  @type t() :: %{
          required(:release_id) => String.t(),
          required(:kind) => String.t(),
          required(:operation) => String.t(),
          required(:object) => String.t(),
          required(:workspace) => String.t(),
          required(:content_digest) => String.t(),
          required(:call_hash) => String.t(),
          required(:scope) => String.t(),
          required(:authority) => String.t(),
          required(:valid_from) => integer(),
          required(:valid_until) => integer(),
          required(:nonce) => String.t(),
          optional(:ausgabeart) => String.t(),
          optional(:ziellabel) => [String.t()]
        }

  @type error() :: %{
          required(:code) => atom(),
          required(:path) => String.t(),
          required(:detail) => String.t()
        }

  @doc """
  Validiert einen geparsten Release-Term (§ 2.6) und liefert die
  kompilierte Auth-Map für den Freigabe-Zweig.
  """
  @spec validate(term()) :: {:ok, t()} | {:error, error()}
  def validate(term) do
    case validate_reason(term) do
      {:ok, release} -> {:ok, release}
      {:error, {code, path, detail}} -> {:error, %{code: code, path: path, detail: detail}}
    end
  end

  @doc """
  Verbindliche Call-Hash-Formel (§ 2.6):
  `sha256(JSON.canonical({"content_digest", "object", "operation", "workspace"}))`
  als Hex kleingeschrieben — `JSON.canonical/1` liefert byte-stabil genau
  ein finales Newline, das Teil des Hash-Eingabe-Bytes ist.
  """
  @spec call_hash(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def call_hash(content_digest, object_ref, operation, workspace) do
    payload =
      JSON.canonical(%{
        "content_digest" => content_digest,
        "object" => object_ref,
        "operation" => operation,
        "workspace" => workspace
      })

    Base.encode16(:crypto.hash(:sha256, payload), case: :lower)
  end

  defp validate_reason(term) do
    # Schema je Art (§ 2.6): komki-release/1 ist die Aktionsfreigabe,
    # komki-release/2 die Offenlegungsfreigabe mit ausgabeart und
    # ziellabel. Die Schema-Kennung muss zur Art passen.
    schema =
      case term do
        %{"kind" => "offenlegungsfreigabe"} -> "komki-release/2"
        _ -> "komki-release/1"
      end

    with {:ok, _} <- Validations.require_map(term, "$"),
         :ok <- Validations.require_schema(term, schema, :missing_field),
         :ok <- closed_fields_for_kind(term),
         :ok <- Validations.require_kebab(term["release_id"], "$.release_id"),
         :ok <- require_kind(term["kind"]),
         :ok <- Validations.require_operation(term["operation"], @known_operations),
         :ok <- Validations.require_object_ref(term["object"], "$.object"),
         :ok <- Validations.require_kebab(term["workspace"], "$.workspace"),
         :ok <-
           Validations.require_hex64(term["content_digest"], "$.content_digest", :invalid_digest),
         :ok <- Validations.require_hex64(term["call_hash"], "$.call_hash", :invalid_digest),
         :ok <- Validations.require_kebab(term["scope"], "$.scope"),
         :ok <- Validations.require_kebab(term["authority"], "$.authority"),
         :ok <- require_window(term),
         :ok <- Validations.require_kebab(term["nonce"], "$.nonce"),
         {:ok, offenlegung} <- require_offenlegung_fields(term) do
      {:ok,
       Map.merge(
         %{
           release_id: term["release_id"],
           kind: term["kind"],
           operation: term["operation"],
           object: term["object"],
           workspace: term["workspace"],
           content_digest: term["content_digest"],
           call_hash: term["call_hash"],
           scope: term["scope"],
           authority: term["authority"],
           valid_from: term["valid_from"],
           valid_until: term["valid_until"],
           nonce: term["nonce"]
         },
         offenlegung
       )}
    end
  end

  # Feldmenge je Art: eine Aktionsfreigabe bleibt beim geschlossenen
  # Satz von komki-release/1; eine Offenlegungsfreigabe (komki-release/2)
  # traegt zusaetzlich ausgabeart und ziellabel, beide Pflicht (§ 2.6).
  defp closed_fields_for_kind(%{"kind" => "offenlegungsfreigabe"} = term) do
    Validations.closed_fields(term, @fields ++ @offenlegung_fields, "$")
  end

  defp closed_fields_for_kind(term), do: Validations.closed_fields(term, @fields, "$")

  # Pflichtfelder der Offenlegungsfreigabe: ausgabeart aus dem
  # geschlossenen Vokabular (§ 2.1), ziellabel sortiert, eindeutig, als
  # Bindungsreferenzen. Die Existenz der Bindungen prueft der
  # Offenlegungsfreigabe-Zweig gegen die konkrete Registry (§ 4.9);
  # hier bleibt die Form geschlossen.
  defp require_offenlegung_fields(%{"kind" => "offenlegungsfreigabe"} = term) do
    with :ok <- require_ausgabeart(term["ausgabeart"]),
         {:ok, ziellabel} <- require_ziellabel(term["ziellabel"]) do
      {:ok, %{ausgabeart: term["ausgabeart"], ziellabel: ziellabel}}
    end
  end

  defp require_offenlegung_fields(%{"kind" => "aktionsfreigabe"}) do
    {:ok, %{ausgabeart: nil, ziellabel: []}}
  end

  defp require_offenlegung_fields(%{"kind" => kind}) do
    {:error,
     {:invalid_kind, "$.kind", "expected one of " <> inspect(@kinds) <> ", got " <> inspect(kind)}}
  end

  defp require_ausgabeart(nil),
    do: {:error, {:missing_field, "$.ausgabeart", "offenlegungsfreigabe requires ausgabeart"}}

  defp require_ausgabeart(value) when is_binary(value) do
    if value in Registry.output_kinds() do
      :ok
    else
      {:error,
       {:invalid_output_kind, "$.ausgabeart",
        "expected one of " <> inspect(Registry.output_kinds()) <> ", got " <> inspect(value)}}
    end
  end

  defp require_ausgabeart(value),
    do:
      {:error,
       {:invalid_output_kind, "$.ausgabeart", "expected a kebab id, got " <> inspect(value)}}

  defp require_ziellabel(nil),
    do: {:error, {:missing_field, "$.ziellabel", "offenlegungsfreigabe requires ziellabel"}}

  defp require_ziellabel(labels) when is_list(labels) do
    if labels == Enum.sort(Enum.uniq(labels)) and labels != [] and
         Enum.all?(labels, &Registry.reference_id?/1) do
      {:ok, labels}
    else
      {:error,
       {:invalid_ziellabel, "$.ziellabel",
        "expected a sorted, duplicate-free, non-empty array of binding references"}}
    end
  end

  defp require_ziellabel(_other) do
    {:error, {:invalid_ziellabel, "$.ziellabel", "expected an array of binding references"}}
  end

  defp require_kind(value) when value in @kinds, do: :ok

  defp require_kind(value) do
    {:error,
     {:invalid_kind, "$.kind",
      "expected one of " <> Kernel.inspect(@kinds) <> ", got " <> Kernel.inspect(value)}}
  end

  defp require_window(term) do
    valid_from = term["valid_from"]
    valid_until = term["valid_until"]

    with :ok <- Validations.require_nonneg_integer(valid_from, "$.valid_from", :invalid_window),
         :ok <- Validations.require_nonneg_integer(valid_until, "$.valid_until", :invalid_window) do
      if valid_from <= valid_until do
        :ok
      else
        {:error,
         {:invalid_window, "$.valid_from",
          "valid_from must not exceed valid_until (#{Kernel.inspect(valid_from)} > #{Kernel.inspect(valid_until)})"}}
      end
    end
  end
end
