defmodule Ratsprojekte.MCP.Tools.ProposeProjektUpdateTest do
  @moduledoc """
  Ticket #22: `beschlussvorschlag` und `adressat` per Proposal + GO setzen.

  Der GO-basierte Workflow muss beide Hard-Gate-Felder abdecken, ohne dass
  die KI direkt in die DB schreibt: Proposal anlegen → ohne GO bleibt das
  Projekt unberührt → erst `decide_proposal` (GO) schreibt → danach bestehen
  die beiden Hard Gates in `check_antragsreife`.
  """

  use Ratsprojekte.DataCase, async: false

  alias Anubis.Server.Frame
  alias Ratsprojekte.MCP.Tools.{CheckAntragsreife, DecideProposal, ProposeProjektUpdate}
  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.{PendingProposal, Projekt}

  import Ratsprojekte.Fixtures

  @beschlussvorschlag "Der Stadtrat beschließt, an allen Freibad-Kassen Kartenzahlung zu einem Kartengebührensatz von höchstens 0,5 Prozent einzuführen."
  @adressat "Stadtrat"

  describe "propose + GO for beschlussvorschlag and adressat" do
    setup do
      projekt = freibad()
      %{projekt: projekt, slug: projekt.slug}
    end

    test "proposal carries both fields and stays pending (no GO yet)", %{slug: slug} do
      assert {:reply, response, _frame} =
               ProposeProjektUpdate.execute(
                 [
                   projekt_slug: slug,
                   beschlussvorschlag: @beschlussvorschlag,
                   adressat: @adressat,
                   begruendung: "Bargeldloser Kassenbetrieb reduziert Ausfälle und Zählfehler."
                 ],
                 Frame.new()
               )

      refute response.isError

      proposal = Repo.one(PendingProposal)
      assert proposal.typ == :update_projekt
      assert proposal.status == :pending
      assert proposal.payload["beschlussvorschlag"] == @beschlussvorschlag
      assert proposal.payload["adressat"] == @adressat
    end

    test "without GO the projekt stays untouched", %{slug: slug, projekt: projekt} do
      assert {:reply, response, _frame} =
               ProposeProjektUpdate.execute(
                 [
                   projekt_slug: slug,
                   beschlussvorschlag: @beschlussvorschlag,
                   adressat: @adressat,
                   begruendung: "Bargeldloser Kassenbetrieb reduziert Ausfälle und Zählfehler."
                 ],
                 Frame.new()
               )

      refute response.isError

      reloaded = Repo.get!(Projekt, projekt.id)
      assert reloaded.beschlussvorschlag == nil
      assert reloaded.adressat == nil
    end

    test "decide_proposal with GO writes both fields and the hard gates pass", %{
      slug: slug,
      projekt: projekt
    } do
      assert {:reply, response, _frame} =
               ProposeProjektUpdate.execute(
                 [
                   projekt_slug: slug,
                   beschlussvorschlag: @beschlussvorschlag,
                   adressat: @adressat,
                   begruendung: "Bargeldloser Kassenbetrieb reduziert Ausfälle und Zählfehler."
                 ],
                 Frame.new()
               )

      refute response.isError

      proposal = Repo.one(PendingProposal)

      # Vor dem GO schlagen beide Hard Gates fehl.
      assert {"fail", _} = gate_status(slug, :adressat_gesetzt)
      assert {"fail", _} = gate_status(slug, :beschlussvorschlag_konkret)

      # GO im Chat: decide_proposal führt es aus (Audit-Trail: stadtrat-via-ai).
      assert {:reply, go_response, _frame} =
               DecideProposal.execute(
                 [proposal_id: proposal.id, aktion: "accept", kommentar: "GO im Chat"],
                 Frame.new()
               )

      refute go_response.isError

      reloaded = Repo.get!(Projekt, projekt.id)
      assert reloaded.beschlussvorschlag == @beschlussvorschlag
      assert reloaded.adressat == @adressat

      assert Repo.get!(PendingProposal, proposal.id).status == :approved

      # Nach dem GO bestehen die beiden Hard Gates.
      assert {"pass", _} = gate_status(slug, :adressat_gesetzt)
      assert {"pass", _} = gate_status(slug, :beschlussvorschlag_konkret)
    end

    test "unknown projekt slug returns an error", %{slug: slug} do
      assert {:reply, response, _frame} =
               ProposeProjektUpdate.execute(
                 [
                   projekt_slug: "gibt-es-nicht-#{slug}",
                   adressat: @adressat,
                   begruendung: "Projekt existiert nicht, es muss ein Fehler kommen."
                 ],
                 Frame.new()
               )

      assert response.isError
      assert error_text(response) =~ "nicht gefunden"
    end
  end

  describe "propose + GO for value proposition and success metrics (#37)" do
    @vp "Bargeldanteil im Bäderbetrieb sinkt, Wartezeiten an den Kassen werden messbar kürzer."
    @sm "Bargeldanteil im Bäderbetrieb unter 30 Prozent, Wartezeit pro Gast unter drei Minuten."

    setup do
      projekt = freibad()
      %{slug: projekt.slug, projekt: projekt}
    end

    test "GO over propose_projekt_update sets both fields", %{slug: slug, projekt: projekt} do
      assert {:reply, response, _frame} =
               ProposeProjektUpdate.execute(
                 [
                   projekt_slug: slug,
                   value_proposition: @vp,
                   success_metrics: @sm,
                   begruendung: "Messbarkeit und Problembezug für die Antragsreife nachtragen."
                 ],
                 Frame.new()
               )

      refute response.isError

      [%{"type" => "text", "text" => json}] = response.content
      body = Jason.decode!(json)

      proposal = Repo.get!(PendingProposal, body["id"])

      assert {:reply, go_response, _frame} =
               DecideProposal.execute(
                 [proposal_id: proposal.id, aktion: "accept", kommentar: "GO im Chat"],
                 Frame.new()
               )

      refute go_response.isError

      reloaded = Repo.get!(Projekt, projekt.id)
      assert reloaded.value_proposition == @vp
      assert reloaded.success_metrics == @sm
    end
  end

  # --- Helpers ---

  defp gate_status(slug, kriterium) do
    assert {:reply, response, _frame} =
             CheckAntragsreife.execute(%{slug: slug, stufe: "stadtrat"}, Frame.new())

    refute response.isError

    [%{"type" => "text", "text" => json}] = response.content
    body = Jason.decode!(json)

    gate =
      Enum.find(body["hard_gates"], &(&1["kriterium"] == Atom.to_string(kriterium))) ||
        flunk("Hard Gate #{kriterium} fehlt im Report")

    {gate["status"], gate["detail"]}
  end

  defp error_text(response) do
    [%{"type" => "text", "text" => text}] = response.content
    text
  end
end
