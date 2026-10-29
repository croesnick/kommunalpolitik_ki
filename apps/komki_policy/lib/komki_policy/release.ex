defmodule KomkiPolicy.Release do
  @moduledoc """
  Aktionsfreigabe-Datensatz `komki-release/1` (CONTRACT.md § 2.6).

  Geschlossene Schema-Validierung plus die verbindliche Call-Hash-Formel
  (R.6.2): ein GO autorisiert ein Ereignis, nicht nur einen Text — die
  Bindung an den exakten Call geschieht ausschließlich über den
  call hash, neu berechnet aus (Inhaltsreferenz, Objekt, Operation,
  Workspace). Kein separater Referenzvergleich; ein abweichender Call
  fällt durch den Hash-Abgleich auf.

  Die Validierung ist rein und umfasst die geschlossene Feldmenge, die
  `kind`-Menge (`aktionsfreigabe` | `offenlegungsfreigabe`; unbekannte
  Werte sind Eingabefehler), die Operation (unbekannte Werte Eingabefehler;
  bekannte Nicht-`emit`-Operationen werden erst im Freigabe-Zweig,
  CONTRACT § 4.6, zu `unsupported`), Hex-Digest-Formate und das
  Frische-Fenster `valid_from <= valid_until` (logische Ganzzahlen —
  die Engine hat keine Uhr, § 1; die Prüfung gegen `as_of` geschieht im
  Freigabe-Zweig, nicht hier).
  """

  alias KomkiPolicy.{JSON, Validations}

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
  @kinds ["aktionsfreigabe", "offenlegungsfreigabe"]
  @known_operations ["start", "admit", "emit", "transfer", "store"]
  @hex_re ~r/\A[0-9a-f]{64}\z/

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
          required(:nonce) => String.t()
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
    with {:ok, _} <- Validations.require_map(term, "$"),
         :ok <- Validations.require_schema(term, "komki-release/1"),
         :ok <- Validations.closed_fields(term, @fields, "$"),
         :ok <- Validations.require_kebab(term["release_id"], "$.release_id"),
         :ok <- require_kind(term["kind"]),
         :ok <- require_operation(term["operation"]),
         :ok <- Validations.require_object_ref(term["object"], "$.object"),
         :ok <- Validations.require_kebab(term["workspace"], "$.workspace"),
         :ok <- require_hex64(term["content_digest"], "$.content_digest"),
         :ok <- require_hex64(term["call_hash"], "$.call_hash"),
         :ok <- Validations.require_kebab(term["scope"], "$.scope"),
         :ok <- Validations.require_kebab(term["authority"], "$.authority"),
         :ok <- require_window(term),
         :ok <- Validations.require_kebab(term["nonce"], "$.nonce") do
      {:ok,
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
       }}
    end
  end

  defp require_kind(value) when value in @kinds, do: :ok

  defp require_kind(value) do
    {:error,
     {:invalid_kind, "$.kind",
      "expected one of " <> Kernel.inspect(@kinds) <> ", got " <> Kernel.inspect(value)}}
  end

  defp require_operation(value) when value in @known_operations, do: :ok

  defp require_operation(value) do
    {:error, {:invalid_operation, "$.operation", "unknown operation: " <> Kernel.inspect(value)}}
  end

  defp require_hex64(value, path) do
    if is_binary(value) and Regex.match?(@hex_re, value) do
      :ok
    else
      {:error,
       {:invalid_digest, path,
        "expected a lowercase sha256 hex string (64 hex digits), got " <> Kernel.inspect(value)}}
    end
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
