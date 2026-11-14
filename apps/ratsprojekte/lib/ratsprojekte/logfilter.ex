defmodule Ratsprojekte.Logfilter do
  @moduledoc """
  Primary logger filter of the released hub (ADR 0004: logs without
  contents, without paths, without parameters). An event passes unchanged
  only when its metadata says `inhaltsfrei: true`, which the hub's own
  messages declare. Everything else — crash reports, exceptions of
  libraries, Phoenix and Bandit errors — keeps its level and time but loses
  its message: those carry process state, queries, parameters and paths.
  What remains names where it happened, not what was in it.

  The level (`:warning`) is set in `config/prod.exs`; this filter is the
  second line for whatever is logged at `:warning` and above.
  """

  @doc "Install as primary filter."
  @spec installieren() :: :ok | {:error, term()}
  def installieren, do: :logger.add_primary_filter(:inhaltsfrei, {&__MODULE__.filter/2, []})

  @doc false
  @spec filter(:logger.log_event(), term()) :: :logger.filter_return()
  def filter(%{meta: %{inhaltsfrei: true}} = event, _arg), do: event

  def filter(%{meta: meta} = event, _arg) do
    %{
      event
      | msg: {:string, "Ereignis ohne Inhalt (" <> herkunft(meta) <> ")"},
        meta: Map.take(meta, [:time, :gl, :pid, :domain])
    }
  end

  defp herkunft(%{mfa: {m, f, a}}), do: "#{inspect(m)}.#{f}/#{a}"
  defp herkunft(%{domain: domain}) when is_list(domain), do: Enum.join(domain, ".")
  defp herkunft(_meta), do: "unbekannt"
end
