{ config, lib, pkgs, ... }:

# Darwin (nix-darwin) impl for the shared radicle-node service.
#
# This module declares:
#   - options.services.radNode.* (imported from ./options.nix)
#   - launchd.user.agents."rad-node" (conditional on services.radNode.enable)
#
# It does NOT declare:
#   - age.secrets bindings (consumer owns agenix-rekey wiring).
#   - Network / firewall policy.
#
# Parity with nixos.nix: same launcher script shape, same three-way
# conditional, same ownership boundary (consumer provides secret backend).

let
  cfg = config.services.radNode;

  radNodeLauncher = pkgs.writeShellApplication {
    name = "rad-node-launcher";
    runtimeInputs = [ cfg.package pkgs.coreutils ];
    text = ''
      set -euo pipefail

      log() {
        printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S%z')" "$*" >&2
      }

      PASSPHRASE_FILE="${cfg.passphrasePath}"

      if [ ! -f "$PASSPHRASE_FILE" ]; then
        log "ERROR: passphrase file $PASSPHRASE_FILE missing; radicle-node not starting"
        log "hint: consumer's secret backend must materialize this path before launchd starts the agent"
        exit 1
      fi

      RAD_PASSPHRASE="$(cat "$PASSPHRASE_FILE")"
      export RAD_PASSPHRASE

      export RAD_HOME="${cfg.radHome}"
      mkdir -p "$RAD_HOME"

      log "starting radicle-node (passphrase loaded, RAD_HOME=$RAD_HOME)"
      exec radicle-node
    '';
  };
in
{
  imports = [ (import ./options.nix { inherit lib; }) ];

  config = lib.mkMerge [
    {
      services.radNode.package = lib.mkDefault pkgs.radicle-node;
    }

    (lib.mkIf cfg.enable {
      launchd.user.agents."rad-node" = {
        command = lib.getExe radNodeLauncher;

        serviceConfig = {
          RunAtLoad = true;
          KeepAlive = true;
        } // lib.optionalAttrs (cfg.logPath != null) {
          StandardOutPath = cfg.logPath;
          StandardErrorPath = cfg.logPath;
        };
      };
    })
  ];
}
