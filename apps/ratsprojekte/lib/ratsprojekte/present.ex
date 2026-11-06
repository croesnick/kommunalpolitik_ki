defmodule Ratsprojekte.Present do
  @moduledoc """
  Minimaler Präsenz-Check für Feldwerte: `nil` und leerer bzw. nur aus
  Whitespace bestehender Text gelten als nicht gesetzt, alles andere als
  gesetzt. Geteilt von Changesets (projekt, quelle) und den Gates des
  check_antragsreife-Tools — eine Definition statt drei Kopien.
  """

  @spec present?(term()) :: boolean()
  def present?(nil), do: false
  def present?(""), do: false
  def present?(value) when is_binary(value), do: String.trim(value) != ""
  def present?(_), do: true

  @spec blank?(term()) :: boolean()
  def blank?(value), do: not present?(value)
end
