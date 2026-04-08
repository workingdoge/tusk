let
  flake = builtins.getFlake (toString ../../..);
  system = builtins.currentSystem;
  pluginPath =
    "${flake.packages.${system}.radicle-flake-wasm-plugin}/share/wasm/radicle_flake_wasm_resolver.wasm";
  bridge = import ./determinate-wasm.nix { inherit builtins pluginPath; };
in
bridge.resolve {
  rid = "rad:z3gqcJUoA1n9HaHKufZs5FCSGazv5";
  seed = "seed.radicle.xyz";
  branch = "master";
}
