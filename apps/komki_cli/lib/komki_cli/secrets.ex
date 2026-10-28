defmodule KomkiCli.Secrets do
  @moduledoc """
  Die Geheimnisse, die komki im Schluesselbund erwartet (Ticket #176).
  Quelle sind die Connector-Manifeste (`credentials`, CONTRACT.md §5); hier
  kommt nur ein kurzer Name fuer `komki secret set NAME` und eine lesbare
  Beschreibung dazu.

  Im Schluesselbund liegt nur das Siegel der Secure Enclave
  (`KomkiCli.Tresor`), nie der Klartext. Ein Schluesselbund-Eintrag ist
  fuer jeden Prozess desselben Nutzers lesbar; erst das Siegel bindet das
  Oeffnen an Touch ID oder das Passwort des Macs. Einen Klartext-Eintrag
  aus der Zeit davor benutzt komki nicht (`:unsealed`), sondern bietet an,
  ihn zu versiegeln.
  """

  alias KomkiCli.{Keychain, Tresor}

  @type t :: %{name: String.t(), service: String.t(), connector: String.t(), label: String.t()}

  # Kurzname und Beschreibung je Keychain-Service. Ein Service ohne Eintrag
  # heisst wie sein Service-Name.
  @names %{"brave-search-api" => {"brave", "Brave-Search-API-Key für die Websuche"}}

  @doc "Alle erwarteten Geheimnisse, sortiert nach Kurzname."
  @spec all() :: [t()]
  def all do
    for manifest <- KomkiConnector.Manifest.all(),
        {_env, service} <- manifest.credentials do
      {name, label} = Map.get(@names, service, {service, service})
      %{name: name, service: service, connector: manifest.id, label: label}
    end
    |> Enum.sort_by(& &1.name)
  end

  @doc "Geheimnis per Kurz- oder Service-Name."
  @spec fetch(String.t()) :: {:ok, t()} | :error
  def fetch(name) do
    case Enum.find(all(), &(name in [&1.name, &1.service])) do
      nil -> :error
      secret -> {:ok, secret}
    end
  end

  @type error :: Keychain.error() | {:tresor, Tresor.error()} | :unsealed | :damaged

  @doc """
  Zustand des Eintrags: versiegelt, Klartext (aus der Zeit vor dem Tresor)
  oder fehlend. Liest den Eintrag, gibt aber nie seinen Wert heraus.
  """
  @spec state(t() | String.t(), keyword()) ::
          :sealed | :unsealed | :damaged | {:error, Keychain.error()}
  def state(entry_or_service, opts \\ [])
  def state(%{service: service}, opts), do: state(service, opts)

  def state(service, opts) when is_binary(service) do
    case Keychain.fetch(service, opts) do
      {:ok, value} -> classify(value)
      {:error, _} = error -> error
    end
  end

  defp classify(value) do
    cond do
      Tresor.well_formed?(value) -> :sealed
      Tresor.sealed?(value) -> :damaged
      true -> :unsealed
    end
  end

  @doc """
  Klartext fuer den Start eines Connectors: Siegel aus dem Schluesselbund
  holen und per Secure Enclave oeffnen (Rueckfrage Touch ID oder Passwort).
  Klartext im Schluesselbund wird nicht benutzt.
  """
  @spec reveal(String.t(), keyword()) :: {:ok, String.t()} | {:error, error()}
  def reveal(service, opts \\ []) when is_binary(service) do
    with {:ok, value} <- Keychain.fetch(service, opts) do
      if Tresor.sealed?(value),
        do: value |> Tresor.open(reason(service), tresor_opts(opts)) |> tresor(),
        else: {:error, :unsealed}
    end
  end

  @doc "Klartext versiegeln und das Siegel im Schlüsselbund ablegen (ersetzt den Eintrag)."
  @spec store(t(), String.t(), keyword()) :: :ok | {:error, error()}
  def store(%{service: service}, value, opts \\ []) do
    with {:ok, sealed} <- tresor(Tresor.seal(value, tresor_opts(opts))) do
      Keychain.store(service, sealed, opts)
    end
  end

  @doc """
  Einen Klartext-Eintrag in sein Siegel umwandeln. Der Eintrag wird in
  place ersetzt; der Klartext steht danach nicht mehr im Schlüsselbund.
  """
  @spec seal_existing(t(), keyword()) :: :ok | {:error, error()}
  def seal_existing(entry, opts \\ []) do
    case Keychain.fetch(entry.service, opts) do
      {:ok, value} -> if Tresor.sealed?(value), do: :ok, else: store(entry, value, opts)
      {:error, _} = error -> error
    end
  end

  @doc "Kurzname fuer `komki secret set` zu einem Service."
  @spec short_name(String.t()) :: String.t()
  def short_name(service) do
    case Enum.find(all(), &(&1.service == service)) do
      nil -> service
      entry -> entry.name
    end
  end

  @doc "Fehler als Text ohne Wert."
  @spec describe(String.t(), error()) :: String.t()
  def describe(service, :unsealed),
    do:
      "Schlüsselbund-Eintrag '" <>
        service <> "' liegt im Klartext vor; komki benutzt ihn erst versiegelt"

  def describe(service, :damaged),
    do: "Schlüsselbund-Eintrag '" <> service <> "' enthält ein beschädigtes Siegel; neu eingeben"

  def describe(service, {:tresor, error}), do: "'" <> service <> "': " <> Tresor.describe(error)

  def describe(service, error), do: Keychain.describe(service, error)

  # `opts` gelten fuer den Schluesselbund (`command:` in Tests); der Tresor
  # bekommt nur `opts[:tresor]`.
  defp tresor_opts(opts), do: Keyword.get(opts, :tresor, [])

  defp tresor({:error, error}), do: {:error, {:tresor, error}}
  defp tresor(ok), do: ok

  # Grund im Dialog von macOS: wer fragt und wofuer.
  defp reason(service) do
    case Enum.find(all(), &(&1.service == service)) do
      nil -> "komki: Schlüssel '" <> service <> "' freigeben"
      entry -> "komki startet den Connector " <> entry.connector <> ": " <> entry.label
    end
  end
end
