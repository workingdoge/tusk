# Tusk Knowledge Layer

## Status

Decision note for the repo-local knowledge layer that should support `tusk`
automation, synthesis, and long-horizon design work.

## Intent

`tusk` should keep a maintained synthesis layer between raw sources and live
operational authority.

That layer exists so the repo can accumulate understanding over time without
forcing every query, lane, or agent session to rediscover the same cross-source
connections from scratch.

The rule is:

- sources are observed
- knowledge is compiled
- authority decides truth

## Why This Exists

The control plane now has enough structure to govern real work:

- tracker issue truth
- lane truth
- receipts
- governed landing
- bounded autonomous execution

What it still lacks is a durable learning surface.

Without that layer, useful synthesis stays trapped in:

- chat history
- lane-local reasoning
- one-off design notes
- remembered but unfiled connections between `tusk`, `kurma`, `fish`,
  `Premath`, `Nerve`, and `WCAT`

The knowledge layer fixes that by making synthesis reviewable, rewriteable, and
repo-local.

## Three Layers

### 1. Raw Sources

These are the observed inputs.

Examples:

- upstream repo snapshots
- notes from `fish`, `kurma`, `home`, and other downstream repos
- receipts and lane records
- protocol docs
- operator observations
- runtime outputs from `tuskd`, `jj`, `bd`, and verification commands

Rules:

- raw sources are evidence
- raw sources should be immutable or treated as append-only observations
- mutable sources should be anchored by repo, revision, file path, URL, or date
- the knowledge layer may read raw sources but should not silently rewrite them

### 2. Compiled Knowledge

This is the maintained synthesis layer.

Examples:

- topology notes
- concept pages
- boundary notes
- comparison notes
- timeline summaries
- source-linked answers worth keeping

Rules:

- compiled knowledge may be rewritten as understanding improves
- compiled knowledge should point back to the sources it synthesizes
- compiled knowledge may record contradiction, uncertainty, or stale claims
- compiled knowledge is not live authority

### 3. Schema And Authority

These are related but distinct.

Schema tells agents how to maintain the knowledge layer and the repo.

Examples:

- `AGENTS.md`
- shared skills
- ingest conventions
- note structure rules

Authority answers what is live right now.

Examples:

- `tuskd`
- tracker issue state
- lane state
- receipts
- operator projections

Rules:

- schema governs maintenance
- authority governs live truth
- compiled knowledge may guide operators, but does not replace authority

## Storage Path

The first repo-local path should be:

```text
knowledge/
  README.md
  index.md
  log.md
  sources/
  wiki/
```

Where:

- `knowledge/sources/` holds raw source packets and pointers
- `knowledge/wiki/` holds compiled pages
- `knowledge/index.md` is the content index
- `knowledge/log.md` is the append-only chronology

## Layering Read Through Premath, Nerve, And WCAT

These names should be read as shaping analogies, not imported theorem objects.

### Premath-Style Ingress

The knowledge layer should begin by normalizing source observations into stable
source packets:

- source identity
- origin
- revision or date
- kind
- local anchors
- short summary

This is the "what was actually observed?" seam.

### Nerve-Style Synthesis

Compiled pages should then carry the connective tissue between observations:

- entities
- topics
- boundaries
- relations
- tensions and contradictions
- evolving theses

This is the "how do these observations hang together?" seam.

### WCAT-Style Projections

Finally, `tusk` should expose stable, reviewable outputs over that compiled
knowledge:

- `index.md`
- `log.md`
- summaries
- comparison pages
- operator-facing briefings
- receipted answers worth filing back into the repo

This is the "what stable artifact can another agent or operator consume?"
seam.

The important rule is:

- do not confuse the compiled knowledge layer with theory authority
- do not confuse projections with live control-plane authority

## Control-Plane Boundary

The knowledge layer helps the control plane, but it is not the control plane.

So the split stays:

- live issue, lane, backend, and receipt truth belongs to `tuskd` and the
  tracker substrate
- maintained synthesis belongs under `knowledge/`
- maintenance rules belong in schema files such as `AGENTS.md` and shared
  skills

## Operating Loop

1. Ingest one source or one bounded source batch.
2. Extract or update a source packet under `knowledge/sources/`.
3. Update the relevant compiled pages under `knowledge/wiki/`.
4. Refresh `knowledge/index.md`.
5. Append one entry to `knowledge/log.md`.
6. If the new knowledge implies work, emit a follow-up issue or receipt-linked
   summary.

## Query Loop

When answering a question from the knowledge layer:

1. read `knowledge/index.md`
2. open the relevant compiled pages
3. follow source anchors when a claim needs checking
4. answer from the compiled layer
5. if the answer is durable, file it back as a new page or page update

## First Executable Follow-Ups

1. Define one source-packet template under `knowledge/sources/`.
2. Define one compiled page template under `knowledge/wiki/`.
3. Teach lane closeout to optionally emit a knowledge update.
4. Add a tiny repo-local search helper once `index.md` stops being enough.

## Final Read

The architecture is:

- raw sources stay observable
- compiled knowledge stays reviewable and rewriteable
- schema governs how agents maintain it
- authority remains in the tracker, lanes, receipts, and `tuskd`

That gives `tusk` a real memory path without relocating operational truth into
chat sessions or runtime homes.
