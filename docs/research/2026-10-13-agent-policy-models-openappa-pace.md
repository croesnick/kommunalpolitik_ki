# Agent policy models: OpenAPPA (APPA) and PACE, dissected against RFC 0003

Stand: 13.10.2026. Multi-Lane-Recherche: OpenAPPA-Dokumentation und Paper (arXiv 2607.24625), PACE-Paper (arXiv 2608.17220), Volllektüre von RFC 0003, auf Glaubwürdigkeit gefilterter Scan der umliegenden Policy-Modelle, Code-Inspektion von `apps/komki_policy` und `apps/komki_cli`. Bericht auf Englisch (Vorgabe der nutzenden Person). Die kanonischen deutschen Begriffe des RFC bleiben unübersetzt. Alle Quellen am Abrufdatum geprüft. Jede Zahl geht auf eine genannte Primärquelle zurück oder ist ausdrücklich als unverifiziert markiert.

## Summary

Two papers from 2026, found independently, describe the two halves of RFC 0003's machinery. Neither cites the other, and neither cites the shared lineage of agent information-flow work (CaMeL, Fides, MCP). Both stop at exactly the places where the RFC already has state built.

**OpenAPPA (APPA)** is the strongest existing formalization of the RFC's enforcement half: the Vermittler (mediator), the label calculus, and, beyond the RFC, a formalized recovery semantics for blocked operations. Its landing-page claim of "100% resistant to data exfiltration" overstates its own paper, which states zero *observed* attacks under *evaluated policies* and admits that finite zero-ASR observations do not prove attacks impossible.

**PACE** is the strongest existing instantiation of the RFC's execution half: the Ausführer discipline of Anhang B.8, commit-before-effect, replay protection, and payload binding, all enforced cryptographically on the blockchain, where the agent cannot reach them. It contains no confidentiality component at all. The words "taint", "confidential", and "information flow" do not appear in the paper.

Both converge on the architecture RFC 0003 specifies as a whole: an untrusted proposer, a deterministic decider outside the model, typed intent objects, decisions bound to the exact effect, versioned rules, replay protection, and commit before effect. For the RFC this is the strongest external validation it could receive. Two independent research streams arrived at its design in the same year.

The surrounding source scan adds a fourth finding. Every single RFC component now has at least one credible external anchor (mediator: Fides, recovery: APPA, execution binding: PACE, purpose conditions: PBAC, releases: Prudentia and Dogwood, disclosure ledger: GAAP and Gradual Release, audit schema: PROV, formal policy verification: Cedar). The combination exists nowhere else. RFC 0003 is redundant in no part and confirmed as a whole.

## OpenAPPA (APPA)

### What it is

The paper and its algebra are called APPA ("Agentic Permissions Policy Algebra", arXiv 2607.24625v2, Archestra AI, all-industry author team). The product that implements them is called OpenAPPA (MIT-licensed, repository created 2026-08-18, about 1,556 stars at retrieval). APPA is a deterministic information-flow guardrail for AI agents. Its one-line thesis is also its architecture: *you cannot prompt-inject an algebra*. A security label is a pair L = (R, t) in a finite product lattice P(U) × T, where R is the set of authorized readers (audience) and t is a position on a totally ordered trust chain, default `suspicious < trusted`. Labels combine by component-wise meet: readers intersect, and trust takes the minimum. Labels descend monotonically. Everything the agent has read constrains everything it can later do, structurally rather than behaviorally.

Enforcement is a dual-phase reference monitor outside the agent loop. Gate 1 checks every tool call before dispatch against the label the call would produce, c_τ(L) = L ∧ d_τ. Gate 2 re-verifies the realized return before it enters the model's context. The LLM is entirely policy-untrusted. It may propose anything, but it cannot manufacture authorization.

### What it can do

