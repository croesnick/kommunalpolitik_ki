defmodule KomkiCli.Secrets do
  @moduledoc """
  Die Geheimnisse, die komki im Schluesselbund erwartet (Ticket #176).
  Quelle sind die Connector-Manifeste (`credentials`, CONTRACT.md §5); hier
  kommt nur ein kurzer Name fuer `komki secret set NAME` und eine lesbare
  Beschreibung dazu.
  """

  alias KomkiCli.Keychain

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

  @doc "Liegt das Geheimnis im Schlüsselbund? Liest nie den Wert."
  @spec present?(t(), keyword()) :: boolean()
  def present?(%{service: service}, opts \\ []), do: Keychain.present(service, opts) == :ok
end
