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
      pkgs = nixpkgs.legacyPackages.${system};
      tuskLib = import ./lib.nix { lib = nixpkgs.lib; };
      tuskFlakeModule = import ./flake-module.nix { inherit tuskLib; };
      tuskSkillBundle = pkgs.runCommand "tusk-openai-skill" { } ''
        mkdir -p "$out"
        cp -R ${./.agents/skills/tusk}/. "$out/"
        chmod -R u+w "$out"
      '';
      beads = llm-agents.packages.${system}.beads;
      codexPkg = llm-agents.packages.${system}.codex;
      codexNixCheck = pkgs.writeShellApplication {
        name = "codex-nix-check";
        runtimeInputs = [
          pkgs.deadnix
          pkgs.git
          pkgs.nix
        ];
        text = ''
          set -euo pipefail

          repo_root="''${BEADS_WORKSPACE_ROOT:-''${DEVENV_ROOT:-}}"
          if [ -z "$repo_root" ]; then
            repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
          fi
          cd "$repo_root"

          deadnix --fail flake.nix flake-module.nix lib.nix
          nix develop --no-pure-eval "path:$repo_root" \
            -c sh -lc "cd \"\$DEVENV_ROOT\" && bd version >/dev/null && jj --version >/dev/null && dolt version >/dev/null && codex --help >/dev/null"
        '';
      };
      repoCodex = pkgs.writeShellApplication {
        name = "codex";
        runtimeInputs = [
          beads
          pkgs.git
        ];
        text = ''
          set -eu

          repo_root="''${BEADS_WORKSPACE_ROOT:-''${DEVENV_ROOT:-}}"
          if [ -z "$repo_root" ]; then
            repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
          fi
          cd "$repo_root"
          export BEADS_WORKSPACE_ROOT="$repo_root"

          if [ -d .beads ]; then
            bd ready --json >/dev/null 2>&1 || true
          fi

          exec ${codexPkg}/bin/codex -C "$repo_root" "$@"
        '';
      };
      installTuskOpenaiSkill = pkgs.writeShellApplication {
        name = "install-tusk-openai-skill";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          set -euo pipefail

          target_root="''${1:-$HOME/.codex/skills}"
          target_dir="$target_root/tusk"

          mkdir -p "$target_root"
          rm -rf "$target_dir"
          cp -R ${tuskSkillBundle} "$target_dir"

          echo "Installed tusk skill to $target_dir"
        '';
      };
      devShellModule =
        { ... }:
        {
          packages = [
            beads
            codexNixCheck
            installTuskOpenaiSkill
            pkgs.deadnix
            pkgs.direnv
            pkgs.dolt
            pkgs.git
            pkgs.jujutsu
            pkgs.jq
            pkgs.nil
            pkgs.nix-output-monitor
            pkgs.nix-tree
            pkgs.nixd
            pkgs.nixfmt
            pkgs.ripgrep
            pkgs.statix
            repoCodex
          ];

          enterShell = ''
            export PATH="${repoCodex}/bin:$PATH"
            export BEADS_WORKSPACE_ROOT="$DEVENV_ROOT"
            echo "tusk dev shell"
            echo "  codex"
            echo "  devenv up"
            echo "  bd status --json"
            echo "  bd ready --json"
            echo "  jj st"
            echo "  codex-nix-check"
            echo "  install-tusk-openai-skill"
            echo "  nix develop --no-pure-eval path:. -c sh -lc 'cd \"$DEVENV_ROOT\" && bd version && jj --version && dolt version'"
          '';

          processes.beads-dolt.exec = ''
            set -euo pipefail
            cd "$DEVENV_ROOT"

            if [ ! -d .beads ]; then
              echo "beads-dolt: skipping, .beads/ is missing"
              exit 0
            fi

            bd dolt start >/dev/null
            echo "beads-dolt: dolt server started"

            cleanup() {
              bd dolt stop >/dev/null 2>&1 || true
            }

            trap cleanup EXIT INT TERM

            while true; do
              sleep 86400
            done
          '';
        };
    in
    {
      lib.tusk = tuskLib;
      flakeModules.tusk = tuskFlakeModule;
      flakeModules.default = tuskFlakeModule;
      packages.${system}.tusk-openai-skill = tuskSkillBundle;

      apps.${system} = {
        beads = {
          type = "app";
          program = "${beads}/bin/bd";
        };
        codex = {
          type = "app";
          program = "${repoCodex}/bin/codex";
        };
        codex-nix-check = {
          type = "app";
          program = "${codexNixCheck}/bin/codex-nix-check";
        };
        install-tusk-openai-skill = {
          type = "app";
          program = "${installTuskOpenaiSkill}/bin/install-tusk-openai-skill";
        };
      };

      devShells.${system}.default = devenv.lib.mkShell {
        inherit inputs pkgs;
        modules = [ devShellModule ];
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
