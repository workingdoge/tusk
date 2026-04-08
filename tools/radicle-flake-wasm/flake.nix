{
  description = "Prototype Wasm resolver from rad: ids to lockable flake fetch metadata";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      rust-overlay,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      perSystem =
        { system, ... }:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import rust-overlay) ];
          };

          rustToolchain = pkgs.rust-bin.stable.latest.default.override {
            extensions = [
              "clippy"
              "rust-analyzer"
              "rust-src"
              "rustfmt"
            ];
            targets = [ "wasm32-wasip1" ];
          };
        in
        {
          devShells.default = pkgs.mkShell {
            packages = [
              pkgs.binaryen
              pkgs.git
              pkgs.jq
              pkgs.nix
              pkgs.radicle-node
              pkgs.wabt
              pkgs.wasm-tools
              rustToolchain
            ];

            shellHook = ''
              echo "radicle-flake-wasm dev shell"
              echo "  goal: resolve rad: ids into lockable git fetch metadata"
              echo "  cargo test -p radicle-flake-wasm-resolver"
              echo "  cargo build --release -p radicle-flake-wasm-resolver --target wasm32-wasip1"
            '';
          };
        };
    };
}
