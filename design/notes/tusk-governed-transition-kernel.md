# Tusk Governed Transition Kernel

## Status

Normative model note for the governed transition kernel in `tusk`.

## Intent

This note names the smallest stable control-plane kernel for `tusk` in the
updated vocabulary:

`proposal -> witness record -> envelope -> admitted execution -> application -> receipt -> projection`

The goal is not to replace the older transition-carrier note. The goal is to
state the same center more cleanly, fix the agent-versus-authority boundary,
and give the follow-on adapter and recast work one stable kernel vocabulary.

## What Is Governed

`tusk` governs proposed changes to trusted repo-local workflow state.

Today that includes:

- issue transitions such as `claim_issue` and `close_issue`
- lane transitions such as `launch_lane`, `handoff_lane`, `finish_lane`, and
  `archive_lane`
- backend and service transitions such as `tracker.ensure`

Later it may include:

- release or publish transitions
- skill-authoring transitions
- other control-plane transitions built on the same kernel

The kernel exists so these transitions do not happen merely because an agent,
user, or shell requested them.

## Agent Versus Kernel

Agents live at the proposal edge. The kernel lives at the authority edge.

Agents:

- inspect projections
- stage or restage proposals
- respond to `need` and `obstruction`
- request admission
- request application

The kernel:

- gathers authoritative witnesses
- constructs the envelope that binds proposal to authoritative context
- decides admission
- applies admitted transitions
- emits receipts
- refreshes projections

Codex is one proposal-side client.
A `pi`-style runtime could become another.
Neither is the kernel.

## Imported Method

This note imports method, not cargo, from nearby lines.

From WCAT-Core:

- raw proposals are distinct from admitted executions
- witnesses are explicit
- failure should stay proof-relevant

From WCAT-Runtime:

- verify is distinct from apply
- only the runtime may emit authoritative receipts

From WCAT-ACT:

- agents stage acts such as `propose`, `inspect`, `repair`, and `apply`
- the kernel returns authoritative responses such as `need`, `obstruction`,
  `admitted`, `receipt`, and `projection`

From Nerve and Premath:

- carry the smallest operational seam first
- keep theorem-facing or protocol-facing structure above the first carried seam

## Kernel Sequence

### 1. Proposal

A proposal is the client-staged request for one transition.

Prototype shape:

```text
Proposal = {
  kind,
  payload,
  refs?,
  request_id,
  client_role
}
```

Examples:

- `claim_issue { issue_id }`
- `launch_lane { issue_id, base_rev, slug? }`
- `tracker.ensure { repair_authorized }`

The proposal is not authority.
It is the thing the kernel is being asked to govern.

### 2. Witness Record

The witness record is the explicit set of authoritative observations and
derived checks relevant to the proposal.

Prototype shape:

```text
WitnessRecord = {
  tracker?,
  service?,
  lane?,
  workspace?,
  backend?,
  checks[]
}
```

Each witness should stay explicit.
Do not collapse them into one Boolean.

Examples:

- issue exists
- issue status is `open` or `in_progress`
- base revision resolves
- no live lane exists
- workspace path is absent
- backend is healthy
- caller holds repair authority

### 3. Envelope

The envelope is the carried kernel object that binds:

- one proposal
- one repo identity
- one authoritative witness record
- and the authority context under which admission will be decided

Prototype shape:

```text
Envelope = {
  repo,
  proposal,
  witnesses,
  authority_context,
  prior_receipts?,
  state_refs?
}
```

The envelope is the runtime cargo.
It is the stable bridge between client intent and kernel authority.

This is the object the older transition-carrier note was aiming at.

### 4. Admitted Execution

An admitted execution is an envelope plus a successful admission decision.

Prototype shape:

```text
AdmittedExecution = {
  envelope,
  admission,
  execution_id
}
```

Admission must remain explicit.
A proposal does not become admitted just because it is well-shaped.

The kernel may also return the negative case:

```text
Obstruction = {
  proposal,
  reason,
  witness_refs,
  obstruction_kind
}
```

### 5. Application

Application is the actual mutation path the kernel realizes for an admitted
execution.

Prototype shape:

```text
Application = {
  admitted_execution,
  mutation_plan,
  rollback_plan?,
  result
}
```

This is where:

- tracker updates happen
- lane state is written
- workspaces are created or removed
- service records are published
- receipts are appended

Application is not the same thing as admission.

### 6. Receipt

A receipt is the durable authoritative record that the kernel stands behind
after application.

