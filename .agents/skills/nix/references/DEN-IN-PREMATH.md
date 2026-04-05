# Den in Premath terms

This note is the compact conceptual companion to the skill.

It does **not** claim that Den already *is* a fibre bundle or sheaf-theoretic
descent calculus.
It claims that Den exposes a shape that can be read productively in
indexed / fibrational language.

## One-sentence reading
Den looks like a **context-indexed family of admissible configuration fragments**
with explicit context transitions and a resolution step that globalizes selected
fragments into a concrete Nix configuration.

## Pi-first reading for authoring
When writing Den top-down, a useful split is:

- Sigma side:
  declare the concrete witnesses that exist, such as `den.hosts`,
  `den.homes`, and other schema entities.
- Pi side:
  declare the aspects, batteries, and defaults that should hold uniformly
  whenever the relevant context witness exists.

This is not only for host configuration.
Use the same reading for any flake layer organized by Den contexts and target
classes.

## The strongest overlap
The deepest overlap with our language is this:

Den's dispatch condition is not primarily a separate boolean.
It is the **shape of the available context**.

A function requiring `{ host }` applies where `{ host }` exists.
A function requiring `{ host, user }` applies only where `{ host, user }`
exists.
So admissibility is carried by witness shape, not bolted on afterwards.

## Working translation table

| Den term | Premath / fibrational reading | Why this is reasonable |
|---|---|---|
| `den.hosts`, `den.homes`, schema entities | indexed objects / base data | they declare the entities over which configuration is organized |
| `den.ctx.*` | context objects in a small index category | each stage is a typed location of admissibility |
| `into.*` transitions | reindexing / context morphisms | they move from one admissible context shape to another |
| context providers (`_` / `provides`) | fibre-populating maps | they contribute aspect fragments at a context stage |
| aspects | local sections / admissible fragments | they assign configuration only where the context shape fits |
| parametric dispatch | witness-shaped admissibility | function arguments determine applicability |
| `includes` / `provides` DAG | dependency / refinement structure | they organize how fragments depend on and refine one another |
| `resolve <class>` | pushforward / collation into a target realization class | it gathers contributions into a class-specific module |
| `nixosSystem`, `darwinSystem`, HM configuration | concrete realization | final instantiation into a system-specific carrier |

## Candidate formalization
A plausible mathematical reading is:

1. there is a small category `C` of context shapes,
2. Den schema declarations pick concrete objects of `C`,
3. `into.*` gives morphisms or transition-generating maps in `C`,
4. each aspect behaves like a partial or admissible section over suitable
   objects of `C`,
5. `resolve <class>` collects these admissible fragments into a class-specific
   realization.

That is still an interpretation, not a theorem proved by Den.

## Where the analogy stops
Den's public docs give a rich context pipeline, but not yet the full structure
we would need for genuine fibre-bundle or descent language.

Missing pieces include:
- an explicit coverage notion
- local trivializations
- descent data and compatibility laws
- witness-carrying coherence proofs for gluing
- a spelled-out separation between local equivalence and global realization

So the strongest honest claim is:

> Den is **proto-fibrational** or **context-fibrational**.

## How to talk about it carefully
Good phrases:
- "Den gives a context-indexed family with explicit transitions."
- "Resolution behaves like a globalization step into a target class."
- "Top-down Den authoring can be read Sigma-first for witnesses and Pi-first for uniform aspects."
- "Den is closer to a configuration fibration than to a host tree."

Avoid:
- "Den already gives descent."
- "Den proves coherence."
- "Den is literally a fibre bundle."

## What would move it closer to our language
To really cross into our bundle / descent language, we would want:
1. an explicit site or coverage on contexts,
2. local triviality conditions,
3. descent-compatible gluing laws,
4. witnesses of admissibility that survive transformation,
5. a principled account of realization as a universal or colimit-like step.

## Suggested names in our stack
Conservative:
- **context-indexed configuration fibration**

A bit stronger:
- **admissible configuration bundle with class-specific realization**

Use the stronger phrase only if we define the missing coherence laws ourselves.
