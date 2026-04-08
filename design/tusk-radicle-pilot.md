# Tusk Radicle Pilot

`tusk` now has a live public Radicle RID:

- RID: `rad:z3fqVWWfMR7HoVJ1y3CNBz5gciXfm`
- Delegate alias: `workingdoge`
- Current published head: `3df3c728d83982a74cf96e80f70c1b394e162ad6`

## Hybrid Model

GitHub remains the default branch upstream for the canonical checkout.

Radicle is an additional distribution and review surface:

- `origin` remains the `main` branch upstream for normal `git push`
- `rad` is the explicit Radicle remote
- `rad patch` is the review surface when we want Radicle-native review flows
- `rad sync` is the announce/fetch step that makes seed visibility explicit

The pilot should not silently repoint `branch.main.remote` from `origin` to
`rad`, because that would collapse the existing GitHub workflow.

## Canonical Checkout Wiring

Use the repo-owned helper to attach the existing RID to a checkout:

```bash
RAD_PASSPHRASE=... nix run .#tusk-radicle -- init-existing --rid rad:z3fqVWWfMR7HoVJ1y3CNBz5gciXfm
```

That command:

1. runs `rad init --existing` to attach the repo to the existing RID
2. keeps Radicle signing configuration in local Git config
3. restores the `main` upstream to whatever it was before, normally `origin`
4. keeps `.gitsigners` local and ignored if the repo has not landed the ignore rule yet

Check the result with:

```bash
nix run .#tusk-radicle -- status
```

Expected shape:

- `origin_url=git@github.com:workingdoge/tusk.git`
- `branch_remote=origin`
- `rad_url=rad://z3fqVWWfMR7HoVJ1y3CNBz5gciXfm`
- `origin_relation=` and `rad_relation=` tell you whether local `main` is already
  published or still needs a push/sync on each surface

## Local Publish Flow

Start the node:

```bash
RAD_PASSPHRASE=... rad node start --foreground
```

Normal hybrid publish:

```bash
git push origin main
git push rad main
RAD_PASSPHRASE=... rad sync rad:z3fqVWWfMR7HoVJ1y3CNBz5gciXfm --timeout 20s --replicas 2
```

If the canonical checkout is dirty or otherwise unsuitable for first-time
bootstrap, use a clean local clone of `main` to initialize the RID and publish,
then attach the canonical checkout with `tusk-radicle init-existing`.

## Review Flow

Use GitHub reviews as before unless a lane explicitly chooses Radicle-native
review.

For Radicle-native review:

- publish the branch to the `rad` remote
- use `rad patch` from the attached checkout
- keep GitHub pushability intact; the pilot is additive, not exclusive

## Verification

Local:

```bash
nix run .#tusk-radicle -- status
rad .
rad ls
```

`tusk-radicle status` is the first check after a local landing: it reports the
local `main` head plus best-effort `origin` and `rad` heads so publish drift is
visible before you assume the repo is distributed.

Remote:

```bash
curl https://iris.radicle.xyz/api/v1/repos/rad:z3fqVWWfMR7HoVJ1y3CNBz5gciXfm
```

The expected public seed record should report:

- `defaultBranch = "main"`
- `head = 3df3c728d83982a74cf96e80f70c1b394e162ad6`
