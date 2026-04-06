---
name: nix
description: >
  Use this skill when Codex needs to understand, author, debug, or restructure
  a Nix, NixOS, Home Manager, nix-darwin, flake, or Den configuration. Trigger
  it for questions about flake exports, realized config values, evaluation
  failures, module or context wiring, Den authoring, or Den's conceptual
  mapping into indexed, Pi-first, fibrational, or bundle-style language.
  Prefer local repo inspection and narrow Nix CLI probes first, then targeted
  docs lookup, then validation.
---

# nix

## What this skill is
This is the operational artifact.

It is **not** a giant Nix encyclopedia.
It teaches the agent how to interrogate a live Nix repository or machine with a
small number of disciplined probes, and only then reach for documentation.

Treat `references/ARCHITECTURE.md` as the design note and
`references/DEN-IN-PREMATH.md` as the companion conceptual spec.
Read `references/DEN-AUTHORING.md` when the task is about writing or reshaping a
flake with Den or a Den-shaped design.
Read `references/NIX-TOOLING.md` when you need the concrete command order and
tooling discipline.

## Core doctrine
Default order:

1. detect the local shape,
2. classify the question,
3. run the smallest factual probe,
4. summarize the machine facts,
5. only then consult the narrowest relevant docs,
6. end with one concrete validation step.

The package exists because Nix docs are large, configuration topologies vary,
and Den introduces a second conceptual vocabulary on top of ordinary Nix.

Default Den design stance:
- start from concrete witnesses and outputs already present in the flake,
- treat schema as the Sigma side that says what exists,
- treat aspects and batteries as the Pi side that says what should hold
  uniformly where a context exists,
- keep aliases thin and validation concrete.

## Run this first
Unless the user already gave you a concrete failing installable or trace,
start with:

`python3 scripts/detect-shape.py .`

This tells you whether the repo looks like:
- a plain flake,
- NixOS,
- nix-darwin,
- Home Manager,
- Den,
- or some mixed shape.

Then route the task.

If the task is authoring rather than debugging, still start here, then inspect
the current `flake.nix` and only the narrow files responsible for the target
output or context family.

## Routing buckets

### 1) Topology
Use when the user asks:
- what does this flake export?
- what hosts or homes exist?
- how is this repo shaped?
- is this Den or ordinary flake wiring?

Default moves:
1. `python3 scripts/detect-shape.py .`
2. `scripts/probe-flake.sh .`
3. inspect only the relevant top-level files (`flake.nix`, the matching modules)
4. if docs are needed, read `references/DOC-LOOKUP.md`

Goal:
Produce a compact map of the repo's configuration domains and exported outputs.

### 2) Realized value / provenance
Use when the user asks:
- where does this value come from?
- why is this option set this way?
- what is the realized value of a config path?
- what does a host, darwin system, or home config actually evaluate to?

Default moves:
1. choose the correct domain (`nixos`, `darwin`, or `home`)
2. run `scripts/probe-config-path.sh <flake-ref> <domain> <name> <config-path>`
3. inspect the defining or overriding modules
4. use docs only for the exact option or semantic point at issue

Goal:
Separate the **realized value** from the **chain of definitions** that produced it.

### 3) Evaluation failure
Use when the user has:
- `attribute 'x' missing`
- `The option '...' does not exist`
- type mismatch
- import/path failure
- infinite recursion
- long `--show-trace` output

Default moves:
1. save or paste the trace
2. run `python3 scripts/classify-trace.py < trace.txt` if you have raw trace text
3. identify the first user-owned file
4. shrink to the smallest failing installable
5. run `scripts/probe-eval.sh '<installable>' [--show-trace]`
6. consult `references/FAILURE-TAXONOMY.md`

Do **not** start by reading giant docs pages.

Goal:
Find the first user-owned cause, not the deepest internal stack frame.

### 4) Den lens / conceptual mapping
Use when the user asks:
- what is Den doing structurally?
- is this feature-first or host-first?
- can we read this top-down from a Pi-type perspective?
- does Den resemble indexed contexts, fibrations, or fibre bundles?
- how should we translate Den into our own Premath vocabulary?

Default moves:
1. confirm the repo actually contains Den markers with `python3 scripts/detect-shape.py .`
2. inspect the specific `den.*` declarations the user is asking about
3. read `references/DEN-IN-PREMATH.md`
4. if needed, read `references/ARCHITECTURE.md`

Treat the mapping as an analogy and working translation, not an identity proof.

### 5) Authoring / design
Use when the user asks:
- how should we write or restructure this flake?
- how should we write Den top-down?
- what should live in schema vs aspects vs defaults?
- how do we use Den batteries or context pipeline correctly?
- can this be written for any flake output, not only host configs?

Default moves:
1. `python3 scripts/detect-shape.py .`
2. inspect `flake.nix` and only the narrow files involved in the target output
3. if Den is present, inspect the relevant `den.default`, `den.hosts`,
   `den.homes`, `den.aspects`, and `den.ctx.*` declarations
4. read `references/DEN-AUTHORING.md`
5. read `references/DEN-IN-PREMATH.md` only if the user wants the conceptual
   translation
6. validate the smallest working slice with focused eval or dry-run

Goal:
Produce the smallest working structural next step, not a giant redesign.

## Local-first rules
Prefer machine-readable local probes over prose docs:

- `python3 scripts/detect-shape.py .` for shape detection
- `scripts/probe-flake.sh` for flake topology
- `scripts/probe-eval.sh` for focused evaluation
- `scripts/probe-config-path.sh` for realized config values
- `python3 scripts/classify-trace.py` for quick trace triage
- `nix repl` only after the scope is already narrowed

If docs are needed, route them through `references/DOC-LOOKUP.md`.
Do not try to absorb the entire manual into context.
Read `references/NIX-TOOLING.md` when you need concrete command choices.

For Den authoring, prefer this order:
1. local flake shape
2. current output path or context path
3. local Den declarations
4. `references/DEN-AUTHORING.md`
5. official Den docs for the exact layer at issue

## Remote policy
Do not start with remote stores, remote REPLs, or remote machines.
Read `references/REMOTE-REPL.md` only when the target state truly lives
elsewhere and the local interrogation workflow is already stable.

## Deliverable shape
When answering the user, produce:
1. the routing bucket,
2. the smallest probe,
3. the factual result,
4. the conceptual reading,
5. the next validation step.

## References
- Read `references/ARCHITECTURE.md` to remember why this is a skill with a companion spec note.
- Read `references/DEN-AUTHORING.md` when the task is about writing or reshaping Den or a Den-shaped flake.
- Read `references/NIX-TOOLING.md` when you need command selection, validation order, or concrete tool use.
- Read `references/DOC-LOOKUP.md` when you need docs after local probing.
- Read `references/QUERY-ROUTING.md` if bucket selection is ambiguous.
- Read `references/FAILURE-TAXONOMY.md` for evaluation-failure triage.
- Read `references/DEN-IN-PREMATH.md` for the Den → Premath translation.
- Read `references/REMOTE-REPL.md` only if remote evaluation is genuinely required.
