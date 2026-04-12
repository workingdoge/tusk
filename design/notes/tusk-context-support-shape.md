# Tusk Context Support Shape

## Status

Repo-scoped design note.

This note is explanatory and design-shaping. It does not define kernel law by
itself.

## Purpose

Name the overall shape that sits underneath the emerging witness-driven runtime
without collapsing everything into either:

- one action pipeline, or
- one decorative topology story.

The clean split is:

- **flow architecture** for typed action composition
- **coherence architecture** for local overlap and admissibility

The witness is where those two architectures meet.

## Sharp claim

Tusk is not well-described as "an agent in the middle calling tools".

The better reading is:

- local contexts exist as bounded authority regions,
- one plan induces only the sparse support it actually touches,
- cross-cutting concerns live on those overlaps,
- compatible local sections glue into a witness,
- and effect only happens through an epoch-bound apply boundary.

In short:

`plan -> support -> concern sections -> witness -> epoch-bound apply`

## Dual architecture

### 1. Flow architecture

The flow side owns what the plan is trying to do.

Examples:

- read document
- compare vendor
- request approval
- sign payment
- write audit record

This is the composition side. It answers:

- what action is being proposed,
- what its inputs and outputs are,
- what next moves are lawful.

### 2. Coherence architecture

The coherence side owns where cross-cutting obligations must agree.

Examples:

- the overlap between repo state and tracker truth
- the overlap between signer scope and approval scope
- the overlap between budget policy, approval state, and execution authority
- the overlap between untrusted content, runtime permissions, and audit policy

This is the support-complex side. It answers:

- which local contexts are jointly relevant,
- what restrictions exist on their overlaps,
- what concern data must agree before execution.

## Site of contexts

The base ingredient is not "services". It is local contexts or authority
regions.

Examples:

- canonical tracker state
- lane workspace
- repo checkout
- service/backend runtime
- approval surface
- secret or signing authority
- audit sink
- external SaaS
- untrusted content source

The important point is locality:

- each context has its own admissibility facts,
- those facts are only globally meaningful after gluing.

## Plan-induced support

The support complex must be plan-induced and sparse.

That means:

- a plan does **not** awaken the whole world,
- it only materializes the contexts jointly relevant to that plan,
- and it only records the overlaps that actually matter for the next bounded
  move.

This is the discipline that prevents global graph soup.

For current Tusk kernel work, the support can be degenerate.

Examples:

- one issue-side base locus plus one lane context
- one service context plus one receipt sink
- one untrusted skill source plus one staging target plus one approval surface

The point is not maximal topology.
The point is explicit, sparse overlap.

## Concern sections

Cross-cutting concerns should not become middleware sludge.

They belong on the support object itself.

Good candidates:

- authority and approval
- provenance
- secrecy and information flow
- budget or quota
- revocation and trust roots
- audit obligations
- freshness windows

Bad candidates:

- generic metadata that has no boundary-sensitive consequences
- decorative labels with no effect on admissibility
- convenience fields that do not constrain a move

The rule is strict:

Only concerns that are local in origin, jointly constraining, and global only by
gluing belong here.

## Temporal filtration

Time is not an afterthought.

It cuts through the whole shape:

- epoch id
- observed-at time
- lease duration
- freshness window
- revocation state
- approval validity

Without this, a witness becomes timeless fiction.

With it, the witness says:

"this move was admissible under this bounded temporal view of the world."

## Witness as meeting point

The witness is not the whole world and it is not metaphysical proof.

It is the compatible bundle that closes the loop between:

- typed action intent,
- local support,
- concern sections,
- and epoch-bound validity.

That is why the witness is the meeting point between flow and coherence.

If action composition is the engine and support is the overlap geometry, the
witness is the admissibility closure that makes bounded effect lawful.

## Relation to the current kernel

This note does not replace the current kernel series.

It tightens how to read it:

- `TUSK-0001` gives the base/fiber split
- `TUSK-0002` gives explicit witnesses and admission classes
- `TUSK-0003` gives descent and closure
- `TUSK-0004` gives concrete transition contracts
- `TUSK-0005` gives the read-side projection surface

The additional claim here is:

- witness production should be read against plan-local support, not only flat
  witness lists,
- and future runtime growth should preserve that plan-local sparsity.

## Mapping to the wider stack

### Premath

Owns admissibility law:

- what obligations exist
- what local sections mean
- what counts as compatible gluing
- what escalations are lawful

### Nerve

Owns support geometry:

- contexts
- overlaps
- sparse support patches
- coherence surfaces

### WCAT

Owns witness packaging:

- plan reference
- concern sections
- epoch binding
- admissibility closure
- execution binding

### Tusk

Owns the operational boundary:

- gather local evidence
- build support
- verify compatibility
- mint bounded apply token
- emit receipts

## Operator vocabulary

The internal math can stay rich, but operator surfaces should stay plain.

Prefer:

- contexts
- overlaps
- checks
- witness
- apply
- receipt

Do not force operators to think in categorical vocabulary just to understand
what is blocked.

## Result

The useful summary sentence is:

> The system is not a stack of modules but a plan-local support complex of
> contexts, carrying transverse concern sections whose compatible gluing forms
> the witness required for bounded execution.

And the shorter slogan is:

> composition in the flow, overlap in the support, admissibility in the
> witness, effect at the boundary.