- **Provable label flow.** Propositions 1 (collapse: folds compose to a running meet) and 2 (monotone descent with settlement on the finite lattice) are real theorems, as are no-laundering for casts, necessity of prospective evaluation for composite read-and-send tools (Prop 4, with a concrete witness), read-based repair (Th 5), no unruled inadequate release (Th 6), recovery containment (Cor 7), and branch taint confinement (Th 8).
- **Call-scoped authority.** A blocked call can be approved by an external authority bound to the exact rendered call hash, atomically, single-use, and mandate-bounded. The trajectory label stays untouched. No privilege lingers, and model tokens cannot forge a ruling.
- **Sanitizers as registered trusted transformations.** Stock redactors, custom, or model-based, each pinned by permitted label transitions and a tool scope. Their output is a new object with the permitted label, not a de-labeling of the old one.
- **Recovery instead of refusal.** A blocked call returns remedy plans from a finite recovery graph over exactly four trusted transition types (effect commit, authority ruling, sanitizer or cast, child branch). The ablation shows where the value is: removing remedy plans drops task completion from 88% to 35% at zero attack success. Utility comes from recovery, not from blocking alone.
- **Subagent confinement.** Forks seed the child with the parent's label. Pending rulings do not cross the boundary in either direction. Exits go through `attest-schema`, a shape-bounded channel (booleans, bounded integers, closed enums, no free text). The paper is blunt about the limit: *a malicious child can still select an allowed false value*.
- **Gradual typing for unannotated tools.** Unknown contributions flow lazily as partial labels until a consuming check forces resolution through a registered cast with a declared ceiling. Otherwise the check fails closed.

The evaluation runs 6,600 episodes over AgentThreatBench (24 OWASP-derived tasks) and Bench-Corp (20 self-built enterprise scenarios), with three models, five seeds, and standard and chaos profiles, over live attack fixtures. Unguarded controls show 40.0 to 69.2% attack success, so the guarded zero is not inertness. Zero observed attacks across 1,320 guarded episodes. Utility is 64.2 to 76.7% on AgentThreatBench and 87 to 91% on Bench-Corp.

### What it cannot do

OpenAPPA's own documentation lists the gaps, which is more than most vendors do:

- Inference is not checked. The model provider sees the full prompt, including everything the agent ever ingested. Mediation happens only at the tool boundary. Provider-side tools get static label deltas and no gating.
- Hook deployments have documented bypass surface. `disableAllHooks` disables enforcement. Native reads of project instructions and memory skip tools. Backgrounded sessions run unprotected. The loopback hook endpoint is unauthenticated. A pre-binding shell copy or move carries no label. *Claude Code is not confined*.
- File-level taint tracking is experimental and, per the docs, *not yet a supported security boundary*.
- Effects are recorded as reported to the monitor. Exactly-once properties hold against the world only with outcome reconciliation or idempotency keys at the tool boundary.

Structurally absent against RFC 0003: no purpose concept and no workspace admission contract. Labels fold per tool call. There is no B_W fixed at start, and no admission rule that checks all room bindings including purpose conditions. The regression case D.1 of the RFC would pass under APPA. In that case, a public file with an empty label fails admission because the case binding's scope condition is false, but "belongs to approved case scope" is neither a reader set nor a trust rank, so the condition has no place in P(U) × T. Also absent: an observer model of the processing path (logs, sync, backups, and provider retention, which are the core of R.3), events as wholes (existence, ordering, and selection between separately approved events), a cumulative disclosure ledger, composition-leak detection, tamper-evident audit with a verifier, quarantine with human first classification, and any noninterference claim, which the paper explicitly declines (*an authorized-and-audited release guarantee … not general noninterference*).

The trust model has its own caveat. Membership is resolved via external directory services that the system trusts but does not verify. A member account an attacker controls is outside the model.

### Where it meets RFC 0003

