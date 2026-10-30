defmodule KomkiMediator.VorpruefungTest do
  # Ticket #165: Schemaverstoesse und unbekannte Felder am MCP-Eingang
  # enden als decision: error mit PDR - nicht als anubis invalid_params
  # ohne PDR und nicht als still verworfene Felder. Die Faelle aus dem
  # Ticket (count: 99, unbekanntes Feld, falscher Typ) laufen hier gegen
  # KomkiMediator.Server.handle_request/2, also gegen denselben Eingang,
  # den die Session-Schicht fuer jeden echten tools/call ruft.
  use ExUnit.Case, async: false

  alias Anubis.Server.Frame
  alias KomkiMediator.{Server, TestHelpers}

  setup do
    base = TestHelpers.provisioned_base()
    env = TestHelpers.restart_env(base)
    %{env: env}
  end

  defp call(name, arguments) do
    Server.handle_request(
      %{"method" => "tools/call", "params" => %{"name" => name, "arguments" => arguments}},
      Frame.new()
    )
  end

  defp body(%{"content" => [%{"type" => "text", "text" => json}]}), do: JSON.decode!(json)

  defp pdrs(%{journal_path: path}), do: TestHelpers.journal_records(path)

  # -----------------------------------------------------------------------
  # Zu messen / Zu verifizieren (Ticket #165)
  # -----------------------------------------------------------------------

  test "Bereichsverstoss count: 99: decision error, ein PDR", %{env: env} do
    assert {:reply, %{"isError" => false} = reply, _frame} =
             call("web_search", %{"query" => "Radweg", "count" => 99})

    assert %{"decision" => "error", "rule" => "emit", "detail" => detail} = body(reply)
    assert detail =~ "ausserhalb 1..10"

    assert [%{"tool" => "web_search", "rule" => "emit"} = pdr] = pdrs(env)
    assert pdr["decision"] == "error"
    assert pdr["outcome"] == "error"
    assert pdr["admitted"] == false
    assert pdr["intent_hash"] =~ "sha256:"
    assert pdr["decision_id"] == body(reply)["decision_id"]
  end

  test "unbekanntes Feld url: decision error, die Suche laeuft nicht", %{env: env} do
    assert {:reply, reply, _frame} =
             call("web_search", %{"query" => "Radweg", "url" => "https://example.com"})

    assert %{"decision" => "error", "detail" => detail} = body(reply)
    assert detail =~ "unbekannte Felder: url"

    # Genau ein PDR: kein emit, kein Vollzug - vorher verschwand das Feld
    # still und die Suche lief ohne es.
    assert [%{"decision" => "error", "rule" => "emit"}] = pdrs(env)
  end

  test "falscher Typ (query: 42, count: viele): decision error mit PDR", %{env: env} do
    assert {:reply, reply, _frame} = call("web_search", %{"query" => 42})

    assert %{"decision" => "error", "detail" => detail} = body(reply)
    assert detail =~ "query: erwartet string"

    # Dasselbe fuer ein Integer-Feld: falscher Typ endet auch hier vor dem Gate.
    assert {:reply, reply_count, _frame} =
             call("web_search", %{"query" => "Radweg", "count" => "viele"})

    assert %{"decision" => "error", "detail" => count_detail} = body(reply_count)
    assert count_detail =~ "count: erwartet integer"

    assert [%{"decision" => "error"}, %{"decision" => "error"}] = pdrs(env)
  end

  test "Pflichtfeld fehlt, auch ganz ohne Argumente: decision error, ein PDR", %{env: env} do
    assert {:reply, reply, _frame} = call("web_search", %{})

    assert %{"decision" => "error", "detail" => detail} = body(reply)
    assert detail =~ "Pflichtfeld fehlt: query"

    assert {:reply, reply_without_arguments, _frame} =
             Server.handle_request(
               %{"method" => "tools/call", "params" => %{"name" => "web_search"}},
               Frame.new()
             )

    assert %{"decision" => "error", "detail" => again} = body(reply_without_arguments)
    assert again =~ "Pflichtfeld fehlt: query"
    assert length(pdrs(env)) == 2
  end

  # -----------------------------------------------------------------------
  # Weitere Verstoesse am Eingang
  # -----------------------------------------------------------------------

  test "Musterverstoss top_id: decision error, ein PDR", %{env: env} do
    assert {:reply, reply, _frame} = call("ris_show", %{"top_id" => "../etc/passwd"})

    assert %{"decision" => "error", "detail" => detail} = body(reply)
    assert detail =~ "top_id: unzulaessiges Format"
    assert [%{"decision" => "error", "rule" => "emit"}] = pdrs(env)
  end

  test "Argumente ueberhaupt kein Objekt: decision error, ein PDR", %{env: env} do
    assert {:reply, reply, _frame} = call("web_search", "kein-objekt")

    assert %{"decision" => "error", "detail" => detail} = body(reply)
    assert detail =~ "Parameter muessen ein Objekt sein"
    assert [%{"decision" => "error"}] = pdrs(env)
  end

  test "ping mit Argument: jedes Feld ist unbekannt, decision error, Regel admit", %{env: env} do
    assert {:reply, reply, _frame} = call("ping", %{"foo" => 1})

    assert %{"decision" => "error", "detail" => detail} = body(reply)
    assert detail =~ "unbekannte Felder: foo"
    assert [%{"decision" => "error", "rule" => "admit", "tool" => "ping"}] = pdrs(env)
  end

  test "list_documents mit Argument: decision error, Regel admit", %{env: env} do
    assert {:reply, reply, _frame} = call("list_documents", %{"alles" => true})

    assert %{"decision" => "error", "detail" => detail} = body(reply)
    assert detail =~ "unbekannte Felder: alles"
    assert [%{"decision" => "error", "rule" => "admit"}] = pdrs(env)
  end

  test "admit_document mit unbekanntem Feld: decision error statt still verworfen", %{env: env} do
    assert {:reply, reply, _frame} =
             call("admit_document", %{"document_id" => "doc-oeffentlich", "extra" => 1})

    assert %{"decision" => "error", "detail" => detail} = body(reply)
    assert detail =~ "unbekannte Felder: extra"
    assert [%{"decision" => "error", "rule" => "admit", "tool" => "admit_document"}] = pdrs(env)
  end

  test "admit_document mit Musterverstoss: decision error, kein Vollzug", %{env: env} do
    assert {:reply, reply, _frame} = call("admit_document", %{"document_id" => "../dieb/stahl"})

    assert %{"decision" => "error", "detail" => detail} = body(reply)
    assert detail =~ "document_id: unzulaessiges Format"
    assert [%{"decision" => "error", "rule" => "admit"}] = pdrs(env)
  end

  # -----------------------------------------------------------------------
  # Grenzen der Vorpruefung
  # -----------------------------------------------------------------------

  test "unbekannter Tool-Name: anubis antwortet Tool not found, ohne PDR", %{env: env} do
    assert {:error, %Anubis.MCP.Error{}, _frame} = call("gibt_es_nicht", %{"query" => "x"})
    assert [] = pdrs(env)
  end

  # Regressionssicherung der Klauselkopf-Haertung: params, die kein Objekt
  # mit `name` sind, faellt die Vorpruefung nicht an (kein PDR, kein
  # Abfangen) - anubis scheitert daran wie vor Ticket #165.
  test "unparsable params (Liste): kein Abfangen durch die Vorpruefung, kein PDR", %{env: env} do
    assert_raise FunctionClauseError, fn ->
      Server.handle_request(%{"method" => "tools/call", "params" => ["x"]}, Frame.new())
    end

    assert [] = pdrs(env)
  end

  # -----------------------------------------------------------------------
  # Bestandene Aufrufe: der Fluss bleibt unveraendert
  # -----------------------------------------------------------------------

  test "gueltiges ris_search: permit, emit und admit wie im Connector-Gate", %{env: env} do
    # Kein Connector-Verzeichnis: emit-PDR, dann Connector-Fehler (Muster
    # wie der Connector-down-Fall im ConnectorGate-Test).
    assert {:reply, reply, _frame} = call("ris_search", %{"text" => "Radweg"})

    assert %{"decision" => "permit", "admitted" => false} = body(reply)

    assert [%{"rule" => "emit", "outcome" => "emitted"}, %{"outcome" => "error"}] = pdrs(env)
  end

  test "gueltiges ping ohne Argumente: permit, zwei PDR", %{env: env} do
    assert {:reply, reply, _frame} = call("ping", %{})

    assert %{"decision" => "permit"} = body(reply)

    assert [%{"outcome" => "executing"}, %{"outcome" => "admitted"}] = pdrs(env)
  end
end
