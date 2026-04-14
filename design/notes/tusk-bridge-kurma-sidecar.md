# Tusk Bridge/Kurma Sidecar Surface

## Status

Repo-scoped placement and deployment note for the first local Bridge/Kurma
sidecar system operated through `tusk`.

## Intent

`tusk` should own the outer deployment, launch, monitor, and receipt seam for a
local sidecar system that consumes:

- Bridge-owned interpretation and admission doctrine
- Kurma-owned runtime and carrier realization

It should not absorb:

- Bridge meaning
- `KCIR` carriage
- or `Nerve` semantics

This note exists to keep the first local sidecar topology bounded and to keep
the repo split honest once Bridge and Kurma already have cleaner upstream
homes.

## Layering

The intended split is:

- `bridge`: canonical meaning for foreign observation interpretation and bridge
  admission
- `kurma`: runtime realization of carried artifacts, witnesses, commitments,
  receipts, and theory-local coordination
- `tusk`: deployment, operator control, receipt recording, and repo-local
  workflow around those realized surfaces

`Nerve` stays inside the `kurma` layer as a higher-level coordination and
coherence surface over carried runtime objects. It is not the outer operator
control plane.

## First Local Topology

The first local deployment should be read as:

```text
operator / CI / automation
        |
        v
      tusk
  - mkNixosSystem entrypoint
  - deploy / launch / inspect / receipt
  - operator-facing checks and projections
        |
        v
  local host or later local microvm
        |
        +--> Caddy
        |
        +--> Bandit or Cowboy
                |
                v
          Kurma sidecar runtime
          - Bridge-owned interpretation binding realized in code
          - KCIR admission and carriage
          - Nerve coordination over carried runtime objects
          - local state, artifacts, and receipts
                |
                v
          SQLite + local artifact store
```

Important reading:

- Bridge is not required to be a separate long-running process in this topology.
  The canonical Bridge contract constrains the meaning and admission boundary.
- Kurma is the runtime shell that realizes that boundary locally.
- Tusk operates around the realized system rather than redefining it.

## Ownership

### `bridge` owns

- interpretation-binding doctrine
- admission semantics
- canonical type-family placement
- public meaning for the adapter boundary

### `kurma` owns

- runtime/carrier realization
- `Premath -> KCIR` method
- `Nerve` as a carried coordination layer
- validators, artifact production, and local durable runtime state

### `tusk` owns

- the machine or VM composition that runs the sidecar
- service wiring around stable Bridge/Kurma surfaces
- operator commands such as deploy, status, health, and receipt collection
- launch receipts, health receipts, and projection of runtime state into repo
  workflow

### downstream repo owns

- product-specific policy
- funded operator state
- consumer-local secrets or env binding
- any live proof that depends on one concrete operator environment

## First Deployment Rule

The first shared deployment path should stay boring:

1. use `tusk.lib.mkNixosSystem` as the first stable machine builder surface
2. run one local-first sidecar system on that machine
3. attach a local microvm only after the operator seam is stable

This follows the existing platform and isolation notes:

- `tusk-platform-surface.md` for stable builder entrypoints
- `../tusk-isolation-attachment.md` for later container or microvm attachment

Kubernetes is not the first move here. The first problem is not cluster
orchestration. It is getting one local operator-controlled sidecar system to be
deployable, inspectable, and receipt-bearing through stable Tusk surfaces.

## Current Module Surface

The first concrete Tusk host surface now lives at:

- `modules/bridge-kurma-sidecar.nix`
- exported as `nixosModules.bridge-kurma-sidecar`

It intentionally owns only:

- one systemd service unit
- state and artifact directory creation
- and optional Caddy reverse-proxy wiring

It still expects the caller to supply the actual runtime `ExecStart`, so the
host surface stays thin and does not become the semantic owner of the Kurma
runtime.

## Edge And Runtime Guidance

For the first local deployment:

- prefer `Caddy` as the public or operator-facing edge when an external HTTP
  edge is needed
- keep `Bandit` or `Cowboy` as the inner HTTP service boundary when the runtime
  stays inside the BEAM stack
- treat `H2O` as an optional later edge optimization, not as the semantic
  center

The main cost center is expected to be interpretation, lineage, carrier
admission, and receipt persistence, not HTTP parsing alone.

## First Tusk Wire

The first Tusk-owned wire is:

- input context:
  stable Bridge contract, stable Kurma runtime/API surface, one local host
  profile
- output artifact:
  one running local sidecar system plus deployment/status/receipt surfaces
- verification boundary:
  Tusk builder evaluation and sidecar operator-surface checks
- landing boundary:
  one Tusk note and later one bounded deployment lane that consumes it

This keeps the wire on the operator/deployment side of the system.

## Working Rule

When a new slice touches this topology:

- if it changes meaning or doctrine, move it to `bridge`
- if it changes carrier/runtime method, move it to `kurma`
- if it changes deploy, launch, monitor, receipts, or operator control around
  stable upstream surfaces, keep it in `tusk`

That is the boundary that keeps `tusk` from turning into a second half-compiler
with workflow state bolted onto it.
