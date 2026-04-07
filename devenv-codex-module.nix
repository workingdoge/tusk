{ tuskLib }:
{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib)
    concatStringsSep
    foldl'
    mapAttrsToList
    mkBefore
    mkIf
    mkMerge
    mkOption
    types
    ;

  cfg = config.codex;
  hasSkills = cfg.skills != { };
  skillEntries = foldl' (acc: attrs: acc // attrs) { } (
    mapAttrsToList (
      name: skill:
      tuskLib.mkDevenvCodexSkillEntries {
        inherit pkgs name;
        src = skill.source;
        root = cfg.installRoot;
      }
    ) cfg.skills
  );
  migrateLegacySkillProjection = concatStringsSep "\n\n" (
    mapAttrsToList (
      name: _:
      ''
        target="${config.devenv.root}/${cfg.installRoot}/${name}"
        if [ -e "$target" ] && [ ! -L "$target" ]; then
          echo "Replacing legacy Codex skill projection at ${cfg.installRoot}/${name}"
          rm -rf -- "$target"
        fi
      ''
    ) cfg.skills
  );
in
{
  options.codex = {
    homeRoot = mkOption {
      type = types.str;
      default = ".codex";
      description = "Devenv-root-relative directory used as the repo-local Codex home.";
    };

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

  config = mkMerge [
    {
      enterShell = mkBefore ''
        export CODEX_HOME="$DEVENV_ROOT/${cfg.homeRoot}"
        sh ${./scripts/codex-home-bootstrap.sh} "$DEVENV_ROOT" "${cfg.homeRoot}"
      '';
    }
    (mkIf hasSkills {
      tasks."devenv:codex-skills:migrate" = {
        description = "Migrate legacy per-file Codex skill projections";
        exec = migrateLegacySkillProjection;
        before = [
          "devenv:files"
          "devenv:enterShell"
        ];
      };

      files = skillEntries;
    })
  ];
}
