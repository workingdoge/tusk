{
  description = "tusk";

  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  inputs = {
    crane = {
      url = "github:ipetkov/crane/v0.23.2";
    };
    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    glistix = {
      url = "github:Glistix/glistix/v0.8.0";
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    llm-agents.url = "github:numtide/llm-agents.nix/6cbeeae9fab23fa0de85930a733df478fbc955b4";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      crane,
      devenv,
      glistix,
      nixpkgs,
      llm-agents,
      rust-overlay,
      ...
    }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ rust-overlay.overlays.default ];
      };
      tuskLib = import ./lib.nix { lib = nixpkgs.lib; };
      tuskFlakeModule = import ./flake-module.nix { inherit tuskLib; };
      devenvCodexModule = import ./devenv-codex-module.nix { inherit tuskLib; };
      codexSkillSources = {
        tusk = ./.agents/skills/tusk;
        ops = ./.agents/skills/ops;
        nix = ./.agents/skills/nix;
      };
      mkSkillModule = name: {
        codex.skills.${name}.source = codexSkillSources.${name};
      };
      devenvTuskSkillModule = mkSkillModule "tusk";
      devenvOpsSkillModule = mkSkillModule "ops";
      devenvNixSkillModule = mkSkillModule "nix";
      tuskSkillBundle = tuskLib.mkCodexSkillPackage {
        inherit pkgs;
        name = "tusk";
        src = codexSkillSources.tusk;
      };
      beads = llm-agents.packages.${system}.beads;
      codexPkg = llm-agents.packages.${system}.codex;
      glistixPkg = glistix.packages.${system}.default;
      rustToolchain = pkgs.rust-bin.stable.latest.default.override {
        extensions = [ "rust-src" ];
      };
      craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;
      codexNixCheck = pkgs.writeShellApplication {
        name = "codex-nix-check";
        runtimeInputs = [
          glistixPkg
          pkgs.deadnix
          pkgs.erlang
          pkgs.git
          pkgs.nix
          pkgs.rebar3
          pkgs.rust-analyzer
          tuskFlakeRefPackage
          tuskTrackerPackage
          rustToolchain
        ];
        text = ''
          set -euo pipefail

          repo_root="''${BEADS_WORKSPACE_ROOT:-''${DEVENV_ROOT:-}}"
          if [ -z "$repo_root" ]; then
            repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
          fi
          cd "$repo_root"

          deadnix --fail flake.nix devenv-codex-module.nix flake-module.nix lib.nix
          nix eval --raw "path:$repo_root#packages.${system}.rust-toolchain.name" >/dev/null
          nix eval --raw "path:$repo_root#packages.${system}.tusk-ui.name" >/dev/null
          nix eval --raw --apply 'x: if builtins.isFunction x || builtins.hasAttr "__functor" x then "ok" else throw "lib.crane.buildDepsOnly is not callable"' "path:$repo_root#lib.crane.buildDepsOnly" >/dev/null
          tusk-flake-ref --repo "$repo_root" --json >/dev/null
          nix develop --no-pure-eval "path:$repo_root" \
            -c sh -lc "export DEVENV_ROOT=\"$repo_root\"; export BEADS_WORKSPACE_ROOT=\"$repo_root\"; cd \"$repo_root\" && bd version >/dev/null && jj --version >/dev/null && dolt version >/dev/null && codex --help >/dev/null && tusk-tracker --help >/dev/null && glistix --help >/dev/null && erl -eval \"erlang:halt().\" -noshell >/dev/null && rebar3 version >/dev/null && cargo --version >/dev/null && rustc --version >/dev/null && rustfmt --version >/dev/null && rust-analyzer --version >/dev/null && test -L .codex/skills/tusk/SKILL.md && test -L .codex/skills/ops/SKILL.md && test -L .codex/skills/ops/references/TOOLING.md && test -L .codex/skills/nix/SKILL.md && test -L .codex/skills/nix/scripts/detect-shape.py"
        '';
      };
      tuskTrackerPackage = pkgs.writeShellApplication {
        name = "tusk-tracker";
        runtimeInputs = [
          beads
          pkgs.git
        ];
        text = ''
          export TUSK_TRACKER_REAL_BD=${beads}/bin/bd
          exec bash ${./scripts/tusk-tracker.sh} "$@"
        '';
      };
      tuskdPackage = pkgs.writeShellApplication {
        name = "tuskd";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
          pkgs.jq
          pkgs.jujutsu
          pkgs.lsof
          pkgs.socat
          tuskTrackerPackage
        ];
        text = ''
          exec bash ${./scripts/tuskd.sh} "$@"
        '';
      };
      repoBeads = pkgs.writeShellApplication {
        name = "bd";
        runtimeInputs = [
          pkgs.git
          pkgs.jq
          pkgs.lsof
        ];
        text = ''
          export TUSK_REAL_BD=${beads}/bin/bd
          export TUSK_REAL_TUSKD=${tuskdPackage}/bin/tuskd
          exec bash ${./scripts/bd.sh} "$@"
        '';
      };
      repoCodex = pkgs.writeShellApplication {
        name = "codex";
        runtimeInputs = [
          pkgs.git
          repoBeads
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
      tuskFlakeRefPackage = pkgs.writeShellApplication {
        name = "tusk-flake-ref";
        runtimeInputs = [
          pkgs.git
          pkgs.jq
          pkgs.jujutsu
        ];
        text = ''
          exec bash ${./scripts/tusk-flake-ref.sh} "$@"
        '';
      };
      tuskUiSrc = craneLib.cleanCargoSource ./crates/tusk-ui;
      tuskUiCommonArgs = {
        src = tuskUiSrc;
        strictDeps = true;
      };
      tuskUiCargoArtifacts = craneLib.buildDepsOnly tuskUiCommonArgs;
      tuskUiPackage = craneLib.buildPackage (
        tuskUiCommonArgs
        // {
          cargoArtifacts = tuskUiCargoArtifacts;
        }
      );
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
          imports = [
            devenvCodexModule
            devenvTuskSkillModule
            devenvOpsSkillModule
            devenvNixSkillModule
          ];

          packages = [
            codexNixCheck
            glistixPkg
            installTuskOpenaiSkill
            repoBeads
            pkgs.deadnix
            pkgs.direnv
            pkgs.dolt
            pkgs.erlang
            pkgs.git
            pkgs.gleam
            pkgs.jujutsu
            pkgs.jq
            pkgs.lsof
            pkgs.nil
            pkgs.nix-output-monitor
            pkgs.nix-tree
            pkgs.nixd
            pkgs.nixfmt
            pkgs.rebar3
            pkgs.ripgrep
            pkgs.rust-analyzer
            pkgs.socat
            pkgs.statix
            repoCodex
            tuskFlakeRefPackage
            tuskTrackerPackage
            tuskdPackage
            rustToolchain
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
            echo "  glistix --help"
            echo "  cargo --version"
            echo "  tusk-flake-ref --json"
            echo "  tusk-tracker --help"
            echo "  tuskd --help"
            echo "  nix build path:.#tusk-ui"
            echo "  nix run path:.#tusk-ui -- --help"
            echo "  nix eval path:.#packages.${system}.rust-toolchain.name"
            echo "  nix eval --apply 'x: if builtins.isFunction x || builtins.hasAttr \"__functor\" x then \"ok\" else throw \"not callable\"' path:.#lib.crane.buildDepsOnly"
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

            tuskd ensure --repo "$DEVENV_ROOT" >/dev/null
            echo "beads-dolt: repo-scoped tracker backend ensured"

            while true; do
              sleep 86400
            done
          '';
        };
    in
    {
      lib = {
        crane = craneLib;
        tusk = tuskLib;
      };
      devenvModules = {
        codex = devenvCodexModule;
        tusk-skill = devenvTuskSkillModule;
        ops-skill = devenvOpsSkillModule;
        nix-skill = devenvNixSkillModule;
      };
      flakeModules.tusk = tuskFlakeModule;
      flakeModules.default = tuskFlakeModule;
      packages.${system} = {
        rust-toolchain = rustToolchain;
        bd = repoBeads;
        beads = repoBeads;
        tusk-flake-ref = tuskFlakeRefPackage;
        tusk-tracker = tuskTrackerPackage;
        tusk-ui = tuskUiPackage;
        tusk-openai-skill = tuskSkillBundle;
      };

      apps.${system} = {
        bd = {
          type = "app";
          program = "${repoBeads}/bin/bd";
        };
        beads = {
          type = "app";
          program = "${repoBeads}/bin/bd";
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
        tusk-flake-ref = {
          type = "app";
          program = "${tuskFlakeRefPackage}/bin/tusk-flake-ref";
        };
        tuskd = {
          type = "app";
          program = "${tuskdPackage}/bin/tuskd";
        };
        tusk-tracker = {
          type = "app";
          program = "${tuskTrackerPackage}/bin/tusk-tracker";
        };
        tusk-ui = {
          type = "app";
          program = "${tuskUiPackage}/bin/tusk-ui";
        };
      };

      devShells.${system}.default = devenv.lib.mkShell {
        inherit inputs pkgs;
        modules = [ devShellModule ];
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
