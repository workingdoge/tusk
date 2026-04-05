# Architecture note: skill first, spec note second

## The decision
This package is **a skill with a companion spec note**, not a standalone spec
that happens to mention skills.

Why:
- the agent needs an operational doctrine it can load and execute,
- the conceptual Den ↔ Premath mapping is real but only needed on demand,
- Agent Skills are built around progressive disclosure, so deep theory belongs
  in references rather than in the main `SKILL.md`.

## Core design rule
Carry **method**, not **environment**.

Good skill content:
- how to distinguish topology from provenance from evaluation failure
- how to move from a flake's present shape into the next small authoring step
- which probe to run first
- how to narrow a failing surface
- when to consult docs
- how to validate

Bad skill content:
- one particular hostname
- one exact secrets path
- one frozen flake layout
- machine-specific facts that should be discovered from the repo

## Why one skill, not five
A future split into several skills might make sense, but the current package is
deliberately coarse-grained because these activities still form one coherent
workflow:

1. detect shape
2. interrogate topology or value
3. diagnose failures
4. optionally design the next authoring slice
5. optionally switch into a Den lens

Splitting too early would risk a family of skills that all activate together.

## How to know when to split later
Split the package only if one of these becomes true:
- Den-specific work starts dominating activations
- runtime / activation failures need a very different procedure from eval failures
- packaging / overrides / devshell work becomes a separate recurring workflow
- the description starts triggering too broadly

At that point, good child skills would be:
- `nix-topology`
- `nix-eval-diagnosis`
- `nix-runtime-activation`
- `den-lens`

## Why CLI-first
Nix documentation is large and many user questions are really questions about
the **local state of a particular flake**. The CLI gives facts about *this*
repo; docs explain those facts after the relevant surface has been localized.

That is why the discipline is:

1. local shape
2. local probe
3. smallest structural move if the task is authoring
4. narrow docs
5. validation

## Why Den notes stay separate
The Den mapping and Den writing workflow are useful, but they are still narrower
than ordinary Nix debugging. Keeping them in references lets the main skill stay
procedural while preserving both the higher-level language and a Pi-first
authoring note.
