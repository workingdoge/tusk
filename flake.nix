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
      devenvScratchModule = import ./devenv-scratch-module.nix;
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
      tuskClean = pkgs.writeShellApplication {
        name = "tusk-clean";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnused
        ];
        text = ''
          exec bash ${./scripts/tusk-clean.sh} "$@"
        '';
      };
      consumerCodexModule =
        {
          lib,
          pkgs,
          config,
          ...
        }:
        let
          inherit (lib)
            mkDefault
            mkEnableOption
            mkIf
            mkMerge
            mkOption
            optional
            optionalString
            types
            ;

          cfg = config.tusk.consumer;
          consumerSystem = pkgs.stdenv.hostPlatform.system;
          consumerBeads = llm-agents.packages.${consumerSystem}.beads;
          consumerCodex = llm-agents.packages.${consumerSystem}.codex;
          repoCodex = pkgs.writeShellApplication {
            name = "codex";
            runtimeInputs = [
              consumerBeads
              pkgs.coreutils
              pkgs.git
            ];
            text = ''
              set -eu

              tracker_root="''${BEADS_WORKSPACE_ROOT:-''${DEVENV_ROOT:-}}"
              if [ -z "$tracker_root" ]; then
                tracker_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
              fi
              export BEADS_WORKSPACE_ROOT="$tracker_root"
              export CODEX_HOME="$tracker_root/.codex"
              sh ${./scripts/codex-home-bootstrap.sh} "$tracker_root" ".codex"

              if [ -d "$tracker_root/.beads" ]; then
                (
                  cd "$tracker_root"
                  bd ready --json >/dev/null 2>&1 || true
                )
              fi

              exec ${consumerCodex}/bin/codex "$@"
            '';
          };
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

              ${optionalString (cfg.smokeCheck.deadnixTargets != [ ]) ''
                deadnix --fail ${nixpkgs.lib.escapeShellArgs cfg.smokeCheck.deadnixTargets}
              ''}

              check_cmd="$(cat <<'EOF'
              cd "$DEVENV_ROOT"
              bd version >/dev/null
              jj --version >/dev/null
              jq --version >/dev/null
              dolt version >/dev/null
              codex --help >/dev/null
              tusk-clean --help >/dev/null
              ${nixpkgs.lib.concatStringsSep "\n" (
                nixpkgs.lib.map (path: "test -L ${nixpkgs.lib.escapeShellArg path}") cfg.smokeCheck.skillChecks
              )}
              test "$CODEX_HOME" = "$DEVENV_ROOT/.codex"
              test -n "$TUSK_SCRATCH_ROOT"
              test -n "$CARGO_TARGET_DIR"
              test -n "$TF_DATA_DIR"
              test -n "$UV_CACHE_DIR"
              test -n "$PIP_CACHE_DIR"
              test -d "$TUSK_SCRATCH_ROOT"
              ${cfg.smokeCheck.extraChecks}
              EOF
              )"

              nix develop --no-pure-eval "path:$repo_root" -c sh -lc "$check_cmd"
            '';
          };
        in
        {
          imports = [
            devenvCodexModule
            devenvScratchModule
          ];

          options.tusk.consumer = {
            enable = mkEnableOption "the shared tusk devenv consumer surface";

            beadsDolt.enable = mkOption {
              type = types.bool;
              default = true;
              description = "Run the shared Beads Dolt process when .beads/ exists.";
            };

            extraPackages = mkOption {
              type = types.listOf types.package;
              default = [ ];
              description = "Additional packages to append to the shared consumer shell.";
            };

            extraEnterShell = mkOption {
              type = types.lines;
              default = "";
              description = "Extra shell lines appended after the shared consumer banner.";
            };

            smokeCheck = {
              enable = mkOption {
                type = types.bool;
                default = true;
                description = "Expose codex-nix-check in the shared consumer shell.";
              };

              deadnixTargets = mkOption {
                type = types.listOf types.str;
                default = [ "flake.nix" ];
                description = "Paths passed to deadnix by codex-nix-check before the shell smoke test.";
              };

              skillChecks = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Projected skill files that codex-nix-check must see in the shell.";
              };

              extraChecks = mkOption {
                type = types.lines;
                default = "";
                description = "Additional shell assertions appended inside codex-nix-check.";
              };
            };
          };

          config = mkIf cfg.enable (mkMerge [
            {
              tusk.scratch.enable = mkDefault true;

              packages =
                [
                  consumerBeads
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
                  tuskClean
                ]
                ++ optional cfg.smokeCheck.enable codexNixCheck
                ++ cfg.extraPackages;

              enterShell = ''
                export PATH="${repoCodex}/bin:$PATH"
                export BEADS_WORKSPACE_ROOT="$DEVENV_ROOT"
                echo "tusk consumer shell"
                echo "  CODEX_HOME=$CODEX_HOME"
                echo "  codex"
                echo "  devenv up"
                echo "  bd status --json"
                echo "  bd ready --json"
                echo "  jj st"
                ${optionalString cfg.smokeCheck.enable ''
                  echo "  codex-nix-check"
                ''}
                echo "  tusk-clean"
                echo "  nix develop --no-pure-eval path:. -c sh -lc 'cd \"$DEVENV_ROOT\" && bd version && jj --version && dolt version'"
                ${cfg.extraEnterShell}
              '';
            }
            (mkIf cfg.beadsDolt.enable {
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
            })
          ]);
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
          tuskdCorePackage
          tuskTrackerPackage
        ];
        text = ''
          export TUSKD_CORE_BIN=${tuskdCorePackage}/bin/tuskd-core
          exec bash ${./scripts/tuskd.sh} "$@"
        '';
      };
      tuskdTransitionTestsPackage = pkgs.writeShellApplication {
        name = "tuskd-transition-tests";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
          pkgs.gnugrep
          pkgs.jq
          pkgs.jujutsu
          pkgs.nix
        ];
        text = ''
          exec bash ${./scripts/tuskd-transition-tests.sh} "$@"
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
          pkgs.coreutils
          pkgs.git
          repoBeads
        ];
        text = ''
          set -eu

          tracker_root="''${BEADS_WORKSPACE_ROOT:-''${DEVENV_ROOT:-}}"
          if [ -z "$tracker_root" ]; then
            tracker_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
          fi
          export BEADS_WORKSPACE_ROOT="$tracker_root"
          export CODEX_HOME="$tracker_root/.codex"
          sh ${./scripts/codex-home-bootstrap.sh} "$tracker_root" ".codex"

          if [ -d "$tracker_root/.beads" ]; then
            (
              cd "$tracker_root"
              bd ready --json >/dev/null 2>&1 || true
            )
          fi

          exec ${codexPkg}/bin/codex "$@"
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
      tuskdCoreSrc = craneLib.cleanCargoSource ./crates/tuskd-core;
      tuskdCoreCommonArgs = {
        src = tuskdCoreSrc;
        strictDeps = true;
      };
      tuskdCoreCargoArtifacts = craneLib.buildDepsOnly tuskdCoreCommonArgs;
      tuskdCorePackage = craneLib.buildPackage (
        tuskdCoreCommonArgs
        // {
          cargoArtifacts = tuskdCoreCargoArtifacts;
        }
      );
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
          tuskClean
          tuskFlakeRefPackage
          tuskTrackerPackage
          tuskdTransitionTestsPackage
          rustToolchain
        ];
        text = ''
          set -euo pipefail

          repo_root="''${BEADS_WORKSPACE_ROOT:-''${DEVENV_ROOT:-}}"
          if [ -z "$repo_root" ]; then
            repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
          fi
          cd "$repo_root"

          deadnix --fail flake.nix devenv-codex-module.nix devenv-scratch-module.nix flake-module.nix lib.nix
          nix eval --raw "path:$repo_root#packages.${system}.rust-toolchain.name" >/dev/null
          nix eval --raw "path:$repo_root#packages.${system}.tusk-ui.name" >/dev/null
          nix eval --raw --apply 'x: if builtins.isFunction x || builtins.hasAttr "__functor" x then "ok" else throw "lib.crane.buildDepsOnly is not callable"' "path:$repo_root#lib.crane.buildDepsOnly" >/dev/null
          tusk-flake-ref --repo "$repo_root" --json >/dev/null
          nix develop --no-pure-eval "path:$repo_root" \
            -c sh -lc "export DEVENV_ROOT=\"$repo_root\"; export BEADS_WORKSPACE_ROOT=\"$repo_root\"; cd \"$repo_root\" && bd version >/dev/null && jj --version >/dev/null && dolt version >/dev/null && codex --help >/dev/null && tusk-clean --help >/dev/null && tusk-tracker --help >/dev/null && tuskd-transition-tests --help >/dev/null && glistix --help >/dev/null && erl -eval \"erlang:halt().\" -noshell >/dev/null && rebar3 version >/dev/null && cargo --version >/dev/null && rustc --version >/dev/null && rustfmt --version >/dev/null && rust-analyzer --version >/dev/null && test \"$CODEX_HOME\" = \"$repo_root/.codex\" && test -L .codex/skills/tusk/SKILL.md && test -L .codex/skills/ops/SKILL.md && test -L .codex/skills/ops/references/TOOLING.md && test -L .codex/skills/nix/SKILL.md && test -L .codex/skills/nix/scripts/detect-shape.py"
          nix eval --raw --expr '
            let
              flake = builtins.getFlake "path:'"$repo_root"'";
              pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
              consumer = flake.inputs.devenv.lib.mkShell {
                inherit (flake) inputs;
                inherit pkgs;
                modules = [
                  flake.devenvModules.consumer
                  {
                    tusk.consumer.enable = true;
                    tusk.consumer.smokeCheck.enable = false;
                  }
                ];
              };
              dogfood = flake.inputs.devenv.lib.mkShell {
                inherit (flake) inputs;
                inherit pkgs;
                modules = [ flake.devenvModules.dogfood ];
              };
              consumerFiles = consumer.config.files or { };
              dogfoodFiles = dogfood.config.files or { };
            in
            if
              (! builtins.hasAttr ".codex/skills/tusk/SKILL.md" consumerFiles)
              && (! builtins.hasAttr ".codex/skills/ops/SKILL.md" consumerFiles)
              && (! builtins.hasAttr ".codex/skills/nix/SKILL.md" consumerFiles)
              && builtins.hasAttr ".codex/skills/tusk/SKILL.md" dogfoodFiles
              && builtins.hasAttr ".codex/skills/ops/SKILL.md" dogfoodFiles
              && builtins.hasAttr ".codex/skills/nix/SKILL.md" dogfoodFiles
            then
              "ok"
            else
              throw "consumer/dogfood skill contract mismatch"
          ' >/dev/null
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
      dogfoodModule =
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
            tuskClean
            tuskFlakeRefPackage
            tuskTrackerPackage
            tuskdPackage
            tuskdTransitionTestsPackage
            rustToolchain
          ];

          enterShell = ''
            export PATH="${repoCodex}/bin:$PATH"
            export BEADS_WORKSPACE_ROOT="$DEVENV_ROOT"
            echo "tusk dogfood shell"
            echo "  CODEX_HOME=$CODEX_HOME"
            echo "  codex"
            echo "  devenv up"
            echo "  bd status --json"
            echo "  bd ready --json"
            echo "  jj st"
            echo "  codex-nix-check"
            echo "  tusk-clean"
            echo "  glistix --help"
            echo "  cargo --version"
            echo "  tusk-flake-ref --json"
            echo "  tusk-tracker --help"
            echo "  tuskd --help"
            echo "  tuskd core-seam --json"
            echo "  tuskd-transition-tests --help"
            echo "  nix build path:.#tuskd-core"
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
        scratch = devenvScratchModule;
        consumer = consumerCodexModule;
        default = consumerCodexModule;
        dogfood = dogfoodModule;
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
        tusk-clean = tuskClean;
        tusk-flake-ref = tuskFlakeRefPackage;
        tusk-tracker = tuskTrackerPackage;
        tuskd-core = tuskdCorePackage;
        tuskd-transition-tests = tuskdTransitionTestsPackage;
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
        tusk-clean = {
          type = "app";
          program = "${tuskClean}/bin/tusk-clean";
        };
        tusk-flake-ref = {
          type = "app";
          program = "${tuskFlakeRefPackage}/bin/tusk-flake-ref";
        };
        tuskd = {
          type = "app";
          program = "${tuskdPackage}/bin/tuskd";
        };
        tuskd-core = {
          type = "app";
          program = "${tuskdCorePackage}/bin/tuskd-core";
        };
        tuskd-transition-tests = {
          type = "app";
          program = "${tuskdTransitionTestsPackage}/bin/tuskd-transition-tests";
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
        modules = [ dogfoodModule ];
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
