defmodule KomkiConnector.TLS do
  @moduledoc """
  CA-Zertifikate fuer Connectoren mit HTTPS (RIS, Web).

  Bewusst NICHT `:public_key.cacerts_get/0`: das fragt auf macOS den
  Schluesselbund-Dienst (`com.apple.SecurityServer`) ab. Das
  Connector-Profil verweigert diesen Dienst, weil er dem Connector den
  Schluesselbund oeffnen wuerde (Labbook L-108). Gelesen wird stattdessen
  die PEM-Datei des Systems. Fehlt sie oder enthaelt sie keine
  Zertifikate, gibt es keinen Rueckfall auf den Schluesselbund: der
  Aufruf scheitert (fail-closed).
  """

  # Erstes vorhandenes Buendel gewinnt: macOS, Debian/Ubuntu, RHEL/Fedora.
  # Das macOS-Connector-Profil erlaubt nur den ersten Pfad; die anderen
  # dienen Tests und CI unter Linux.
  @bundles [
    "/etc/ssl/cert.pem",
    "/etc/ssl/certs/ca-certificates.crt",
    "/etc/pki/tls/certs/ca-bundle.crt"
  ]

  @doc "Pfad des Zertifikatsbuendels (erstes vorhandenes der Plattform)."
  @spec bundle_path() :: Path.t()
  def bundle_path, do: Enum.find(@bundles, hd(@bundles), &File.regular?/1)

  @doc """
  DER-kodierte CA-Zertifikate aus `path`, einmal je Knoten gelesen und in
  `:persistent_term` gehalten.
  """
  @spec cacerts(Path.t()) :: [binary()]
  def cacerts(path \\ bundle_path()) do
    key = {__MODULE__, path}

    case :persistent_term.get(key, nil) do
      nil ->
        certs = load!(path)
        :persistent_term.put(key, certs)
        certs

      certs ->
        certs
    end
  end

  @doc "Liest und dekodiert ein PEM-Buendel; scheitert laut, wenn es leer ist."
  @spec load!(Path.t()) :: [binary()]
  def load!(path) do
    certs =
      for {:Certificate, der, :not_encrypted} <- :public_key.pem_decode(File.read!(path)),
          do: der

    if certs == [], do: raise("keine CA-Zertifikate in #{path}"), else: certs
  end
end
