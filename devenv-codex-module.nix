{ tuskLib }:
{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib)
    foldl'
    mapAttrsToList
    mkIf
    mkOption
    types
    ;

  cfg = config.codex;
  hasSkills = cfg.skills != { };
in
{
  options.codex = {
    installRoot = mkOption {
      type = types.str;
      default = ".codex/skills";
      description = "Devenv-root-relative directory where Codex skills are projected.";
    };

    skills = mkOption {
      default = { };
      description = "Codex/OpenAI skills to project into the developer environment.";
      type = types.attrsOf (
        types.submodule (
          { ... }:
          {
            options.source = mkOption {
              type = types.path;
              description = "Path to the skill directory that contains SKILL.md.";
            };
          }
        )
      );
    };
  };

  config = mkIf hasSkills {
    files = foldl' (acc: attrs: acc // attrs) { } (
      mapAttrsToList (
        name: skill:
        tuskLib.mkDevenvCodexSkillFiles {
          inherit pkgs name;
          src = skill.source;
          root = cfg.installRoot;
        }
      ) cfg.skills
    );
  };
}
