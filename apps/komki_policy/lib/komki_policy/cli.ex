defmodule KomkiPolicy.CLI do
  @moduledoc """
  Escript-Einstiegspunkt `komki-policy` (CONTRACT.md § 7).

  Verfügbare Befehle:

  ```
  komki-policy validate --registry <registry.json>
  komki-policy decide   --registry <r.json> --snapshot <s.json> --intent <i.json>
  komki-policy verify   --registry <r.json> --snapshot <s.json> --intent <i.json> --proof <p.json>
  komki-policy plan
  ```

  Exit-Codes:

  | Code | Bedeutung |
  |---|---|
  | `0` | Erfolg; auch `deny`/`indeterminate` (decide) und `valid` (verify) sind legitime Ergebnisse |
  | `1` | `verify` hat den vorgelegten Beweis verworfen (`invalid`) |
  | `2` | Eingabefehler: Parse-/Schemaverstoß, Kohärenz, fehlende oder unerwartete Argumente, fehlende Datei, **unbekannter Befehl** — mit strukturiertem Fehlerdatensatz auf stdout |
  | `3` | `unsupported`: nicht implementierter Regelzweig (und explizit `plan`) — niemals ein `deny` |
  | `4` | unerwarteter interner Fehler (Crash-Handler) — erzeugt niemals eine Decision und fällt nie auf `permit` zurück (§ 1) |

  Deterministische Wahl für Grenzfälle:

  * `plan` wird als `unsupported` (Exit 3) beantwortet — der Regelzweig
    `plan`/`infer_plan` ist in Lieferung 1 bewusst nicht geliefert, kein
    Bedienfehler; zusätzliche Argumente nach `plan` werden deterministisch ignoriert.
  * Jeder sonstige unbekannte Befehl (auch leeres argv) ist ein Usage-Fehler
    (Exit 2) mit `code: "unknown_command"` bzw. `code: "usage"`.
  * Fehlt einem Flag sein Wert oder taucht ein unbeabsichtigtes Argument auf,
    ist das `code: "usage"` (Exit 2); fehlt ein Pflicht-Flag, ebenfalls
    `code: "usage"`. Wird ein Flag zweimal angegeben, gewinnt der letzte Wert
    (deterministisch).
  * Eine fehlende/unlesbare Datei ist kein Crash, sondern
    `code: "read_error"` (Exit 2).

  Alle Ausgaben (Ergebnisse wie Fehler) laufen über
  `KomkiPolicy.JSON.canonical/1`: byte-stabil, deterministisch, mit genau
  einem finalen Newline — zwei identische Aufrufe erzeugen byte-identisches
  stdout. Datei-I/O geschieht ausschließlich in diesem Modul; der Rest der
  Bibliothek bleibt pur.
  """

  alias KomkiPolicy.{Derive, JSON, Registry, Verify}

  @flags ["registry", "snapshot", "intent", "proof"]

  @usage "usage: komki-policy validate --registry <r.json>; " <>
           "komki-policy decide --registry <r.json> --snapshot <s.json> --intent <i.json>; " <>
           "komki-policy verify --registry <r.json> --snapshot <s.json> --intent <i.json> --proof <p.json>; " <>
           "komki-policy plan (unsupported, Exit 3)"

  @type outcome :: {String.t(), non_neg_integer()}

  @type error_detail :: %{
          code: atom(),
          path: String.t(),
          detail: String.t()
        }

  # ===========================================================================
  # Einstieg
  # ===========================================================================

  @doc false
  @spec main([binary()]) :: no_return()
  def main(argv) do
    {output, code} = run(argv)
    IO.write(output)
    halt(code)
  end

  @doc """
  Testbare Kernfunktion (CONTRACT.md § 7): liefert `{canonical_output, exit_code}`
  ohne `System.halt`. Fängt jede unerwartete Exception/throw um die
  Kommando-Ausführung ab und mündet dann in Exit 4 mit strukturiertem
  Fehlerdatensatz — **niemals** in eine Decision, niemals mit Fallback `permit`.
  """
  @spec run(term()) :: outcome()
  def run(argv) when is_list(argv) do
    {output, code} =
      try do
        dispatch(argv)
      rescue
        exception ->
          internal_crash("unhandled exception: " <> Exception.format(:error, exception))
      catch
        kind, thrown ->
          internal_crash("unhandled " <> Atom.to_string(kind) <> ": " <> Kernel.inspect(thrown))
      end

    {output, code}
  end

  def run(_argv), do: input_error(usage_error("unexpected non-list argv; " <> @usage))

  @doc false
  @dialyzer {:nowarn_function, halt: 1}
  def halt(code), do: System.halt(code)

  # ===========================================================================
  # Befehlsdispatch
  # ===========================================================================

  @spec dispatch([binary()]) :: outcome()
  defp dispatch(["validate" | rest]), do: cmd_validate(rest)
  defp dispatch(["decide" | rest]), do: cmd_decide(rest)
  defp dispatch(["verify" | rest]), do: cmd_verify(rest)

  # `plan`: nicht gelieferter Regelzweig, keine Bedienpanne -> Exit 3 (!!).
  # Zusätzliche Argumente nach `plan` werden deterministisch ignoriert.
  defp dispatch(["plan" | _rest]),
    do: emit(Derive.unsupported_info("plan"), 3)

  defp dispatch([]), do: input_error(usage_error("no command given; " <> @usage))

  # Jeder sonstige Befehl ist ein Bedienfehler (Exit 2), `plan` allein ist
  # unsupported (siehe oben).
  defp dispatch([command | _rest]),
    do:
      input_error(%{
        code: :unknown_command,
        path: "$",
        detail: "unknown command " <> Kernel.inspect(command) <> "; " <> @usage
      })

  # ===========================================================================
  # Befehle
  # ===========================================================================

  @spec cmd_validate([binary()]) :: outcome()
  defp cmd_validate(argv) do
    with {:ok, opts} <- parse_opts(argv, ["registry"]),
         {:ok, compiled} <- load_registry(Map.fetch!(opts, "registry")) do
      emit(%{"result" => "valid", "registry_id" => compiled.registry_id}, 0)
    else
      {:error, detail} -> input_error(detail)
    end
  end

  @spec cmd_decide([binary()]) :: outcome()
  defp cmd_decide(argv) do
    with {:ok, opts} <- parse_opts(argv, ["registry", "snapshot", "intent"]),
         {:ok, registry} <- load_registry(Map.fetch!(opts, "registry")),
         {:ok, snapshot} <- load_json(Map.fetch!(opts, "snapshot")),
         {:ok, intent} <- load_json(Map.fetch!(opts, "intent")) do
      output_decision(Derive.decide(registry, snapshot, intent))
    else
      {:error, detail} -> input_error(detail)
    end
  end

  @spec output_decision(term()) :: outcome()
  defp output_decision({:ok, decision}), do: emit(decision, 0)
  defp output_decision({:unsupported, info}), do: emit(info, 3)
  defp output_decision({:error, detail}), do: input_error(detail)

  @spec cmd_verify([binary()]) :: outcome()
  defp cmd_verify(argv) do
    with {:ok, opts} <- parse_opts(argv, ["registry", "snapshot", "intent", "proof"]),
         {:ok, registry} <- load_registry(Map.fetch!(opts, "registry")),
         {:ok, snapshot} <- load_json(Map.fetch!(opts, "snapshot")),
         {:ok, intent} <- load_json(Map.fetch!(opts, "intent")),
         {:ok, proof} <- load_json(Map.fetch!(opts, "proof")),
         {:ok, outcome} <- Verify.check(registry, snapshot, intent, proof) do
      # valid und invalid sind beide legitime Prüfungsergebnisse (§ 5);
      # lediglich der Exit: valid -> 0, invalid (Beweis verworfen) -> 1.
      case Map.fetch!(outcome, "result") do
        "valid" -> emit(outcome, 0)
        "invalid" -> emit(outcome, 1)
      end
    else
      {:error, detail} -> input_error(detail)
    end
  end

  # ===========================================================================
  # Optionen
  # ===========================================================================

  @spec parse_opts([binary()], [String.t()]) ::
          {:ok, %{String.t() => String.t()}} | {:error, error_detail()}
  defp parse_opts(args, required) do
    case collect_opts(args, %{}) do
      {:ok, opts} -> require_opts(opts, required)
      {:error, _} = error -> error
    end
  end

  @spec collect_opts([binary()], %{String.t() => String.t()}) ::
          {:ok, %{String.t() => String.t()}} | {:error, error_detail()}
  defp collect_opts([], acc), do: {:ok, acc}

  # Flag mit Wert; Wiederholung: letzter Wert gewinnt (deterministisch).
  defp collect_opts(["--" <> flag, value | rest], acc) when flag in @flags,
    do: collect_opts(rest, Map.put(acc, flag, value))

  # Unbekanntes Flag MIT Wert: eigenes Detail statt "requires a value".
  defp collect_opts(["--" <> flag, _value | _rest], _acc) when flag not in @flags,
    do: {:error, usage_error("unknown option --" <> flag <> "; " <> @usage)}

  defp collect_opts(["--" <> flag | _rest], _acc) when flag in @flags,
    do: {:error, usage_error("option --" <> flag <> " requires a value; " <> @usage)}

  defp collect_opts(["--" <> flag | _rest], _acc),
    do: {:error, usage_error("unknown option --" <> flag <> "; " <> @usage)}

  defp collect_opts([arg | _rest], _acc),
    do: {:error, usage_error("unexpected argument " <> Kernel.inspect(arg) <> "; " <> @usage)}

  @spec require_opts(%{String.t() => String.t()}, [String.t()]) ::
          {:ok, %{String.t() => String.t()}} | {:error, error_detail()}
  defp require_opts(opts, required) do
    missing = Enum.reject(required, &Map.has_key?(opts, &1))

    case Enum.sort(missing) do
      [] ->
        {:ok, opts}

      missing ->
        {:error,
         usage_error(
           "missing required option(s) --" <> Enum.join(missing, " --") <> "; " <> @usage
         )}
    end
  end

  # ===========================================================================
  # Datei-I/O (ausschließlich hier)
  # ===========================================================================

  @spec load_registry(binary()) :: {:ok, Registry.compiled()} | {:error, error_detail()}
  defp load_registry(path) do
    case load_json(path) do
      {:ok, term} -> Registry.compile(term)
      {:error, _} = error -> error
    end
  end

  @spec load_json(binary()) :: {:ok, term()} | {:error, error_detail()}
  defp load_json(path) do
    case File.read(path) do
      {:ok, content} ->
        JSON.parse(content)

      {:error, posix} ->
        {:error,
         %{
           code: :read_error,
           path: "$",
           detail: "cannot read " <> path <> ": " <> List.to_string(:file.format_error(posix))
         }}
    end
  end

  # ===========================================================================
  # Ausgabe-Helfer: alles kanonisch (§ 6)
  # ===========================================================================

  @spec emit(term(), non_neg_integer()) :: outcome()
  defp emit(value, code), do: {JSON.canonical(value), code}

  @spec input_error(error_detail()) :: outcome()
  defp input_error(%{code: code, path: path, detail: detail}),
    do:
      emit(
        %{
          "code" => code_name(code),
          "detail" => detail,
          "path" => path,
          "result" => "error"
        },
        2
      )

  @spec usage_error(String.t()) :: error_detail()
  defp usage_error(detail), do: %{code: :usage, path: "$", detail: detail}

  @spec code_name(atom()) :: String.t()
  defp code_name(code), do: Atom.to_string(code)

  defp internal_crash(detail) do
    emit(
      %{
        "code" => "internal_error",
        "detail" => detail,
        "path" => "$",
        "result" => "internal_error"
      },
      4
    )
  end
end
