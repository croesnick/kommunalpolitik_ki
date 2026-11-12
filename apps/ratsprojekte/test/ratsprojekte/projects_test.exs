defmodule Ratsprojekte.ProjectsTest do
  use Ratsprojekte.DataCase, async: false

  alias Ratsprojekte.Projects

  @on ~D[2026-11-03]

  defp idea(attrs \\ %{}) do
    {:ok, project} =
      Projects.create_project(
        Map.merge(
          %{
            title: "Sitzbänke am Stadtweiher",
            short: "Bänke für Ältere",
            origin: "Seniorenbeirat",
            on: @on
          },
          attrs
        )
      )

    project
  end

  defp lines(project), do: Enum.map(project.timeline, &{&1.kind, &1.text, &1.in_briefing})

  describe "create_project/1" do
    test "starts as an idea with its own first line and a slug from the title" do
      project = idea()

      assert project.slug == "sitzbaenke-am-stadtweiher"
      assert project.phase == :idea
      assert lines(project) == [{:created, "Idee aufgenommen", true}]
      assert hd(project.timeline).on == @on
    end

    test "a taken short name gets a number, a chosen one stays" do
      idea()
      assert Projects.suggest_slug("Sitzbänke am Stadtweiher") == "sitzbaenke-am-stadtweiher-2"
      assert idea(%{slug: "baenke"}).slug == "baenke"
    end

    test "refuses a malformed or taken short name" do
      idea()
      assert {:error, cs} = Projects.create_project(%{title: "X", slug: "Nicht Gültig"})
      assert %{slug: [_]} = errors_on(cs)

      assert {:error, cs} =
               Projects.create_project(%{title: "Y", slug: "sitzbaenke-am-stadtweiher"})

      assert %{slug: ["ist schon vergeben"]} = errors_on(cs)
    end

    test "removes invisible characters before saving" do
      project = idea(%{title: "Sitz\u{200B}bänke\u{202E}", short: "a\u{E0041}b"})
      assert project.title == "Sitzbänke"
      assert project.short == "ab"
    end
  end

  describe "record_event/2, the main flow" do
    test "only the text is required" do
      assert {:error, cs} = Projects.record_event(idea(), %{text: "  \u{200B} "})
      assert %{text: ["can't be blank"]} = errors_on(cs)
    end

    test "a private note stays out of the briefing" do
      {:ok, project} = Projects.record_event(idea(), %{text: "Telefonat", by: :editor, on: @on})

      assert {:note, "Telefonat", false} in lines(project)
      assert project.opinions == []
    end

    test "a circle that spoke becomes an opinion of that circle" do
      {:ok, project} =
        Projects.record_event(idea(), %{text: "Vorstand ist dafür", by: "board", on: @on})

      assert {:opinion, "Vorstand ist dafür", true} in lines(project)
      assert [%{circle: :board, statement: "Vorstand ist dafür", on: @on}] = project.opinions
    end

    test "what a circle said privately is no opinion" do
      {:ok, project} =
        Projects.record_event(idea(), %{
          text: "Selin unter vier Augen",
          by: "fraction",
          in_briefing: false
        })

      assert {:note, "Selin unter vier Augen", false} in lines(project)
      assert project.opinions == []
    end

    test "carries phase and next step along in one step" do
      {:ok, project} =
        Projects.record_event(idea(), %{
          "text" => "Fraktion will weiter ausarbeiten",
          "by" => "fraction",
          "in_briefing" => "true",
          "phase" => "drafting",
          "step_text" => "Statik anfragen",
          "step_assignee" => "Selin",
          "step_due_on" => "2026-11-24",
          "on" => "2026-11-03"
        })

      assert project.phase == :drafting
      assert project.next_step.text == "Statik anfragen"
      assert project.next_step.due_on == ~D[2026-11-24]

      assert {:decision, "Idee → Ausarbeitung: Fraktion will weiter ausarbeiten", true} in lines(
               project
             )

      assert {:next_step, "Als Nächstes: Statik anfragen, Selin, bis 24.11.2026", true} in lines(
               project
             )

      assert [%{circle: :fraction}] = project.opinions
    end

    test "a phase change is always in the briefing" do
      {:ok, project} =
        Projects.record_event(idea(), %{
          text: "verschoben",
          phase: :opinion_forming,
          in_briefing: false
        })

      assert {:decision, "Idee → Meinungsbildung: verschoben", true} in lines(project)
    end

    test "phases change freely, also backwards" do
      {:ok, project} = Projects.record_event(idea(), %{text: "vor", phase: :at_council})
      {:ok, project} = Projects.record_event(project, %{text: "zurück", phase: :idea})

      assert project.phase == :idea
      assert {:decision, "Im Rat → Idee: zurück", true} in lines(project)
    end

    test "unchanged step fields write no line, an empty step text removes the step" do
      {:ok, project} = Projects.set_next_step(idea(), %{text: "Ortstermin", assignee: "ich"})
      count = length(project.timeline)

      {:ok, project} =
        Projects.record_event(project, %{
          text: "nichts Neues",
          step_text: "Ortstermin",
          step_assignee: "ich"
        })

      assert length(project.timeline) == count + 1

      {:ok, project} = Projects.record_event(project, %{text: "erledigt", step_text: ""})
      assert project.next_step == nil
      assert {:next_step, "Nächsten Schritt entfernt", true} in lines(project)
    end

    test "without step fields the step stays" do
      {:ok, project} = Projects.set_next_step(idea(), %{text: "Ortstermin"})
      {:ok, project} = Projects.record_event(project, %{text: "Notiz"})
      assert project.next_step.text == "Ortstermin"
    end
  end

  test "„du“ and „ich“ both mean the editor, the timeline says „du“" do
    {:ok, project} = Projects.set_next_step(idea(), %{text: "Ortstermin", assignee: "Du"})
    assert project.next_step.assignee == "ich"
    assert {:next_step, "Als Nächstes: Ortstermin, du", true} in lines(project)

    count = length(project.timeline)

    {:ok, project} =
      Projects.record_event(project, %{text: "x", step_text: "Ortstermin", step_assignee: "ich"})

    assert length(project.timeline) == count + 1
  end

  test "set_entry_visibility/3 switches notes only" do
    {:ok, project} = Projects.record_event(idea(), %{text: "privat", by: :editor})
    note = Enum.find(project.timeline, &(&1.kind == :note))
    created = Enum.find(project.timeline, &(&1.kind == :created))

    assert {:ok, project} = Projects.set_entry_visibility(project, note.id, true)
    assert {:note, "privat", true} in lines(project)
    assert {:error, :not_found} = Projects.set_entry_visibility(project, created.id, false)
  end

  test "dispose/2 and resume/2 write decisions and clear the next step" do
    {:ok, project} = Projects.set_next_step(idea(), %{text: "Ortstermin"})

    assert {:error, cs} = Projects.dispose(project, %{disposition: "resting"})
    assert %{reason: ["can't be blank"]} = errors_on(cs)

    {:ok, project} =
      Projects.dispose(project, %{
        disposition: "resting",
        reason: "Haushalt",
        by: "fraction",
        on: @on
      })

    assert project.disposition == :resting
    assert project.disposed_on == @on
    assert project.next_step == nil
    assert {:decision, "Ruht: Haushalt", true} in lines(project)

    {:ok, project} = Projects.resume(project, %{reason: "Neue Förderung", by: "board"})
    assert project.disposition == nil
    assert {:decision, "Wieder aufgenommen: Neue Förderung", true} in lines(project)
  end

  test "set_value/2 writes a line only when something changed" do
    {:ok, project} = Projects.set_value(idea(), %{proposition: "Ältere können rasten"})
    assert project.value.proposition == "Ältere können rasten"
    {:ok, same} = Projects.set_value(project, %{proposition: "Ältere können rasten"})
    assert length(same.timeline) == length(project.timeline)
    assert {:value, "Nutzen und Erfolg geändert", true} in lines(project)
  end

  test "add_fact/2 keeps citation and check status" do
    assert {:error, _} = Projects.add_fact(idea(), %{statement: "ohne Beleg"})

    {:ok, project} =
      Projects.add_fact(idea(%{slug: "f"}), %{
        statement: "Der Weiher hat 1,2 km Uferweg.",
        citation: "Grünflächenamt, Auskunft",
        fetched_on: @on,
        verified: true
      })

    assert [%{verified: true, citation: "Grünflächenamt, Auskunft"}] = project.facts
    assert {:fact, "Fakt ergänzt: Der Weiher hat 1,2 km Uferweg.", true} in lines(project)
  end

  test "variants get the next label and are chosen or rejected with a reason" do
    {:ok, project} =
      Projects.add_variant(idea(), %{
        title: "Schutzstreifen",
        prerequisites: [%{text: "Art. 46 BayStrWG", kind: "legal"}]
      })

    {:ok, project} = Projects.add_variant(project, %{title: "Einbahn"})
    assert Enum.map(project.variants, & &1.label) == ["A", "B"]
    assert [%{kind: :legal, met: false}] = hd(project.variants).prerequisites

    {:ok, project} =
      Projects.decide_variant(project, "B", %{
        status: "rejected",
        reason: "zu teuer",
        by: "fraction"
      })

    assert Enum.find(project.variants, &(&1.label == "B")).status == :rejected
    assert {:decision, "Variante B verworfen: zu teuer", true} in lines(project)
  end

  test "cross references never go into the briefing" do
    {:ok, project} = Projects.add_cross_reference(idea(), %{kind: "komki_room", target: "r-7f3a"})
    assert [%{kind: :komki_room, target: "r-7f3a"}] = project.cross_references
    assert {:cross_reference, "Querverweis ergänzt: Recherche in komki", false} in lines(project)
  end

  describe "motions" do
    test "create_motion/2 starts a draft" do
      {:ok, project} =
        Projects.create_motion(idea(), %{
          title: "Bänke am Weiher",
          motion_text: "Die Verwaltung stellt sechs Bänke auf.",
          addressee: "Stadtrat",
          document_ref: "Nextcloud/Anträge/baenke.odt"
        })

      assert [%{status: :draft, kind: :motion}] = project.motions
      assert {:motion, "Antrag „Bänke am Weiher“ begonnen", true} in lines(project)
    end

    test "record_motion_event/3 sets status and outcome with phase and next step in one step" do
      {:ok, project} = Projects.create_motion(idea(), %{title: "Bänke"})
      [motion] = project.motions

      {:ok, project} =
        Projects.record_motion_event(project, motion, %{
          "status" => "deliberated",
          "outcome" => "adopted",
          "submitted_on" => "2026-10-01",
          "ris" => "Sitzung 1003, TOP 4",
          "text" => "Stadtrat stimmt zu",
          "by" => "council",
          "phase" => "implementation",
          "step_text" => "Aufstellung nachhalten",
          "on" => "2026-11-17"
        })

      assert [%{status: :deliberated, outcome: :adopted, ris: "Sitzung 1003, TOP 4"}] =
               project.motions

      assert project.phase == :implementation
      assert {:decision, "Idee → Umsetzung: Stadtrat stimmt zu", true} in lines(project)
      assert project.next_step.text == "Aufstellung nachhalten"
      assert project.opinions == []
    end

    test "without status the motion keeps it, without a decider the line is a motion line" do
      {:ok, project} = Projects.create_motion(idea(), %{title: "Bänke"})

      {:ok, project} =
        Projects.record_motion_event(project, hd(project.motions), %{
          text: "In die Fraktion gegeben"
        })

      assert hd(project.motions).status == :draft
      assert {:motion, "In die Fraktion gegeben", true} in lines(project)
    end
  end
end
