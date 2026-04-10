# Tusk Architecture

## Status

Second design sketch for `tusk` as a reusable Nix-native operational layer.

This revision tightens the core semantics. The first sketch had the correct
center, but it compressed too many axes into a single `effect -> adapter`
shape. This note separates witness production, intent declaration, admission,
realization, and receipts before more backend code accumulates.

## Intent

`tusk` should package the operational side of a Nix flake the way a config
library packages the configuration side.

The semantic center is now:

1. verified base entries that emit witnesses,
2. declared intents that consume those witnesses,
3. an admission boundary that decides whether an intent is runnable,
4. realizations that bind admitted intents to an executor and a driver,
5. and receipts that record what the realization claimed or did.

This is not generic "devops".
It is a Nix-native operational calculus that can be exported and reused by
other flakes.

## Why Flake Parts

For `tusk`, `flake-parts` is still the right first substrate.

Reasons:

- we want a reusable export surface, not just one repo-local script pile;
- we want module/options composition for operational surfaces;
- we want to expose `flakeModules.tusk` and related adapter modules cleanly;
- and we want consumers to import a stable operational layer without adopting
  this repo's whole flake shape.

`flake-parts` gives a packaging and composition shell.
It does **not** define the semantics of `tusk`; it only carries them.

## Why Not Den As The Center

Den remains the right place to think about configuration contexts and
admissibility in the config world.

`tusk` is different:

- its base is a verified operational substrate,
- its witnesses are attested operational inputs,
- its intents are operational continuations,
- and its realizations externalize those continuations into a backend.

So the clean boundary remains:

- Den may produce realized configurations or artifacts,
- `tusk` consumes those as operational inputs,
- but `tusk` itself should not depend on Den as its primary substrate.

They should rhyme. They should not collapse into one system.

## Semantic Spine

The core model should read as:

`witnesses -> intents -> admission -> realization -> receipts`

This is stronger than a plain
`checks -> effects -> adapters`
shape because it preserves:

- dataflow, not just control-flow;
- authority, not just declaration;
- transport, not just target;
- and traceability, not just execution.

## Core Object Model

### 1. Verified Base

The verified base is the pure layer.

It contains:

- flake checks,
- package builds,
- configuration dry-runs,
- structural validations,
- and any other reproducible evaluation step that does not require operational
  secrets or mutable external state.

But a base entry is not only "pass/fail".
It emits one or more witnesses.

Prototype shape:

```nix
tusk.base."<name>" = {
  systems = [ "x86_64-linux" "aarch64-darwin" ];
  kind = "darwin-dry-run";
  installable = ".#darwinConfigurations.arj.system";

  witnesses.plan = {
    kind = "darwin.plan";
    format = "installable";
  };
};
```

The important invariant is:
effects should consume witnesses, not merely follow a passed job by name.

### 2. Declared Effects

Effects are declared operational intents over verified witnesses.

They should say:

- which verified base entries they depend on,
- which emitted witnesses they consume,
- which capabilities they require,
- and what semantic intent they express.

Prototype shape:

```nix
tusk.effects.update-flake-lock = {
  requires.base = [ "lock-validate" ];
  requires.capabilities = {
    secrets = [ "secret.github-token" ];
    authorities = [ "forge.pr.write" ];
    state = [ "repo.branch:automation/lock" ];
    approvals = [ "policy.automation" ];
  };

  inputs = [ "base.lock-validate.patch" ];

  intent = {
    kind = "forge.pull-request.open";
    target = "origin";
  };
};
```

The effect declaration is not authority.
It is only a proposal.

### 3. Admission

Admission is the boundary between declaration and authority.

An effect may be declared in the flake without being admitted.

Admission should depend on:

- successful base witnesses,
- required witness availability,
- capability availability,
- approval or policy requirements,
- and executor support.

`tusk` should therefore preserve a distinction between:

- declared effects,
- structurally admissible effects,
- and realized effects.

The planner must not silently become the authority.

