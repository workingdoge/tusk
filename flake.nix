{
  description = "tusk";

  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  inputs = {
    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    llm-agents.url = "github:numtide/llm-agents.nix/6cbeeae9fab23fa0de85930a733df478fbc955b4";
  };

  outputs =
    inputs@{
      devenv,
      nixpkgs,
      llm-agents,
      ...
    }:
    let
      system = "aarch64-darwin";
      tuskLib = import ./lib.nix { lib = nixpkgs.lib; };
      repoShellLib = import ./repo-shell-lib.nix {
        lib = nixpkgs.lib;
        inherit
          devenv
          llm-agents
          nixpkgs
          ;
        skillSource = ./.agents/skills/tusk;
      };
      tuskFlakeModule = import ./flake-module.nix { inherit tuskLib; };
      repoShell = repoShellLib.mkRepoShell {
        inherit system;
        repoName = "tusk";
        checkFiles = [
          "flake.nix"
          "flake-module.nix"
          "lib.nix"
        ];
      };
    in
    {
      lib.tusk = tuskLib // repoShellLib;
      flakeModules.tusk = tuskFlakeModule;
      flakeModules.default = tuskFlakeModule;
      packages.${system}.tusk-openai-skill = repoShell.skillBundle;

      apps.${system} = repoShell.apps;

      devShells.${system}.default = repoShell.mkShell { inherit inputs; };

      formatter.${system} = repoShell.pkgs.nixfmt;
    };
}
