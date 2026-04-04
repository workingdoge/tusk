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
      devenvSharedSkillsModule = {
        imports = [ devenvCodexModule ];
        codex.skills = {
          tusk.source = codexSkillSources.tusk;
          ops.source = codexSkillSources.ops;
          nix.source = codexSkillSources.nix;
        };
      };
      devenvTuskSkillModule = mkSkillModule "tusk";
      devenvOpsSkillModule = mkSkillModule "ops";
      devenvNixSkillModule = mkSkillModule "nix";
      devenvConsumerModule =
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
          beads = llm-agents.packages.${consumerSystem}.beads;
          codexPkg = llm-agents.packages.${consumerSystem}.codex;
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
                default = [ ".codex/skills/tusk/SKILL.md" ];
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
              codex.skills.tusk.source = mkDefault codexSkillSources.tusk;

              packages = [
                beads
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
      beads = llm-agents.packages.${system}.beads;
      codexPkg = llm-agents.packages.${system}.codex;
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

          deadnix --fail flake.nix devenv-codex-module.nix devenv-scratch-module.nix flake-module.nix lib.nix
          nix develop --no-pure-eval "path:$repo_root" \
            -c sh -lc "cd \"\$DEVENV_ROOT\" && bd version >/dev/null && jj --version >/dev/null && dolt version >/dev/null && codex --help >/dev/null && tusk-clean --help >/dev/null && test -L .codex/skills/tusk/SKILL.md && test -L .codex/skills/tusk/agents/openai.yaml && test -L .codex/skills/ops/SKILL.md && test -L .codex/skills/ops/references/TOOLING.md && test -L .codex/skills/nix/SKILL.md && test -L .codex/skills/nix/scripts/detect-shape.py && test -n \"\$TUSK_SCRATCH_ROOT\" && test -n \"\$CARGO_TARGET_DIR\" && test -n \"\$TF_DATA_DIR\" && test -n \"\$UV_CACHE_DIR\" && test -n \"\$PIP_CACHE_DIR\" && test -d \"\$TUSK_SCRATCH_ROOT\""
          nix eval --no-pure-eval --expr '
            let
              flake = builtins.getFlake "path:'"$repo_root"'";
              pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
              shell = flake.inputs.devenv.lib.mkShell {
                inherit (flake) inputs;
                inherit pkgs;
                modules = [
                  flake.devenvModules.codex
                  flake.devenvModules.tusk-skill
                  flake.devenvModules.ops-skill
                  flake.devenvModules.nix-skill
                ];
              };
            in [
              (builtins.hasAttr ".codex/skills/tusk/SKILL.md" shell.config.files)
              (builtins.hasAttr ".codex/skills/ops/SKILL.md" shell.config.files)
              (builtins.hasAttr ".codex/skills/nix/SKILL.md" shell.config.files)
            ]
          ' >/dev/null
          nix eval --no-pure-eval --expr '
            let
              flake = builtins.getFlake "path:'"$repo_root"'";
              pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
              shell = flake.inputs.devenv.lib.mkShell {
                inherit (flake) inputs;
                inherit pkgs;
                modules = [
                  flake.devenvModules.consumer
                  flake.devenvModules.ops-skill
                  flake.devenvModules.nix-skill
                  {
                    tusk.consumer.enable = true;
                    tusk.consumer.smokeCheck.enable = false;
                  }
                ];
              };
            in [
              (builtins.hasAttr ".codex/skills/tusk/SKILL.md" shell.config.files)
              (builtins.hasAttr ".codex/skills/ops/SKILL.md" shell.config.files)
              (builtins.hasAttr ".codex/skills/nix/SKILL.md" shell.config.files)
            ]
          ' >/dev/null
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
      devShellModule =
        { ... }:
        {
          imports = [
            devenvSharedSkillsModule
            devenvScratchModule
          ];

          tusk.scratch.enable = true;

          packages = [
            beads
            codexNixCheck
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
            echo "  tusk-clean"
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
      devenvModules.codex = devenvCodexModule;
      devenvModules.scratch = devenvScratchModule;
      devenvModules.consumer = devenvConsumerModule;
      devenvModules.default = devenvConsumerModule;
      devenvModules.tusk-skill = devenvTuskSkillModule;
      devenvModules.ops-skill = devenvOpsSkillModule;
      devenvModules.nix-skill = devenvNixSkillModule;
      flakeModules.tusk = tuskFlakeModule;
      flakeModules.default = tuskFlakeModule;

      apps.${system} = {
        beads = {
          type = "app";
          program = "${beads}/bin/bd";
        };
        codex = {
          type = "app";
          program = "${repoCodex}/bin/codex";
        };
        "tusk-clean" = {
          type = "app";
          program = "${tuskClean}/bin/tusk-clean";
        };
        codex-nix-check = {
          type = "app";
          program = "${codexNixCheck}/bin/codex-nix-check";
        };
      };

      devShells.${system}.default = devenv.lib.mkShell {
        inherit inputs pkgs;
        modules = [ devShellModule ];
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
