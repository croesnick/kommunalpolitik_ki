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
  Eingabe (stdin zu Ende, etwa ohne Terminal) ist die Antwort immer nein:
  Ein Default-Ja darf nur eine Person mit Enter geben, nie ein Skript.
  """
  @spec confirm(String.t(), boolean()) :: boolean()
  def confirm(question, default_yes? \\ true) do
    hint = if default_yes?, do: " [J/n] ", else: " [j/N] "

    case IO.gets(question <> hint) do
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

  defp stty(arg) do
    port =
      Port.open({:spawn_executable, "/bin/stty"}, [:nouse_stdio, :exit_status, args: [arg]])

    receive do
      {^port, {:exit_status, code}} -> code
    after
      5_000 -> 1
    end
  end
end
