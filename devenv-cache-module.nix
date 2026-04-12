{ tuskLib }:
{ config, lib, ... }:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.tusk.drivers.attic.cache.consumerShell;

  rendered = tuskLib.atticCacheConsumeConfig {
    url = cfg.url;
    publicKeys = cfg.publicKeys;
  };
in
{
  options.tusk.drivers.attic.cache.consumerShell = {
    enable = mkEnableOption "tusk-specified Nix cache consumption inside the current dev shell";

    url = mkOption {
      type = types.str;
      example = "https://cache.example.com";
      description = "HTTPS cache endpoint appended as an extra substituter for this shell.";
    };

    publicKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "cache-public-prod:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=" ];
      description = "Trusted public keys appended for substitutes fetched from the cache.";
    };
  };

  config = mkIf cfg.enable {
    enterShell = ''
      if [ -n "''${NIX_CONFIG:-}" ]; then
        export NIX_CONFIG="$NIX_CONFIG
      ${rendered.nixConfigFragment}"
      else
        export NIX_CONFIG=${lib.escapeShellArg rendered.nixConfigFragment}
      fi
    '';
  };
}
