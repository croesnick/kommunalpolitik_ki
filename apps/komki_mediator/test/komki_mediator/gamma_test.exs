defmodule KomkiMediator.GammaTest do
  use ExUnit.Case, async: true

  alias KomkiMediator.{Gamma, Hash}
  alias KomkiPolicy.JSON

  setup do
    %{base: KomkiMediator.TestHelpers.provisioned_base()}
  end

  test "laedt aus der provisionierten Vorlage: registry_id und gamma_hash", %{base: base} do
    {:ok, gamma} = Gamma.load(Path.join([base, "mediator", "registry.json"]))

    assert gamma.registry_id == "reg-komki-arbeitsraum"
    assert gamma.gamma_hash == "sha256:" <> String.slice(gamma.gamma_hash, 7, 64)
    assert byte_size(gamma.gamma_hash) == 7 + 64
  end

  test "gamma_hash ist byte-stabil ueber zwei Laeufe (kanonische Bytes)", %{base: base} do
    path = Path.join([base, "mediator", "registry.json"])
    {:ok, first} = Gamma.load(path)
    {:ok, second} = Gamma.load(path)

    assert first.gamma_hash == second.gamma_hash
    assert Hash.sha256_hex(JSON.canonical(first.term)) == first.gamma_hash
  end

  test "malformed JSON faellt in einen strukturierten Parse-Fehler", %{base: base} do
    path = Path.join([base, "mediator", "registry-broken.json"])
    File.write!(path, "{definitely not json")

    assert {:error, {:gamma_parse, %{code: code}}} = Gamma.load(path)

    assert is_atom(code)
  end

  test "fehlende Quellendatei muendet in Read-Fehler", %{base: base} do
    path = Path.join([base, "mediator", "existiert-nicht.json"])

    assert {:error, {:gamma_read, :enoent}} = Gamma.load(path)
  end

  # Relaxationsbefugnisse stehen nur im rohen Registry-Term; der Zugriff
  # laeuft als Oeffnung ueber Gamma statt als Grab im Term fremden Modulen.
  test "relaxation_authorities liest die Befugnis aus dem rohen Registry-Term", %{base: base} do
    {:ok, gamma} = Gamma.load(Path.join([base, "mediator", "registry.json"]))

    assert Gamma.relaxation_authorities(gamma, "doc-pending-freigabe@1") == ["nutzende-person"]
  end

  test "relaxation_authorities faellt fuer Bindung ohne Befugnis auf die leere Liste", %{
    base: base
  } do
    {:ok, gamma} = Gamma.load(Path.join([base, "mediator", "registry.json"]))

    assert Gamma.relaxation_authorities(gamma, "doc-oeffentlich@1") == []
  end

  test "relaxation_authorities faellt fuer unbekannte Bindung auf die leere Liste", %{base: base} do
    {:ok, gamma} = Gamma.load(Path.join([base, "mediator", "registry.json"]))

    assert Gamma.relaxation_authorities(gamma, "gibt-es-nicht@1") == []
  end
end
