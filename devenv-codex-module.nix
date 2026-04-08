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
    filterAttrs
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
  codexPackagedSkills = filterAttrs (_: skill: skill.runtimePath == null) codexCfg.skills;
  codexRuntimeLinkedSkills = filterAttrs (_: skill: skill.runtimePath != null) codexCfg.skills;
  claudePackagedSkills = filterAttrs (_: skill: skill.runtimePath == null) claudeCfg.skills;
  claudeRuntimeLinkedSkills = filterAttrs (_: skill: skill.runtimePath != null) claudeCfg.skills;
  codexSkillEntries = foldl' (acc: attrs: acc // attrs) { } (
    mapAttrsToList (
      name: skill:
      tuskLib.mkDevenvCodexSkillEntries {
        inherit pkgs name;
        src = skill.source;
        root = codexCfg.installRoot;
      }
    ) codexPackagedSkills
  );
  claudeSkillEntries = foldl' (acc: attrs: acc // attrs) { } (
    mapAttrsToList (
      name: skill:
      tuskLib.mkDevenvSkillEntries {
        inherit pkgs name;
        src = skill.source;
        root = claudeCfg.installRoot;
      }
    ) claudePackagedSkills
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
  mkRuntimeProjectionTask =
    installRoot: skillAttrs:
    concatStringsSep "\n\n" (
      mapAttrsToList (
        name: skill:
        let
          runtimePath = skill.runtimePath;
        in
        ''
          target_root="${config.devenv.root}/${installRoot}"
          target="$target_root/${name}"
          source="${config.devenv.root}/${runtimePath}"

          mkdir -p "$target_root"

          if [ -e "$target" ] || [ -L "$target" ]; then
            if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
              :
            else
              rm -rf -- "$target"
            fi
          fi

          if [ ! -L "$target" ]; then
            ln -s "$source" "$target"
          fi

          if [ -d "$source" ]; then
            for link_path in "$source"/*; do
              [ -e "$link_path" ] || continue
              [ -L "$link_path" ] || continue
              link_target="$(readlink "$link_path")"
              case "$link_target" in
                /nix/store/*-skill|/nix/store/*-openai-skill)
                  echo "Removing stale skill projection artifact ${name}/$(basename "$link_path")"
                  rm -f -- "$link_path"
                  ;;
              esac
            done
          fi
        ''
      ) skillAttrs
    );
  migrateLegacyCodexProjection = mkLegacyProjectionMigration codexCfg.installRoot codexCfg.skills;
  migrateLegacyClaudeProjection = mkLegacyProjectionMigration claudeCfg.installRoot claudeCfg.skills;
  codexRuntimeProjection = mkRuntimeProjectionTask codexCfg.installRoot codexRuntimeLinkedSkills;
  claudeRuntimeProjection = mkRuntimeProjectionTask claudeCfg.installRoot claudeRuntimeLinkedSkills;
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
            options = {
              source = mkOption {
                type = types.path;
                description = "Path to the skill directory that contains SKILL.md.";
              };

              runtimePath = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Optional devenv-root-relative skill root to symlink at runtime instead of projecting a store copy.";
              };
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
            options = {
              source = mkOption {
                type = types.path;
                description = "Path to the skill directory that contains SKILL.md.";
              };

              runtimePath = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Optional devenv-root-relative skill root to symlink at runtime instead of projecting a store copy.";
              };
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

      tasks."devenv:codex-skills:runtime-links" = mkIf (codexRuntimeLinkedSkills != { }) {
        description = "Project runtime-linked Codex skills into the live checkout";
        exec = codexRuntimeProjection;
        before = [ "devenv:enterShell" ];
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

      tasks."devenv:claude-skills:runtime-links" = mkIf (claudeRuntimeLinkedSkills != { }) {
        description = "Project runtime-linked Claude skills into the live checkout";
        exec = claudeRuntimeProjection;
        before = [ "devenv:enterShell" ];
      };

      files = claudeSkillEntries;
    })
  ];
}