| RFC 0003 | OpenAPPA | Befund |
|---|---|---|
| Vermittler, judgment separated from execution (§7, R.4.4) | dual-phase reference monitor, invisible to the model | Strong. APPA proves the pre-dispatch necessity (Prop 4) that the RFC postulates in R.4.3 |
| λ labels, Bindungen, set algebra (R.2, R.5.1) | audience × trust lattice, fold | Same monotone spirit. The RFC fixes B_W at start and checks purpose on admission. APPA folds per call |
| Empfängerkreis R_b, intersection R_Γ(L) | reader set R, meet | Structurally near-identical. The RFC resolves observer contexts on the path (ρ_Γ(c)). APPA only addresses identities |
| Aktionsfreigabe (R.6.1) | authority ruling, call-scoped, hash-bound | Strong and more tightly engineered. But approvers may be LLMs, and the approver deliberately does not see the trajectory label |
| Offenlegungsfreigabe, Offenlegungsstand, Reservierung/Verbrauch (R.6.2, R.6.3) | — | Break. No cumulative disclosure state, no composition-leak detection |
| Quarantäne with human Erstklassifikation (R.2.5) | automatic taint on ingest | Break. Classification as a governance act does not exist |
| Agentendelegation (R.7 table) | fork, label inheritance, attest-schema | Good with a difference. APPA children never start less bound. The RFC allows deliberately lighter target rooms for released intermediates |
| Ereignisse: Existenz, Reihenfolge, Auswahl (§6, R.4.2) | effects for gating only | Partial. No output-side event discipline between approved events |
| Audit-Journal, three event types, verifier (R.11, Anhang F) | SQLite log, OTEL, digests | Break. No hash chain, no signatures, no verifier. *Telemetry is not a durable audit log* |
| Γ versioned rule stands | policy pinned per trajectory | Partial. Pinning is not versioned, historically reconstructible rule state |
| Nichtinterferenz A.5/A.6 | explicitly not claimed | RFC-only |

### Evidence quality

The formal work is solid and honest about its trusted-computing-base assumptions, and the theorems are the right theorems for this design. The empirical hygiene is unusually good (no episode swapping, ablations, authorization-control experiments, live attack controls). Three qualifications:

1. The website markets what the paper qualifies. "100% resistant", "89% task completion" (that number is Bench-Corp only. AgentThreatBench is 64.2 to 76.7%), and the Fides comparison (41% and 31%) are website claims. The paper says the evaluated Fides baselines are two policy mappings the authors wrote themselves, and that the results concern those configurations. APPA even loses the Memory-Poisoning subset to its baseline with every model. The auto-mode comparison prominent on the site is not in the paper at all.
2. The NeurIPS-acceptance badge is website-only. The paper text contains no venue statement, and the acceptance could not be verified against an official program. Treat the badge with caution when citing.
3. Spec and reference implementation live with one company that also sells the Archestra platform. The authors' own broader-impact line is the correct closing quote: *use APPA as one defense-in-depth layer*.

## PACE

### What it is

PACE ("Policy-Attested Contract Execution for Safe AI Agents in Decentralized Finance", arXiv 2608.17220v1, 18 Aug 2026, under review, University of Houston and PayPal, anonymized artifact to be open-sourced on acceptance, CC BY-NC-ND). Lead author Rabimba Karanjai works on TEE and blockchain security (Dan E. Wells dissertation award) and is a Staff Agentic AI Researcher at PayPal. The lineage PACE claims is Alqithami et al. (arXiv 2601.04583, Jan 2026), which proposed a Transaction Intent Schema and a Policy Decision Record as a roadmap. PACE claims the first evaluated, on-chain-enforced instantiation of that roadmap, verified against the source.

Thesis, verbatim: *the safety of an agent's action need not depend on the trustworthiness of the model that proposed it: if every action is reduced to an explicit, typed object, checked by a deterministic procedure that never consults the model, and the decision is cryptographically bound to that action and re-verified at execution, then even a fully compromised LLM cannot cause a policy-violating transaction to settle.*

Three layers. A typed `TransactionIntent` with deterministic canonical JSON, a `hash_intent`, and a separate `calldata_hash`. A `PolicyVerifier` (*a pure, stateless function that neither accesses the network nor consults the LLM*) that checks a declarative `UserPolicy` (allowlists, spend caps, slippage bounds, blocked selectors, rejection of unlimited approvals, simulation freshness, post-state thresholds, and intent-hash equality). And a signed PDR (Policy Decision Record) plus an on-chain smart account whose `executePDR` validates a 12-field keccak256 digest (policyHash, intentHash, simulationHash, calldataHash, chainId, account, target, value, nonce, validAfter, validUntil, simulationBlock) before executing. The LLM proposes, the verifier disposes, the chain enforces.

