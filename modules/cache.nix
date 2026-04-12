{ config, lib, ... }:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    types
    ;

  cfg = config.tusk.drivers.attic.cache;

  stripScheme =
    endpoint:
    let
      withoutHttps = lib.removePrefix "https://" endpoint;
    in
    lib.removePrefix "http://" withoutHttps;

  renderValue =
    value: if builtins.isBool value then (if value then "true" else "false") else toString value;

  encodeQuery =
    attrs:
    lib.concatStringsSep "&" (
      lib.mapAttrsToList (name: value: "${name}=${renderValue value}") (
        lib.filterAttrs (_: value: value != null && value != "") attrs
      )
    );

  withQuery =
    base: attrs:
    let
      query = encodeQuery attrs;
      separator = if lib.hasInfix "?" base then "&" else "?";
    in
    if query == "" then base else "${base}${separator}${query}";

  internalStoreUrl = withQuery "s3://${cfg.internal.bucket}" (
    {
      endpoint = stripScheme cfg.internal.endpoint;
      inherit (cfg.internal) region scheme;
      profile = cfg.internal.profile;
    }
    // cfg.internal.extraStoreParams
  );
in
{
  options.tusk.drivers.attic.cache = {
    enable = mkEnableOption "tusk-specified Nix cache consume surface";

    internal = {
      enable = mkEnableOption "internal cache substituter and trusted key";

      bucket = mkOption {
        type = types.str;
        example = "nix-cache-internal-prod";
        description = "Bucket name for the canonical internal S3-compatible cache.";
      };

      region = mkOption {
        type = types.str;
        example = "us-east";
        description = "Region for the internal cache origin.";
      };

      endpoint = mkOption {
        type = types.str;
        example = "<account-id>.s3.latitude.sh";
        description = "S3-compatible endpoint host or full URL for the internal cache origin.";
      };

      scheme = mkOption {
        type = types.enum [
          "http"
          "https"
        ];
        default = "https";
        description = "Transport scheme for the internal cache origin.";
      };

      profile = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "latitude-internal";
        description = "Optional AWS credential profile the reader uses against the internal origin.";
      };

      publicKey = mkOption {
        type = types.str;
        example = "cache-internal-prod:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        description = "Trusted public key for internal cache substitutes.";
      };

      extraStoreParams = mkOption {
        type = types.attrsOf (
          types.oneOf [
            types.str
            types.int
            types.bool
          ]
        );
        default = { };
        description = "Extra query parameters appended to the internal S3 store URL.";
      };

      storeUrl = mkOption {
        type = types.str;
        readOnly = true;
        description = "Computed Nix S3 binary cache URL for the internal cache origin.";
      };
    };

    public = {
      enable = mkEnableOption "public cache substituter and trusted key";

      url = mkOption {
        type = types.str;
        example = "https://cache.example.com";
        description = "Public HTTPS mirror for laptops, external CI, and release consumers.";
      };

      publicKey = mkOption {
        type = types.str;
        example = "cache-public-prod:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
        description = "Trusted public key for the public cache mirror.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      tusk.drivers.attic.cache.internal.storeUrl = internalStoreUrl;
    }
    (mkIf cfg.internal.enable {
      nix.settings.substituters = [ cfg.internal.storeUrl ];
      nix.settings.trusted-public-keys = [ cfg.internal.publicKey ];
    })
    (mkIf cfg.public.enable {
      nix.settings.substituters = [ cfg.public.url ];
      nix.settings.trusted-public-keys = [ cfg.public.publicKey ];
    })
  ]);
}
