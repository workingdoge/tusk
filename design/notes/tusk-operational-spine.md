# Tusk Operational Spine — v0 Doctrine

Status: Draft v0 doctrine. Blocks lanes C through J.

This note locks the v0 operational spine for the LLC (workingdoge). It does not merely name where components run. It fixes the initial trust roots, the credential authority classes, the pure/observe/mutate/publish boundary, the bootstrap sequence, the collapsed trust regions on the v0 primary, the authority handoff conditions, the self-escalation defence, and the recovery path.

Without this lock, downstream lanes will drift on backend state, secret custody, CI trigger semantics, signing policy, and host bootstrap.

One-line summary: **the operational spine must lock trust geometry, not just service placement.**

## 1. Context

Today the LLC has no operational substrate in service.

What already exists:

- Cloudflare account.
- Latitude account (software-defined; tofu-addressable).
- `workingdoge.com` static landing page deployed via Wrangler.
- Existing Radicle-related tooling in `scripts/tusk-radicle.sh`, `tools/radicle-flake-wasm/`, and the `tusk-flake-ref` package.
- Existing cache-consume surface in `modules/cache.nix` and the `tusk.drivers.attic.cache` namespace (landed in `tusk-asy.2.38`).
- Existing ops skill material under `.agents/skills/ops/`.

What does not yet exist:

- No live Latitude host.
- No live Radicle seed.
- No live CI runner.
- No live binary cache bucket.
- No remote IaC state backend.
- No signing key in service.
- No secret materialization runtime beyond current spec direction (see `fish/sites/bridge/specs/secrets/secret-0002/`).

This note sets v0 doctrine only. It does not implement lanes C through J.

## 2. Locked architecture

### 2.1 Source transport

Radicle is canonical source transport. There is no GitHub mirror in v0.

Implication: CI must be self-hosted and must trigger from Radicle-native observation rather than GitHub-native webhooks.

### 2.2 Primary runner

One long-running Latitude bare-metal NixOS host is the v0 primary.

For v0, the primary co-locates:

- Radicle seed.
- CI broker and runner.
- Build host.
- Secret-decrypting runtime surfaces.
- Publish surfaces.

This is a temporary collapse of multiple trust regions into one machine. The collapse is explicit, not accidental. Section 4 names the compartments that MUST remain logically distinct inside the collapsed host.

### 2.3 Elastic compute

Additional Latitude instances may be introduced later as tofu-managed workers. Elastic compute is explicitly out of scope for v0.

### 2.4 CI pattern

The intended v0 path is broker-native Radicle CI.

Fallback polling is break-glass only. It is not co-equal architecture. If used at all, it exists only to close the first operational loop while preserving the same admission and publish boundaries defined in sections 2.10 and 7.

### 2.5 Credential custody

Operational credentials are handled with sops-nix.

Credentials that authorize mutation or publication decrypt only at effect-runtime on the target host. They MUST NOT enter flake evaluation, module evaluation, or other pure closures. Read-only observational credentials are governed by section 2.10.

Bridge materialization (`SECRET-0002 MaterializationSession`) remains the long-term target. That runtime does not yet exist. Retrofit into bridge is a later lane and MUST preserve the trust boundaries defined in this note.

### 2.6 Credentials by authority class

v0 distinguishes four authority classes. Confusing them creates the kind of delegated slop this note exists to prevent. Classify by authority, not by vendor.

**Trust roots** (long-lived, strictest custody, backed up off-host):

- Host machine age/sops identity used for long-lived encrypted custody.
- Radicle seed identity.
- Cache signing key (also a publish credential; strictest because it blesses artifacts for downstream consumers).
- Break-glass recovery material.
- Operator workstation trust anchor for first install.

**Publish credentials** (authorize canonical blessing of artifacts):

- Cache signing key (also a trust root).
- Publish-scoped tokens that upload artifacts to the cache origin under signing authority.

**Mutation credentials** (authorize state-changing provider calls):

- Cloudflare API tokens with write scope for admitted infra changes.
- Latitude API tokens with write scope for host and network provisioning.
- R2 write-scoped tokens used during effect-runtime.

**Observational credentials** (read-only; may appear above the admit line):

- Read-only Cloudflare tokens for `tofu plan` refresh and state reads.
- Read-only Latitude tokens for planning and host inspection.
- Read-only R2 tokens for remote-state reads during observational planning.

Trust roots require stricter custody, backup, and rotation policy than operational credentials. Publish credentials MUST NOT be confused with mutation credentials. Observational credentials are the only class that MAY appear during observational planning; all others enter only below the admit line (section 2.10). Signing authority is only exercised below the publish line.

### 2.7 IaC

