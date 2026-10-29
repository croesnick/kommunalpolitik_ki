defmodule Ratsinfo.Config do
  @moduledoc """
  Konfiguration für den RIS-API-Client.

  Credentials werden aus ~/.config/kommunalpolitik_ki/.env geladen
  (RIS_EMAIL, RIS_PASSWORD). Die Datei liegt außerhalb des Repos.
  """

  @base_url "https://risapi1.komuna.net/web/"
  @org_key "RIS51"
  @customname "vgbuchloe"
  @unique_id "ris.komuna.net/vgbuchloe"

  @doc """
  Base URL der RIS-API. Überschreibbar über die Umgebungsvariable `RIS_BASE_URL`,
  z. B. für den Aufzeichnungs-Proxy `apps/komki_connector_ris/priv/ris_recorder.exs`
  oder den Replay-Modus des Mocks (jeweils ohne `/web/`-Präfix). Ein
  abschließender Schrägstrich wird ergänzt, wenn er fehlt.
  """
  def base_url do
    case System.get_env("RIS_BASE_URL") do
      url when is_binary(url) and url != "" ->
        String.trim_trailing(url, "/") <> "/"

      _ ->
        @base_url
    end
  end

  @doc "Erforderliche Custom-Header für alle API-Requests"
  def headers do
    [
      {"x-orgkey", @org_key},
      {"x-customname", @customname},
      {"x-uniqueid", @unique_id},
      {"accept", "application/json"}
    ]
  end

  @doc "Auth-Header mit Bearer-Token (falls eingeloggt)"
  def auth_headers(token) when is_binary(token) do
    [{"authorization", "Bearer #{token}"} | headers()]
  end

  def auth_headers(nil), do: headers()

  @doc "Client-ID der Stadt Buchloe"
  def client_stadt_buchloe, do: 32

  @doc "Client-ID der VGem Buchloe"
  def client_vgem_buchloe, do: 2445

  @doc "RIS-Credentials aus Env-Vars oder ~/.config/kommunalpolitik_ki/.env"
  def credentials do
    case System.get_env("RIS_EMAIL") do
      nil -> read_env_file()
      email -> {email, System.get_env("RIS_PASSWORD")}
    end
  end

  defp read_env_file do
    env_path = Path.join(System.user_home!(), ".config/kommunalpolitik_ki/.env")

    if File.exists?(env_path) do
      env_path
      |> File.read!()
      |> parse_env()
    else
      {nil, nil}
    end
  end

  defp parse_env(content) do
    email = Regex.run(~r/RIS_EMAIL=(.+)/, content, capture: :all_but_first)
    password = Regex.run(~r/RIS_PASSWORD=(.+)/, content, capture: :all_but_first)
    {List.first(email), List.first(password)}
  end
end
