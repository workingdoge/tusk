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

  codexCfg = config.codex;
  claudeCfg = config.claude;
  hasCodexSkills = codexCfg.skills != { };
  hasClaudeSkills = claudeCfg.skills != { };
  codexSkillEntries = foldl' (acc: attrs: acc // attrs) { } (
    mapAttrsToList (
      name: skill:
      tuskLib.mkDevenvCodexSkillEntries {
        inherit pkgs name;
        src = skill.source;
        root = codexCfg.installRoot;
      }
    ) codexCfg.skills
  );
  claudeSkillEntries = foldl' (acc: attrs: acc // attrs) { } (
    mapAttrsToList (
      name: skill:
      tuskLib.mkDevenvSkillEntries {
        inherit pkgs name;
        src = skill.source;
        root = claudeCfg.installRoot;
      }
    ) claudeCfg.skills
  );
  mkLegacyProjectionMigration =
    installRoot: skillAttrs:
    concatStringsSep "\n\n" (
      mapAttrsToList (
        name: _:
        ''
          target="${config.devenv.root}/${installRoot}/${name}"
          if [ -e "$target" ] && [ ! -L "$target" ]; then
            echo "Replacing legacy skill projection at ${installRoot}/${name}"
            rm -rf -- "$target"
          fi
        ''
      ) skillAttrs
    );
  migrateLegacyCodexProjection = mkLegacyProjectionMigration codexCfg.installRoot codexCfg.skills;
  migrateLegacyClaudeProjection = mkLegacyProjectionMigration claudeCfg.installRoot claudeCfg.skills;
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

  options.claude = {
    installRoot = mkOption {
      type = types.str;
      default = ".claude/skills";
      description = "Devenv-root-relative directory where Claude project skills are projected.";
    };

    skills = mkOption {
      default = { };
      description = "Claude project skills to project into the developer environment.";
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
        export CODEX_HOME="$DEVENV_ROOT/${codexCfg.homeRoot}"
        sh ${./scripts/codex-home-bootstrap.sh} "$DEVENV_ROOT" "${codexCfg.homeRoot}"
      '';
    }
    (mkIf hasCodexSkills {
      tasks."devenv:codex-skills:migrate" = {
        description = "Migrate legacy per-file Codex skill projections";
        exec = migrateLegacyCodexProjection;
        before = [
          "devenv:files"
          "devenv:enterShell"
        ];
      };

      files = codexSkillEntries;
    })
    (mkIf hasClaudeSkills {
      tasks."devenv:claude-skills:migrate" = {
        description = "Migrate legacy per-file Claude skill projections";
        exec = migrateLegacyClaudeProjection;
        before = [
          "devenv:files"
          "devenv:enterShell"
        ];
      };

      files = claudeSkillEntries;
    })
  ];
}
