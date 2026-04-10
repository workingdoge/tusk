# Tusk Semantic Spine Map

## Status

This note maps the semantic spine that already exists in the tree today and
names the first core slices needed to stabilize it.

It is narrower than `design/tusk-architecture.md`.
That architecture note defines the intended calculus.
This note answers a different question:

- what is already implemented structurally,
- what is still only conceptual,
- and what the next reviewable core slices should be.

## Current Spine In Tree

The intended spine is still:

`witness -> intent -> admission -> realization -> receipts`

The current tree encodes most of that spine already, but with one important
compression:

- the user-facing module surface names declared continuations as `effects`
- the semantic intent sits inside each effect as `effect.intent`

So the current implementation is best read as:

`base -> witnesses -> effects(intent) -> structural admission -> realizations -> expected receipts`

That is enough to expose the semantic center explicitly, but not yet enough to
claim that the admission law or runtime carrier are fully stabilized.

## What Exists Structurally

### 1. Verified Base

`flake-module.nix` already exposes `tusk.base` as a first-class option surface.
Each base entry carries:

- stable id
- systems
- semantic kind / short label
- installable or command locator
- emitted witness declarations

`lib.nix` normalizes these entries and guarantees that every base emits at
least one witness. When the source declaration omits witnesses, normalization
injects a default witness for the base entry.

Meaning:
- the tree already treats "verified base" as more than pass/fail
- witness emission is already part of the schema, not only design prose

### 2. Witnesses

Witnesses exist structurally in both the module and the normalized graph.

Today they carry only:

- id
- kind
- format
- path
- description

`lib.nix` also collects witnesses into a repo-wide witness graph keyed by
identifier.

Meaning:
- witness identity is real
- witness payload typing is still thin

### 3. Declared Intent

The tree does not yet expose a top-level `tusk.intents` surface.
Instead, intent is nested inside `tusk.effects.<name>.intent`.

That nested shape already carries:

- kind
- target
- action
- description

Meaning:
- declared intent exists semantically
- the current public naming still collapses declaration and continuation into
  `effects`

### 4. Admission

Admission exists today as a normalized structural projection under
`flake.tusk.admission`.

The normalized output already distinguishes:

- declared effect ids
- structurally ready effect ids
- blocked effect ids
- pending-capability effect ids
- per-effect blockers and capability requirements

The current blocker law is narrow:

- missing required base references
- missing required witness references

Meaning:
- admission is already distinct from declaration in the data model
- admission is not yet a full authority/policy decision

### 5. Executors

`flake-module.nix` already exposes `tusk.executors`.
`lib.nix` normalizes executor id, kind, enable flag, description, and leaves
the rest as freeform executor-specific config.

Meaning:
- the authority axis exists
- executor availability is declared, but not yet fed into the admission law

### 6. Drivers

`flake-module.nix` already exposes `tusk.drivers` grouped by driver family.
`lib.nix` normalizes them into stable ids like `family.name`.

Meaning:
- the target/transport axis is distinct from executor choice
- the executor/driver split is already present in the schema

### 7. Realizations

`flake-module.nix` already exposes `tusk.realizations`.
Each realization binds:

- one effect
- one executor
- one driver
- one receipt expectation

`lib.nix` validates that the referenced effect, executor, and driver ids exist.

Meaning:
- realization is already downstream of declaration
- realization validity is still reference-level, not admission-law-level

### 8. Receipts

Receipts exist structurally as expected receipt metadata in both the
realization schema and the normalized `flake.tusk.receipts.expected` output.

Today that receipt surface is still expectation-only:

- kind
- mode
- externalRef
- description

Meaning:
- receipts exist from v0 structurally
- runtime receipt recording is still out of tree for this core surface

## What Is Still Only Conceptual

The architecture note promises a stronger semantic center than the current tree
fully delivers.

These parts are still conceptual or only partially implemented:

- a first-class public "intent" surface distinct from the current `effects`
  name
- an admission law that evaluates capability availability, approval policy, and
  executor admissibility instead of only missing references
- typed witness payloads beyond id/kind/format/path/description
- receipt records as runtime facts rather than only expected shapes
- executor- and driver-specific flake modules such as GitHub driver support,
  Hercules executor support, or richer executor families beyond the first
  local trace carrier

## Current Typeholes

### 1. Naming Compression