OpenTofu is the sole v0 IaC tool for infrastructure resources.

One tofu tree manages:

- Cloudflare account resources needed for the ops substrate.
- Latitude bare-metal host resources.
- Related DNS and tokenized service plumbing.

Wrangler remains responsible for the existing frontend Worker deploy path and is not absorbed into tofu in v0.

### 2.8 Backend state and cache separation

Remote IaC state and Nix binary cache are separate planes.

- They MUST NOT share token scope.
- v0 SHOULD use separate buckets for remote state and binary cache.
- Prefix-only separation is a temporary concession and MUST be called out explicitly if used, with a follow-up to split buckets when cost or policy permits.
- They MUST be governed by separate lifecycle and access policies.

The state plane is control-plane data. The cache plane is data-plane distribution. They do not get treated as one blob.

### 2.9 Host install

Initial installation is destructive bootstrap via `nixos-anywhere` from the operator laptop to the Latitude bare-metal host.

Subsequent deploys occur in situ on the host.

Because the install path is destructive, it is treated as a trust transition, not as a routine deployment detail. Section 6.3 names the preflight checklist.

### 2.10 Pure vs effectful boundary

The boundary is not binary. v0 uses four stages:

1. **Pure evaluation** — flake evaluation, module evaluation, static checks, structural validation. No network, no credentials of any class.
2. **Observational planning** — reads, refreshes, and plans that may observe real provider state but do not mutate it.
3. **Admitted mutation** — infrastructure apply, host switch, Radicle publish, cache publish, and other state-changing effects.
4. **Publish and sign** — any act that blesses outputs for downstream consumers by signed publication or canonical promotion.

The **admit line** sits between observational planning and admitted mutation. The **publish line** sits after mutation and before public blessing.

Read-only observational credentials (section 2.6) MAY be used during observational planning when remote provider state must be read. Credentials that authorize mutation or publication MUST enter only below the admit line. Signing authority is only exercised below the publish line.

### 2.11 Code topology

Operational code lives in `fish/sites/workingdoge/cloud/`.

Expected sub-topology:

- `cloud/tofu/` for infrastructure resources.
- `cloud/host/` for host NixOS surfaces.
- `cloud/README.md` for the operator entrypoint.

Consumer-side configuration remains in home (`system/darwin/arj.nix`, `system/modules/determinate-nix-custom-conf.nix`; wired by `home-6xd`). Tusk remains the place for doctrine, specs, and skills. Bridge (`fish/sites/bridge`) remains the place for future secret and cache domain contracts.

## 3. Bootstrap root set

This section is mandatory. The v0 spine is not complete without it.

### 3.1 Required roots

Organized by authority class (section 2.6):

**Trust roots:**

- Operator bootstrap SSH key.
- Operator workstation trust anchor for first install.
- Host age/sops identity.
- Radicle seed identity.
- Cache signing key.
- Break-glass recovery material.

**Publish credentials:**

- Cache signing key (same object as the trust-root entry; named here for the publish axis).
- Publish-scoped R2 token for cache upload.

**Mutation credentials:**

- Cloudflare API token (write scope) for admitted infra changes.
- Latitude API token (write scope) for host and network provisioning.

**Observational credentials (optional in v0):**

- Read-only Cloudflare token for `tofu plan` refresh.
- Read-only Latitude token for host inspection.

### 3.2 Birthplace and first residence

Each root MUST declare:

- Where it is generated.
- Where it first resides.
- How it is backed up.
- Who may rotate it.
- Whether it is hot, warm, cold, or burnable.

### 3.3 v0 residence rules

- Cloudflare and Latitude operator tokens (mutation class) may begin life on the operator laptop under local encrypted custody until the host exists. They migrate to host-held sops custody once the primary is authoritative (section 3.4).
- Host age identity is generated on the host after first successful bootstrap, then exported to an encrypted recovery package that leaves the host.
- Radicle seed identity is generated in the host trust domain and backed up offline in encrypted form.
- Cache signing key is generated in the host trust domain, or injected once into a narrow publish compartment, then backed up offline in encrypted form.
- Break-glass recovery material MUST exist off-host before the primary becomes authoritative.
- Observational credentials, if used, SHOULD be separate tokens from mutation credentials, not a down-scoped copy of the same token.

### 3.4 Authority handoff to the primary

The v0 primary becomes authoritative only when all of the following hold:

- Remote tofu state has been migrated off local bootstrap state.
- Host custody identity has been generated and backed up off-host.
- Break-glass recovery material exists off-host.
- Host ingress is known and verified.
- The kill switch path is documented.
- Operator runbook reflects the new control-plane location.

