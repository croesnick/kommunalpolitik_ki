defmodule KomkiMediator.Hash do
  @moduledoc """
  Byte-stabile Pruefwerks-Erzeugung fuer den Vermittler: Intent-Hash,
  Payload-Hash und Gamma-Stand-Hash basieren auf `:crypto.hash(:sha256, …)`
  ueber Kanonisierungsbytes (`KomkiPolicy.JSON.canonical/1`) — gleiches
  Eingabe-Material, gleiches Pruefwerk-Präfix.
  """

  @doc """
  SHA-256 ueber die gegebenen Bytes, dargestellt als
  `"sha256:" <> 64 lowercase hex` (Payload-weise byte-stabil).
  """
  @spec sha256_hex(binary() | iodata()) :: String.t()
  def sha256_hex(data) when is_binary(data) or is_list(data) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, data), case: :lower)
  end

  @doc """
  Erste 12 Hexzeichen eines `sha256:…`-Pruefwerks. Dient als kurzes,
  kebab-taugliches ID-Suffix fuer `intent-…`/`snap-…`-Kennungen.
  """
  @spec digest12(String.t()) :: String.t()
  def digest12("sha256:" <> hex) when byte_size(hex) >= 12 do
    binary_part(hex, 0, 12)
  end
end
