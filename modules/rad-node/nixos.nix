{ config, lib, pkgs, ... }:

# NixOS impl for the shared radicle-node service.
#
# This module declares:
#   - options.services.radNode.* (imported from ./options.nix)
#   - systemd.services.radicle-seed (conditional on services.radNode.enable)
#
# It does NOT declare:
#   - Users/groups for the service (consumer owns compartment-specific
#     user/group/state-directory policy; see spine §4.1 compartments).
#   - sops-nix / agenix bindings (consumer owns secret-backend wiring).
#   - Firewall policy (consumer decides seed port exposure per spine §5.1).
#
# Three-way conditional matches home's rad-node.nix and workingdoge's
# cloud/host/modules/seed.nix for behavioral parity:
#   enable + passphrase exists    -> service runs radicle-node
#   enable + passphrase missing   -> service logs error and exits (1)
#   !enable                        -> service not declared

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
        log "hint: the consumer's secret backend must materialize this path before systemd starts the unit"
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
      systemd.services.radicle-seed = {
        description = "Radicle node/seed (tusk shared module)";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "10s";
          ExecStart = lib.getExe radNodeLauncher;

          # Hardening defaults. Consumers SHOULD ALSO supply their own
          # User/Group/StateDirectory/ReadWritePaths via an additional
          # module ingredient (compartment-specific, per spine §4.1).
          # This module does NOT set User/Group so the consumer is
          # forced to declare them.
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
        };
      };
    })
  ];
}