### What it can do

- **Bind an approval to the exact bytes, twice.** Off-chain intent-hash equality is the decisive check against post-simulation calldata mutation, which the SimGuard baseline misses in the worked example. On-chain keccak calldata binding is re-verified where the transaction executes.
- **Commit before effect, atomically.** The nonce is consumed before the external call (checks-effects-interactions). On the EVM, the property the RFC calls its hardest implementation duty (Anhang F.5: *eine zu implementierende Protokolleigenschaft, keine automatisch vorhandene verteilte Transaktion*) comes for free.
- **Scope honestly.** *Pace targets soundness … It makes no completeness claim—whether the policy captures every unsafe outcome is the author's responsibility.* This is the same boundary as R.1.2, where fachliche Richtigkeit lies outside the calculus.
- **The field-provenance rule (§4.6) is the most useful single lesson in the paper.** Typed fields must be *reconstructed … from decoded calldata and the simulation trace using trusted code, never trusting the LLM-supplied fields*. That rule is R.2 and B.2 of the RFC ("Sicherheitsangaben aus Agentenargumenten ungeprüft übernehmen" is forbidden) made concrete and enforceable.
- **Run an unusually honest evaluation.** The ablation's own headline reads *Pace's safety rests on the policy values a deployer chooses*. The permissive-policy variant accounts for +57.5 percentage points of unsafe executions, more than every mechanism combined. The mainnet-fork section is an explicit no-claims-without-RPC placeholder. Zero variance is explained as a consequence of deterministic verification, not sampling luck. The adaptive study separately publishes the eight policy-valid-but-harmful transactions it admits.
- **Report the numbers.** 0.00 unsafe and 0.00 false-positive rate across 2,800 deterministic trials over 40 tasks (regex-based mock LLM, which the paper itself qualifies as validating decision logic, not real-world robustness). Live LLMs (three models, 595 trials) all reached 0.000 guarded attack success with 5.0 to 12.8% benign false positives.

### What it cannot do

Admitted by the authors: no outcome binding (approval at state S may execute at S′), key and policy compromise out of scope, no reentrancy, governance, or bridge coverage, an owner-only raw-execution bypass path by design, single-seed ablations, and live-trial denominators that drift without explanation (595 of 600, DeepSeek 156 of 160).

Structurally, against RFC 0003, PACE has no confidentiality at all: no labels, no recipients, no observers, no quarantine, no purpose, no workspace admission. Its UserPolicy is a slice of the RFC's Erlaubt (Basis_Γ plus some of P_b) without the Empfängerkreis and Zweck parts. The audit story ends with the PDR. There is no third event, no OutcomeRecorded, no append-only journal, no independent verifier, and no historical conformance. The decision field is not in the signed digest, so a valid signature attests approval only implicitly. The paper names the hardening (*adding an explicit decision field … is a simple further hardening*) and does not do it.

The most instructive break is the composition problem. PACE verifies one transaction at a time and admits 8 of 8 policy-valid-but-harmful multi-step sequences, delegating the rest to future policy-authoring work. This gap is precisely the RFC's Offenlegungsstand territory (R.6.3, D.5): two individually valid releases that together reconstruct a protected value. APPA reaches the same limit, since it has no cumulative disclosure bookkeeping. Both papers independently arrive at the boundary where the RFC already specifies state, atomic reservation, consumption, and a versioned disclosure ledger.

### Where it meets RFC 0003

The strongest single correspondence is between the nine on-chain `executePDR` checks and the Ausführer re-verification of B.8. The RFC says a transmitted `permit` is never an authorization, and neither payload nor target may be swapped between check and effect. One difference remains. PACE checks consistency against the attested PDR, while the RFC's executor re-resolves the current context, including object versions and registry revisions.

