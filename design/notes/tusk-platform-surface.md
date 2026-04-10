# Tusk Platform Surface

## Intent

`tusk` should be the stable platform entrypoint that downstream repos call,
not a bag of upstream input internals they reach through ad hoc.

The first exported platform surface is intentionally small:

- `tusk.lib.mkRepoShell`
- `tusk.lib.mkNixosSystem`
- `tusk.lib.mkDarwinSystem`
- `tusk.lib.mkHomeConfiguration`
- `tusk.devenvModules.consumer`

This is enough to name one stable consumer API without pretending that `tusk`
already owns every machine-policy module.

## Platform Versus Leaf Ownership

What belongs in `tusk`:

- shared flake input ownership and version discipline
- shared repo-shell/runtime conventions
- the stable builder entrypoints consumers call
- reusable module layers that clearly generalize across consumers

What stays in the consumer repo:

- app-specific runtime dependencies
- host or user policy that is not yet shared
- product-specific secrets, state, and service bindings
- consumer-local Codex skills and wrappers

The rule is:
consumers should call `tusk` builders first and only drop to raw upstream
builder libs when `tusk` does not yet expose the required surface.

## Current Builder Contract

### Repo Shell

Use `tusk.lib.mkRepoShell` for downstream dev shells.

It already composes `tusk.devenvModules.consumer`, so consumers should pass
configuration modules, not re-import the consumer module again.

Example:

```nix
devShells.${system}.default = inputs.tusk.lib.mkRepoShell {
  inherit system inputs;
  modules = [
    ({ ... }: {
      tusk.consumer.enable = true;
    })
  ];
};
```

### NixOS

Use `tusk.lib.mkNixosSystem` instead of reaching through
`inputs.nixpkgs.lib.nixosSystem`.

Example:

```nix
nixosConfigurations.host = inputs.tusk.lib.mkNixosSystem {
  system = "x86_64-linux";
  inherit inputs;
  modules = [ ./hosts/host/configuration.nix ];
};
```

### nix-darwin

Use `tusk.lib.mkDarwinSystem` instead of reaching through
`inputs.nix-darwin.lib.darwinSystem`.

The caller still supplies an `inputs` set containing `nix-darwin`; the stable
surface is the `tusk` wrapper, not the raw upstream path.

Example:

```nix
darwinConfigurations.mac = inputs.tusk.lib.mkDarwinSystem {
  system = "aarch64-darwin";
  inherit inputs;
  modules = [ ./darwin/mac.nix ];
};
```

### Home Manager

Use `tusk.lib.mkHomeConfiguration` instead of reaching through
`inputs.home-manager.lib.homeManagerConfiguration`.

Example:

```nix
homeConfigurations.user = inputs.tusk.lib.mkHomeConfiguration {
  inherit inputs pkgs;
  modules = [ ./home/user.nix ];
};
```

## Why Thin Wrappers First

The first exported machine builders are deliberately thin wrappers.

They provide:

- stable names
- a stable call boundary rooted at `tusk`
- a place to add shared platform defaults later without rewriting consumers

They do **not** yet claim that `tusk` owns every shared NixOS, Darwin, or Home
Manager module. That policy can become shared later when it actually
generalizes.
