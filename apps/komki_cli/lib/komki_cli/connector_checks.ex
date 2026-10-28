defmodule KomkiCli.ConnectorChecks do
  @moduledoc """
  Doctor-Checks fuer Egress, Connectoren und Vermittler-Profil (Tickets
  #146/#137): Binaries, Profile byte-stabil, Socket-Laenge, Credentials
  (nur Existenz, Warnung statt FAIL) und je laufendem Connector die
  reservierte Operation `ping` ueber den Socket.

  Ein fehlendes Credential ist kein FAIL: Der Connector startet trotzdem
  und meldet `credential-missing`; der Doctor zeigt die Warnung.
  """

  alias KomkiCli.{Config, Connectors, Keychain, Mediator, MediatorProfile, Secrets, Tresor}
  alias KomkiConnector.Manifest

  @type check :: %{name: String.t(), ok: boolean(), reason: String.t()}

  @typedoc "Zustand eines Geheimnisses, wie `KomkiCli.Secrets.state/2` ihn liefert."
  @type secret_state :: :sealed | :unsealed | {:error, Keychain.error()}

  @doc "Alle Checks; `keychain` ersetzt `Secrets.state/2` je Service (Testnaht)."
  @spec all(Config.t(), (String.t() -> secret_state())) :: [check()]
  def all(%Config{} = cfg, keychain \\ &Secrets.state/1) do
    [escript_check(cfg), socket_check(cfg), ris_url_check(cfg)] ++
      binary_checks(cfg) ++
      profile_checks(cfg) ++
      credential_checks(cfg, keychain) ++
      ping_checks(cfg)
  end

  # Burrito-Einzeldatei (Ticket #181): Laufzeit ist die entpackte Wurzel
  defp escript_check(%Config{launcher: "burrito", runtime_root: root}) do
    if is_binary(root) and File.dir?(root),
      do: %{name: "runtime", ok: true, reason: root},
      else: %{
        name: "runtime",
        ok: false,
        reason: "entpackte Laufzeit fehlt: " <> to_string(root) <> " — 'komki setup' entdeckt neu"
      }
  end

  defp escript_check(cfg) do
    case cfg.escript_bin do
      bin when is_binary(bin) ->
        if File.exists?(bin),
          do: %{name: "escript", ok: true, reason: bin},
          else: %{
            name: "escript",
            ok: false,
            reason: "missing: " <> bin <> " — 'komki setup' entdeckt neu"
          }

      nil ->
        %{
          name: "escript",
          ok: false,
          reason: "Erlang-escript nicht entdeckt — Erlang installieren, 'komki setup'"
        }
    end
  end

  defp socket_check(cfg) do
    case Connectors.socket_length(cfg.base_dir) do
      :ok ->
        %{name: "socket path", ok: true, reason: Connectors.longest_socket(cfg.base_dir)}

      {:error, reason} ->
        %{
          name: "socket path",
          ok: false,
          reason: reason <> " — kürzere Basis (KOMKI_HOME) wählen"
        }
    end
  end

  # Echter Betrieb: Host der RIS-URL muss in der Allowlist des Manifests
  # stehen, sonst lehnt der Egress jede Anfrage ab.
  defp ris_url_check(cfg) do
    name = "ris base url"
    url = Config.ris_url(cfg)

    if Config.ris_mock?(cfg) do
      %{name: name, ok: true, reason: url <> " (Mock, ohne Proxy)"}
    else
      uri = URI.parse(url)
      target = (uri.host || "") <> ":" <> Integer.to_string(uri.port || 0)

      if uri.scheme == "https" and target in Manifest.fetch!("ris").egress_hosts,
        do: %{name: name, ok: true, reason: url},
        else: %{
          name: name,
          ok: false,
          reason: url <> " — Host nicht in egress_hosts des Manifests (oder kein https)"
        }
    end
  end

  defp binary_checks(cfg) do
    egress = if Connectors.egress_needed?(cfg), do: [{"komki-egress", cfg.egress_bin}], else: []

    connectors =
      Enum.map(Connectors.enabled(cfg), &{&1.binary, Connectors.binary(cfg, &1.id)})

    Enum.map(egress ++ connectors, fn
      {name, nil} ->
        %{name: name, ok: false, reason: Connectors.missing_binary(name)}

      {name, path} ->
        if File.exists?(path),
          do: %{name: name, ok: true, reason: path},
          else: %{
            name: name,
            ok: false,
            reason: "missing: " <> path <> " — 'komki setup' entdeckt neu"
          }
    end)
  end

  @doc "Profile (Vermittler, Egress, Connectoren): Pfad und Generator."
  @spec profiles(Config.t()) :: [{String.t(), String.t(), (-> String.t())}]
  def profiles(cfg) do
    [
      {"mediator profile", MediatorProfile.path(cfg),
       fn -> MediatorProfile.generate(cfg, Mediator.listen(cfg)) end}
    ] ++ Connectors.profiles(cfg)
  end

  @doc "Byte-Identität jedes Profils mit seiner Regeneration."
  @spec profile_checks(Config.t()) :: [check()]
  def profile_checks(cfg) do
    Enum.map(profiles(cfg), fn {name, path, generate} ->
      identity(name, path, generate)
    end)
  end

  defp identity(name, path, generate) do
    expected = generate.()

    cond do
      not File.exists?(path) ->
        %{name: name, ok: false, reason: "missing (init first)"}

      File.read!(path) == expected ->
        %{name: name, ok: true, reason: "regeneration byte-stabil"}

      true ->
        %{
          name: name,
          ok: false,
          reason:
            "drift: regenerierter Profiltext weicht ab — nach einem Update 'komki setup'; bleibt sie, wurde das Profil verändert"
        }
    end
  rescue
    e in ArgumentError -> %{name: name, ok: false, reason: Exception.message(e)}
  end

  defp credential_checks(cfg, keychain) do
    tresor_checks(cfg) ++ secret_checks(cfg, keychain)
  end

  # Nur wenn ein aktiver Connector ein Geheimnis braucht.
  defp tresor_checks(cfg) do
    if Enum.any?(Connectors.enabled(cfg), &(&1.credentials != %{})),
      do: [tresor_check(Tresor.binary())],
      else: []
  end

  defp tresor_check(nil),
    do: %{name: "komki-tresor", ok: false, reason: Tresor.describe(:missing_bin)}

  defp tresor_check(bin) do
    case System.cmd(bin, ["check"], stderr_to_stdout: true) do
      {_, 0} -> %{name: "komki-tresor", ok: true, reason: bin <> " (Secure Enclave verfügbar)"}
      {_, 3} -> %{name: "komki-tresor", ok: false, reason: Tresor.describe(:no_enclave)}
      {_, code} -> %{name: "komki-tresor", ok: false, reason: Tresor.describe({:failed, code})}
    end
  end

  defp secret_checks(cfg, keychain) do
    for manifest <- Connectors.enabled(cfg),
        {name, service} <- Enum.sort(manifest.credentials) do
      check = "credential " <> name

      case keychain.(service) do
        :sealed ->
          %{
            name: check,
            ok: true,
            reason: "Schlüsselbund-Eintrag '" <> service <> "' versiegelt (Secure Enclave)"
          }

        # Warnung wie beim fehlenden Schluessel: komki benutzt den Klartext
        # nicht (der Connector startet ohne), ihn zu versiegeln ist der Weg.
        :unsealed ->
          %{
            name: check,
            ok: true,
            reason:
              "WARNUNG: " <>
                Secrets.describe(service, :unsealed) <>
                " — 'komki setup' oder 'komki secret set " <>
                Secrets.short_name(service) <> "' versiegelt ihn"
          }

        {:error, error} ->
          %{
            name: check,
            ok: true,
            reason:
              "WARNUNG: " <>
                Keychain.describe(service, error) <>
                " — " <> manifest.id <> " meldet credential-missing"
          }
      end
    end
  end

  defp ping_checks(cfg), do: Enum.map(Connectors.enabled(cfg), &ping_check(cfg, &1))

  defp ping_check(cfg, manifest) do
    name = "ping " <> manifest.id

    if File.exists?(Manifest.socket_path(cfg.base_dir, manifest.id)) do
      case Connectors.ping(cfg, manifest) do
        {:ok, %{"fassung" => fassung}} -> %{name: name, ok: true, reason: fassung}
        {:error, reason} -> %{name: name, ok: false, reason: reason}
      end
    else
      %{name: name, ok: true, reason: "nicht aktiv"}
    end
  end
end