### 4. Executors

Executors are the authority/runtime axis.

Examples:

- `local`
- `hercules`
- later perhaps `github-runner` or other controlled runtimes

Prototype shape:

```nix
tusk.executors.hercules = {
  enable = true;
};
```

An executor answers:
"where, and under what authority, can this effect run?"

### 5. Drivers

Drivers are the target-system axis.

Examples:

- `drivers.github.origin`
- later `drivers.attic.cache`
- later `drivers.deploy-rs.prod`

Prototype shape:

```nix
tusk.drivers.github.origin = {
  repo = "owner/repo";
};
```

A driver answers:
"how do we talk to the external system we are targeting?"

This is distinct from executor choice.

For example:

- execute on Hercules,
- target GitHub.

Those are different axes and should stay different in the schema.

### 6. Realizations

Realization is the compiled binding of:

- one effect,
- one executor,
- and one driver.

Prototype shape:

```nix
tusk.realizations.update-flake-lock = {
  effect = "update-flake-lock";
  executor = "hercules";
  driver = "github.origin";

  receipt.kind = "forge.pull-request";
};
```

The semantic center stays upstream.
Realization is deliberately downstream of intent and admission.
For repo-placement rules across `fish`, `kurma`, and `tusk`, see
[`design/migration-candidates/tusk-upstream-boundary.md`](../migration-candidates/tusk-upstream-boundary.md).

### 7. Receipts

Receipts should exist in v0, even minimally.

We do not need the grand final receipt model yet, but we do need a structural
place for:

- effect name,
- executor,
- driver,
- result mode,
- and an external reference when one exists.

That buys us:

- traceability,
- idempotence hooks,
- replay discipline,
- and backend correlation.

## Capability Model

This should not remain a vague "later" concern.

At minimum, `tusk` should distinguish:

- secret references
  e.g. `secret.github-token`
- resource authorities
  e.g. `forge.pr.write`
- mutable state scopes
  e.g. `repo.branch:automation/lock`
- approval classes
  e.g. `policy.automation`

If those remain mushed into generic strings like
`secrets = [...]` and `state = [...]`
without a stable vocabulary, the operational model will decay into untyped
workflow plumbing.

## Export Surface

The export surface is still:

```nix
flake.flakeModules.tusk
flake.flakeModules.tusk-github
flake.flakeModules.tusk-hercules
flake.lib.tusk
```

Likely roles:

- `flakeModules.tusk`:
  core options and normalization for base, witnesses, effects, executors,
  drivers, realizations, and receipts
- `flakeModules.tusk-github`:
  GitHub driver support
- `flakeModules.tusk-hercules`:
  Hercules executor support
- `lib.tusk`:
  constructors, normalizers, and helper combinators

The first priority remains a stable module and library surface.

## Likely Flake-Parts Shape

The internal implementation should still use:

- top-level `flake.flakeModules`
- top-level `flake.lib`
- `perSystem` for system-dependent helper packages or checks
- module options under a `tusk.*` namespace

The core options should now look closer to:

```nix
tusk.enable
tusk.base
tusk.effects
tusk.executors
tusk.drivers
tusk.realizations
```

This keeps the semantic axes explicit and gives us a place to normalize
declarations before any backend code is emitted.

## Semantic Core Versus Transport

Keep this distinction hard:

See also [`design/tusk-transition-carrier.md`](./tusk-transition-carrier.md)
for the runtime-side carried seam that applies this semantic spine to the
existing `tuskd` transition surface, and
[`design/tusk-governed-transition-kernel.md`](./tusk-governed-transition-kernel.md)
for the updated kernel vocabulary that separates proposal-side agents from the
authority-bearing runtime, plus
[`design/tusk-governed-transition-adapters.md`](./tusk-governed-transition-adapters.md)
for the adapter map beneath that kernel.

### Semantic core

- verified base entries
- emitted witnesses
- declared intents
- admission state
- capability requirements
- executor and driver binding
- receipt expectations