Nonce consumption and validity windows map fully onto Reservierung/Verbrauch and Gültigkeit/Widerruf (R.6.3, R.6.5, and the `freigabe-replay` family in D.4). The policy hash pinned in each PDR is a per-artifact Γ stand. The §4.6 field-provenance rule maps fully onto B.2 and B.3. "The verifier never queries the LLM" is the same stance as "Agentenbehauptungen ersetzen die Fakten nicht". And "not outcome binding" is the gap the RFC closes with OutcomeRecorded evidence classes: ExecutionCommitted *ausdrücklich nicht* means the recipient confirmed the effect.

Evidence-quality verdict: honest engineering argument, not a theorem. The words theorem, lemma, and proof do not appear in the paper. The claim "provably satisfies" rests on structural argument plus two assumptions (field provenance, state equivalence) that the abstract does not mention. The main benchmark is circular by its own admission, the artifact is not public, there is no conflict-of-interest statement despite a four-of-seven PayPal authorship, and the paper had no citations found and no community footprint eight weeks after release. One formal tier below APPA and below the RFC's own proof obligations (A.7, A.8). The PayPal framing is custody thinking, protecting the owner's money from the agent, rather than GO thinking, in which a human institution authorizes exceptions. The difference between custody thinking and GO thinking decides what to copy.

## The three-way result

APPA is the strongest existing formalization of the RFC's mediation half (dispatch gates, label dynamics, recovery). PACE is the strongest, and only evaluated, instantiation of its execution half (B.8, F.5, R.11.3: *kein auditpflichtiger Effekt ohne vorherigen dauerhaften Vorbeleg*). RFC 0003 is what neither has: confidentiality with a noninterference claim, quarantine with human first classification, a disclosure ledger against composition leaks, outcome evidence, and the GO-Prinzip as institutional architecture rather than LLM auto-approvers.

The framing holds with two refinements. PACE's UserPolicy is itself a full action-level Erlaubt slice, so the halves overlap rather than split cleanly. And APPA does carry execution state (the committed-effect log), weaker than the RFC's but present. What neither paper has at all: OutcomeRecorded, in either form.

The net assessment for the RFC: partially redundant at component level, confirmed at system level. Calibrate the mediator against APPA, build the executor on PACE's mechanics, and keep building what neither paper does. The convergence observation belongs in Anhang E: two independent, mutually unaware literature streams (information-flow control and transaction integrity) converged in 2026 on exactly the RFC-0003 architecture.

## Related policy models

Two scans filtered for credibility: peer-reviewed venues, canonical literature, major-lab primary publications, or production-adopted open source. No vendor marketing. The scan outputs contained formatting corruption in places, so everything below is extracted only where source-anchored (IDs, venues, and dates are re-checkable). Anything load-bearing for an RFC revision should get a short primary check first.

### Read next

