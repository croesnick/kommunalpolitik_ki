defmodule KomkiMediator.ConnectorGateTest do
  use ExUnit.Case, async: false

  alias Anubis.Server.Frame
  alias KomkiMediator.{ConnectorGate, FakeConnector, Journal, Templates, TestHelpers, Tools}

  @recherche [
    "doc-oeffentlich@2",
    "ris-oeffentlich@1",
    "vault-oeffentlich@1",
    "web-oeffentlich@1"
  ]

  setup do
    base = TestHelpers.provisioned_base()
    dir = FakeConnector.short_dir()
    on_exit(fn -> File.rm_rf!(dir) end)

    env = TestHelpers.restart_env(base, %{connectors_dir: dir, session_id: "sess-test"})
    %{env: env, dir: dir}
  end

  defp fake(env, id, reply) do
    pid = FakeConnector.start(id, env.connectors_dir, env.journal_path, reply)
    on_exit(fn -> Process.exit(pid, :kill) end)
  end

  defp ok(result), do: fn _op, _params, _context -> {:ok, result} end

  defp records(env), do: TestHelpers.journal_records(env.journal_path)

  defp ris_hits do
    %{
      "results" => [
        %{
          "top_id" => "top-1",
          "nummer" => "3",
          "titel" => "Bahnhofstrasse",
          "sitzung" => "Stadtrat",
          "datum" => "2026-10-01",
          "url" => "https://ris.example/top-1"
        }
      ],
      "abrufdatum" => "2026-10-23"
    }
  end

  defp note(labels) do
    %{"note_id" => "a.md", "title" => "A", "content" => "geheimer Inhalt", "labels" => labels}
  end

  defp remedy_codes(response), do: Enum.map(response["remedies"], & &1["code"])

  # -----------------------------------------------------------------------
  # Permit flow: every decision journaled when made, then the record before
  # effect, then admit; one call_id (#298)
  # -----------------------------------------------------------------------

  test "recherche ris_search: Entscheidungen und Vorbeleg liegen vor dem Connector-Aufruf, dann admit",
       %{env: env} do
    fake(env, "ris", ok(ris_hits()))

    response = ConnectorGate.call(env, "ris_search", %{"text" => "Bahnhof"})

    # When called, the fake saw exactly three journal records: the emit and
    # transfer decisions and the record before effect. Default parameters
    # are set, no context for a read.
    assert_received {:connector_called, "ris", "search", %{"text" => "Bahnhof", "limit" => 10},
                     %{}, 3}

    assert response["decision"] == "permit"
    assert response["labels"] == ["ris-oeffentlich@1"]
    assert response["results"] == ris_hits()["results"]
    assert response["payload_hash"] =~ "sha256:"

    [decided, transfer, emit, admit] = records(env)

    # The emit decision itself, with the assigned λ(y) = B_W.
    assert decided["rule"] == "emit"
    assert decided["outcome"] == "permitted"
    assert decided["assigned_label"] == @recherche
    assert decided["snapshot_id"] =~ "snap-emit-"
    assert decided["call_id"] == emit["decision_id"]

    # Handover to the RIS under λ(y) = B_W, in the manifest environment.
    assert transfer["rule"] == "transfer"
    assert transfer["outcome"] == "permitted"
    assert transfer["call_id"] == emit["decision_id"]
    assert transfer["checked_label"] == @recherche
    assert transfer["snapshot_id"] =~ "snap-transfer-"
    assert transfer["intent_hash"] == emit["intent_hash"]

    assert emit["rule"] == "emit"
    assert emit["outcome"] == "emitted"
    assert emit["call_id"] == emit["decision_id"]
    assert emit["checked_label"] == @recherche
    assert emit["session_id"] == "sess-test"
    assert emit["schema"] == "komki-pdr/4"
    # The record before effect decides nothing and names the two decisions
    # it relies on (R.11).
    assert emit["decision"] == nil
    assert emit["authorized_by"] == [decided["decision_id"], transfer["decision_id"]]
    assert transfer["authorized_by"] == nil

    assert admit["rule"] == "admit"
    assert admit["outcome"] == "admitted"
    assert admit["call_id"] == emit["decision_id"]
    assert admit["decision_id"] == response["decision_id"]
    assert admit["intent_hash"] == emit["intent_hash"]
    assert admit["payload_hash"] == response["payload_hash"]
    assert response["emit_decision_id"] == emit["decision_id"]

    assert {:ok, %{records: 4}} = Journal.verify(File.read!(env.journal_path))
  end

  test "call_id im Frame ist die decision_id des Vorbelegs (emitted)", %{env: env} do
    test = self()

    fake(env, "web", fn _op, _params, _context ->
      send(test, :web_called)
      {:ok, %{"results" => [], "abrufdatum" => "2026-10-23"}}
    end)

    response = ConnectorGate.call(env, "web_search", %{"query" => "Foerderung"})
    assert_received :web_called
    assert response["labels"] == ["web-oeffentlich@1"]

    # The server side answers only if the call_id matches (the client checks
    # it); a permit therefore proves call_id == record before effect.
    [_decided, _transfer, emitted, _admit] = records(env)
    assert emitted["outcome"] == "emitted"
    assert emitted["decision"] == nil
    assert response["emit_decision_id"] == emitted["decision_id"]
  end

  # -----------------------------------------------------------------------
  # Lethal-Trifecta-Sperre: Raum vertraulich
  # -----------------------------------------------------------------------

  for {tool, id, params} <- [
        {"web_search", "web", %{"query" => "Buergerfall 4711"}},
        {"ris_search", "ris", %{"text" => "Buergerfall"}}
      ] do
    # Producing inside the room is allowed; the handover to RIS or web
    # search fails on the recipient set of vault-vertraulich (#298).
    test "vertraulich #{tool}: transfer deny recipient_not_allowed, Connector nicht gerufen",
         %{env: env} do
      fake(env, unquote(id), ok(%{}))
      env = TestHelpers.vertraulich(env)

      response = ConnectorGate.call(env, unquote(tool), unquote(Macro.escape(params)))

      assert response["decision"] == "deny"
      assert response["rule"] == "transfer"
      assert "recipient_not_allowed" in remedy_codes(response)
      # Endpunkt fuers Modell (#166)
      assert response["hinweis"] == KomkiMediator.Hinweis.text(:deny)
      refute_received {:connector_called, _, _, _, _, _}

      # The emit decision is journaled although nothing runs; the denial
      # carries the same call_id, and the answer names no record before
      # effect, because nothing was executed.
      [decided, pdr] = records(env)
      assert decided["rule"] == "emit"
      assert decided["outcome"] == "permitted"
      assert decided["assigned_label"] == env.room.workspace_bindings
      assert decided["call_id"] == pdr["call_id"]
      assert pdr["rule"] == "transfer"
      assert pdr["decision"] == "deny"
      assert is_binary(pdr["call_id"])
      refute Map.has_key?(response, "emit_decision_id")
      # The label the handover was denied under: λ(y) = B_W of the room.
      assert pdr["checked_label"] == env.room.workspace_bindings
    end
  end

  test "vertraulich vault_read: vertrauliche Notiz wird zugelassen", %{env: env} do
    fake(env, "vault", ok(note(["vault-vertraulich@1"])))
    env = TestHelpers.vertraulich(env)

    response = ConnectorGate.call(env, "vault_read", %{"note_id" => "a.md"})

    assert response["decision"] == "permit"
    assert response["content"] == "geheimer Inhalt"
    assert response["labels"] == ["vault-vertraulich@1"]
  end

  # -----------------------------------------------------------------------
  # Gate 2: Labels und Ergebnisform
  # -----------------------------------------------------------------------

  test "recherche vault_read einer vertraulichen Notiz: deny, kein Inhalt", %{env: env} do
    fake(env, "vault", ok(note(["vault-vertraulich@1"])))

    response = ConnectorGate.call(env, "vault_read", %{"note_id" => "a.md"})

    assert response["decision"] == "deny"
    assert response["rule"] == "admit"
    assert "label_not_included" in remedy_codes(response)
    refute Map.has_key?(response, "content")
    refute inspect(response) =~ "geheimer Inhalt"

    [_decided, _transfer, emit, admit] = records(env)
    assert admit["call_id"] == emit["decision_id"]
    assert admit["outcome"] == "not_admitted"
  end

  test "recherche vault_search: vertraulicher Treffer faellt still heraus (kein Orakel, L-109)",
       %{env: env} do
    hits = [
      %{"note_id" => "a.md", "title" => "A", "labels" => ["vault-oeffentlich@1"]},
      %{"note_id" => "b.md", "title" => "Geheim B", "labels" => ["vault-vertraulich@1"]}
    ]

    fake(env, "vault", ok(%{"results" => hits}))

    response = ConnectorGate.call(env, "vault_search", %{"text" => "x"})
    assert response["decision"] == "permit"
    assert Enum.map(response["results"], & &1["note_id"]) == ["a.md"]
    assert response["labels"] == ["vault-oeffentlich@1"]
    refute inspect(response) =~ "Geheim B"
  end

  test "recherche vault_search: nur vertrauliche Treffer sehen aus wie keine Treffer",
       %{env: env} do
    secret = [%{"note_id" => "b.md", "title" => "Geheim B", "labels" => ["vault-vertraulich@1"]}]
    fake(env, "vault", ok(%{"results" => secret}))
    with_secret = ConnectorGate.call(env, "vault_search", %{"text" => "x"})

    fake(env, "vault", ok(%{"results" => []}))
    without = ConnectorGate.call(env, "vault_search", %{"text" => "x"})

    keys = ["decision", "results", "labels"]
    assert Map.take(with_secret, keys) == Map.take(without, keys)
  end

  test "Fake meldet ein Label ausserhalb von Γ: redacted (#211)", %{env: env} do
    fake(env, "vault", ok(note(["gibt-es-nicht@1"])))

    response = ConnectorGate.call(env, "vault_read", %{"note_id" => "a.md"})

    assert response["admitted"] == "redacted"
    assert response["verify"] == ["label_not_in_gamma"]
    refute Map.has_key?(response, "content")

    [_decided, _transfer, _emit, admit] = records(env)
    assert admit["outcome"] == "redacted"
  end

  test "Notiz ohne Labels: redacted (fail-closed)", %{env: env} do
    fake(env, "vault", ok(note([])))

    response = ConnectorGate.call(env, "vault_read", %{"note_id" => "a.md"})
    assert response["admitted"] == "redacted"
  end

  test "RIS-Labels kommen aus dem Manifest, nicht aus der Antwort", %{env: env} do
    fake(env, "ris", ok(Map.put(ris_hits(), "labels", ["vault-vertraulich@1"])))

    # Zusatzfeld verletzt die geschlossene Ergebnisform.
    response = ConnectorGate.call(env, "ris_search", %{"text" => "x"})
    assert response["admitted"] == "redacted"
    refute Map.has_key?(response, "results")
  end

  test "Ergebnisform verletzt (fehlendes Feld, falscher Typ): redacted", %{env: env} do
    fake(env, "ris", fn
      "show", _params, _context -> {:ok, %{"top_id" => "t", "titel" => 1}}
    end)

    response = ConnectorGate.call(env, "ris_show", %{"top_id" => "t"})
    assert response["admitted"] == "redacted"
    assert response["reason"] =~ "Ergebnisform"
  end

  # -----------------------------------------------------------------------
  # Vorpruefung: Schema, B_W
  # -----------------------------------------------------------------------

  test "Schemaverstoss: error mit PDR, kein Vollzug", %{env: env} do
    fake(env, "ris", ok(%{}))

    for params <- [
          %{"top_id" => "../etc/passwd"},
          %{"top_id" => "t", "url" => "https://evil.example"},
          %{}
        ] do
      response = ConnectorGate.call(env, "ris_show", params)
      assert response["decision"] == "error"
      assert response["detail"] =~ "Parameter"
    end

    refute_received {:connector_called, _, _, _, _, _}

    pdrs = records(env)
    assert length(pdrs) == 3
    assert Enum.all?(pdrs, &(&1["decision"] == "error" and &1["rule"] == "emit"))
    # A pre-check rejection happens before there is a call: no call_id.
    assert Enum.all?(pdrs, &is_nil(&1["call_id"]))
  end

  test "Raum ohne workspace_bindings: Connector-Tools fail-closed", %{env: env} do
    fake(env, "web", ok(%{}))
    env = put_in(env.room.workspace_bindings, nil)

    response = ConnectorGate.call(env, "web_search", %{"query" => "x"})

    assert response["decision"] == "error"
    assert response["detail"] =~ "workspace_bindings"
    refute_received {:connector_called, _, _, _, _, _}
    assert [%{"decision" => "error", "admitted" => false}] = records(env)
  end

  # -----------------------------------------------------------------------
  # Connector-Fehler
  # -----------------------------------------------------------------------

  test "Connector down: admitted false mit allen Entscheidungen, Vorbeleg und admit-PDR", %{
    env: env
  } do
    response = ConnectorGate.call(env, "ris_search", %{"text" => "x"})

    assert response["decision"] == "permit"
    assert response["admitted"] == false
    assert response["error"]["code"] == "upstream-error"

    [decided, transfer, emit, admit] = records(env)
    assert decided["outcome"] == "permitted"
    assert transfer["rule"] == "transfer"
    assert emit["rule"] == "emit"
    assert admit["outcome"] == "error"
    assert admit["call_id"] == emit["decision_id"]
  end

  test "Connector meldet not-found: admitted false", %{env: env} do
    fake(env, "ris", fn _op, _params, _context -> {:error, "not-found", "FREITEXT-KANARIE"} end)

    response = ConnectorGate.call(env, "ris_show", %{"top_id" => "t"})
    assert response["admitted"] == false
    # Der Freitext des Connectors erreicht das Modell nicht, nur der feste Text.
    assert response["error"] == %{"code" => "not-found", "detail" => "nicht gefunden"}
    refute inspect(response) =~ "FREITEXT-KANARIE"
  end

  # -----------------------------------------------------------------------
  # Schreibende Operation
  # -----------------------------------------------------------------------

  # Seit #205 braucht jedes Schreiben ein GO (store ohne Regel in Γ); der
  # Weg mit GO steht in KomkiMediator.GoStoreTest.
  test "vault_write_test ohne GO: emit erlaubt, store abgelehnt, kein Vollzug", %{env: env} do
    fake(env, "vault", ok(%{"note_id" => "komki-test/x.md", "labels" => @recherche}))

    response = ConnectorGate.call(env, "vault_write_test", %{"title" => "T", "body" => "B"})

    assert response["decision"] == "deny"
    assert response["rule"] == "store"
    # Ein Blocker je Bindung in λ(y) = B_W.
    assert remedy_codes(response) == List.duplicate("missing_operation_rule", length(@recherche))

    assert %{"type" => "aktionsfreigabe", "scope" => "call"} =
             response["remedies"] |> hd() |> Map.fetch!("transitions") |> List.last()

    refute_received {:connector_called, "vault", _, _, _, _}

    [decided, store] = records(env)
    assert {decided["rule"], decided["outcome"]} == {"emit", "permitted"}
    assert store["rule"] == "store"
    assert store["decision"] == "deny"
    assert store["outcome"] == "not_admitted"
  end

  # -----------------------------------------------------------------------
  # MCP-Tool und Default-Raum
  # -----------------------------------------------------------------------

  test "MCP-Tool ris_search laeuft ueber Env und ConnectorGate", %{env: env} do
    fake(env, "ris", ok(ris_hits()))

    assert {:reply, response, _frame} =
             Tools.RisSearch.execute(%{text: "Bahnhof", limit: 3}, Frame.new())

    refute response.isError
    [%{"type" => "text", "text" => json}] = response.content
    body = JSON.decode!(json)
    assert body["decision"] == "permit"
    assert_received {:connector_called, "ris", "search", %{"limit" => 3}, _, 3}
  end

  test "Default-Raum ist recherche", %{env: env} do
    assert env.room.workspace_bindings == Templates.recherche_bindings()
    assert Templates.recherche_bindings() == @recherche
  end
end
