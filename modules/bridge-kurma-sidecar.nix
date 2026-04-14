{ config, lib, ... }:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optionalString
    types
    ;

  cfg = config.tusk.services.bridgeKurmaSidecar;
  sidecarServiceName = "bridge-kurma-sidecar";
  effectiveWorkingDirectory =
    if cfg.workingDirectory != null then cfg.workingDirectory else cfg.stateDir;
  reverseProxyTarget = "${cfg.listen.address}:${toString cfg.listen.port}";
in
{
  options.tusk.services.bridgeKurmaSidecar = {
    enable = mkEnableOption "tusk-managed local Bridge/Kurma sidecar host surface";

    execStart = mkOption {
      type = types.str;
      default = "";
      example = "\${pkgs.kurma}/bin/kurma-sidecar --listen 127.0.0.1:4310";
      description = ''
        Fully rendered systemd ExecStart command for the sidecar runtime.
        Tusk keeps this caller-provided so the host surface does not become the
        semantic owner of the Kurma runtime.
      '';
    };

    path = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Additional packages added to the sidecar service PATH.";
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Extra environment variables passed to the sidecar service.";
    };

    user = mkOption {
      type = types.str;
      default = "bridge-kurma";
      description = "System user that runs the local sidecar service.";
    };

    group = mkOption {
      type = types.str;
      default = "bridge-kurma";
      description = "System group that owns the local sidecar runtime files.";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/bridge-kurma-sidecar";
      description = "Persistent state directory for the local sidecar runtime.";
    };

    artifactDir = mkOption {
      type = types.str;
      default = "/var/lib/bridge-kurma-sidecar/artifacts";
      description = "Directory for receipts, projections, and other sidecar artifacts.";
    };

    workingDirectory = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional override for the sidecar service working directory.";
    };

    listen = {
      address = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Local listen address exposed by the sidecar runtime.";
      };

      port = mkOption {
        type = types.port;
        default = 4310;
        description = "Local listen port exposed by the sidecar runtime.";
      };
    };

    caddy = {
      enable = mkEnableOption "optional Caddy reverse proxy in front of the sidecar runtime";

      host = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "sidecar.local";
        description = "Virtual host served by Caddy for the sidecar edge.";
      };

      tlsInternal = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the Caddy virtual host should use `tls internal`.";
      };

      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = "Extra Caddy directives appended after the reverse_proxy rule.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.execStart != "";
          message = "tusk.services.bridgeKurmaSidecar.execStart must be set when the sidecar host surface is enabled";
        }
        {
          assertion = (!cfg.caddy.enable) || cfg.caddy.host != null;
          message = "tusk.services.bridgeKurmaSidecar.caddy.host must be set when Caddy proxying is enabled";
        }
      ];

      users.groups.${cfg.group} = { };
      users.users.${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
        home = cfg.stateDir;
        createHome = true;
        description = "Bridge/Kurma sidecar runtime user";
      };

      systemd.tmpfiles.rules = [
        "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} -"
        "d ${cfg.artifactDir} 0750 ${cfg.user} ${cfg.group} -"
      ];

      systemd.services.${sidecarServiceName} = {
        description = "Local Bridge/Kurma sidecar";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        inherit (cfg) environment path;
        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          WorkingDirectory = effectiveWorkingDirectory;
          ExecStart = cfg.execStart;
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };
    }

    (mkIf cfg.caddy.enable {
      services.caddy.enable = true;
      services.caddy.virtualHosts.${cfg.caddy.host}.extraConfig = ''
        ${optionalString cfg.caddy.tlsInternal "tls internal"}
        reverse_proxy ${reverseProxyTarget}
        ${cfg.caddy.extraConfig}
      '';
    })
  ]);
}
