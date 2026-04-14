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
    llm-agents.url = "github:numtide/llm-agents.nix";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Canonical bridge skill source. Non-flake path input so tusk can
    # project the bridge SKILL.md into its Claude + Codex shells without
    # bridge needing to ship its own flake. Authored content stays at
    # fish/sites/bridge/.agents/skills/bridge/; tusk consumes it here.
    #
    # Absolute path (machine-local) chosen because relative `path:../..`
    # inputs escape the flake store boundary and break nix's store-path
    # resolution. A follow-up lane can convert this to a Radicle- or
    # flake-parts-based cross-repo mechanism once the ecosystem is ready;
    # for v0 we accept the machine-locality and rely on flake.lock's
    # narHash to pin content.
    bridge-src = {
      url = "path:/Users/arj/irai/fish/sites/bridge";
      flake = false;
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
      bridge-src,
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
      devenvCacheModule = import ./devenv-cache-module.nix { inherit tuskLib; };
      skillSources = {
        tusk = ./.agents/skills/tusk;
        ops = ./.agents/skills/ops;
        nix = ./.agents/skills/nix;
        skill-dev = ./.agents/skills/skill-dev;
        topology = ./.agents/skills/topology;
        # Canonical authoring at fish/sites/bridge/.agents/skills/bridge/;
        # consumed via the bridge-src non-flake path input. No duplicate.
        bridge = "${bridge-src}/.agents/skills/bridge";
      };
      mkSkillModule = name: {
        codex.skills.${name}.source = skillSources.${name};
      };
      mkClaudeSkillModule = name: {
        claude.skills.${name}.source = skillSources.${name};
      };
      devenvTuskSkillModule = mkSkillModule "tusk";
      devenvOpsSkillModule = mkSkillModule "ops";
      devenvNixSkillModule = mkSkillModule "nix";
      devenvSkillDevSkillModule = mkSkillModule "skill-dev";
      devenvTopologySkillModule = mkSkillModule "topology";
      devenvBridgeSkillModule = mkSkillModule "bridge";
      devenvTuskClaudeSkillModule = mkClaudeSkillModule "tusk";
      devenvOpsClaudeSkillModule = mkClaudeSkillModule "ops";
      devenvNixClaudeSkillModule = mkClaudeSkillModule "nix";
      devenvSkillDevClaudeSkillModule = mkClaudeSkillModule "skill-dev";
      devenvTopologyClaudeSkillModule = mkClaudeSkillModule "topology";
      devenvBridgeClaudeSkillModule = mkClaudeSkillModule "bridge";
      devenvConsumerSharedSkillsModule = {
        imports = [
          devenvTuskSkillModule
          devenvOpsSkillModule
          devenvNixSkillModule
          devenvTopologySkillModule
          devenvBridgeSkillModule
          devenvTuskClaudeSkillModule
          devenvOpsClaudeSkillModule
          devenvNixClaudeSkillModule
          devenvTopologyClaudeSkillModule
          devenvBridgeClaudeSkillModule
        ];
      };
      tuskOpenaiSkillBundle = tuskLib.mkOpenAISkillPackage {
        inherit pkgs;
        name = "tusk";
        src = skillSources.tusk;
      };
      beads = llm-agents.packages.${system}.beads;
      codexPkg = llm-agents.packages.${system}.codex;
      glistixPkg = glistix.packages.${system}.default;
      rustToolchain = pkgs.rust-bin.stable.latest.default.override {
        extensions = [ "rust-src" ];
      };
      craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;
      radicleWasmToolchain = pkgs.rust-bin.stable.latest.default.override {
        extensions = [ "rust-src" ];
        targets = [
          "wasm32-unknown-unknown"
          "wasm32-wasip1"
        ];
      };
      radicleWasmCraneLib = (crane.mkLib pkgs).overrideToolchain radicleWasmToolchain;
      radicleFlakeWasmSrc = radicleWasmCraneLib.cleanCargoSource ./tools/radicle-flake-wasm;
      radicleFlakeWasmCommonArgs = {
        pname = "radicle-flake-wasm-resolver";
        src = radicleFlakeWasmSrc;
        strictDeps = true;
        version = "0.1.0";
        cargoExtraArgs = "-p radicle-flake-wasm-resolver";
      };
      radicleFlakeWasmCargoArtifacts = radicleWasmCraneLib.buildDepsOnly radicleFlakeWasmCommonArgs;
      radicleFlakeWasmResolverRawPackage = radicleWasmCraneLib.buildPackage (
        radicleFlakeWasmCommonArgs
        // {
          cargoArtifacts = radicleFlakeWasmCargoArtifacts;
        }
      );
      radicleFlakeWasmResolverPackage = pkgs.symlinkJoin {
        name = "radicle-flake-wasm-resolver";
        paths = [ radicleFlakeWasmResolverRawPackage ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram "$out/bin/radicle-flake-wasm-resolver" \
            --prefix PATH : ${nixpkgs.lib.makeBinPath [ pkgs.git ]}
        '';
      };
      radicleFlakeWasmWasiArgs = radicleFlakeWasmCommonArgs // {
        cargoExtraArgs = "-p radicle-flake-wasm-resolver --target wasm32-wasip1";
      };
      radicleFlakeWasmPluginArgs = radicleFlakeWasmCommonArgs // {
        cargoExtraArgs = "-p radicle-flake-wasm-resolver --lib --target wasm32-unknown-unknown";
      };
      radicleFlakeWasmPluginCargoArtifacts = radicleWasmCraneLib.buildDepsOnly radicleFlakeWasmPluginArgs;
      radicleFlakeWasmPluginPackage = radicleWasmCraneLib.buildPackage (
        radicleFlakeWasmPluginArgs
        // {
          cargoArtifacts = radicleFlakeWasmPluginCargoArtifacts;
          doCheck = false;
          nativeBuildInputs = [ pkgs.wasm-tools ];
          installPhase = ''
            wasm_path="target/wasm32-unknown-unknown/release/radicle_flake_wasm_resolver.wasm"
            test -f "$wasm_path"
            wasm-tools validate "$wasm_path"
            mkdir -p "$out/share/wasm"
            cp "$wasm_path" "$out/share/wasm/"
          '';
        }
      );
      radicleFlakeWasmWasiCargoArtifacts = radicleWasmCraneLib.buildDepsOnly radicleFlakeWasmWasiArgs;
      radicleFlakeWasmResolverWasiCheck = radicleWasmCraneLib.buildPackage (
        radicleFlakeWasmWasiArgs
        // {
          cargoArtifacts = radicleFlakeWasmWasiCargoArtifacts;
          doCheck = false;
          nativeBuildInputs = [ pkgs.wasm-tools ];
          installPhase = ''
            wasm_path="target/wasm32-wasip1/release/radicle-flake-wasm-resolver.wasm"
            test -f "$wasm_path"
            wasm-tools validate "$wasm_path"
            mkdir -p "$out/share/wasm"
            cp "$wasm_path" "$out/share/wasm/"
          '';
        }
      );
      resolveFlakeInput =
        name: explicit: flakeInputs:
        if explicit != null then
          explicit
        else if builtins.hasAttr name flakeInputs then
          builtins.getAttr name flakeInputs
        else
          throw "tusk platform builder requires `${name}` in `flakeInputs` or as an explicit argument";
      mkPlatformPkgs =
        {
          system,
          flakeInputs ? inputs,
          nixpkgsInput ? null,
          rustOverlayInput ? null,
        }:
        let
          nixpkgsSource = resolveFlakeInput "nixpkgs" nixpkgsInput flakeInputs;
          rustOverlaySource = resolveFlakeInput "rust-overlay" rustOverlayInput flakeInputs;
        in
        import nixpkgsSource {
          inherit system;
          overlays = [ rustOverlaySource.overlays.default ];
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

              export TUSK_PATHS_SH=${./scripts/tusk-paths.sh}
              # shellcheck disable=SC1090
              source "$TUSK_PATHS_SH"

              checkout_root="$(tusk_resolve_checkout_root)"
              tracker_root="$(tusk_resolve_tracker_root)"
              tusk_export_runtime_roots "$checkout_root" "$tracker_root"
              export CODEX_HOME="$checkout_root/.codex"
              sh ${./scripts/codex-home-bootstrap.sh} "$checkout_root" ".codex"

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

              export TUSK_PATHS_SH=${./scripts/tusk-paths.sh}
              # shellcheck disable=SC1090
              source "$TUSK_PATHS_SH"

              checkout_root="$(tusk_resolve_checkout_root)"
              tracker_root="$(tusk_resolve_tracker_root)"
              tusk_export_runtime_roots "$checkout_root" "$tracker_root"
              cd "$checkout_root"

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

              nix develop --no-pure-eval "path:$checkout_root" -c sh -lc "export TUSK_CHECKOUT_ROOT=\"$TUSK_CHECKOUT_ROOT\"; export TUSK_TRACKER_ROOT=\"$TUSK_TRACKER_ROOT\"; export DEVENV_ROOT=\"$TUSK_CHECKOUT_ROOT\"; export BEADS_WORKSPACE_ROOT=\"$TUSK_TRACKER_ROOT\"; $check_cmd"
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

              packages = [
                repoBeads
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
                source ${./scripts/tusk-paths.sh}
                export TUSK_CHECKOUT_ROOT="$(tusk_resolve_checkout_root "$PWD")"
                export DEVENV_ROOT="$TUSK_CHECKOUT_ROOT"
                export BEADS_WORKSPACE_ROOT="$(tusk_resolve_tracker_root)"
                export TUSK_TRACKER_ROOT="$BEADS_WORKSPACE_ROOT"
                export PATH="${repoCodex}/bin:${repoBeads}/bin:$PATH"
                hash -r >/dev/null 2>&1 || true
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

                tracker_root="$(git -C "$DEVENV_ROOT" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$DEVENV_ROOT")"
                export TUSK_CHECKOUT_ROOT="$DEVENV_ROOT"
                export BEADS_WORKSPACE_ROOT="$tracker_root"
                export TUSK_TRACKER_ROOT="$tracker_root"
                cd "$tracker_root"

                if [ ! -d .beads ]; then
                  echo "beads-dolt: skipping, .beads/ is missing"
                  exit 0
                fi

                tuskd ensure --repo "$tracker_root" >/dev/null
                echo "beads-dolt: repo-scoped tracker backend ensured"

                while true; do
                  sleep 86400
                done
              '';
            })
          ]);
        };
      mkRepoShell =
        {
          system,
          flakeInputs ? inputs,
          pkgs ? mkPlatformPkgs { inherit system flakeInputs; },
          devenvInput ? null,
          modules ? [ ],
        }:
        let
          resolvedDevenv = resolveFlakeInput "devenv" devenvInput flakeInputs;
        in
        resolvedDevenv.lib.mkShell {
          inputs = flakeInputs;
          inherit pkgs;
          modules = [ consumerCodexModule ] ++ modules;
        };
      mkNixosSystem =
        {
          system,
          flakeInputs ? inputs,
          nixpkgsInput ? null,
          modules ? [ ],
          specialArgs ? { },
        }:
        let
          resolvedNixpkgs = resolveFlakeInput "nixpkgs" nixpkgsInput flakeInputs;
        in
        resolvedNixpkgs.lib.nixosSystem {
          inherit system modules specialArgs;
        };
      mkDarwinSystem =
        {
          system,
          flakeInputs ? inputs,
          darwinInput ? null,
          modules ? [ ],
          specialArgs ? { },
        }:
        let
          resolvedDarwin = resolveFlakeInput "nix-darwin" darwinInput flakeInputs;
        in
        resolvedDarwin.lib.darwinSystem {
          inherit system modules specialArgs;
        };
      mkHomeConfiguration =
        {
          flakeInputs ? inputs,
          homeManagerInput ? null,
          pkgs,
          modules ? [ ],
          extraSpecialArgs ? { },
        }:
        let
          resolvedHomeManager = resolveFlakeInput "home-manager" homeManagerInput flakeInputs;
        in
        resolvedHomeManager.lib.homeManagerConfiguration {
          inherit pkgs modules extraSpecialArgs;
        };
      tuskTrackerPackage = pkgs.writeShellApplication {
        name = "tusk-tracker";
        runtimeInputs = [
          beads
          pkgs.git
        ];
        text = ''
          export TUSK_TRACKER_REAL_BD=${beads}/bin/bd
          export TUSK_PATHS_SH=${./scripts/tusk-paths.sh}
          exec bash ${./scripts/tusk-tracker.sh} "$@"
        '';
      };
      tuskTraceExecutorPackage = pkgs.writeShellApplication {
        name = "tusk-trace-executor";
        runtimeInputs = [
          pkgs.jq
          pkgs.nix
        ];
        text = ''
          export TUSK_PATHS_SH=${./scripts/tusk-paths.sh}
          export TUSKD_CORE_BIN=${tuskdCorePackage}/bin/tuskd-core
          export JQ_BIN=${pkgs.jq}/bin/jq
          export NIX_BIN=${pkgs.nix}/bin/nix
          exec bash ${./scripts/tusk-trace-executor.sh} "$@"
        '';
      };
      tuskSelfHostPackage = pkgs.writeShellApplication {
        name = "tusk-self-host";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
          pkgs.nix
          tuskTraceExecutorPackage
        ];
        text = ''
          export TUSK_PATHS_SH=${./scripts/tusk-paths.sh}
          export TUSKD_CORE_BIN=${tuskdCorePackage}/bin/tuskd-core
          export TUSK_TRACE_EXECUTOR_BIN=${tuskTraceExecutorPackage}/bin/tusk-trace-executor
          export JQ_BIN=${pkgs.jq}/bin/jq
          export NIX_BIN=${pkgs.nix}/bin/nix
          exec bash ${./scripts/tusk-self-host.sh} "$@"
        '';
      };
      tuskHermesProbePackage = pkgs.writeShellApplication {
        name = "tusk-hermes-probe";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
          pkgs.jq
          pkgs.podman
          tuskdCorePackage
        ];
        text = ''
          export JQ_BIN=${pkgs.jq}/bin/jq
          export TUSK_PATHS_SH=${./scripts/tusk-paths.sh}
          export TUSKD_CORE_BIN=${tuskdCorePackage}/bin/tuskd-core
          export TUSK_HERMES_PROBE_CONTAINER_SH=${./scripts/tusk-hermes-probe-container.sh}
          exec bash ${./scripts/tusk-hermes-probe.sh} "$@"
        '';
      };
      tuskHermesRuntimePackage = pkgs.writeShellApplication {
        name = "tusk-hermes-runtime";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
          pkgs.jq
          pkgs.podman
          tuskdCorePackage
        ];
        text = ''
          export JQ_BIN=${pkgs.jq}/bin/jq
          export TUSK_PATHS_SH=${./scripts/tusk-paths.sh}
          export TUSKD_CORE_BIN=${tuskdCorePackage}/bin/tuskd-core
          export TUSK_HERMES_RUNTIME_CONTAINER_SH=${./scripts/tusk-hermes-runtime-container.sh}
          exec bash ${./scripts/tusk-hermes-runtime.sh} "$@"
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
          tuskSelfHostPackage
          tuskdCorePackage
          tuskTrackerPackage
        ];
        text = ''
          export TUSKD_CORE_BIN=${tuskdCorePackage}/bin/tuskd-core
          export TUSK_SELF_HOST_BIN=${tuskSelfHostPackage}/bin/tusk-self-host
          : "''${TUSKD_CODEX_LAUNCHER:=''${TUSK_CODEX_LAUNCHER:-${tuskdCodexLauncherPackage}/bin/tuskd-codex-launcher}}"
          export TUSKD_CODEX_LAUNCHER
          export TUSK_PATHS_SH=${./scripts/tusk-paths.sh}
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
          export TUSK_PATHS_SH=${./scripts/tusk-paths.sh}
          exec bash ${./scripts/bd.sh} "$@"
        '';
      };
      repoCodex = pkgs.writeShellApplication {
        name = "codex";
        runtimeInputs = [
          repoTuskCodex
        ];
        text = ''
          exec ${repoTuskCodex}/bin/tusk-codex "$@"
        '';
      };
      repoTuskCodex = pkgs.writeShellApplication {
        name = "tusk-codex";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
          pkgs.jq
          repoBeads
          tuskdCorePackage
        ];
        text = ''
          export TUSK_PATHS_SH=${./scripts/tusk-paths.sh}
          export TUSK_CODEX_BOOTSTRAP_SH=${./scripts/codex-home-bootstrap.sh}
          export TUSKD_CORE_BIN=${tuskdCorePackage}/bin/tuskd-core
          export TUSK_REAL_BD=${repoBeads}/bin/bd
          export TUSK_REAL_CODEX=${codexPkg}/bin/codex
          exec bash ${./scripts/tusk-codex.sh} "$@"
        '';
      };
      tuskdCodexLauncherPackage = pkgs.writeShellApplication {
        name = "tuskd-codex-launcher";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
          pkgs.jq
          tuskdCorePackage
        ];
        text = ''
          export TUSK_PATHS_SH=${./scripts/tusk-paths.sh}
          export TUSK_CODEX_BOOTSTRAP_SH=${./scripts/codex-home-bootstrap.sh}
          export TUSKD_CORE_BIN=${tuskdCorePackage}/bin/tuskd-core
          export TUSK_REAL_BD=${beads}/bin/bd
          export TUSK_REAL_CODEX=${codexPkg}/bin/codex
          exec bash ${./scripts/tusk-codex.sh} "$@"
        '';
      };
      repoTuskClaude = pkgs.writeShellApplication {
        name = "tusk-claude";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
          pkgs.jq
          repoBeads
          tuskdCorePackage
        ];
        text = ''
          export TUSK_PATHS_SH=${./scripts/tusk-paths.sh}
          export TUSKD_CORE_BIN=${tuskdCorePackage}/bin/tuskd-core
          export TUSK_REAL_BD=${repoBeads}/bin/bd
          exec bash ${./scripts/tusk-claude.sh} "$@"
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
          export TUSK_PATHS_SH=${./scripts/tusk-paths.sh}
          exec bash ${./scripts/tusk-flake-ref.sh} "$@"
        '';
      };
      tuskRadiclePackage = pkgs.writeShellApplication {
        name = "tusk-radicle";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
          pkgs.gawk
          pkgs.gnugrep
          pkgs.openssh
          pkgs.radicle-node
        ];
        text = ''
          export TUSK_PATHS_SH=${./scripts/tusk-paths.sh}
          exec bash ${./scripts/tusk-radicle.sh} "$@"
        '';
      };
      tuskUiSrc = craneLib.cleanCargoSource ./crates/tusk-ui;
      tuskUiCommonArgs = {
        src = tuskUiSrc;
        strictDeps = true;
      };
      tuskUiCargoArtifacts = craneLib.buildDepsOnly tuskUiCommonArgs;
      tuskUiBinaryPackage = craneLib.buildPackage (
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
      tuskBridgeAdapterSrc = craneLib.cleanCargoSource ./crates/tusk-bridge-adapter;
      tuskBridgeAdapterCommonArgs = {
        src = tuskBridgeAdapterSrc;
        strictDeps = true;
        # Fixture-driven tests read adjunct examples outside the cleaned crate source.
        doCheck = false;
      };
      tuskBridgeAdapterCargoArtifacts = craneLib.buildDepsOnly tuskBridgeAdapterCommonArgs;
      tuskBridgeAdapterPackage = craneLib.buildPackage (
        tuskBridgeAdapterCommonArgs
        // {
          cargoArtifacts = tuskBridgeAdapterCargoArtifacts;
        }
      );
      tuskUiPackage = pkgs.writeShellApplication {
        name = "tusk-ui";
        runtimeInputs = [ tuskdPackage ];
        text = ''
          export TUSKD_BIN=${tuskdPackage}/bin/tuskd
          exec ${tuskUiBinaryPackage}/bin/tusk-ui "$@"
        '';
      };
      tuskSkillContractCheck = pkgs.writeShellApplication {
        name = "tusk-skill-contract-check";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gawk
          pkgs.git
          pkgs.gnugrep
          pkgs.nix
        ];
        text = ''
          export TUSK_PATHS_SH=${./scripts/tusk-paths.sh}
          export TUSK_SKILL_CHECK_SYSTEM=${system}
          exec bash ${./scripts/tusk-skill-contract-check.sh} "$@"
        '';
      };
      tuskBridgeConformanceCheck = pkgs.writeShellApplication {
        name = "tusk-bridge-conformance-check";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
          pkgs.nix
          rustToolchain
        ];
        text = ''
          export TUSK_PATHS_SH=${./scripts/tusk-paths.sh}
          exec bash ${./scripts/tusk-bridge-conformance-check.sh} "$@"
        '';
      };
      tuskSkillLoopPackage = pkgs.writeShellApplication {
        name = "tusk-skill-loop";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.git
          repoTuskCodex
          tuskSkillContractCheck
        ];
        text = ''
          export TUSK_PATHS_SH=${./scripts/tusk-paths.sh}
          export TUSK_CODEX_LAUNCHER=${repoTuskCodex}/bin/tusk-codex
          export TUSK_SKILL_CONTRACT_CHECK_BIN=${tuskSkillContractCheck}/bin/tusk-skill-contract-check
          exec bash ${./scripts/tusk-skill-loop.sh} "$@"
        '';
      };
      codexNixCheck = pkgs.writeShellApplication {
        name = "codex-nix-check";
        runtimeInputs = [
          glistixPkg
          pkgs.deadnix
          pkgs.erlang
          pkgs.git
          pkgs.nix
          pkgs.rebar3
          repoTuskClaude
          pkgs.rust-analyzer
          tuskClean
          tuskFlakeRefPackage
          tuskSkillContractCheck
          tuskTrackerPackage
          tuskdTransitionTestsPackage
          rustToolchain
        ];
        text = ''
          set -euo pipefail

          export TUSK_PATHS_SH=${./scripts/tusk-paths.sh}
          # shellcheck disable=SC1090
          source "$TUSK_PATHS_SH"

          checkout_root="$(tusk_resolve_checkout_root)"
          tracker_root="$(tusk_resolve_tracker_root)"
          tusk_export_runtime_roots "$checkout_root" "$tracker_root"
          cd "$checkout_root"

          deadnix --fail flake.nix devenv-codex-module.nix devenv-scratch-module.nix flake-module.nix lib.nix
          nix eval --raw "path:$checkout_root#packages.${system}.rust-toolchain.name" >/dev/null
          nix eval --raw "path:$checkout_root#packages.${system}.tusk-ui.name" >/dev/null
          nix eval --raw --apply 'x: if builtins.isFunction x || builtins.hasAttr "__functor" x then "ok" else throw "lib.crane.buildDepsOnly is not callable"' "path:$checkout_root#lib.crane.buildDepsOnly" >/dev/null
          tusk-flake-ref --repo "$checkout_root" --json >/dev/null
          check_cmd="$(cat <<'EOF'
          cd "$DEVENV_ROOT"
          bd version >/dev/null
          jj --version >/dev/null
          dolt version >/dev/null
          codex --help >/dev/null
          tusk-claude --launcher-help >/dev/null
          tusk-codex --launcher-help >/dev/null
          tusk-skill-loop --watch-help >/dev/null
          tusk-clean --help >/dev/null
          tusk-tracker --help >/dev/null
          tuskd-transition-tests --help >/dev/null
          glistix --help >/dev/null
          erl -eval "erlang:halt()." -noshell >/dev/null
          rebar3 version >/dev/null
          cargo --version >/dev/null
          rustc --version >/dev/null
          rustfmt --version >/dev/null
          rust-analyzer --version >/dev/null
          tusk-skill-contract-check --repo "$DEVENV_ROOT"
          EOF
          )"
          nix develop --no-pure-eval "path:$checkout_root" \
            -c sh -lc "export TUSK_CHECKOUT_ROOT=\"$TUSK_CHECKOUT_ROOT\"; export TUSK_TRACKER_ROOT=\"$TUSK_TRACKER_ROOT\"; export DEVENV_ROOT=\"$TUSK_CHECKOUT_ROOT\"; export BEADS_WORKSPACE_ROOT=\"$TUSK_TRACKER_ROOT\"; $check_cmd"
        '';
      };
      stageTuskOpenaiSkill = pkgs.writeShellApplication {
        name = "stage-tusk-openai-skill";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          set -euo pipefail

          target_root="''${1:-$HOME/.codex/skills}"
          target_dir="$target_root/tusk"

          mkdir -p "$target_root"
          rm -rf "$target_dir"
          cp -R ${tuskOpenaiSkillBundle} "$target_dir"

          echo "Staged tusk OpenAI skill at $target_dir"
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
            devenvSkillDevSkillModule
            devenvTopologySkillModule
            devenvBridgeSkillModule
            devenvTuskClaudeSkillModule
            devenvOpsClaudeSkillModule
            devenvNixClaudeSkillModule
            devenvSkillDevClaudeSkillModule
            devenvTopologyClaudeSkillModule
            devenvBridgeClaudeSkillModule
          ];

          # In-tree skills use runtimePath so edits to .agents/skills/<name>/
          # reflect live in the projection. Bridge is consumed via the
          # bridge-src non-flake path input (fish/sites/bridge); it has no
          # runtimePath and is projected as a packaged skill, so bridge-side
          # edits require `nix flake update bridge-src` to appear here.
          codex.skills.tusk.runtimePath = ".agents/skills/tusk";
          codex.skills.ops.runtimePath = ".agents/skills/ops";
          codex.skills.nix.runtimePath = ".agents/skills/nix";
          codex.skills.skill-dev.runtimePath = ".agents/skills/skill-dev";
          codex.skills.topology.runtimePath = ".agents/skills/topology";

          claude.skills.tusk.runtimePath = ".agents/skills/tusk";
          claude.skills.ops.runtimePath = ".agents/skills/ops";
          claude.skills.nix.runtimePath = ".agents/skills/nix";
          claude.skills.skill-dev.runtimePath = ".agents/skills/skill-dev";
          claude.skills.topology.runtimePath = ".agents/skills/topology";

          packages = [
            codexNixCheck
            glistixPkg
            stageTuskOpenaiSkill
            repoBeads
            repoTuskClaude
            repoTuskCodex
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
          tuskHermesProbePackage
          tuskHermesRuntimePackage
          tuskSkillContractCheck
          tuskSkillLoopPackage
          tuskClean
          tuskFlakeRefPackage
          tuskTrackerPackage
            tuskdPackage
            tuskdTransitionTestsPackage
            rustToolchain
          ];

          enterShell = ''
            source ${./scripts/tusk-paths.sh}
            export TUSK_CHECKOUT_ROOT="$(tusk_resolve_checkout_root "$PWD")"
            export DEVENV_ROOT="$TUSK_CHECKOUT_ROOT"
            export BEADS_WORKSPACE_ROOT="$(tusk_resolve_tracker_root)"
            export TUSK_TRACKER_ROOT="$BEADS_WORKSPACE_ROOT"
            export PATH="${repoCodex}/bin:${repoBeads}/bin:$PATH"
            hash -r >/dev/null 2>&1 || true
            echo "tusk dogfood shell"
            echo "  CODEX_HOME=$CODEX_HOME"
            echo "  codex"
            echo "  tusk-claude --launcher-help"
            echo "  tusk-codex --launcher-help"
            echo "  tusk-skill-loop --watch-help"
            echo "  devenv up"
            echo "  bd status --json"
            echo "  bd ready --json"
            echo "  jj st"
            echo "  tusk-skill-contract-check"
            echo "  tusk-bridge-conformance-check --help"
            echo "  codex-nix-check"
            echo "  tusk-clean"
            echo "  glistix --help"
            echo "  cargo --version"
            echo "  tusk-flake-ref --json"
            echo "  tusk-hermes-probe --help"
            echo "  tusk-hermes-runtime --help"
            echo "  tusk-tracker --help"
            echo "  tuskd --help"
            echo "  tuskd core-seam --json"
            echo "  tuskd-transition-tests --help"
            echo "  nix build path:.#tuskd-core"
            echo "  nix build path:.#tusk-ui"
            echo "  nix run path:.#tusk-ui -- --help"
            echo "  nix eval path:.#packages.${system}.rust-toolchain.name"
            echo "  nix eval --apply 'x: if builtins.isFunction x || builtins.hasAttr \"__functor\" x then \"ok\" else throw \"not callable\"' path:.#lib.crane.buildDepsOnly"
            echo "  stage-tusk-openai-skill"
            echo "  nix develop --no-pure-eval path:. -c sh -lc 'cd \"$DEVENV_ROOT\" && bd version && jj --version && dolt version'"
          '';

          processes.beads-dolt.exec = ''
            set -euo pipefail

            tracker_root="$(git -C "$DEVENV_ROOT" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$DEVENV_ROOT")"
            export TUSK_CHECKOUT_ROOT="$DEVENV_ROOT"
            export BEADS_WORKSPACE_ROOT="$tracker_root"
            export TUSK_TRACKER_ROOT="$tracker_root"
            cd "$tracker_root"

            if [ ! -d .beads ]; then
              echo "beads-dolt: skipping, .beads/ is missing"
              exit 0
            fi

            tuskd ensure --repo "$tracker_root" >/dev/null
            echo "beads-dolt: repo-scoped tracker backend ensured"

            while true; do
              sleep 86400
            done
          '';
        };
      repoSelfHostBase = {
        "self.codex-nix-check" = {
          systems = [ system ];
          kind = "repo.check";
          what = "self-host codex-nix-check";
          command = "nix run path:.#codex-nix-check";
          description = "Composite repo-local smoke check for the flake, runtime contract, and projected skills.";
          witnesses.contract = {
            kind = "repo.contract";
            format = "command.success";
            path = ".#codex-nix-check";
            description = "The repo-local Nix and runtime contract passes through codex-nix-check.";
          };
        };
        "self.tuskd-core-build" = {
          systems = [ system ];
          kind = "package.build";
          what = "tuskd-core build";
          installable = ".#tuskd-core";
          description = "Build the Rust control-plane core that owns coordinator and receipt seams.";
          witnesses.binary = {
            kind = "package.build";
            format = "nix.installable";
            path = ".#tuskd-core";
            description = "The tuskd-core package builds for the canonical repo toolchain.";
          };
        };
        "self.tusk-ui-build" = {
          systems = [ system ];
          kind = "package.build";
          what = "tusk-ui build";
          installable = ".#tusk-ui";
          description = "Build the operator-facing TUI over the same repo-local control plane.";
          witnesses.binary = {
            kind = "package.build";
            format = "nix.installable";
            path = ".#tusk-ui";
            description = "The tusk-ui package builds for the canonical repo toolchain.";
          };
        };
        "self.tuskd-status" = {
          systems = [ system ];
          kind = "repo.state";
          what = "repo-local control-plane status";
          command = "nix run path:.#tuskd -- status --repo \"$PWD\"";
          description = "Read the repo-scoped control-plane status without mutating state.";
          witnesses.service = {
            kind = "repo.state.service";
            format = "json.status";
            path = ".beads/tuskd/service.json";
            description = "The repo-local tuskd service can publish a healthy status snapshot.";
          };
        };
      };
      repoSelfHostWitnessIds = [
        "base.self.codex-nix-check.contract"
        "base.self.tuskd-core-build.binary"
        "base.self.tusk-ui-build.binary"
        "base.self.tuskd-status.service"
      ];
      repoSelfHostTusk =
        (nixpkgs.lib.evalModules {
          modules = [
            (
              { lib, ... }:
              {
                options.flake = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                  description = "Plain module-eval hook for exporting flake attributes.";
                };
              }
            )
            tuskFlakeModule
            {
              tusk = {
                enable = true;
                base = repoSelfHostBase;
                effects."self.trace-core-health" = {
                  requires.base = builtins.attrNames repoSelfHostBase;
                  inputs = repoSelfHostWitnessIds;
                  intent = {
                    kind = "self-host.trace";
                    target = "tusk";
                    action = "core-health";
                    description = "Record a local trace over the first self-host witness set.";
                  };
                  description = "Trace the first self-host witness root through a safe repo-local executor.";
                };
                executors.local-trace = {
                  enable = true;
                  kind = "local-trace";
                  description = "Safe repo-local executor that realizes admitted effects by appending trace receipts only.";
                  mode = "receipt-only";
                  receiptKind = "effect.trace";
                };
                drivers.local.receipts = {
                  kind = "local-receipt";
                  description = "Repo-local driver that sinks trace realizations into tuskd receipts.";
                  sink = ".beads/tuskd/receipts.jsonl";
                };
                realizations."self.trace-core-health.local" = {
                  effect = "self.trace-core-health";
                  executor = "local-trace";
                  driver = "local.receipts";
                  receipt = {
                    kind = "effect.trace";
                    mode = "local-trace";
                    description = "Repo-local trace receipt for the first self-host realization.";
                  };
                  description = "Bind the first self-host trace effect to the local receipt sink.";
                };
              };
            }
          ];
        }).config.flake.tusk;
      repoSelfHostWitnessCheck = pkgs.writeText "tusk-self-host-witnesses.json" (
        builtins.toJSON repoSelfHostTusk
      );
      repoSelfHostTraceCheck = pkgs.writeText "tusk-self-host-trace.json" (
        builtins.toJSON {
          admittedRealizations = repoSelfHostTusk.admission.realizations.admittedRealizationIds;
          localTraceExecutor = repoSelfHostTusk.executors.local-trace;
          traceRealization = repoSelfHostTusk.realizations."self.trace-core-health.local";
        }
      );
      cacheConsumeModuleSmokeCheck =
        let
          systemEvalCfg = pkgs.lib.evalModules {
            modules = [
              ./modules/cache.nix
              (
                { lib, ... }:
                {
                  options.nix.settings = {
                    substituters = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      default = [ ];
                    };
                    trusted-public-keys = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      default = [ ];
                    };
                  };
                }
              )
              {
                tusk.drivers.attic.cache = {
                  enable = true;
                  internal = {
                    enable = true;
                    bucket = "nix-cache-internal-prod";
                    region = "us-east";
                    endpoint = "https://abc123.s3.latitude.sh";
                    publicKey = "cache-internal-prod:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
                  };
                  public = {
                    enable = true;
                    url = "https://cache.example.com";
                    publicKey = "cache-public-prod:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
                  };
                };
              }
            ];
          };
          systemCfg = systemEvalCfg.config;

          shellEvalCfg = pkgs.lib.evalModules {
            modules = [
              devenvCacheModule
              (
                { lib, ... }:
                {
                  options.enterShell = lib.mkOption {
                    type = lib.types.lines;
                    default = "";
                  };
                }
              )
              {
                tusk.drivers.attic.cache.consumerShell = {
                  enable = true;
                  url = "https://cache.example.com";
                  publicKeys = [ "cache-public-prod:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=" ];
                };
              }
            ];
          };
          shellCfg = shellEvalCfg.config;

          expectedInternalStoreUrl = "s3://nix-cache-internal-prod?endpoint=abc123.s3.latitude.sh&region=us-east&scheme=https";
          assertContains =
            label: expected: actual:
            if builtins.elem expected actual then
              true
            else
              throw "tusk.drivers.attic.cache smoke: ${label} missing ${expected}; got ${builtins.toJSON actual}";
          assertHasInfix =
            label: expected: haystack:
            if pkgs.lib.hasInfix expected haystack then
              true
            else
              throw "tusk.drivers.attic.cache smoke: ${label} missing infix ${expected}; got ${haystack}";
          checks = [
            (assertContains "system internal.storeUrl" expectedInternalStoreUrl [ systemCfg.tusk.drivers.attic.cache.internal.storeUrl ])
            (assertContains "system substituters (internal)" expectedInternalStoreUrl systemCfg.nix.settings.substituters)
            (assertContains "system substituters (public)" "https://cache.example.com" systemCfg.nix.settings.substituters)
            (assertContains "system trusted-public-keys (internal)"
              "cache-internal-prod:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
              systemCfg.nix.settings.trusted-public-keys
            )
            (assertContains "system trusted-public-keys (public)"
              "cache-public-prod:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="
              systemCfg.nix.settings.trusted-public-keys
            )
            (assertHasInfix "shell enterShell substituter"
              "extra-substituters = https://cache.example.com"
              shellCfg.enterShell
            )
            (assertHasInfix "shell enterShell public key"
              "extra-trusted-public-keys = cache-public-prod:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="
              shellCfg.enterShell
            )
          ];
        in
        assert builtins.all (x: x) checks;
        pkgs.writeText "tusk-cache-consume-module-smoke.json" (
          builtins.toJSON {
            system = {
              internalStoreUrl = systemCfg.tusk.drivers.attic.cache.internal.storeUrl;
              substituters = systemCfg.nix.settings.substituters;
              trustedPublicKeys = systemCfg.nix.settings.trusted-public-keys;
            };
            shell = {
              enterShell = shellCfg.enterShell;
            };
          }
        );

      radNodeModuleSmokeCheck =
        let
          nixosEvalCfg = pkgs.lib.evalModules {
            modules = [
              ./modules/rad-node/nixos.nix
              (
                { lib, ... }:
                {
                  options.systemd.services = lib.mkOption {
                    type = lib.types.attrsOf (lib.types.attrsOf lib.types.unspecified);
                    default = { };
                  };
                }
              )
              {
                services.radNode = {
                  enable = true;
                  passphrasePath = "/var/lib/rad-seed/.rad-passphrase";
                  radHome = "/var/lib/rad-seed/.radicle";
                };
              }
            ];
            specialArgs = { inherit pkgs; };
          };
          nixosCfg = nixosEvalCfg.config;

          assertContains =
            label: expected: actual:
            if builtins.elem expected actual then
              true
            else
              throw "radNode smoke: ${label} missing ${expected}; got ${builtins.toJSON actual}";
          assertEquals =
            label: expected: actual:
            if actual == expected then
              true
            else
              throw "radNode smoke: ${label} expected ${builtins.toJSON expected}; got ${builtins.toJSON actual}";

          checks = [
            (assertEquals "nixos radicle-seed Restart" "always" nixosCfg.systemd.services.radicle-seed.serviceConfig.Restart)
            (assertEquals "nixos radicle-seed Type" "simple" nixosCfg.systemd.services.radicle-seed.serviceConfig.Type)
            (assertContains "nixos radicle-seed wantedBy" "multi-user.target" nixosCfg.systemd.services.radicle-seed.wantedBy)
          ];
        in
        assert builtins.all (x: x) checks;
        pkgs.writeText "tusk-rad-node-module-smoke.json" (
          builtins.toJSON {
            nixosServiceConfig = {
              Type = nixosCfg.systemd.services.radicle-seed.serviceConfig.Type;
              Restart = nixosCfg.systemd.services.radicle-seed.serviceConfig.Restart;
              NoNewPrivileges = nixosCfg.systemd.services.radicle-seed.serviceConfig.NoNewPrivileges;
            };
          }
        );
    in
    {
      tusk = repoSelfHostTusk;
      lib = {
        crane = craneLib;
        tusk = tuskLib;
        mkRepoShell = mkRepoShell;
        mkNixosSystem = mkNixosSystem;
        mkDarwinSystem = mkDarwinSystem;
        mkHomeConfiguration = mkHomeConfiguration;
      };
      devenvModules = {
        codex = devenvCodexModule;
        scratch = devenvScratchModule;
        cache = devenvCacheModule;
        consumer = consumerCodexModule;
        default = consumerCodexModule;
        dogfood = dogfoodModule;
        consumer-shared-skills = devenvConsumerSharedSkillsModule;
        tusk-skill = devenvTuskSkillModule;
        ops-skill = devenvOpsSkillModule;
        nix-skill = devenvNixSkillModule;
        skill-dev-skill = devenvSkillDevSkillModule;
        topology-skill = devenvTopologySkillModule;
        bridge-skill = devenvBridgeSkillModule;
      };
      flakeModules.tusk = tuskFlakeModule;
      flakeModules.default = tuskFlakeModule;
      nixosModules.cache = ./modules/cache.nix;
      nixosModules.default = ./modules/cache.nix;
      nixosModules.radNode = ./modules/rad-node/nixos.nix;
      darwinModules.cache = ./modules/cache.nix;
      darwinModules.default = ./modules/cache.nix;
      darwinModules.radNode = ./modules/rad-node/darwin.nix;
      checks.${system} = {
        radicle-flake-wasm-plugin = radicleFlakeWasmPluginPackage;
        radicle-flake-wasm-resolver-wasi = radicleFlakeWasmResolverWasiCheck;
        tusk-self-host-witnesses = repoSelfHostWitnessCheck;
        tusk-self-host-trace = repoSelfHostTraceCheck;
        tusk-cache-consume-module-smoke = cacheConsumeModuleSmokeCheck;
        tusk-rad-node-module-smoke = radNodeModuleSmokeCheck;
      };
      packages.${system} = {
        rust-toolchain = rustToolchain;
        bd = repoBeads;
        beads = repoBeads;
        tusk-claude = repoTuskClaude;
        tusk-codex = repoTuskCodex;
        tusk-skill-contract-check = tuskSkillContractCheck;
        tusk-bridge-conformance-check = tuskBridgeConformanceCheck;
        tusk-skill-loop = tuskSkillLoopPackage;
        radicle-flake-wasm-plugin = radicleFlakeWasmPluginPackage;
        radicle-flake-wasm-resolver = radicleFlakeWasmResolverPackage;
        tusk-clean = tuskClean;
        tusk-flake-ref = tuskFlakeRefPackage;
        tusk-radicle = tuskRadiclePackage;
        tusk-hermes-probe = tuskHermesProbePackage;
        tusk-hermes-runtime = tuskHermesRuntimePackage;
        tusk-self-host = tuskSelfHostPackage;
        tusk-trace-executor = tuskTraceExecutorPackage;
        tusk-tracker = tuskTrackerPackage;
        tusk-bridge-adapter = tuskBridgeAdapterPackage;
        tuskd-core = tuskdCorePackage;
        tuskd-transition-tests = tuskdTransitionTestsPackage;
        tusk-ui = tuskUiPackage;
        tusk-openai-skill = tuskOpenaiSkillBundle;
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
        tusk-claude = {
          type = "app";
          program = "${repoTuskClaude}/bin/tusk-claude";
        };
        tusk-codex = {
          type = "app";
          program = "${repoTuskCodex}/bin/tusk-codex";
        };
        codex-nix-check = {
          type = "app";
          program = "${codexNixCheck}/bin/codex-nix-check";
        };
        tusk-skill-contract-check = {
          type = "app";
          program = "${tuskSkillContractCheck}/bin/tusk-skill-contract-check";
        };
        tusk-bridge-conformance-check = {
          type = "app";
          program = "${tuskBridgeConformanceCheck}/bin/tusk-bridge-conformance-check";
        };
        tusk-skill-loop = {
          type = "app";
          program = "${tuskSkillLoopPackage}/bin/tusk-skill-loop";
        };
        radicle-flake-wasm-resolver = {
          type = "app";
          program = "${radicleFlakeWasmResolverPackage}/bin/radicle-flake-wasm-resolver";
        };
        stage-tusk-openai-skill = {
          type = "app";
          program = "${stageTuskOpenaiSkill}/bin/stage-tusk-openai-skill";
        };
        tusk-clean = {
          type = "app";
          program = "${tuskClean}/bin/tusk-clean";
        };
        tusk-flake-ref = {
          type = "app";
          program = "${tuskFlakeRefPackage}/bin/tusk-flake-ref";
        };
        tusk-radicle = {
          type = "app";
          program = "${tuskRadiclePackage}/bin/tusk-radicle";
        };
        tusk-hermes-probe = {
          type = "app";
          program = "${tuskHermesProbePackage}/bin/tusk-hermes-probe";
        };
        tusk-hermes-runtime = {
          type = "app";
          program = "${tuskHermesRuntimePackage}/bin/tusk-hermes-runtime";
        };
        tusk-self-host = {
          type = "app";
          program = "${tuskSelfHostPackage}/bin/tusk-self-host";
        };
        tusk-trace-executor = {
          type = "app";
          program = "${tuskTraceExecutorPackage}/bin/tusk-trace-executor";
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
        tusk-bridge-adapter = {
          type = "app";
          program = "${tuskBridgeAdapterPackage}/bin/tusk-bridge-adapter";
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
