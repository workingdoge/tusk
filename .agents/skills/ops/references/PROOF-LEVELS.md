# Proof levels and close-boundary rule

Do **not** start here.
Use this note once you already know what the operational question is and
what the flake is claiming.

This note exists because ops-shaped lanes keep collapsing two different
questions into one:

1. Does the structure evaluate cleanly?
2. Does the thing actually run against a live host or executor?

A structural probe is not a live proof, and a doc-shaped lane does not need
a live proof to be complete. This note names the rungs and the close
boundary so the two are not confused.

## The proof ladder

Read operational evidence as five rungs, in ascending cost and authority:

1. **Local flake inspection**
   Read the flake, grep for operational markers, open the narrow modules
   that define the surface under question. No evaluation yet.
   Tells you what the flake *claims*.

2. **Structural probe**
   Narrow `nix eval`, `nix flake show`, `nix build --dry-run`, and shape
   checks on derivations or declared outputs. Also: skill contract checks,
   spec readbacks, and other static validators.
   Tells you the declared structure evaluates cleanly and is internally
   consistent.
   Does **not** tell you the thing runs on any host.

3. **Lane-scoped local proof**
   Actually build or execute the narrow slice inside this lane's workspace
   against the lane's base revision. One-shot verification that the path
   works on this host, against this commit.
   Good for gating a handoff. Sufficient close evidence only for lanes
   whose landing boundary is structural (skill text, spec language, pure
   eval shape, doc-only changes).

4. **Live host smoke**
   Exercise the real effectful continuation: hits the target host or
   runtime, real network, real cache, real secrets, real receipts.
   Required before closing any lane that changed executor behavior, runtime
   admission, effect wiring, or published transport.
   A live host smoke is the first rung that proves the realization edge.

5. **Reusable executor-family promotion**
   The constructor has been proven across multiple lanes, its receipts
   repeat, its failure modes are characterized, and it has been admitted
   into the shared executor surface.
   This is a separate decision and a separate issue. Do not reach it by
   silently widening a lane that happened to pass a live smoke once.

## Close-boundary rule

Match the rung reached against the lane's declared landing boundary.

- **Skill, spec, doc, or pure-eval-shape lanes**
  Close on rung 2 (structural probe) plus, where applicable, rung 3 (a
  lane-scoped local proof such as `tusk-skill-contract-check`, a `nix eval`
  readback, or a `nix flake check` on the affected outputs).
  Do **not** demand a live host smoke for a skill-surface edit.

- **Executor, runtime, effect, admission, or transport lanes**
  Do **not** close on structural completion. Require at least rung 3 *and*
  rung 4 (a live host smoke on a representative target) unless the brief
  explicitly scopes the lane to structural-only landing.
  If the live smoke cannot run inside the lane, the lane lands as a handoff
  and the live proof is filed as a follow-up issue.

- **Promotion into an executor family**
  Always a separate issue. Never the implicit side effect of closing a
  working lane.

## What this prevents

- Closing an executor lane because `nix eval` succeeded on the declared
  output, while the runtime has never actually started.
- Reopening a doc lane because someone wanted a full live smoke for a text
  edit that cannot meaningfully smoke-test.
- Promoting a one-shot experimental constructor into the shared executor
  surface as an invisible side effect of "landing" a lane.

## Decision checklist

Before calling an ops-shaped lane done, answer:

1. What is the highest rung this lane actually reached?
2. What is the lane's declared landing boundary?
3. Is the rung I reached equal to or above that boundary?
4. If not, is the gap a follow-up issue, a handoff, or a scope error in the
   original issue?
5. Am I implicitly promoting something into a reusable executor family? If
   yes, stop and file that as its own issue.

If any of 3, 4, or 5 is unresolved, the lane is not cleanly closeable yet.

## Anti-patterns

Avoid:

- treating a passing structural probe as evidence that the thing runs
- demanding a live host smoke on a skill, spec, or doc-only lane
- collapsing handoff, close, and executor-family promotion into one action
- closing a runtime or effect lane when the live smoke has only ever run in
  the coordinator's head
