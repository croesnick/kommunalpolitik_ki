defmodule KomkiCli.Terminal do
  @moduledoc """
  Terminal-Ausgang (Ticket #132): pis Ausgabe erreicht das Terminal des
  Menschen ausserhalb der Seatbelt-Grenze. Ein injiziertes Modell koennte
  dort per OSC 52 in die Zwischenablage schreiben, per OSC 8 Links mit
  Exfil-URL setzen oder per CSI/`\\r` Zeilen ueberschreiben.

  `sanitize/1` entfernt deshalb alle Steuersequenzen (ESC-Folgen, C1) und
  C0-Steuerzeichen ausser Zeilenumbruch und Tab. Ungueltiges UTF-8 wird
  ersetzt, damit kein Rohbyte als 8-Bit-C1 interpretiert wird.
  """

  # OSC/DCS/SOS/PM/APC bis BEL oder ST; danach CSI; danach jede weitere
  # ESC-Folge (inkl. einzelnem ESC am Ende).
  @escape ~r/\e[\]PX^_].*?(?:\a|\e\\|$)|\e\[[0-?]*[ -\/]*[@-~]?|\e.?/su
  @controls ~r/[\x00-\x08\x0B-\x1F\x7F\x{80}-\x{9F}]/u

  @spec sanitize(binary()) :: String.t()
  def sanitize(text) when is_binary(text) do
    text
    |> String.replace_invalid()
    |> then(&Regex.replace(@escape, &1, ""))
    |> then(&Regex.replace(@controls, &1, ""))
  end
end