1. **Fides.** *Securing AI Agents with Information-Flow Control* (Costa, Köpf et al., Microsoft Research, arXiv 2505.23643, May 2025). The closest published cousin of the RFC's mediator. Two policies: trusted action and permitted flow. A variable store with selective hiding. A quarantined, tool-less LLM with constrained decoding. Labels as security × type lattice (bool ⊑ enum ⊑ string, so one-bit answers from untrusted sources can pass policy). In production as the security middleware of the Microsoft Agent Framework, fail-closed by default. Its candor is valuable: full confidentiality-noninterference is explicitly rejected as impractical in favor of "explicit secrecy". That rejection names exactly the gap the RFC's deliberate release machinery manages with human GOs. The peer venue is unverified. Production adoption compensates.
2. **Prudentia.** *Optimizing Agent Planning for Security and Autonomy* (Kolluri et al., Microsoft, ICLR 2026, arXiv 2602.11416). Reframes the payoff of deterministic IFC as autonomy, measured as human-in-the-loop load and task completion. Its endorsement mechanism is the RFC's Erstklassifikation with a usability design: a human reviews untrusted material once and relabels it as trusted, and subsequent trusted actions need no further GO. Measured at 1.9 times less human intervention than Fides and zero attack success on WASP. Deliberately no declassification. Peer-reviewed confirmation of the GO-Prinzip.
3. **Dogwood** (AWS, August 2026, Apache 2.0, in AgentCore). Cedar extended with temporal policies over session event logs (`formerly within 1h Action::"Login"` for approval precedence, `since`, count and sum within for budgets), grounded in Metric First-Order Temporal Logic from the runtime-verification school. The state of the art for history-conditioned permissions, which is exactly R.6 semantics. AWS itself documents the correctness-critical catch (a response-based rate limit can be raced by three concurrent transfers. A request-based one cannot: *one word separates the policies*) and admits there is no automated-reasoning tooling for the temporal fragment.
4. **GAAP.** *An AI Agent Execution Environment to Safeguard User Data* (UCLA and Google, arXiv 2604.19657, April 2026, under submission). User prompt, model provider, and model context are fully untrusted. Permissions live in human-managed stores. Uniquely in the whole scan, a disclosure log tracks transitive flows across temporally separated tasks, with the model provider itself modeled as an external recipient. The only found external source with an Offenlegungsstand-like ledger. Cite with the under-submission caveat.
5. **CaMeL.** *Defeating Prompt Injections by Design* (Debenedetti et al., Google DeepMind and ETH, arXiv 2503.18813). Already anchored in the RFC's Anhang E and worth a full read: per-value capabilities (provenance tags plus allowed readers on each value rather than per session), the value-level counterpart of the RFC's object labels, with policy violations escalating to user confirmation.

### Cite as formal anchors

- **Gradual Release** (Askarov and Sabelfeld, IEEE S&P 2007): attacker knowledge stays constant between release events, the formal core of the Offenlegungsstand invariant. With **Menz et al. (OOPSLA 2023)** on compositional declassification for the D.5 two-sums problem.
- **Cedar and cedar-spec** (OOPSLA 2024, Lean-mechanized): proven deny-by-default, forbid-overrides-permit, evaluation-order independence, SMT symbolic compiler. The strongest formal-verification story of any policy language and the pattern to emulate if komki_policy proof trees should become citable theorems. Cedar was donated to the CNCF sandbox in late 2025, per secondary reporting.
- **PBAC** (Byun, Bertino, Li, SACMAT 2005; Byun and Li, VLDB Journal 2008): purpose trees with explicit prohibitions, the mature formal literature for the RFC's purpose-bound operation conditions.
- **Zanzibar** (USENIX ATC 2019): the peer-reviewed anchor for set algebra (union, intersection) over recipient sets. Its distribution machinery is overspecified for a single-user harness. Cite it, do not imitate it.
- **Gradual IFC canon** for Anhang E: Toro et al. (TOPLAS 2018), GLIO (LICS 2020), λ★IFC (PLDI 2024). The paired-execution proofs of Bichhawat, McCall, and Jia (CSF 2021) are the academic anchor for the RFC's Zwei-Ausführungs-Simulator.
- **HiStar, Flume, Asbestos** (OSDI 2006 and 2010, SOSP 2005): HiStar's declassification only through authority gateways is the direct ancestor of the RFC's Lockerungsbefugnisse.
- **W3C PROV (2013)** and **PROV-AGENT** (IEEE e-Science 2025, MCP-native capture): the schema basis for Belegablage and audit journal.
- **NGAC** (INCITS 567, recommended for agentic systems in the NIST NCCoE concept paper of February 2026): a standards-anchored formal policy-graph citation, should one be needed.

### Harness and taxonomy context

The MCP authorization specification (2025-06-18: OAuth 2.1, PKCE, resource indicators per RFC 8707, token passthrough explicitly forbidden) handles credentials only and specifies no data-flow policy. The RFC should state in two sentences what it adds on top. OpenCode's permission model (allow, ask, deny; last match wins; session-scoped always-patterns; a global-beats-project trust tier) and Claude Code's (first match wins; fixed deny, ask, allow order; an LLM-classifier auto mode) are pattern-matching allowlists that the workspace-contract layer would formalize. These are scan-level details. Re-verify before quoting mechanics. The OWASP Top 10 for Agentic Applications (ASI01 to ASI10, published December 2025) is the threat taxonomy to map R.8 against. It is not a policy model.