Prototype shape:

```text
Receipt = {
  kind,
  execution_id,
  issue_id?,
  state_refs,
  result,
  timestamp
}
```

Receipts are evidence of application.
They are not the sole source of current truth.

### 7. Projection

A projection is a derived read view over authoritative state and receipts.

Examples:

- `tracker_status`
- `board_status`
- `receipts_status`

Projections are what agents inspect.
They are not what agents mutate directly.

## Carried Versus Semantic-Only

### Carried

The first carried kernel rows should be:

- proposal
- witness record
- envelope
- admission result
- admitted execution handle
- receipt reference
- projection references or roots

### Semantic-only for now

These remain above the first carried seam:

- richer planner-side narratives
- theorem or proof vocabulary
- public federated action schema
- non-local protocol compilation
- agent-local aliases and scratch structure

The kernel should carry only what it needs to govern one transition safely.

## Mapping The Current `tuskd` Surface

The current code already contains a partial kernel.
The vocabulary is just mixed.

### Current request surface

Current:

- CLI action commands
- `query`
- `respond`
- `action-prepare`

Kernel reading:

- client proposal acts and inspect/apply requests

### Current `new_transition_carrier(...)`

Current fields:

- `repo`
- `tracker`
- `service`
- `issue`
- `lane`
- `workspace`
- `witnesses`
- `intent`
- `admission`
- `realization`
- `receipts`

Kernel reading:

- `intent` is the proposal
- `witnesses` are the witness record
- the whole object is closest to the envelope scaffold
- `admission` is the gate to admitted execution
- `realization` is the application slot
- `receipts` are receipt references and emitted receipt state

### Current delegated write path

Current:

- `action_prepare_result(...)`
- delegated `respond`
- Rust `action-run`

Kernel reading:

- prepare/admit is the proposal-to-admitted-execution path
- action-run is the application path

### Current read surface

Current:

- `status_projection`
- `board_status_projection`
- `receipts_status_projection`

Kernel reading:

- projections returned to clients for inspection

## First Act Surface

The kernel should converge on a small act vocabulary:

- `propose`
- `inspect`
- `repair`
- `apply`

And a small authoritative response vocabulary:

- `need`
- `obstruction`
- `admitted`
- `receipt`
- `projection`

The existing `tuskd` commands may stay as compatibility wrappers, but they
should be read as specialized client-side acts over this kernel boundary.

## Example: `launch_lane`

The kernel reading of `launch_lane` should be:

1. proposal
   `launch_lane { issue_id, base_rev, slug? }`
2. witness record
   - issue exists
   - issue is `in_progress`
   - no live lane exists
   - base revision resolves
   - workspace path is absent
3. envelope
   proposal plus repo identity, lane/workspace observations, prior receipts,
   and authority context
4. admitted execution
   kernel says lane launch is admissible in this state
5. application
   - create workspace
   - write lane state
   - append `lane.launch` receipt
6. receipt
   durable `lane.launch`
7. projection
   board shows the launched lane

That same law should apply to the other control-plane actions.

## Relationship To Existing Notes

- [`design/tusk-transition-carrier.md`](./tusk-transition-carrier.md)
  gives the older runtime-carrier shape; read it now as the envelope-side note.
- [`design/tusk-backend-service-carrier.md`](./tusk-backend-service-carrier.md)
  is the first specialized seam under this kernel.
- [`design/tusk-architecture.md`](./tusk-architecture.md)
  keeps the wider witness/intention/admission/realization story for the flake
  and operations layer.

## Immediate Consequences

This note implies the next order of work.

1. `8.6.2` should name adapter seams beneath the kernel:
   tracker, lane state, workspace, backend, receipt, and projection
   boundaries. See
   [`design/tusk-governed-transition-adapters.md`](./tusk-governed-transition-adapters.md).
2. `8.6.3` should recast current `tuskd` action code so proposal, witness,
   envelope, admitted execution, application, receipt, and projection are
   explicit in the code structure.
3. Future clients should talk to the kernel through act and response surfaces,
   not by reaching around it into tracker or workspace mutation paths.

## Recommendation

Proceed as if:

- `tuskd` is the governed transition kernel,
- agents are proposal-side clients,
- the transition carrier is best read as an envelope-shaped runtime object,
- admission and application must remain separate,
- receipts are authoritative evidence,
- projections are read views for agents,
- and later protocol or theorem layers should compile from this kernel rather
  than replacing it.