The architecture says `witness -> intent -> admission -> realization ->
receipts`.
The public module surface still says `tusk.effects`, with intent nested inside
that declaration.

This is workable, but it means the exported surface still partially reflects
the older `checks -> effects` mental model.

### 2. Structural Admission Only

`flake.tusk.admission` already exists, but it only checks missing base and
witness references.

It does not yet answer:

- are the required capabilities actually available?
- is an approval class satisfied?
- is any executor willing and able to admit this effect?
- does a realization bind only an admitted effect?

### 3. Thin Witness Payloads

Witnesses currently expose identity and light metadata, not typed payload
contracts.

That is enough for graph shape, but not enough for richer continuation logic.

### 4. Untightened Capability Vocabulary

The schema distinguishes:

- secrets
- authorities
- state
- approvals

That is already better than one flat list, but the vocabulary remains strings
without a stabilized type or resolver contract.

### 5. Mixed-Purpose Library Surface

`lib.nix` currently holds both:

- the semantic-core constructors and normalizer for `tusk`
- repo-local skill packaging / projection helpers

That does not break correctness, but it blurs the core operational surface with
repo-dogfood runtime convenience code.

### 6. Thin Executor Admission

The repo now ships one concrete `local-trace` executor slice and one repo-local
trace realization, but the general admission law is still thin.

It still does not answer broader questions such as:

- executor capability availability beyond `enable = true`
- multi-executor choice or ranking
- policy admission distinct from executor admission

## First Reviewable Core Slices

### 1. Split Semantic Core From Repo Runtime Helpers

The first slice should separate the core `tusk` calculus from unrelated
repo-local skill runtime helpers.

Practical shape:

- move semantic normalization into a dedicated `lib.tusk` core file
- keep skill packaging / projection helpers in a separate library file

Why first:
- it makes the semantic center reviewable on its own
- it stops future dogfood/runtime work from obscuring the core model

### 2. Tighten Admission Into A Real Law

The second slice should turn the current structural admission snapshot into an
explicit admission law.

That law should distinguish at least:

- structurally ready
- blocked on witnesses / base
- pending capabilities
- executor inadmissible
- policy-gated

Why second:
- `tusk-asy.2.2` depends on a real admission boundary, not only a graph walk

### 3. Reconcile Public Naming Around Intent

The third slice should decide whether to:

- keep `effects` as the stable public name and document intent as a nested
  semantic field, or
- introduce a clearer top-level intent/declaration layer with compatibility for
  `effects`

Why third:
- the current tree already contains the intent axis
- but the public surface still teaches the older collapsed vocabulary

### 4. Ship One Local Trace Executor Slice

The fourth slice should first pin one concrete self-hosting witness set over
this repo, then add the smallest concrete executor module for dry
planning and local inspection.

Practical target:

- one exported repo-local witness graph for `tusk` itself
- `flakeModules.tusk-trace` or equivalent
- one trace/null executor
- one trivial driver or local receipt expectation path

Why fourth:
- it gives the executor a stable self-hosting witness root to consume
- it proves the executor/driver/receipt path without jumping straight to a
  remote backend

Status:
- complete for the first repo-local `local-trace` carrier
- follow-on work should now widen admission law and later remote executors,
  not rediscover the first trace path

### 5. Attach Isolation Downstream Of The Spine

The next isolation-facing slice should not invent a second center for
containers or microvms.

It should first define:

- one normalized local runtime-constructor request
- one lane-scoped receipt-bearing probe path
- and one promotion rule for when that probe becomes a reusable executor family

See [`design/tusk-isolation-attachment.md`](../tusk-isolation-attachment.md).

Why here:
- isolation only makes sense once witness, admission, executor, driver, and
  receipt boundaries already exist
- the first Hermes-style probe needs a bounded local runtime contract, not a
  universal virtualization framework

## Dependency Read

This map implies the following order:

1. `tusk-asy.2.1`
   map the semantic spine and name the core slices
2. `tusk-asy.2.2`
   map the pure base, admissible effects, transports, and state boundary on
   top of that spine
3. first self-hosting witness slice
   export one concrete repo-local witness graph for `tusk` itself
4. later executor / driver slices
   likely a trace/null local path first, then remote drivers or executors
5. local isolation attachment
   one lane-scoped constructor and receipt path first, then optional promotion
   into a reusable executor family

That keeps composition, isolation, and paid-HTTP work downstream of an explicit
semantic center instead of rediscovering it ad hoc.
