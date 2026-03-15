{ tuskLib }:
{ lib, config, ... }:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.tusk;
  normalized = tuskLib.normalize cfg;
in
{
  options.tusk = {
    enable = mkEnableOption "the tusk operational surface";

    base = mkOption {
      default = { };
      description = "Pure verified entries that emit witnesses for later operational intents.";
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              id = mkOption {
                type = types.str;
                default = name;
                description = "Stable identifier for the base entry.";
              };
              systems = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Systems on which the base entry is expected to run.";
              };
              kind = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Semantic kind of the verified entry.";
              };
              what = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Short semantic label for the verified entry.";
              };
              installable = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Installable reference evaluated by this base entry.";
              };
              command = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Optional command used to realize this base entry.";
              };
              description = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Human-readable description of the base entry.";
              };
              witnesses = mkOption {
                default = { };
                description = "Named witnesses emitted by the verified entry.";
                type = types.attrsOf (
                  types.submodule (
                    { name, ... }:
                    {
                      options = {
                        id = mkOption {
                          type = types.nullOr types.str;
                          default = null;
                          description = "Optional override for the witness identifier.";
                        };
                        kind = mkOption {
                          type = types.str;
                          default = name;
                          description = "Semantic kind of the witness.";
                        };
                        format = mkOption {
                          type = types.nullOr types.str;
                          default = null;
                          description = "Optional format label for the emitted witness.";
                        };
                        path = mkOption {
                          type = types.nullOr types.str;
                          default = null;
                          description = "Optional path or locator associated with the witness.";
                        };
                        description = mkOption {
                          type = types.nullOr types.str;
                          default = null;
                          description = "Human-readable description of the witness.";
                        };
                      };
                    }
                  )
                );
              };
            };
          }
        )
      );
    };

    effects = mkOption {
      default = { };
      description = "Declared operational intents over verified witnesses.";
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              id = mkOption {
                type = types.str;
                default = name;
                description = "Stable identifier for the effect.";
              };
              requires.base = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Base entries that must succeed before admission is possible.";
              };
              requires.capabilities = {
                secrets = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "Secret references required by the effect.";
                };
                authorities = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "Authority capabilities required by the effect.";
                };
                state = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "Mutable state scopes required by the effect.";
                };
                approvals = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "Approval classes required by the effect.";
                };
              };
              inputs = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Witness identifiers consumed by the effect.";
              };
              intent = {
                kind = mkOption {
                  type = types.str;
                  description = "Semantic kind of operational intent.";
                };
                target = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Named target addressed by the intent.";
                };
                action = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Optional concrete action label under the intent kind.";
                };
                description = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Human-readable description of the intent.";
                };
              };
              description = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Human-readable description of the effect.";
              };
            };
          }
        )
      );
    };

    executors = mkOption {
      default = { };
      description = "Execution authorities that may admit and run effects.";
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            freeformType = types.attrsOf types.anything;

            options = {
              id = mkOption {
                type = types.str;
                default = name;
                description = "Stable identifier for the executor.";
              };
              kind = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Semantic kind of executor.";
              };
              enable = mkOption {
                type = types.bool;
                default = false;
                description = "Whether this executor is available for admission.";
              };
              description = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Human-readable description of the executor.";
              };
            };
          }
        )
      );
    };

    drivers = mkOption {
      default = { };
      description = "Target-system drivers grouped by driver family.";
      type = types.attrsOf (
        types.attrsOf (
          types.submodule (
            { ... }:
            {
              freeformType = types.attrsOf types.anything;

              options = {
                id = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Optional override for the driver binding identifier.";
                };
                kind = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Optional override for the driver family kind.";
                };
                description = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Human-readable description of the driver binding.";
                };
              };
            }
          )
        )
      );
    };

    realizations = mkOption {
      default = { };
      description = "Compiled bindings of effects to an executor and a driver.";
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              id = mkOption {
                type = types.str;
                default = name;
                description = "Stable identifier for the realization.";
              };
              effect = mkOption {
                type = types.str;
                description = "Effect realized by this binding.";
              };
              executor = mkOption {
                type = types.str;
                description = "Executor responsible for admitting and running the effect.";
              };
              driver = mkOption {
                type = types.str;
                description = "Driver used to talk to the target system.";
              };
              receipt = {
                kind = mkOption {
                  type = types.str;
                  default = "trace";
                  description = "Expected receipt kind.";
                };
                mode = mkOption {
                  type = types.str;
                  default = "planned";
                  description = "Receipt mode for the realization.";
                };
                externalRef = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Optional external reference associated with the receipt.";
                };
                description = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Human-readable description of the receipt expectation.";
                };
              };
              description = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Human-readable description of the realization.";
              };
            };
          }
        )
      );
    };
  };

  config = mkIf cfg.enable {
    flake.tusk =
      if normalized.validations.isValid then
        normalized
      else
        throw (tuskLib.renderValidationError normalized.validations);
  };
}
