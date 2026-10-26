defmodule KomkiCli.Roles do
  @moduledoc """
  Rollen des Multicall-Programms `komki` (Ticket #179): Vermittler,
  Egress-Proxy und Connectoren laufen als `komki <rolle> <args>` aus
  derselben Datei, jede weiter als eigener Prozess unter ihrem eigenen
  Seatbelt-Profil.

  Die Rollennamen sind die frueheren Programmnamen (`komki-mediator`, ...):
  So steht der Name weiter in der Kommandozeile, und die Identitaetspruefung
  per `ps` (`KomkiCli.Proc.pid_alive?/2`) bleibt unveraendert. Eine Rolle
  startet nur ihren eigenen Einstieg; die anderen Apps sind geladen, aber
  nicht gestartet (keine von ihnen hat einen Application-Callback).
  """

  @roles %{
    "komki-mediator" => KomkiMediator.CLI,
    "komki-egress" => KomkiEgress.CLI,
    "komki-connector-documents" => KomkiConnectorDocuments.CLI,
    "komki-connector-ris" => KomkiConnectorRis.CLI,
    "komki-connector-web" => KomkiConnectorWeb.CLI,
    "komki-connector-vault" => KomkiConnectorVault.CLI
  }

  @doc "Alle Rollennamen, sortiert."
  @spec names() :: [String.t()]
  def names, do: @roles |> Map.keys() |> Enum.sort()

  @doc "Einstiegsmodul und restliche Argumente, wenn argv eine Rolle nennt."
  @spec dispatch([String.t()]) :: {module(), [String.t()]} | nil
  def dispatch([name | rest]) do
    case Map.fetch(@roles, name) do
      {:ok, module} -> {module, rest}
      :error -> nil
    end
  end

  def dispatch([]), do: nil

  @doc """
  Argumente, die vor die Rollen-Argumente gehoeren: der Rollenname, wenn
  `binary` das Multicall-Programm ist; leer fuer ein eigenstaendiges
  Escript alter Bauart.
  """
  @spec prefix(KomkiCli.Config.t(), String.t() | nil, String.t()) :: [String.t()]
  def prefix(%{komki_bin: komki}, binary, name) when is_binary(komki) and binary == komki,
    do: [name]

  def prefix(_cfg, _binary, _name), do: []
end
