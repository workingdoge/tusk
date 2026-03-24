{
  lib,
  devenv,
  nixpkgs,
  llm-agents,
  sharedSkillSources ? { },
}:
let
  inherit (builtins)
    attrNames
    hasAttr
    pathExists
    readDir
    ;
  inherit (lib)
    filter
    foldl'
    concatStringsSep
    escapeShellArg
    listToAttrs
    map
    mapAttrsToList
    nameValuePair
    optionalString
    setAttrByPath
    ;

  repoRootResolver = ''
    repo_root="''${BEADS_WORKSPACE_ROOT:-''${DEVENV_ROOT:-}}"
    if [ -z "$repo_root" ]; then
      repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    fi
  '';

  validateCodexSkillSource =
    {
      name,
      src,
      requiredFiles ? [
        "SKILL.md"
        "agents/openai.yaml"
      ],
    }:
    let
      sourcePath = toString src;
      missing = filter (relativePath: !(pathExists "${sourcePath}/${relativePath}")) requiredFiles;
    in
    if missing == [ ] then
      src
    else
      throw "Codex skill `${name}` is missing required files: ${concatStringsSep ", " missing}";

  mkCodexSkillPackage =
    {
      pkgs,
      name,
      src,
      bundleName ? "${name}-openai-skill",
    }:
    let
      checkedSource = validateCodexSkillSource { inherit name src; };
    in
    pkgs.runCommand bundleName { } ''
      mkdir -p "$out"
      cp -R ${checkedSource}/. "$out/"
      chmod -R u+w "$out"
    '';

  listRelativeFiles =
    src:
    let
      go =
        prefix: path:
        let
          entries = readDir path;
        in
        builtins.concatLists (
          mapAttrsToList (
            name: kind:
            let
              relativePath = if prefix == "" then name else "${prefix}/${name}";
            in
            if kind == "directory" then go relativePath (path + "/${name}") else [ relativePath ]
          ) entries
        );
    in
    go "" src;

  mkDevenvCodexSkillFiles =
    {
      pkgs,
      name,
      src,
      root ? ".codex/skills",
    }:
    let
      checkedSource = validateCodexSkillSource { inherit name src; };
      package = mkCodexSkillPackage {
        inherit pkgs name;
        src = checkedSource;
      };
    in
    listToAttrs (
      map (
        relativePath:
        nameValuePair "${root}/${name}/${relativePath}" {
          source = package + "/${relativePath}";
        }
      ) (listRelativeFiles checkedSource)
    );

  selectSkillSources =
    names: sources:
    listToAttrs (
      map (
        name:
        if hasAttr name sources then
          nameValuePair name sources.${name}
        else
          throw "Unknown shared skill `${name}` requested from mkRepoShell"
      ) names
    );

  mkRepoShell =
    {
      system,
      repoName ? "repo",
      shellName ? "${repoName} dev shell",
      checkFiles ? [ ],
      extraPackages ? [ ],
      extraCheckCommands ? [ ],
      extraEnterShellLines ? [ ],
      extraProcesses ? { },
      enableBeadsProcess ? true,
      trackerDir ? ".beads",
      trackerProcessName ? "beads-dolt",
      skillName ? "tusk",
      skillBundleName ? "${skillName}-openai-skill",
      installSkillCommandName ? "install-${skillName}-openai-skill",
      installSkillTargetName ? skillName,
      projectSharedSkills ? true,
      sharedSkillNames ? attrNames sharedSkillSources,
      repoSkillSources ? { },
      codexInstallRoot ? ".codex/skills",
    }:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      beads = llm-agents.packages.${system}.beads;
      codexPkg = llm-agents.packages.${system}.codex;
      checkArgs = concatStringsSep " " (map escapeShellArg checkFiles);
      extraChecks = concatStringsSep "\n" extraCheckCommands;
      extraEnterShell = concatStringsSep "\n" extraEnterShellLines;
      projectedSharedSkillSources =
        if projectSharedSkills then selectSkillSources sharedSkillNames sharedSkillSources else { };
      duplicateSkillNames = filter (name: hasAttr name projectedSharedSkillSources) (
        attrNames repoSkillSources
      );
      activeSkillSources =
        if duplicateSkillNames == [ ] then
          projectedSharedSkillSources // repoSkillSources
        else
          throw "repoSkillSources redefines shared skills: ${concatStringsSep ", " duplicateSkillNames}";
      projectedSkillFiles = foldl' (acc: attrs: acc // attrs) { } (
        mapAttrsToList (
          name: src:
          mkDevenvCodexSkillFiles {
            inherit pkgs name src;
            root = codexInstallRoot;
          }
        ) activeSkillSources
      );
      projectedSkillChecks = concatStringsSep " && " (
        map (
          name:
          "test -L ${escapeShellArg "${codexInstallRoot}/${name}/SKILL.md"} && test -L ${escapeShellArg "${codexInstallRoot}/${name}/agents/openai.yaml"}"
        ) (attrNames activeSkillSources)
      );
      projectionCheckSuffix = optionalString (projectedSkillChecks != "") " && ${projectedSkillChecks}";
      skillBundleSource =
        if hasAttr installSkillTargetName activeSkillSources then
          activeSkillSources.${installSkillTargetName}
        else if hasAttr skillName activeSkillSources then
          activeSkillSources.${skillName}
        else
          throw "No skill source is available for `${installSkillTargetName}`";
      skillBundle = mkCodexSkillPackage {
        inherit pkgs;
        name = installSkillTargetName;
        src = skillBundleSource;
        bundleName = skillBundleName;
      };
      codexNixCheck = pkgs.writeShellApplication {
        name = "codex-nix-check";
        runtimeInputs = [
          pkgs.deadnix
          pkgs.git
          pkgs.nix
        ];
        text = ''
          set -euo pipefail

          ${repoRootResolver}
          cd "$repo_root"

          ${optionalString (checkFiles != [ ]) "deadnix --fail ${checkArgs}"}
          ${extraChecks}
          if [ "''${DEVENV_ROOT:-}" = "$repo_root" ]; then
            bd version >/dev/null
            jj --version >/dev/null
            dolt version >/dev/null
            codex --help >/dev/null
            ${projectedSkillChecks}
          else
            nix develop --no-pure-eval "path:$repo_root" \
              -c sh -lc "cd \"\$DEVENV_ROOT\" && bd version >/dev/null && jj --version >/dev/null && dolt version >/dev/null && codex --help >/dev/null${projectionCheckSuffix}"
          fi
        '';
      };
      repoCodex = pkgs.writeShellApplication {
        name = "codex";
        runtimeInputs = [
          beads
          pkgs.git
        ];
        text = ''
          set -eu

          ${repoRootResolver}
          cd "$repo_root"
          export BEADS_WORKSPACE_ROOT="$repo_root"

          if [ -d ${escapeShellArg trackerDir} ]; then
            bd ready --json >/dev/null 2>&1 || true
          fi

          exec ${codexPkg}/bin/codex -C "$repo_root" "$@"
        '';
      };
      installSkill = pkgs.writeShellApplication {
        name = installSkillCommandName;
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          set -euo pipefail

          target_root="''${1:-$HOME/.codex/skills}"
          target_dir="$target_root/${installSkillTargetName}"

          mkdir -p "$target_root"
          rm -rf "$target_dir"
          cp -R ${skillBundle} "$target_dir"

          echo "Installed compatibility projection for ${installSkillTargetName} to $target_dir"
        '';
      };
      packages = [
        beads
        codexNixCheck
        installSkill
        pkgs.deadnix
        pkgs.direnv
        pkgs.dolt
        pkgs.git
        pkgs.jujutsu
        pkgs.jq
        pkgs.nil
        pkgs.nix-output-monitor
        pkgs.nix-tree
        pkgs.nixd
        pkgs.nixfmt
        pkgs.ripgrep
        pkgs.statix
        repoCodex
      ]
      ++ extraPackages;
      beadsProcess = setAttrByPath [ trackerProcessName "exec" ] ''
        set -euo pipefail
        cd "$DEVENV_ROOT"

        if [ ! -d ${escapeShellArg trackerDir} ]; then
          echo "${trackerProcessName}: skipping, ${trackerDir}/ is missing"
          exit 0
        fi

        bd dolt start >/dev/null
        echo "${trackerProcessName}: dolt server started"

        cleanup() {
          bd dolt stop >/dev/null 2>&1 || true
        }

        trap cleanup EXIT INT TERM

        while true; do
          sleep 86400
        done
      '';
      processes = (if enableBeadsProcess then beadsProcess else { }) // extraProcesses;
      devenvModule =
        { ... }:
        {
          inherit packages processes;
          files = projectedSkillFiles;

          enterShell = ''
            export PATH="${repoCodex}/bin:$PATH"
            export BEADS_WORKSPACE_ROOT="$DEVENV_ROOT"
            echo "${shellName}"
            echo "  codex"
            echo "  devenv up"
            echo "  bd status --json"
            echo "  bd ready --json"
            echo "  jj st"
            echo "  codex-nix-check"
            echo "  ${codexInstallRoot}"
            echo "  ${installSkillCommandName}"
            echo "  nix develop --no-pure-eval path:. -c sh -lc 'cd \"$DEVENV_ROOT\" && bd version && jj --version && dolt version'"
            ${extraEnterShell}
          '';
        };
      apps = {
        beads = {
          type = "app";
          program = "${beads}/bin/bd";
        };
        codex = {
          type = "app";
          program = "${repoCodex}/bin/codex";
        };
        codex-nix-check = {
          type = "app";
          program = "${codexNixCheck}/bin/codex-nix-check";
        };
        ${installSkillCommandName} = {
          type = "app";
          program = "${installSkill}/bin/${installSkillCommandName}";
        };
      };
      mkShell =
        {
          inputs,
          modules ? [ ],
          pkgs ? null,
        }:
        devenv.lib.mkShell {
          inherit inputs;
          pkgs = if pkgs == null then nixpkgs.legacyPackages.${system} else pkgs;
          modules = [ devenvModule ] ++ modules;
        };
    in
    {
      inherit
        apps
        beads
        codexNixCheck
        devenvModule
        installSkill
        mkCodexSkillPackage
        mkDevenvCodexSkillFiles
        mkShell
        packages
        pkgs
        repoCodex
        skillBundle
        validateCodexSkillSource
        ;
    };
in
{
  inherit
    mkCodexSkillPackage
    mkDevenvCodexSkillFiles
    mkRepoShell
    validateCodexSkillSource
    ;
}
