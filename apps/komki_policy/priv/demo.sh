#!/usr/bin/env bash
# Demo: komki-policy — Abnahme der Kernpfade (CONTRACT.md § 7/§ 8).
#
# Baut den Escript und führt decide/verify über die Repository-Fixtures aus:
# permit, deny, indeterminate, unsupported (Exit 3) sowie verify valid (Exit 0)
# und verworfen (Exit 1). Jede Abweichung vom erwarteten Exit-Code bricht laut ab.
#
# Läuft von überall; arbeitet im App-Verzeichnis mit relativen Pfaden.
# Nur synthetische Fixtures, keine produktiven Daten.

set -euo pipefail

cd "$(cd "$(dirname "$0")/.." && pwd)"

echo "== 0. Build: mix escript.build =="
mix escript.build > /dev/null
echo "escript ./komki-policy gebaut."

registry="priv/fixtures/registry.json"
fix="priv/fixtures"

run_check() {
  local title="$1" expected="$2"
  shift 2

  printf '\n== %s (erwarteter Exit-Code: %s) ==\n' "$title" "$expected"

  set +e
  output="$(./komki-policy "$@" 2>&1)"
  code=$?
  set -e

  printf '%s\n' "$output"
  if [ "$code" -ne "$expected" ]; then
    printf '\nFEHLER: "%s" endete mit %d, erwartet %d\n' "$title" "$code" "$expected" >&2
    exit 1
  fi
  printf '\n-- Exit %d (OK)\n' "$code"
}

run_check "decide case_permit (permit)"      0 decide --registry "$registry" --snapshot "$fix/case_permit/snapshot.json"        --intent "$fix/case_permit/intent.json"
run_check "decide case_deny (deny)"          0 decide --registry "$registry" --snapshot "$fix/case_deny/snapshot.json"         --intent "$fix/case_deny/intent.json"
run_check "decide case_indeterminate"        0 decide --registry "$registry" --snapshot "$fix/case_indeterminate/snapshot.json" --intent "$fix/case_indeterminate/intent.json"
run_check "decide case_unsupported (Exit 3)" 3 decide --registry "$registry" --snapshot "$fix/case_unsupported/snapshot.json"  --intent "$fix/case_unsupported/intent.json"
run_check "decide case_quarantine (deny, Quarantäne)" 0 decide --registry "$registry" --snapshot "$fix/case_quarantine/snapshot.json" --intent "$fix/case_quarantine/intent.json"
run_check "verify case_permit/proof_valid (valid)" 0 verify --registry "$registry" --snapshot "$fix/case_permit/snapshot.json" --intent "$fix/case_permit/intent.json" --proof "$fix/case_permit/proof_valid.json"
run_check "verify case_deny/proof_false_condition (verworfen)" 1 verify --registry "$registry" --snapshot "$fix/case_deny/snapshot.json" --intent "$fix/case_deny/intent.json" --proof "$fix/proofs/proof_false_condition.json"
run_check "verify proofs/proof_missing_binding_condition (unvollständiger Beweis verworfen)" 1 verify --registry "$registry" --snapshot "$fix/case_permit/snapshot.json" --intent "$fix/case_permit/intent.json" --proof "$fix/proofs/proof_missing_binding_condition.json"

printf '\n== Alle erwarteten Exit-Codes beobachtet. Demo erfolgreich. ==\n'
