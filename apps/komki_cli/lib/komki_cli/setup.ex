defmodule KomkiCli.Setup do
  @moduledoc """
  Gefuehrte Einrichtung `komki setup` (Ticket #176, Plan
  `docs/research/2026-10-24-komki-devx-installation.md`, V1).

  Reihenfolge: Werkzeuge pruefen, Instanz anlegen (mit Vault-Wahl),
  Geheimnisse hinterlegen, starten und pruefen. Jeder Schritt sagt, was er
  tut, bevor er Platz belegt oder Prozesse startet (GO-Prinzip). Ein
  zweiter Lauf aendert nichts an einer bestehenden Instanz.

  Ein-/Ausgabe kommt als `ui`-Map herein (`say`, `ask`, `confirm`,
  `secret`, `render`), damit die CLI-Schicht das Terminal besitzt und
  Tests die Antworten vorgeben koennen.
  """

  alias KomkiCli.{Config, DemoVault, Keychain, Model, Secrets, Steps}

  @type ui :: %{
          say: (String.t() -> any()),
          ask: (String.t(), String.t() -> String.t()),
          confirm: (String.t(), boolean() -> boolean()),
          secret: (String.t() -> {:ok, String.t()} | {:error, atom()}),
          render: (Steps.result() -> any())
        }

  @bausteine_hint "im Repo 'make komki' ausfuehren (baut und legt die komki-Bausteine ab)"

  @spec run(%{String.t() => String.t()}, ui()) :: {:setup, :ok} | {:error, String.t(), 2..4}
  def run(opts, ui) do
    base = Config.default_base()

    with :ok <- tools(Config.defaults(base), ui),
         :ok <- instance(base, opts, ui),
         :ok <- secrets(ui) do
      start(ui)
    end
  end

  # ---------------------------------------------------------------- Werkzeuge

  @doc false
  @spec tool_report(Config.t(), String.t() | nil) ::
          %{required: [{String.t(), String.t() | nil, String.t()}], tmux: String.t() | nil}
  def tool_report(%Config{} = cfg, tmux) do
    connectors =
      for {id, bin} <- Enum.sort(cfg.connector_bins),
          do: {"komki-connector-" <> id, bin, @bausteine_hint}

    %{
      required:
        [
          {"llama-server", cfg.llama_server_bin, "brew install llama.cpp"},
          {"node", cfg.node_bin, "brew install node"},
          {"pi", cfg.cli_js, "npm install -g @earendil-works/pi-coding-agent"},
          runtime_entry(cfg),
          {"komki-mediator", cfg.mediator_bin, @bausteine_hint},
          {"komki-egress", cfg.egress_bin, @bausteine_hint}
        ] ++ connectors,
      tmux: tmux
    }
  end

  # Burrito-Einzeldatei (Ticket #181) bringt ihre Laufzeit mit
  defp runtime_entry(%Config{launcher: "burrito"} = cfg),
    do: {"Laufzeit (eingebaut)", cfg.runtime_root, "komki-Binary neu herunterladen"}

  defp runtime_entry(cfg),
    do: {"Erlang (escript)", cfg.escript_bin, "brew install erlang (oder per asdf)"}

  defp tools(cfg, ui) do
    %{required: required, tmux: tmux} = tool_report(cfg, System.find_executable("tmux"))
    missing = Enum.filter(required, fn {_name, path, _hint} -> is_nil(path) end)

    if missing == [] do
      names = Enum.map_join(required, ", ", fn {name, _, _} -> name end)
      ui.say.("Werkzeuge   ok (" <> names <> ")")

      unless tmux,
        do: ui.say.("            tmux fehlt: nur fuer 'komki session' noetig (brew install tmux)")

      :ok
    else
      ui.say.("Werkzeuge   es fehlt:")

      Enum.each(missing, fn {name, _, hint} -> ui.say.("            " <> name <> ": " <> hint) end)

      {:error,
       "setup angehalten: erst die fehlenden Werkzeuge installieren, dann 'komki setup' erneut",
       2}
    end
  end

  # ----------------------------------------------------------------- Instanz

  defp instance(base, opts, ui) do
    if File.exists?(Config.config_path(base)) do
      existing_instance(base, ui)
    else
      with {:ok, vault_dir} <- vault(base, opts, ui) do
        create_instance(base, vault_dir, opts, ui)
      end
    end
  end

  # Bestehende Instanz: Einstellungen bleiben, nur Programmpfade werden nach
  # einem Update aufgefrischt (Ticket #179).
  defp existing_instance(base, ui) do
    case Steps.refresh_instance() do
      :unchanged ->
        ui.say.("Instanz     vorhanden: " <> base <> " (unveraendert)")
        :ok

      {:refreshed, fields} ->
        ui.say.(
          "Instanz     vorhanden: " <>
            base <>
            "; Programmpfade aufgefrischt (" <>
            Enum.join(fields, ", ") <> "), Profile neu geschrieben"
        )

        :ok

      {:error, _reason, _code} = error ->
        error
    end
  end

  defp create_instance(base, vault_dir, opts, ui) do
    with :ok <- ensure_model(opts, ui) do
      init_instance(base, vault_dir, opts, ui)
    end
  end

  # Modell (Ticket #178): vorhanden am Staging-Ort oder per --gguf-from,
  # sonst nach Rueckfrage laden (Groesse, Quelle, Lizenz vorab).
  defp ensure_model(opts, ui) do
    if Map.has_key?(opts, "gguf-from") or Config.default_probe_gguf() do
      :ok
    else
      Enum.each(Model.summary(), ui.say)

      cond do
        not ui.confirm.("            jetzt herunterladen?", true) ->
          {:error, "setup angehalten: ohne Modell keine Instanz (oder --gguf-from PFAD angeben)",
           2}

        (check = Model.remote_matches?()) not in [:ok, :unknown] ->
          {:error, elem(check, 1), 2}

        true ->
          download(ui)
      end
    end
  end

  defp download(ui) do
    case Model.download() do
      {:ok, path} ->
        ui.say.("Modell      geladen und geprueft: " <> path)
        :ok

      {:error, reason} ->
        {:error, reason, 2}
    end
  end

  defp init_instance(base, vault_dir, opts, ui) do
    ui.say.("Instanz     wird angelegt unter " <> base <> " (prueft das Modell, etwa 30 s)")

    init_opts =
      %{"vault-dir" => vault_dir}
      |> put_if("gguf-from", Map.get(opts, "gguf-from"))
      |> put_if("port", Map.get(opts, "port"))

    case Steps.init(init_opts) do
      {:inited, _cfg, _lines} ->
        ui.say.("Instanz     angelegt")
        :ok

      {:error, reason, code} ->
        {:error, reason <> model_hint(reason), code}
    end
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp model_hint(reason) do
    if String.contains?(reason, "GGUF"),
      do: "\nModell angeben: komki setup --gguf-from PFAD/ZUM/MODELL.gguf",
      else: ""
  end

  # Vault: --vault-dir, --demo oder Frage. Leere Antwort (und Dateiende bei
  # nicht-interaktivem Aufruf) waehlt den Test-Vault; der echte Vault wird
  # nie vorgeschlagen.
  defp vault(base, opts, ui) do
    choice =
      cond do
        Map.has_key?(opts, "vault-dir") -> Map.fetch!(opts, "vault-dir")
        Map.has_key?(opts, "demo") -> ""
        true -> ui.ask.("Vault       Pfad zu deinem Vault, oder Enter fuer den Test-Vault: ", "")
      end

    case choice do
      "" -> demo_vault(base, ui)
      path -> own_vault(path, ui)
    end
  end

  defp demo_vault(base, ui) do
    dir = Path.join(base, "vault")

    case DemoVault.install(dir) do
      {:ok, count} ->
        ui.say.(
          "Vault       Test-Vault mit " <> to_string(count) <> " erfundenen Notizen unter " <> dir
        )

        {:ok, dir}

      {:error, reason} ->
        {:error, reason <> " (eigenen Vault mit --vault-dir angeben)", 2}
    end
  end

  defp own_vault(path, ui) do
    dir = Config.canonical(path)

    if File.dir?(dir) do
      ui.say.("Vault       " <> dir <> " (nur Notizen mit komki_labels sind fuer komki sichtbar)")
      {:ok, dir}
    else
      {:error, "Vault-Ordner nicht gefunden: " <> dir, 2}
    end
  end

  # ------------------------------------------------------------ Geheimnisse

  defp secrets(ui) do
    Enum.each(Secrets.all(), &secret(&1, ui))
  end

  defp secret(entry, ui) do
    if Secrets.present?(entry) do
      ui.say.(pad(entry.name) <> "ok (Schluesselbund-Eintrag '" <> entry.service <> "')")
    else
      ui.say.(pad(entry.name) <> entry.label <> " fehlt im Schluesselbund")

      if ui.confirm.("            jetzt eingeben?", true) do
        ui.say.(pad("") <> store_secret(entry, ui))
      else
        ui.say.(pad("") <> "uebersprungen; spaeter: komki secret set " <> entry.name)
      end
    end
  end

  @doc """
  Fragt ein Geheimnis zweimal verdeckt ab und legt es ab. Liefert eine
  Meldung ohne den Wert.
  """
  @spec store_secret(Secrets.t(), ui()) :: String.t()
  def store_secret(entry, ui) do
    with {:ok, first} <- ui.secret.("            Wert (wird nicht angezeigt): "),
         {:ok, ^first} <- ui.secret.("            noch einmal: "),
         :ok <- Keychain.store(entry.service, first) do
      "gespeichert im Schluesselbund als '" <> entry.service <> "'"
    else
      {:ok, _different} ->
        "die beiden Eingaben stimmen nicht ueberein; nichts gespeichert"

      {:error, :no_tty} ->
        "kein Terminal: 'komki secret set " <> entry.name <> "' in einem Terminal ausfuehren"

      {:error, :empty} ->
        "leere Eingabe; nichts gespeichert"

      {:error, error} ->
        Keychain.describe(entry.service, error)
    end
  end

  defp pad(name), do: String.pad_trailing(name, 12)

  # ------------------------------------------------------------------ Start

  defp start(ui) do
    ui.say.(
      "Start       llama, Egress, Connectoren und Vermittler (beim ersten Mal bis zu einer Minute)"
    )

    case Steps.up(%{}) do
      {:up, _} = up ->
        ui.render.(up)
        check(ui)

      {:error, _reason, _code} = error ->
        error
    end
  end

  defp check(ui) do
    case Steps.doctor() do
      {:checks, _checks, :ok} ->
        ui.say.("Pruefung    doctor ok")
        ui.say.("")
        ui.say.("Fertig. Probier zum Beispiel:")
        ui.say.("  komki run \"Was steht im RIS zum Radverkehrskonzept?\"")
        ui.say.("  komki session")
        {:setup, :ok}

      {:checks, _checks, _summary} = checks ->
        ui.render.(checks)
        {:error, "setup: Pruefung nicht gruen, Details oben ('komki doctor')", 3}

      {:error, _reason, _code} = error ->
        error
    end
  end
end
