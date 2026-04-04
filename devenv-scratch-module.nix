{
  lib,
  config,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    optionalString
    types
    ;

  cfg = config.tusk.scratch;
in
{
  options.tusk.scratch = {
    enable = mkEnableOption "repo-aware scratch relocation for common build tools";

    root = mkOption {
      type = types.str;
      default = "$HOME/.cache/tusk-scratch";
      description = ''
        Shell-expanded root under which per-repo scratch directories are created.
      '';
    };

    slug = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Optional stable directory slug. When null, the module derives one from
        DEVENV_ROOT at shell entry.
      '';
    };

    cargo.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Export CARGO_TARGET_DIR under the scratch root.";
    };

    terraform.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Export TF_DATA_DIR under the scratch root.";
    };

    uv.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Export UV_CACHE_DIR under the scratch root.";
    };

    pip.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Export PIP_CACHE_DIR under the scratch root.";
    };

    tmp.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Export TMPDIR under the scratch root.";
    };
  };

  config = mkIf cfg.enable {
    enterShell = ''
      : ''${XDG_CACHE_HOME:="$HOME/.cache"}

      tusk_sanitize_slug() {
        printf '%s' "$1" | tr '/: ' '---' | tr -cd '[:alnum:]._\n-'
      }

      repo_root="''${DEVENV_ROOT:-$PWD}"
      repo_slug=${
        if cfg.slug == null then ''"$(tusk_sanitize_slug "$repo_root")"'' else ''"${cfg.slug}"''
      }
      export TUSK_SCRATCH_ROOT="${cfg.root}/$repo_slug"

      mkdir -p "$TUSK_SCRATCH_ROOT"
      mkdir -p "$TUSK_SCRATCH_ROOT/tmp"
      mkdir -p "$TUSK_SCRATCH_ROOT/cargo-target"
      mkdir -p "$TUSK_SCRATCH_ROOT/terraform-data"
      mkdir -p "$TUSK_SCRATCH_ROOT/uv-cache"
      mkdir -p "$TUSK_SCRATCH_ROOT/pip-cache"

      ${optionalString cfg.tmp.enable ''
        export TMPDIR="$TUSK_SCRATCH_ROOT/tmp"
      ''}
      ${optionalString cfg.cargo.enable ''
        export CARGO_TARGET_DIR="$TUSK_SCRATCH_ROOT/cargo-target"
      ''}
      ${optionalString cfg.terraform.enable ''
        export TF_DATA_DIR="$TUSK_SCRATCH_ROOT/terraform-data"
      ''}
      ${optionalString cfg.uv.enable ''
        export UV_CACHE_DIR="$TUSK_SCRATCH_ROOT/uv-cache"
      ''}
      ${optionalString cfg.pip.enable ''
        export PIP_CACHE_DIR="$TUSK_SCRATCH_ROOT/pip-cache"
      ''}
    '';
  };
}
