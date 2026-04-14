{ lib }:

# Shared option set for the radicle-node service.
#
# Consumed by:
#   nixosModules.radNode  (modules/rad-node/nixos.nix)
#   darwinModules.radNode (modules/rad-node/darwin.nix)
#
# Secret-backend abstraction: the shared options DO NOT pick agenix-rekey
# vs sops-nix vs plaintext. Consumers wire their own secret backend to
# materialize `passphrasePath`. Tusk eval never sees the decrypted value.

{
  options.services.radNode = {
    enable = lib.mkEnableOption "radicle-node service managed by tusk shared module";

    passphrasePath = lib.mkOption {
      type = lib.types.str;
      description = ''
        Filesystem path where the consumer's secret backend materializes
        the decrypted RAD_PASSPHRASE at runtime. The launcher script
        reads this file, exports `RAD_PASSPHRASE`, and execs radicle-node.

        Consumers choose the path to match their secret backend:
          - agenix / agenix-rekey: typically `/run/agenix/rad_passphrase`
            or `/private/tmp/agenix/rad_passphrase` (darwin).
          - sops-nix:              typically the `sops.secrets.<name>.path`
                                   value declared by the consumer.
      '';
      example = "/var/lib/rad-seed/.rad-passphrase";
    };

    radHome = lib.mkOption {
      type = lib.types.str;
      description = ''
        RAD_HOME environment variable passed to radicle-node. Must be
        writable by the user the service runs as. Consumers typically
        place this inside the service user's home or state directory.
      '';
      example = "/var/lib/rad-seed/.radicle";
    };

    logPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Darwin-only: launchd stdout/stderr path. Ignored on NixOS
        (systemd journal captures output). Null on NixOS consumers.
      '';
      example = "/tmp/rad-node.log";
    };

    package = lib.mkOption {
      type = lib.types.package;
      description = ''
        The radicle-node package to run. Consumers may override to pin
        a specific version; default is `pkgs.radicle-node` from the
        consumer's nixpkgs.
      '';
    };
  };
}
