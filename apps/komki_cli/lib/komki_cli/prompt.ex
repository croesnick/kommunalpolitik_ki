defmodule KomkiCli.Prompt do
  @moduledoc """
  Fragen am Terminal fuer `komki setup` und `komki secret set` (Ticket #176).

  Verdeckte Eingabe: `:io.get_password/0` ist im Escript (noshell) nicht
  verfuegbar (`{:error, :enotsup}`), und Port-Kinder haben kein steuerndes
  Terminal (`/dev/tty` liefert ENXIO). `stty -echo` wirkt deshalb ueber
  einen Port mit `:nouse_stdio`: das Kind erbt fd 0 des Emulators, also das
  Terminal der Person, und schaltet dort das Echo ab. Ist stdin kein
  Terminal, verweigert `secret/1` die Eingabe, statt einen Schluessel mit
  Echo zu lesen.

  Ja/Nein-Fragen beantwortet nur eine Person am Terminal (Ticket #262):
  Ist stdin kein Terminal, ist die Antwort nein, auch wenn etwas
  hineingepipt wird (`yes j | komki setup` uebernimmt weder Download noch
  Programm-Pruefsummen). Geprueft wird wie bei `stty` ueber einen Port mit
  `:nouse_stdio`, der fd 0 des Emulators erbt (`test -t 0`).
  """

  @doc "Frage mit Vorgabe; leere Eingabe oder Dateiende ergibt die Vorgabe."
  @spec ask(String.t(), String.t()) :: String.t()
  def ask(question, default \\ "") do
    case IO.gets(question) do
      text when is_binary(text) ->
        case String.trim(text) do
          "" -> default
          answer -> answer
        end

      _eof ->
        default
    end
  end

  @doc """
  Ja/Nein-Frage; `default_yes?` bestimmt die Antwort auf Enter. Ohne
  Terminal oder ohne Eingabe (stdin zu Ende) ist die Antwort immer nein:
  Ein Ja darf nur eine Person geben, nie ein Skript. `terminal?` ist fuer
  Tests ersetzbar.
  """
  @spec confirm(String.t(), boolean(), (-> boolean())) :: boolean()
  def confirm(question, default_yes? \\ true, terminal? \\ &terminal?/0) do
    hint = if default_yes?, do: " [J/n] ", else: " [j/N] "

    if terminal?.() do
      answer(question <> hint, default_yes?)
    else
      IO.puts(
        question <>
          hint <>
          "nein (kein Terminal: das beantwortet nur eine Person; den Befehl in einem Terminal wiederholen)"
      )

      false
    end
  end

  defp answer(prompt, default_yes?) do
    case IO.gets(prompt) do
      text when is_binary(text) ->
        case text |> String.trim() |> String.downcase() do
          "" -> default_yes?
          answer -> answer in ["j", "ja", "y", "yes"]
        end

      _eof ->
        IO.write("\n")
        false
    end
  end

  @doc """
  Verdeckte Eingabe. Der Wert wird nicht angezeigt; nach der Eingabe ist
  das Echo in jedem Fall wieder an.
  """
  @spec secret(String.t()) :: {:ok, String.t()} | {:error, :no_tty | :empty}
  def secret(question) do
    if stty("-echo") == 0 do
      try do
        IO.write(question)
        value = IO.gets("")
        IO.write("\n")
        trimmed = if is_binary(value), do: String.trim(value), else: ""
        if trimmed == "", do: {:error, :empty}, else: {:ok, trimmed}
      after
        stty("echo")
      end
    else
      {:error, :no_tty}
    end
  end

  @doc "Ist stdin ein Terminal? (`test -t 0` auf dem fd 0 des Emulators)"
  @spec terminal?() :: boolean()
  def terminal?, do: run_on_stdin("/bin/test", ["-t", "0"]) == 0

  defp stty(arg), do: run_on_stdin("/bin/stty", [arg])

  defp run_on_stdin(executable, args) do
    port = Port.open({:spawn_executable, executable}, [:nouse_stdio, :exit_status, args: args])

    receive do
      {^port, {:exit_status, code}} -> code
    after
      5_000 -> 1
    end
  end
end
