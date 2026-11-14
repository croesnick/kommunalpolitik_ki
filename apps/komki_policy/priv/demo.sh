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
run_check "decide case_emit_permit (permit, emit)" 0 decide --registry "$registry" --snapshot "$fix/case_emit_permit/snapshot.json" --intent "$fix/case_emit_permit/intent.json"
run_check "decide case_emit_deny_purpose (deny mit remedy-Katalog)" 0 decide --registry "$registry" --snapshot "$fix/case_emit_deny_purpose/snapshot.json" --intent "$fix/case_emit_deny_purpose/intent.json"
run_check "decide Freigabe-Zweig case_release_permit (permit mit release-Objekt)" 0 decide --registry "$registry" --snapshot "$fix/case_release_permit/snapshot.json" --intent "$fix/case_release_permit/intent.json" --release "$fix/case_release_permit/release.json" --stand "$fix/case_release_permit/stand.json"
run_check "decide --release ohne --stand (usage, Exit 2)" 2 decide --registry "$registry" --snapshot "$fix/case_release_permit/snapshot.json" --intent "$fix/case_release_permit/intent.json" --release "$fix/case_release_permit/release.json"
run_check "verify case_permit/proof_valid (valid)" 0 verify --registry "$registry" --snapshot "$fix/case_permit/snapshot.json" --intent "$fix/case_permit/intent.json" --proof "$fix/case_permit/proof_valid.json"
run_check "verify proofs/proof_emit_valid (valid, emit)" 0 verify --registry "$registry" --snapshot "$fix/case_emit_permit/snapshot.json" --intent "$fix/case_emit_permit/intent.json" --proof "$fix/proofs/proof_emit_valid.json"
run_check "verify case_deny/proof_false_condition (verworfen)" 1 verify --registry "$registry" --snapshot "$fix/case_deny/snapshot.json" --intent "$fix/case_deny/intent.json" --proof "$fix/proofs/proof_false_condition.json"
run_check "verify proofs/proof_missing_binding_condition (unvollständiger Beweis verworfen)" 1 verify --registry "$registry" --snapshot "$fix/case_permit/snapshot.json" --intent "$fix/case_permit/intent.json" --proof "$fix/proofs/proof_missing_binding_condition.json"

# advance: Verbrauchs-Vorschlag aus der Freigabe-Permit-Decision extrahieren
# (release-Objekt als eigenständige Datei, CONTRACT § 7) und zweimal committen.
# Fallback /tmp: TMPDIR ist auf Linux-Runnern nicht gesetzt (macOS immer; set -u).
work_dir="${TMPDIR:-/tmp}"
proposal="$work_dir/komki-policy-advance-proposal.json"
stand_next="$work_dir/komki-policy-stand-next.json"

./komki-policy decide --registry "$registry" --snapshot "$fix/case_release_permit/snapshot.json" \
  --intent "$fix/case_release_permit/intent.json" \
  --release "$fix/case_release_permit/release.json" \
  --stand "$fix/case_release_permit/stand.json" > "$work_dir/komki-policy-release-decision.json"

# Elixir-first: Extraktion im Familien-Stack (Elixir-stdlib-JSON), kein python3.
elixir -e 'File.write!(Enum.fetch!(System.argv, 1), JSON.encode!(Map.fetch!(JSON.decode!(File.read!(Enum.fetch!(System.argv, 0))), "release")))' \
  "$work_dir/komki-policy-release-decision.json" "$proposal"

# advance: erster Commit des GOs; das Ergebnis (neuer Stand) wird Vollzug
# und Grundlage des CAS-Gegenversuchs.
printf '\n== advance: erster Commit des GOs (erwarteter Exit-Code: 0) ==\n'
set +e
first_out="$(./komki-policy advance --stand "$fix/case_release_permit/stand.json" --proposal "$proposal")"
first_code=$?
set -e
printf '%s\n' "$first_out"

if [ "$first_code" -ne 0 ]; then
  printf 'FEHLER: erster advance endete mit %d, erwartet 0\n' "$first_code" >&2
  exit 1
fi
printf '%s' "$first_out" > "$stand_next"
printf '\n-- Exit 0 (OK)\n'

printf '\n== advance CAS: derselbe GO-Vorschlag gegen den fortgeschriebenen Stand (erwarteter Exit-Code: 1) ==\n'
run_check "advance: zweiter Commit gegen stand@v+1 (refused)" 1 advance --stand "$stand_next" --proposal "$proposal"

printf '\n== Alle erwarteten Exit-Codes beobachtet. Demo erfolgreich. ==\n'
