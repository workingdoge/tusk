# Placement And Wires

Use this reference when a slice could plausibly land in more than one repo or
when the next lane boundary is unclear.

## Placement test

Ask these in order:

1. Does this define meaning, doctrine, law, or public semantics?
   Put it in tracked upstream `premath` or `fish`.
2. Does this define the canonical bridge+secret domain contract stack?
   Put it in `bridge`.
3. Does this carry, compile, bind, normalize, validate, or publish reusable
   runtime-facing method?
   Put it in `kurma`.
4. Does this operate around stable artifacts, repo workflow, operator control,
   receipts, shared runtime adapters, or generic shared infra?
   Put it in `tusk`.
5. Does this implement a consumer product surface, ingest path, local policy, or
   funded operator runtime?
   Put it in the downstream repo.

If the slice fails step 3, it should not land in `tusk`.

## Current map

Use this map unless a newer explicit issue or design note overrides it.

### `fish`

Owns:

- normative meaning
- doctrine
- public schemas and laws

Tracked upstream `premath` is the active doctrine surface when the question is
Premath kernel law or realization-profile classification.

### `bridge`

Owns:

- canonical bridge adapter contract
- canonical secret suite
- bridge-to-secret handoff
- bridge-domain conformance harnesses
- the canonical `bridge` skill for bridge admission and secret materialization
  questions

If the active repo exposes the `bridge` skill and the question names
`AuthorizeRequest`, `ProviderResults`, `PolicyInput`,
`MaterializationPlanRequest`, `MaterializationSession`, or the burn/restore
flow around a materialized capability, route there before widening `tusk`.

### `kurma`

Owns:

- carriage method
- `Premath` row and shape discipline
- `Nerve` carried-seam method
- `WCAT` proposal/runtime/receipt/projection boundaries
- reusable crate surfaces for carrying and validating method

### `tusk`

Owns:

- repo-local workflow
- operator control plane
- tracker, lane, receipt, and projection orchestration
- shared operational infra that is broader than one consumer but narrower than
  upstream method
- generic adapters over stable upstream or downstream surfaces
- compatibility copies or consumer glue when the canonical domain lives
  elsewhere

### `aac`

Owns:

- paid source connector behavior
- ingest/runtime integration
- source artifacts and receipt handling inside AAC's product/runtime boundary

### `home`

Owns:

- funded executor implementations
- provider policy
- operator secrets and env wiring
- first live proof of a shared seam when that proof depends on real wallet or
  operator behavior

## Paid HTTP rule

For paid HTTP, use this split:

- protocol boundary and shared paid-request kernel: `tusk`
- source-facing paid connector and ingest behavior: `aac`
- funded settlement executors, provider policy, and operator runtime: `home`

Sequence it as:

1. `tusk` shared seam
2. one real proof consumer
3. second consumer integration

Do not collapse all three into one lane.

## Isolation rule

For container and microvm work, use this split:

- shared lane-scoped runtime attachment, admission boundary, and receipt
  contract: `tusk`
- engine-specific implementation details only if they remain generic
  operational infra and reusable across more than one proof: `tusk`
- agent-specific payloads, bootstrap commands, credentials, and product policy:
  downstream repo or a separate runtime context

Sequence it as:

1. `tusk` attachment contract
2. one lane-scoped local probe
3. only then promotion into a reusable executor family if the constructor
   actually stabilizes

Do not start with a general agent-runtime framework when the real first wire is
one bounded local probe.

## Wire contract

Every consequential issue should declare one main wire:

- input context
- output artifact
- verification boundary
- landing boundary

If the same contract spans multiple repos, declare the simplex alongside the
wire:

- simplex kind: `1-simplex` or `2-simplex`
- common contract
- vertex roles

Good wire examples:

- upstream row surface -> publishable crate API
- canonical bridge-domain change -> refreshed `tusk` compatibility bundle
- bridge admission or materialization question -> canonical `bridge` skill
- crate API -> one `tusk` governed runtime seam
- shared infra -> one downstream proof consumer
- proof result -> one follow-up integration issue

Bad wire examples:

- mixed architecture note plus runtime refactor plus downstream adoption
- one issue that changes shared infra and two consumers at once
- one lane that starts from ambient default dirt and calls it feature work

## Simplex patterns

When the same contract spans more than one repo, model the organization as a
simplex instead of pretending each repo task is unrelated.

### 1-simplex

Use a 1-simplex when two repos meet at one explicit edge contract.

- vertex A: the canonical owner of the contract
- vertex B: the consumer or compatibility owner
- edge: the stable contract both lanes refer to

Execution rule:

- file one issue per endpoint repo
- keep both issues tied to the same edge contract
- do not widen one repo lane until it starts doing the other repo's job

Current example:

- `bridge` exports the canonical bridge flake surface
- `tusk` consumes that surface as a compatibility seam
- the edge contract is the minimal exported flake surface itself

### 2-simplex

Use a 2-simplex when a third repo joins the same contract and creates a
coherence condition across all three vertices.

- vertex A: canonical contract owner
- vertex B: shared consumer or operator seam
- vertex C: downstream proof or product consumer

Execution rule:

- keep one issue per vertex or per edge-owned realization
- name the common contract explicitly
- treat the downstream proof as a third vertex, not as an afterthought hidden
  inside one of the upstream lanes

Likely next example:

- `bridge` canonical contract
- `tusk` compatibility seam
- `home` first live proof consumer

That turns the bridge export/consume edge into a 2-simplex once the proof repo
must agree with the same contract.

## Split rules

Split issues when any of these change:

- owning repo or layer
- verification boundary
- landing owner
- authority boundary
- consumer versus shared-infra responsibility

Prefer one issue per wire, not one issue per nearby file.

## Cleanup rule

If `default` is carrying mixed consequential work:

1. create a cleanup issue
2. move the ambient stack into a dedicated workspace
3. restore `default` to a clean coordinator line
4. only then start the new feature or adoption lane

Do not pretend a dirty default checkout is a legitimate base for new work.

## Output template

When routing a slice, answer in this order:

1. `Context:` one of the context classes
2. `Owner:` repo or layer
3. `Why here:` one or two concrete reasons
4. `Simplex:` `none`, `1-simplex`, or `2-simplex`
   - `Common contract:` required when simplex is not `none`
   - `Vertices:` required when simplex is not `none`; name vertex A, B, and C
     roles as applicable
5. `Wire:`
   - input context
   - output artifact
   - verification
   - landing boundary
6. `Next:` issue to file, issue to reshape, or lane to launch
