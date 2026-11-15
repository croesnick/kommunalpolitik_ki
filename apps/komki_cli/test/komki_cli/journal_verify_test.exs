defmodule KomkiCli.JournalVerifyTest do
  @moduledoc """
  Ticket #499 (Audit-Fund F32): `komki journal verify` führt den gepinnten
  Vermittler aus — ohne den Pin-Gate, den up/run/session vor jeder Ausführung
  verlangen. Ein am Pfad getauschtes Vermittler-Escript druckt sonst ein
  gültig aussehendes Urteil, das komki als „Journal ok" ausgibt.

  Der Attrappen-Vermittler ist ein echtes Escript; es schreibt beim Lauf eine
  Marker-Datei (Beweis der Ausführung) und druckt ein gefälschtes JSON-Urteil.
  Die Pins der Instanz werden über `Pins.compute/1` aus dem Attrappen-Zustand
  selbst berechnet, damit der Grün-Fall (Pins stimmen ⇒ Ausführung erlaubt)
  herstellerunabhängig gilt.
  """

  # KOMKI_HOME ist eine globale Umgebung; keine parallelen Module (Race).
  use ExUnit.Case, async: false

  alias KomkiCli.{Config, Pins, Steps, TestSupport}

  describe "journal_verify/0 (Pin-Gate, Ticket #499)" do
    setup do
      base = TestSupport.tmp_area!("k499")
      System.put_env("KOMKI_HOME", base)
      on_exit(fn -> System.delete_env("KOMKI_HOME") end)
      {:ok, base: base}
    end

    # Der getauschte Vermittler druckt ein auffällig gefälschtes Urteil
    # („records": 999), damit der Rot-Befund das Ergebnis der Attrappe
    # zweifelsfrei zeigt.
    defp mediator_escript(base, marker, records) do
      path = Path.join([base, "bin", "komki-mediator"])
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, mediator_body(marker, records))
      path
    end

    # Instanz mit gepinnten Programmen; nur der Vermittler ist eine Attrappe.
    defp pinned_instance(base, mediator) do
      cfg =
        Map.merge(Config.defaults(base), %{
          komki_bin: nil,
          mediator_bin: mediator,
          launcher: "escript",
          egress_bin: nil,
          connector_bins: %{}
        })

      cfg = %{cfg | pins: Pins.compute(cfg)}
      Config.save(cfg)
      cfg
    end

    test "Pin-Abweichung: verweigert VOR der Ausführung, der getauschte Vermittler läuft nicht",
         %{
           base: base
         } do
      marker = Path.join(base, "marker")
      mediator = mediator_escript(base, marker, 1)
      pinned_instance(base, mediator)

      # Der Angriff aus F32: same-uid-Tausch am gepinnten Pfad, nachdem die
      # Pins festgehalten sind (Journal vorher manipuliert — hier: Attrappe).
      File.write!(mediator, mediator_body(marker, 999))

      assert {:error, reason, 3} = Steps.journal_verify()
      assert reason =~ "pin komki"
      assert reason =~ "komki doctor"
      refute File.exists?(marker)
    end

    test "Pins grün: journal_verify führt den gepinnten Vermittler aus", %{base: base} do
      marker = Path.join(base, "marker")
      mediator = mediator_escript(base, marker, 1)
      pinned_instance(base, mediator)

      assert {:journal, %{"result" => "valid"} = urteil} = Steps.journal_verify()
      assert urteil["records"] == 1
      assert File.exists?(marker)
    end

    defp mediator_body(marker, records) do
      """
      #!/usr/bin/env escript
      main(_Args) ->
          _ = file:write_file("#{marker}", "ran"),
          io:format("{\\"result\\": \\"valid\\", \\"records\\": #{records}, \\"head_hash\\": \\"forged\\"}~n"),
          halt(0).
      """
    end
  end
end