### Skip, despite hype

- **Permissive IFC** (Siddiqui et al., TMLR 2025, arXiv 2410.03055): influence-based label dropping is declassification by another route, performed by an LLM. Cite it in Anhang E as the anti-pattern for this RFC.
- **AgentArmor** (ByteDance, venue open, with some dependency edges annotated by an LLM) and **Progent** (arXiv only): context, not foundation.
- **Chinese Wall** (Brewer and Nash, IEEE S&P 1989): models third-party conflict of interest, not the problem of one person working in two contexts. R.3 already states the real constraint: no technically separated memory. Historical contrast only.
- **ISO/IEC 42001 and 23894, NIST governance documents, OPA and Rego as an engine candidate, Casbin, Oso (OSS deprecated December 2023), LLM-classifier auto-modes**: no IFC semantics, or pure governance boilerplate.

## What this means for komki

Current state, from code inspection: `komki_policy` (about 3,150 lines, 87.6% line coverage, zero runtime dependencies) implements the RFC Anhang B admit kernel with nine fixed premises, a three-valued expression evaluator where a missing fact is unknown rather than false, and an independent verify that never calls derive. The release branch is a declared stub (`relaxation_authorities` is parsed but always empty and not evaluated). Plan, start, emit, transfer, and store are intentionally unsupported. `komki_cli` wraps only the `pi` agent in a deny-default Seatbelt profile with a boot gate. llama-server runs unsandboxed by convention, which the RFC's own R.3 and D.9 requirements flag as an unproven assumption.

The research translates into five concrete moves, in priority order.

1. **Build the release and remedy branch.** A blocked decision should return an enumerable set of legal continuations (which fact, which GO, which new workspace would clear this blocker) instead of a bare deny. APPA's Theorem 5 (exactly four trusted transition types clear a gap) is the product spec, and its ablation (35% without remedy plans, 88% with) says where the utility lives. Add PACE's mechanics to each release: a freshness window and an atomically consumed nonce. R.6.3 and B.8 already demand both.
2. **Make the mediator dual-phase at the MCP boundary, with PDR-style records.** Check the exact rendered call before dispatch, check the return before admission, and bind each decision record to the intent hash, the payload hash, and a Γ snapshot hash. This is nearly free given komki_policy's byte-stable JSON. Re-verify at each connector via a versioned, enumerated checklist in the style of PACE's nine checks (the D.9 `connector-bypass` family, one attack and one positive control per check).
3. **Write field provenance into the connector contract.** The §4.6 lesson as a hard rule: security-relevant metadata over an MCP call (read-only claims, target identifiers, scope markers) comes from the fixed Connector-Fassung of R.4.3 or from trusted decoding, never from agent arguments.
4. **Adopt bounded return channels.** attest-schema-style shape bounds (closed enums, bounded integers) for delegated reads are cheap in Elixir and honest about bandwidth.
5. **Run D.4 and D.9 as a live attack corpus** with attack-success and utility metrics, two-execution comparisons (CSF 2021 paired execution as the academic anchor), and APPA's reporting honesty as the standard: misses stay in the denominators.

Do not copy two things. First, PACE's owner-only raw-execution bypass is an untyped authority path outside the mediator. Second, treating policy-conform as safe is wrong here: in this RFC, an Einzelfallfreigabe lands in a checked event plan and the Offenlegungsstand, not in a standing competence of the policy author.

### Relation to the immediate next steps

The three stated next steps map onto the RFC path in order.

**(a) Getting files into a session.** That step is R.5.4 (Aufnahme) plus the B.3 Object and Workspace data contracts. Files enter a workspace whose binding set was fixed at start (R.4.1), and admission checks all room bindings, not just the file's own label. Unclassified arrivals go to quarantine (R.2.5) and stay out of regular workspaces until a human or an approved import rule classifies them. Prudentia's endorsement is the measured design reference for that human step. APPA's file-taint tracking shows the risk of the shortcut: the same idea is still marked experimental and is not a security boundary.