Until all six hold, the operator workstation remains part of the active control plane. Lanes that depend on the primary being authoritative (H, I, J) MUST NOT begin before handoff is declared complete.

## 4. Trust compartments on the v0 primary

The v0 primary is one machine but four compartments.

### 4.1 Compartments

The host contains at least these logical regions:

- **Seed compartment** — Radicle node and persistent seed state.
- **Runner compartment** — CI broker and job orchestration.
- **Build compartment** — sandboxed builds.
- **Custody / publish compartment** — secret decryption, signing, controlled publish.

v0 collapses custody and publish into one compartment for operability; future versions SHOULD split them once elastic compute exists. The collapse is tracked as a named debt, not a permanent design.

### 4.2 Minimum separation

Even on one machine, v0 MUST aim for:

- Separate service users.
- Separate state directories.
- Separate systemd units.
- Narrow filesystem permissions.
- No runner read access to seed private state.
- No generic builder access to decrypted secret material.
- No broad signing authority in the runner itself.

### 4.3 Security stance

A CI escape MUST NOT automatically imply total sovereignty loss.

v0 will not perfectly achieve that on one host, but this is the bar that all service layout decisions must target. When elastic compute arrives, the compartments split across machines along exactly these boundaries.

## 5. Network exposure and egress policy

### 5.1 Public ingress

No CI control surface, publish compartment, or custody surface SHOULD be internet-reachable in v0 unless the justification is explicitly written down and reviewed. Default posture for control surfaces is not-public.

The host NixOS config (lane E) MUST declare:

- Whether SSH is public or restricted (source IP allow-list expected).
- Whether the Radicle seed is public.
- Whether any CI control surface is public (default: no).
- Whether cache distribution is direct, proxied via Cloudflare, or deferred.

### 5.2 Administrative ingress

Administrative access SHOULD be as narrow as possible and SHOULD NOT be shared with general CI execution paths.

### 5.3 Job egress

CI and build jobs MUST NOT assume unrestricted internet egress by default. Any required outbound classes SHOULD be named, for example:

- Provider API access for admitted infra changes (Cloudflare, Latitude).
- Cache publish path (R2 endpoint).
- Source transport path (Radicle seeds).
- Package fetches, if allowed.

### 5.4 Default posture

Default-deny is the desired posture. Any broader egress in v0 is a temporary concession and MUST be named as such in lane E.

## 6. Recovery, break-glass, and destruction doctrine

### 6.1 Recovery is first-class

The primary is not real unless it can be lost and reconstructed.

### 6.2 Minimum recoverables

The following MUST be recoverable off-host:

- Tofu state.
- Radicle persistent state or seed identity sufficient to reconstitute authority.
- Cache signing key.
- Host decryption identity or equivalent recovery path.
- Operator runbook sufficient to re-bootstrap service.

### 6.3 Install transition

The first `nixos-anywhere` install is destructive. Lane F MUST preflight:

- Target host identity confirmed.
- Disk layout confirmed.
- Recovery package prepared off-host.
- Operator access path verified.
- Expected post-install ingress known.

### 6.4 Kill switch

v0 MUST define a documented kill switch that can:

- Stop CI execution.
- Stop publish and sign.
- Preserve read-only diagnostic access where possible.

The kill switch lives in the custody/publish compartment (section 4.1), not the runner.

### 6.5 Recovery rehearsal

Untested recovery is fiction.

Before lanes H or I, the operator MUST perform at least one documented recovery rehearsal sufficient to prove that off-host material can reconstruct control-plane continuity. A tabletop-only rehearsal is acceptable for v0 if destructive restore is too expensive, but the exact gaps MUST be written down and carried as explicit residual risk until a live rehearsal is feasible.

## 7. CI doctrine

### 7.1 Target

The target is Radicle-native CI observation and execution.

### 7.2 Admission model

CI does not mean "execute on new commits."

CI means:

- **Observe** — detect that new commits or refs have appeared.
- **Evaluate** — run pure-eval and structural checks.
- **Plan** — produce an observational plan of intended effects (may use observational credentials per section 2.6).
- **Admit** — cross the admit line under explicit policy.
- **Realize** — execute admitted effects using mutation credentials.
- **Optionally sign/publish** — cross the publish line under explicit policy, using publish credentials.

These are distinct stages, not a single pipeline step.

### 7.3 Fallback

Polling fallback, if used, MUST preserve the same admission and publish boundaries and MUST NOT silently widen authority.

### 7.4 Policy-repo non-self-escalation

A repository or ref that defines CI policy, signing policy, host deployment policy, secret bindings, or admission rules MUST NOT be able to self-authorize expansion of its own authority merely by changing the files the runner interprets. Changes to policy-bearing surfaces require a stronger admission path than ordinary workload changes.

