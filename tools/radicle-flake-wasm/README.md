# radicle-flake-wasm

Prototype a Wasm-targetable resolver from `rad:` repository identifiers to
immutable fetch metadata that ordinary Nix flakes can consume.

## Why this exists

`tusk` should not make its stable flake contract depend on an experimental
fetch path. The near-term contract stays on ordinary Git refs such as `main`.

This repo exists to prove a narrower idea:

1. take a Radicle repository identifier as input,
2. resolve it through Radicle-aware logic,
3. return lockable fetch metadata in a shape that stock flake fetchers already
   understand.

The first intended prototype path is Determinate Nix `builtins.wasm`.

## Non-goals

- patching upstream Nix fetchers immediately
- changing `tusk` consumers to depend on this repo
- embedding Tvix or GPLv3 code into `tusk`
- designing a full decentralized package ecosystem up front

## Prototype target

The first concrete slice now chooses one narrow output path: Git fetch metadata.

The resolver accepts JSON shaped like:

```json
{
  "rid": "rad:z3...",
  "seed": "iris.radicle.xyz",
  "branch": "main"
}
```

and returns JSON shaped like:

```json
{
  "kind": "git",
  "url": "https://seed.radicle.xyz/z3....git",
  "ref": "main",
  "rev": "<immutable-commit>"
}
```

The current native implementation now uses one explicit host-side transport seam:

- it validates the request shape
- it derives the seed smart-HTTP endpoint as `https://<seed>/<rid>.git`
- it runs `git ls-remote --refs --heads <url> refs/heads/<branch>`
- it uses the returned commit OID as the lockable `rev`

This keeps the contract in ordinary Git fetch terms while making the
Radicle-aware lookup path concrete.

For Determinate Nix, the first host bridge is narrower:

- the Wasm module normalizes `rid`, `seed`, and `branch`
- the host callback resolves `rev` with ordinary Nix `fetchTree`
- the module returns `{ kind, url, ref, rev }`

## Current design stance

- keep the experiment isolated under `tools/` and out of `tusk`'s stable
  consumer contract
- prefer a small Rust/Wasm module over a large evaluator fork
- treat Radicle resolution as a separate concern from flake fetching
- keep the stable consumer path on normal Git refs until this prototype proves
  itself
- keep the live native resolution mechanism explicit as a bounded subprocess
  seam for now instead of pretending plain `wasm32-wasip1` can do host
  networking alone
- use a Determinate-only host callback for the first `builtins.wasm` proof
  instead of claiming native `rad:` flake support too early

## Development

Enter the shell:

```bash
nix develop
```

The shell is intended to provide:

- Rust tooling with a Wasm target
- Radicle CLI tools for local interrogation
- Wasm inspection tools

## Current prototype surface

Inside the tool directory:

```bash
cargo test -p radicle-flake-wasm-resolver
cargo run -p radicle-flake-wasm-resolver -- '{"rid":"rad:z3gqcJUoA1n9HaHKufZs5FCSGazv5","seed":"seed.radicle.xyz","branch":"master"}'
```

From the repo root:

```bash
nix build .#radicle-flake-wasm-resolver
nix build .#checks.aarch64-darwin.radicle-flake-wasm-resolver-wasi
nix run .#radicle-flake-wasm-resolver -- '{"rid":"rad:z3gqcJUoA1n9HaHKufZs5FCSGazv5","seed":"seed.radicle.xyz","branch":"master"}'
```

Current runtime assumption:

- live resolution currently needs `git` available on the host
- the repo-root `nix run` surface wraps that dependency for the packaged binary
- the `wasm32-wasip1` output is still a build-validated artifact, not yet a
  fully network-capable Wasm host integration

Current Determinate host path:

- `tools/radicle-flake-wasm/nix/determinate-wasm.nix` wraps the plugin through
  `builtins.wasm`
- `resolveWithRev` proves the Wasm value bridge with a caller-supplied `rev`
- `resolve` proves a live host-assisted path by calling back into Nix
  `fetchTree` to obtain `rev`

Example calls from the repo root:

```bash
nix build .#radicle-flake-wasm-plugin
nix eval --extra-experimental-features wasm-builtin --impure --json \
  --file tools/radicle-flake-wasm/nix/demo-with-rev.nix
nix eval --extra-experimental-features wasm-builtin --impure --json \
  --file tools/radicle-flake-wasm/nix/demo-live.nix
```

## Next steps

1. Replace the subprocess seam with a first-class host API once the right
   Radicle crate or protocol boundary is proven.
2. Decide whether a tarball-shaped output belongs beside the Git-shaped one.
3. Decide whether the Determinate host callback should stay a demo wrapper or
   become a reusable flake helper surface.
