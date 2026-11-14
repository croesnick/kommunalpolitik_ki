defmodule KomkiCli.Gamma do
  @moduledoc """
  Γ aus dem Label-Store (Ticket #208): der Store `<base>/registry.db` ist
  die einzige Quelle; `<base>/mediator/registry.json`, aus dem der
  Vermittler entscheidet, ist sein Export.

  `sync/1` laeuft vor jedem Start des Vermittlers: Es importiert die
  Vorlage des Arbeitsraums (`KomkiMediator.Templates.label_store_seed/0`)
  in den Store und schreibt den Export, wenn er sich geaendert hat. Der
  Import ist ein Merge: eigene Bindungen aus `komki label import` bleiben,
  ein identischer Re-Import aendert nichts, eine abweichend registrierte
  Bindung bricht ab (Bindungen sind unveraenderlich, R.2.1). Validiert wird
  ueber `KomkiPolicy.Registry.compile/1` im Export.
  """

  alias KomkiCli.{Config, LabelStore}

  @doc "Pfad des Label-Store der Instanz."
  @spec db_path(Config.t()) :: Path.t()
  def db_path(%Config{base_dir: base}), do: Path.join(base, "registry.db")

  @doc "Pfad der Vermittler-Registry (Export)."
  @spec registry_path(Config.t()) :: Path.t()
  def registry_path(%Config{base_dir: base}), do: Path.join([base, "mediator", "registry.json"])

  @doc """
  Seed importieren, Export schreiben. `:unchanged`, wenn `registry.json`
  schon dem Export entspricht, sonst `:written`.
  """
  @spec sync(Config.t()) :: :unchanged | :written | {:error, String.t()}
  def sync(%Config{} = cfg) do
    db = db_path(cfg)
    path = registry_path(cfg)

    with {:ok, _counts} <-
           LabelStore.import_registry(db, KomkiMediator.Templates.label_store_seed()),
         {:ok, export} <- LabelStore.export(db),
         {:ok, term} <- parse(export) do
      # Kanonische Form wie die Vorlagen des Vermittlers: so erkennt dessen
      # Migration (SHA-256) den Export der Vorlage als aktuell.
      json = KomkiPolicy.JSON.canonical(term)

      if File.read(path) == {:ok, json} do
        :unchanged
      else
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, json)
        :written
      end
    else
      {:error, reason} -> {:error, "Γ aus dem Label-Store: " <> reason}
    end
  end

  defp parse(export) do
    case KomkiPolicy.JSON.parse(export) do
      {:ok, term} -> {:ok, term}
      {:error, err} -> {:error, "Export nicht lesbar: " <> inspect(err)}
    end
  end
end
