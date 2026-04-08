{ lib }:
let
  inherit (builtins)
    pathExists
    removeAttrs
    ;
  inherit (lib)
    attrNames
    attrValues
    concatStringsSep
    elem
    filter
    flatten
    listToAttrs
    map
    mapAttrs
    mapAttrsToList
    nameValuePair
    optional
    ;

  mkBase = args: args // { kind = args.kind or "base"; };
  mkWitness = args: args // { kind = args.kind or "witness"; };
  mkIntent = args: args // { kind = args.kind or "intent"; };
  mkEffect = args: args // { kind = "effect"; };
  mkExecutor = args: args // { kind = args.kind or "executor"; };
  mkDriver = args: args // { kind = args.kind or "driver"; };
  mkRealization = args: args // { kind = "realization"; };

  validateSkillSource =
    {
      name,
      src,
      requiredFiles ? [ "SKILL.md" ],
    }:
    let
      sourcePath = toString src;
      missing = filter (relativePath: !(pathExists "${sourcePath}/${relativePath}")) requiredFiles;
    in
    if missing == [ ] then
      src
    else
      throw "Skill `${name}` is missing required files: ${concatStringsSep ", " missing}";

  validateCodexSkillSource =
    {
      name,
      src,
      requiredFiles ? [
        "SKILL.md"
        "agents/openai.yaml"
      ],
    }:
    validateSkillSource {
      inherit name src requiredFiles;
    };

  mkSkillPackage =
    {
      pkgs,
      name,
      src,
      requiredFiles ? [ "SKILL.md" ],
    }:
    let
      checkedSource = validateSkillSource {
        inherit name src requiredFiles;
      };
    in
    pkgs.runCommand "${name}-skill" { } ''
      mkdir -p "$out"
      cp -R ${checkedSource}/. "$out/"
      chmod -R u+w "$out"
    '';

  mkCodexSkillPackage =
    {
      pkgs,
      name,
      src,
    }:
    let
      checkedSource = validateCodexSkillSource { inherit name src; };
    in
    pkgs.runCommand "${name}-openai-skill" { } ''
      mkdir -p "$out"
      cp -R ${checkedSource}/. "$out/"
      chmod -R u+w "$out"
    '';

  mkDevenvSkillEntries =
    {
      pkgs,
      name,
      src,
      root ? ".codex/skills",
      requiredFiles ? [ "SKILL.md" ],
    }:
    let
      checkedSource = validateSkillSource {
        inherit name src requiredFiles;
      };
      package = mkSkillPackage {
        inherit pkgs name;
        src = checkedSource;
        inherit requiredFiles;
      };
    in
    {
      "${root}/${name}" = {
        source = package;
      };
    };

  mkDevenvCodexSkillEntries =
    {
      pkgs,
      name,
      src,
      root ? ".codex/skills",
    }:
    mkDevenvSkillEntries {
      inherit pkgs name src root;
      requiredFiles = [
        "SKILL.md"
        "agents/openai.yaml"
      ];
    };

  resolveId = value: fallback: if value != null then value else fallback;

  normalizeWitness = baseId: name: witness: {
    id = resolveId (witness.id or null) "base.${baseId}.${name}";
    name = name;
    kind = witness.kind or name;
    format = witness.format or null;
    path = witness.path or null;
    description = witness.description or null;
  };

  normalizeBase =
    name: entry:
    let
      baseId = entry.id or name;
      rawWitnesses = entry.witnesses or { };
      witnessSource =
        if attrNames rawWitnesses == [ ] then
          {
            default = {
              kind = entry.kind or baseId;
              description = "Default witness emitted by ${baseId}.";
            };
          }
        else
          rawWitnesses;
    in
    {
      id = resolveId (entry.id or null) baseId;
      kind = "base";
      systems = entry.systems or [ ];
      what = entry.what or (entry.kind or baseId);
      installable = entry.installable or null;
      command = entry.command or null;
      description = entry.description or null;
      witnesses = mapAttrs (normalizeWitness baseId) witnessSource;
    };

  normalizeCapabilities = capabilities: {
    secrets = capabilities.secrets or [ ];
    authorities = capabilities.authorities or [ ];
    state = capabilities.state or [ ];
    approvals = capabilities.approvals or [ ];
  };

  flattenCapabilities =
    capabilities:
    capabilities.secrets ++ capabilities.authorities ++ capabilities.state ++ capabilities.approvals;

  normalizeIntent = intent: {
    kind = intent.kind or "unspecified";
    target = intent.target or null;
    action = intent.action or null;
    description = intent.description or null;
  };

  normalizeEffect =
    name: effect:
    let
      requires = effect.requires or { };
    in
    {
      id = resolveId (effect.id or null) name;
      kind = "effect";
      requires = {
        base = requires.base or [ ];
        capabilities = normalizeCapabilities (requires.capabilities or { });
      };
      inputs = effect.inputs or [ ];
      intent = normalizeIntent (effect.intent or { });
      description = effect.description or null;
    };

  normalizeExecutor = name: executor: {
    id = resolveId (executor.id or null) name;
    kind = executor.kind or name;
    enable = executor.enable or false;
    description = executor.description or null;
    config = removeAttrs executor [
      "id"
      "kind"
      "enable"
      "description"
    ];
  };

  normalizeDriver = family: name: driver: {
    id = resolveId (driver.id or null) "${family}.${name}";
    family = family;
    name = name;
    kind = driver.kind or family;
    description = driver.description or null;
    config = removeAttrs driver [
      "id"
      "kind"
      "description"
    ];
  };

  normalizeReceipt = name: receipt: {
    kind = receipt.kind or "trace";
    mode = receipt.mode or "planned";
    externalRef = receipt.externalRef or null;
    description = receipt.description or "Receipt expectation for ${name}.";
  };

  normalizeRealization = name: realization: {
    id = resolveId (realization.id or null) name;
    kind = "realization";
    effect = realization.effect;
    executor = realization.executor;
    driver = realization.driver;
    receipt = normalizeReceipt name (realization.receipt or { });
    description = realization.description or null;
  };

  collectWitnesses =
    bases:
    listToAttrs (
      flatten (
        mapAttrsToList (
          _: base:
          mapAttrsToList (
            _: witness: nameValuePair witness.id (witness // { base = base.id; })
          ) base.witnesses
        ) bases
      )
    );

  collectMissingBaseRefs =
    baseIds: effects:
    flatten (
      mapAttrsToList (
        _: effect:
        map (baseId: "${effect.id}:${baseId}") (
          filter (baseId: !(elem baseId baseIds)) effect.requires.base
        )
      ) effects
    );

  collectMissingWitnessRefs =
    witnessIds: effects:
    flatten (
      mapAttrsToList (
        _: effect:
        map (witnessId: "${effect.id}:${witnessId}") (
          filter (witnessId: !(elem witnessId witnessIds)) effect.inputs
        )
      ) effects
    );

  collectMissingEffectRefs =
    effectIds: realizations:
    flatten (
      mapAttrsToList (
        _: realization:
        optional (!(elem realization.effect effectIds)) "${realization.id}:${realization.effect}"
      ) realizations
    );

  collectMissingExecutorRefs =
    executorIds: realizations:
    flatten (
      mapAttrsToList (
        _: realization:
        optional (!(elem realization.executor executorIds)) "${realization.id}:${realization.executor}"
      ) realizations
    );

  collectMissingDriverRefs =
    driverIds: realizations:
    flatten (
      mapAttrsToList (
        _: realization:
        optional (!(elem realization.driver driverIds)) "${realization.id}:${realization.driver}"
      ) realizations
    );

  effectBlockers =
    baseIds: witnessIds: effect:
    optional (
      filter (baseId: !(elem baseId baseIds)) effect.requires.base != [ ]
    ) "missing required base witnesses"
    ++ optional (
      filter (witnessId: !(elem witnessId witnessIds)) effect.inputs != [ ]
    ) "missing required input witnesses";

  renderValidationError =
    validations:
    let
      parts =
        optional (validations.missingBaseRefs != [ ]) (
          "missing base references: ${concatStringsSep ", " validations.missingBaseRefs}"
        )
        ++ optional (validations.missingWitnessRefs != [ ]) (
          "missing witness references: ${concatStringsSep ", " validations.missingWitnessRefs}"
        )
        ++ optional (validations.missingEffectRefs != [ ]) (
          "missing effect references: ${concatStringsSep ", " validations.missingEffectRefs}"
        )
        ++ optional (validations.missingExecutorRefs != [ ]) (
          "missing executor references: ${concatStringsSep ", " validations.missingExecutorRefs}"
        )
        ++ optional (validations.missingDriverRefs != [ ]) (
          "missing driver references: ${concatStringsSep ", " validations.missingDriverRefs}"
        );
    in
    "tusk declarations are inconsistent: ${concatStringsSep "; " parts}";

  normalize =
    cfg:
    let
      bases = mapAttrs normalizeBase (cfg.base or { });
      witnesses = collectWitnesses bases;
      effects = mapAttrs normalizeEffect (cfg.effects or { });
      executors = mapAttrs normalizeExecutor (cfg.executors or { });
      drivers = mapAttrs (family: mapAttrs (normalizeDriver family)) (cfg.drivers or { });
      realizations = mapAttrs normalizeRealization (cfg.realizations or { });

      baseIds = attrNames bases;
      witnessIds = attrNames witnesses;
      effectIds = attrNames effects;
      executorIds = map (executor: executor.id) (attrValues executors);
      driverIds = map (driver: driver.id) (flatten (mapAttrsToList (_: attrValues) drivers));
      realizationIds = attrNames realizations;

      missingBaseRefs = collectMissingBaseRefs baseIds effects;
      missingWitnessRefs = collectMissingWitnessRefs witnessIds effects;
      missingEffectRefs = collectMissingEffectRefs effectIds realizations;
      missingExecutorRefs = collectMissingExecutorRefs executorIds realizations;
      missingDriverRefs = collectMissingDriverRefs driverIds realizations;

      admission = listToAttrs (
        mapAttrsToList (
          _: effect:
          let
            blockers = effectBlockers baseIds witnessIds effect;
          in
          nameValuePair effect.id {
            blockers = blockers;
            capabilities = effect.requires.capabilities;
            status = if blockers == [ ] then "proposed" else "blocked";
          }
        ) effects
      );

      structurallyReadyEffectIds = map (effect: effect.id) (
        filter (effect: (effectBlockers baseIds witnessIds effect) == [ ]) (attrValues effects)
      );

      blockedEffectIds = map (effect: effect.id) (
        filter (effect: (effectBlockers baseIds witnessIds effect) != [ ]) (attrValues effects)
      );

      pendingCapabilityEffectIds = map (effect: effect.id) (
        filter (effect: flattenCapabilities effect.requires.capabilities != [ ]) (attrValues effects)
      );
    in
    {
      enable = cfg.enable or false;
      base = bases;
      inherit
        witnesses
        effects
        executors
        drivers
        realizations
        ;
      admission = {
        declaredEffectIds = effectIds;
        inherit structurallyReadyEffectIds blockedEffectIds pendingCapabilityEffectIds;
        byEffect = admission;
      };
      receipts = {
        expected = mapAttrs (_: realization: realization.receipt) realizations;
      };
      graph = {
        inherit
          baseIds
          witnessIds
          effectIds
          executorIds
          driverIds
          realizationIds
          ;
      };
      validations = {
        inherit
          missingBaseRefs
          missingWitnessRefs
          missingEffectRefs
          missingExecutorRefs
          missingDriverRefs
          ;
        isValid =
          missingBaseRefs == [ ]
          && missingWitnessRefs == [ ]
          && missingEffectRefs == [ ]
          && missingExecutorRefs == [ ]
          && missingDriverRefs == [ ];
      };
    };
in
{
  inherit
    mkDevenvSkillEntries
    mkCodexSkillPackage
    mkDevenvCodexSkillEntries
    mkSkillPackage
    mkBase
    mkDriver
    mkEffect
    mkExecutor
    mkIntent
    mkRealization
    mkWitness
    normalize
    renderValidationError
    validateSkillSource
    validateCodexSkillSource
    ;
}