**(b) Assigning labels, origin, and secrecy level.** The Registry schema already exists in komki_policy: bindings with readers, operation conditions, and relaxation authorities, in a closed schema with version checks. What the RFC adds as obligations: labels live outside the agent's write domain (R.2.1), so a renamed file or a claimed anonymization carries its label unchanged. Origin and classification decision are stored separately from content (R.2.1, B.3). Provenance classes are distinguished: technical property, test result, or accepted operator assumption (B.3). The PACE field-provenance rule governs every tool-supplied attribute.

**(c) The RIS as first connector.** R.4.3 gives the shape: a fixed, versioned Connector-Fassung. Credentials stay at the connector. Outbound calls are outputs, and inbound responses are new inputs that need classification before admission. The R.7.1 pattern does the workflow: fetch the RIS snapshot before protected analysis starts, so no external recall channel is needed mid-session. The building blocks exist (`ratsinfo` sync, search, and show, plus `ratsinfo_mcp`). The missing component is the mediator in front of them, which is move 2 above. One detail matters for real data: nichtöffentliche Ratsvorlagen carry what is effectively a `ratsarbeit` binding, and even public RIS files still pass the admission check against the room's bindings. That case is D.1, and it is the first regression test the connector should face.

## Open items

- Anhang E of RFC 0003 could grow: Fides, Prudentia, Dogwood, GAAP, Gradual Release with Menz et al., PBAC, cedar-spec, PROV-AGENT, APPA, PACE, plus the convergence note. Needs a GO.
- A komki roadmap issue for moves 1 to 3 (release branch, dual-phase mediator with PDR records, connector contract) would make the session's findings actionable. Needs a GO.
- Fides and Prudentia deserve a full read before any Anhang E revision. Both are the nearest neighbors, and both are short.
- Unverified at retrieval date: APPA's NeurIPS acceptance (website-only claim), Fides' peer venue, GAAP's review status, Cedar's CNCF donation (secondary source only).

## Sources

- OpenAPPA and APPA: openappa.com (all cited pages fetched 2026-10-13), arXiv 2607.24625v2, github.com/archestra-ai/OpenAPPA.
- PACE: arXiv 2608.17220v1 (full text). Lineage: Alqithami et al., arXiv 2601.04583 (abstract verified).
- Fides: arXiv 2505.23643, Microsoft Agent Framework security docs.
- Prudentia: ICLR 2026 proceedings, arXiv 2602.11416.
- GAAP: arXiv 2604.19657.
- AirGapAgent: CCS 2024 (10.1145/3658644.3690350).
- CaMeL: arXiv 2503.18813.
- Cedar: OOPSLA 2024 (10.1145/3649835), cedar-spec.
- Dogwood: AWS Open Source Blog, github.com/dogwood-policy/dogwood.
- Zanzibar: USENIX ATC 2019.
- Askarov and Sabelfeld: IEEE S&P 2007. Menz et al.: OOPSLA 2023.
- Byun, Bertino, Li: SACMAT 2005. Byun and Li: VLDB Journal 2008.
- Toro et al.: TOPLAS 2018. GLIO: LICS 2020. Bichhawat et al.: CSF 2021. λ★IFC: PLDI 2024.
- W3C PROV (2013). PROV-AGENT: IEEE e-Science 2025.
- NGAC: INCITS 567, NIST NCCoE concept paper (February 2026).
- MCP authorization specification 2025-06-18.
- OpenCode and Claude Code permission docs.
- OWASP Top 10 for Agentic Applications (December 2025).
- Siddiqui et al.: TMLR 2025, arXiv 2410.03055. AgentArmor: arXiv 2508.01249. Progent: arXiv 2504.11703.
- Brewer and Nash: IEEE S&P 1989. HiStar, Flume, Asbestos: OSDI 2006 and 2010, SOSP 2005.