### Transport and backend layers

- GitHub workflow generation
- Hercules effects emission
- deploy-rs integration
- cache publication integration

If this boundary becomes blurry, `tusk` will collapse back into tool wrappers.

See also [`design/migration-candidates/tusk-paid-http-protocol-boundary.md`](../migration-candidates/tusk-paid-http-protocol-boundary.md)
for the first incubation-boundary example that separates reusable paid-request
protocol artifacts from consumer-local mode policy and wallet-local execution,
plus [`design/migration-candidates/tusk-paid-http-executor-contract.md`](../migration-candidates/tusk-paid-http-executor-contract.md)
for the wallet-agnostic settlement seam beneath the paid-http kernel.

## First Useful Slice For This Repo

The first repo-local slice should still stay small.

Recommended initial base:

- `codex-nix-check`
- Darwin dry-run
- skill validation for repo-local skills

Recommended first execution path:

1. compile the normalized `tusk` graph,
2. inspect a local trace-style realization,
3. then bind the same effect to GitHub or Hercules.

Recommended first remote effect:

- open or refresh a `flake.lock` update PR

Why this is still the right first remote effect:

- it is clearly post-validation,
- it uses capabilities and mutable state,
- it does not require immediate deployment infrastructure,
- and it exercises the full witness -> intent -> realization path.

## Current Typeholes

These should stay explicit for now:

See also [`design/tusk-semantic-spine-map.md`](./tusk-semantic-spine-map.md)
for the current-tree map of what is already implemented structurally versus
what remains conceptual.

1. Admission policy
   We can model structural readiness now, but the exact runtime or policy
   admission interface still needs tightening.

2. Witness payload typing
   Witness identity is modeled now, but richer payload typing can come later.

3. Executor support matrix
   We still need to decide how much of executor admissibility lives in core
   versus executor-specific modules.

4. Receipt enrichment
   v0 receipts exist structurally, but not yet as a full runtime record.

5. Transition carrier
   The runtime-side carried transition object and admission law now live in
   [`design/tusk-transition-carrier.md`](./tusk-transition-carrier.md); the
   governed transition kernel vocabulary now lives in
   [`design/tusk-governed-transition-kernel.md`](./tusk-governed-transition-kernel.md);
   the operator-facing information architecture now lives in
   [`design/tusk-operator-ux-model.md`](./tusk-operator-ux-model.md);
   the
   first Rust-owned specialization for backend ensure and service publication
   now lives in
   [`design/tusk-backend-service-carrier.md`](./tusk-backend-service-carrier.md),
   and the current shell implementation still needs to be rewritten around
   that seam.

These are acceptable holes.
They should not block the schema rewrite.

## Follow-Up Work

This note should now split naturally into:

1. rewrite the core `flakeModules.tusk` surface around witnesses, admission,
   executor/driver split, and receipts
2. add a local trace/null executor for dry operational planning
3. implement one driver, probably GitHub
4. implement one executor, probably Hercules
5. connect `config-8vr.2` so skills and tool surfaces can be exported through
   the same flake story

The first part of step 2 now exists as the repo-local `local-trace` executor
and `tusk-trace-executor` runtime entrypoint described in
[`design/tusk-local-trace-executor.md`](./tusk-local-trace-executor.md).

The first part of the fixed-point loop now exists as
[`design/tusk-self-host-automation.md`](./tusk-self-host-automation.md):
`tuskd self-host-run` uses the declared witness graph to run the real repo
checks/builds, then records both `effect.trace` and `self_host.run` receipts.

## Recommendation

Proceed as if:

- `flake-parts` is the packaging substrate,
- `tusk` is the operational semantics layer,
- effects consume witnesses rather than bare passed checks,
- admission remains distinct from declaration,
- executors and drivers are different axes,
- receipts exist from v0,
- Hercules remains the most promising executor backend,
- GitHub remains a driver/transport layer rather than the semantic center,
- and Den stays adjacent, not foundational, for this part of the system.
