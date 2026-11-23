# PROTOTYPE (throwaway): the RFC 0003 calculus in Lean 4

Not part of komki and not on `main`. It lives on the branch
`prototype/lean-kalkuel` as a primary source for the verdict below.

**Question:** Do Γ, labels and recipient sets model naturally in Lean, and
does an executable checker connect to the Prop-level spec?

**Answer:** Yes to both. Details below.

## Run

```sh
curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
  | ELAN_HOME=~/.cache/elan sh -s -- -y --default-toolchain leanprover/lean4:v4.35.0 --no-modify-path
./run.sh   # checks every proof, then prints the D.1 demo and the axioms used
```

`rm -rf ~/.cache/elan` removes the toolchain again (2.8 GB).

## What is proven

| File | Content | RFC |
|---|---|---|
| `KomkiKalkuel/Calculus.lean` | R_Γ(L), Erlaubt, both halves of monotonicity, V_o downward closed, preservation along paths, no forbidden recipient without Lockerung | R.5.1, R.5.2, A.2, A.3, A.5 (lemma) |
| `KomkiKalkuel/Evaluator.lean` | three-valued B.4 evaluator; more facts never flip a known verdict | CONTRACT.md § 3, R.5.2 |
| `KomkiKalkuel/Engine.lean` | executable `allowed_recipients` = R_Γ(L) on a well-formed registry; `admit = permit` implies the Aufnahme rule | R.5.4, a miniature A.7 |
| `Demo.lean` | D.1 through the engine: deny; the λ(x)-only engine: permit; positive control, missing fact, cloud recipient | D.1 |

No `sorry`. `#print axioms`: the A.2/A.3 theorems use no axioms at all; the
evaluator and engine theorems use only `propext` and `Quot.sound`.

## Findings

1. **The calculus maps one to one.** Predicate sets without Mathlib are
   enough. A.2 and the core of A.3 are a few lines each. Calculus and
   evaluator compiled on the first attempt, including the termination
   proof for the nested `all`/`any`. The engine needed one real fix (a
   `nomatch` parse and an over-eager `simp only`), none about the model.
2. **The proof bites.** A mutant `admit` that checks recipients and
   conditions against λ(x) instead of B_W (the broken engine D.1 warns
   about) fails `admit_sound` at exactly those two subgoals.
3. **Lean made three implicit rules explicit.**
   - R.5.2 "a predicate must not depend on which other bindings are
     checked" becomes a type: `condition : B → Prop`. A.2 rests on it.
   - The Elixir formula equals the RFC's R_Γ(L) only if every binding's
     readers lie in 𝒪. `registry.ex` enforces that (`subset_observers` on
     `readers`); the demo shows what the formula returns without it. By
     hand, not proven here: the admit decision would stay correct even
     then, because environment observers are also checked against 𝒪.
   - Ill-typed facts: Elixir crashes (`subset`) or compares by term order
     (`at_most`); both are unreachable because `context.ex` types facts.
     Lean demands a total answer (here: `false`). A differential test must
     either type facts in Lean or keep ill-typed facts out of its generator.
4. **Costs.** 2.8 GB toolchain, builds in under two seconds, no Mathlib.
   Lemma names move between Lean releases (`if_pos` is deprecated in
   v4.35.0), so a permanent spec needs a pinned toolchain and occasional
   upkeep.

## Not answered here

- The full step model for A.3/A.4 (rooms, objects, events), not just labels.
- `verify` and proof trees (`komki-proof/1`), the part where the audit found
  forged trees (#477, #479, #480).
- The bridge to the Elixir code: differential random testing against the
  compiled Lean checker, as cedar-spec does.

## Simplifications

`admit` here leaves out `not_quarantine` and `workspace_contract_valid`;
a false `environment_observers_complete` denies instead of yielding
`unknown` (CONTRACT.md § 4.3, premise 6). `P_b(c)` is defined through the
evaluator, so `admit_sound` shows that the engine assembles the premises
correctly, not that the evaluator matches the intended B.4 semantics;
`eval_mono` is the independent property of the evaluator.
