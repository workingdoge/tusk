let
  flake = builtins.getFlake (toString ../../..);
  system = builtins.currentSystem;
  pluginPath =
    "${flake.packages.${system}.radicle-flake-wasm-plugin}/share/wasm/radicle_flake_wasm_resolver.wasm";
  bridge = import ./determinate-wasm.nix { inherit builtins pluginPath; };
in
bridge.resolveWithRev {
  rid = "rad:z3gqcJUoA1n9HaHKufZs5FCSGazv5";
  seed = "seed.radicle.xyz";
  branch = "master";
  rev = "22b2871f64ecf34a22d32add0dd59a0c7c96ad10";
}
