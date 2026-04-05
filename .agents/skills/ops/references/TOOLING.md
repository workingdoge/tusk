# Operational tooling after local inspection

Do **not** start here.
Use this note once you know the operational question.

## Command order
1. inspect `flake.nix`
2. grep for operational markers
3. inspect only the narrow files involved
4. run the smallest check or eval that matches the layer
5. only then read platform docs

## Useful local probes
### Shape and declarations
```bash
rg -n "checks|githubActions|herculesCI|effects|deploy-rs|colmena|attic" .
```

Use this before any platform comparison.

### Output surface
```bash
nix flake show --json .
```

Use this to see whether the flake already exports checks or operational outputs.

### Narrow evaluation
```bash
nix eval .#checks.<system>.<name>
nix build .#checks.<system>.<name> --dry-run
```

Use this for pure check layers.

### Build and log inspection
```bash
nix log <drv>
nix why-depends <installable-a> <installable-b>
nix store diff-closures <path-a> <path-b>
```

Use these only after the failing or changed installable is already narrow.

### Better build output
```bash
nom build .#checks.<system>.<name>
```

Use when the repo already has `nix-output-monitor`.

## Layer-specific guidance
- For pure CI questions, prefer `nix eval` and `nix build --dry-run`.
- For effect questions, inspect the effect definition before touching runtime
  infrastructure.
- For forge transport questions, inspect generated workflow definitions only
  after understanding the Nix-side source.

## Anti-patterns
Avoid:
- comparing platforms before inspecting the local flake
- treating all operational tools as if they solved the same layer
- debugging an effect before confirming the pure job it depends on