In v0, runner policy and publish authority are treated as higher-trust control-plane surfaces even if their source lives in the same Radicle universe. Ordinary workload changes ride the normal CI admission path; changes to policy-bearing surfaces ride a more restrictive path named in lane E (operator-gated at minimum).

## 8. IaC state bootstrap doctrine

This is the bootstrap knot. It cannot be skipped.

You cannot begin with remote R2-backed tofu state before the remote-state plane exists.

v0 explicitly uses a two-step backend bootstrap:

1. **D0 — bootstrap apply with local state only.** Create the remote-state bucket and the narrowly-scoped credentials needed for remote backend use. Nothing else in this step.
2. **D1 — immediate migration to remote backend.** Move tofu state into the dedicated remote-state plane. Only then grow infrastructure further (cache plane, DNS, host resources).

After migration, local bootstrap state is transitional residue and is cleaned or archived under explicit operator control.

This is not optional. Without this split, lane D would improvise state management and create future drift.

## 9. Signing doctrine

The signing key does not yet exist, but the policy is locked now.

### 9.1 Signed publish surface

Only explicitly named artifacts may be published under signing authority. v0's signed publish surface is the Nix binary cache (`narinfo` signing). Any additional signed surface is a separate policy decision.

Unsigned store production does not imply publish eligibility. Artifacts that exist in the build compartment's Nix store are candidates; only those that pass the publish line (section 2.10) are blessed for downstream consumers.

### 9.2 Separation of build from bless

The component that builds an artifact MUST NOT automatically be the component that blesses it for downstream consumption.

### 9.3 v0 stance

v0 may physically co-locate build and sign on one machine, but they remain logically distinct stages with distinct authority. The build compartment (section 4.1) produces unsigned store paths; the custody/publish compartment signs and uploads. Inter-compartment hand-off is via filesystem paths, not shared process state.

## 10. Out of scope

Explicitly out of scope for this note and this coordinator cycle:

- Hercules CI adoption.
- GitHub mirroring.
- `atticd` in v0 (the Nix native S3 binary cache against R2 is sufficient).
- Elastic compute in v0.
- Bridge materialization runtime in v0.
- Full host implementation details (delegated to lane E).
- Actual tofu code (delegated to lanes C and D0/D1).
- Actual resource provisioning (delegated to D0/D1).
- Actual Radicle seed setup (delegated to E).
- Actual signing key generation (delegated to G).
- Actual home flip (delegated to H).
- Actual workingdoge Radicle publish (delegated to I).
- Observed CI closed-loop execution (delegated to J).

## 11. Lane sequence after doctrine lock

This note unblocks the lanes below but does not implement them. Each gets its own bd issue filed after this note lands.

- **C** — scaffold `cloud/tofu/`, `cloud/host/`, `cloud/README.md`.
- **D0** — tofu bootstrap apply with local state only; create remote-state plane (state bucket, scoped token).
- **D1** — migrate tofu state to remote backend; then create cache plane, DNS, and host resources.
- **E** — host NixOS config with compartments (section 4), seed, CI broker, sops receiver, disko layout, network posture (section 5), policy-surface admission path (section 7.4).
- **F** — `nixos-anywhere` bootstrap onto Latitude host (section 6.3 preflight).
- **G** — signing key generation and narrow publish wrapper with build/bless separation (section 9).
- **H** — home flip to `tusk.drivers.attic.cache.public.enable = true` with real URL and pubkey; gated on section 3.4 handoff and section 6.5 rehearsal.
- **I** — workingdoge Radicle publish against registered RID using `tusk-radicle init-existing`; gated on section 3.4 handoff and section 6.5 rehearsal.
- **J** — observe CI closed loop under admission discipline (section 7.2) with policy-surface non-self-escalation (section 7.4).

## 12. Acceptance criteria

This note is acceptable only if it states, plainly and concretely:

- What the control plane is (section 2.8).
- What the data plane is (section 2.8).
- What the bootstrap roots are (section 3.1).
- How credentials are classified by authority (section 2.6).
- Where the admit line sits (section 2.10).
- Where the publish line sits (section 2.10).
- Which credentials may appear above the admit line (section 2.10).
- Which trust regions are collapsed on the v0 primary (sections 2.2, 4.1).
- The conditions for authority handoff to the primary (section 3.4).
- How recovery works (section 6).
- That recovery is rehearsed before public dependence (section 6.5).
- How tofu backend bootstrap works (section 8).
- What CI is allowed to do (section 7).
- How policy-surface self-escalation is prevented (section 7.4).
- What is explicitly not in scope (section 10).

If any of those are missing, the note is not spine doctrine. It is just topology prose.
