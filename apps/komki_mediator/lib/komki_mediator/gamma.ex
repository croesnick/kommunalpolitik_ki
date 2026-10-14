defmodule KomkiMediator.Gamma do
  @moduledoc """
  Gamma-Stand: der Registry-Snapshot, gegen den die Vermittlungsregeln
  wirken. Laedt `registry.json`, parst sie rigide
  (`KomkiPolicy.JSON.parse`) und kompiliert sie
  (`KomkiPolicy.Registry.compile`); haelt den rohen Term UND den
  kompilierten Stand bereit. Gamma-Stand-Hash = `registry_id` +
  `gamma_hash` (SHA-256 ueber die Kanonisierungsbytes des rohen Terms);
  beides geht in jeden PDR-Auditdatensatz ein.
  """

  defstruct [:term, :compiled, :registry_id, :gamma_hash]

  @type t :: %__MODULE__{
          term: map(),
          compiled: map(),
          registry_id: String.t(),
          gamma_hash: String.t()
        }

  @typedoc "Ladefehler (POSIX-Grund bei Read; strukturiert bei Parse/Compile)."
  @type load_error ::
          {:gamma_read, term()}
          | {:gamma_parse, map()}
          | {:gamma_registry, map()}

  @doc "Laedt und kompiliert `registry.json` aus dem gegebenen Pfad."
  @spec load(Path.t()) :: {:ok, t()} | {:error, load_error()}
  def load(path) do
    with {:ok, raw} <- read(path),
         {:ok, term} <- parse(raw),
         {:ok, compiled} <- compile(term) do
      {:ok,
       %__MODULE__{
         term: term,
         compiled: compiled,
         registry_id: compiled.registry_id,
         gamma_hash: KomkiMediator.Hash.sha256_hex(KomkiPolicy.JSON.canonical(term))
       }}
    end
  end

  defp read(path) do
    case File.read(path) do
      {:ok, raw} -> {:ok, raw}
      {:error, reason} -> {:error, {:gamma_read, reason}}
    end
  end

  defp parse(raw) do
    case KomkiPolicy.JSON.parse(raw) do
      {:ok, term} -> {:ok, term}
      {:error, err} -> {:error, {:gamma_parse, err}}
    end
  end

  defp compile(term) do
    case KomkiPolicy.Registry.compile(term) do
      {:ok, compiled} -> {:ok, compiled}
      {:error, err} -> {:error, {:gamma_registry, err}}
    end
  end
end
