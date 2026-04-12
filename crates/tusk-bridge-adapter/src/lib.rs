use axum::{
    Json, Router,
    extract::{State, rejection::JsonRejection},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::fmt::Write as _;
use std::fs;
use std::path::Path;
use std::sync::{Arc, RwLock};

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct AuthorizeRequest {
    pub version: String,
    #[serde(default)]
    pub request_id: Option<String>,
    pub witness: Witness,
    pub call: Call,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(transparent)]
pub struct Witness {
    raw: Value,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Call {
    pub requested_tool: String,
    pub requested_resource: String,
    pub source_domain: String,
    #[serde(default)]
    pub destination_domain: Option<String>,
    #[serde(default)]
    pub cross_domain: Option<bool>,
    #[serde(default)]
    pub payload_hash: Option<String>,
    pub session_nonce: String,
    pub rp_initiated: bool,
    pub pop_proof: Value,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ProviderResults {
    pub version: String,
    pub preflight: Preflight,
    pub runtime: Runtime,
    pub events: Events,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct Preflight {
    pub schema_valid: bool,
    pub signature_valid: bool,
    pub issuer_not_revoked: bool,
    pub jti_not_revoked: bool,
    pub replay_cache_absent: bool,
    pub pop_valid: bool,
    pub posture_match: bool,
    pub subject_allowed: bool,
    pub delegated_actor_allowed: bool,
    pub materialize_only_at_execution_leaf: bool,
    pub evidence_emit_ok: bool,
    pub release_basis_allowed: bool,
    pub release_review_chain_complete: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct Events {
    pub bridge_host_attestation_failed: bool,
    pub issuer_compromise_detected: bool,
    pub audit_tamper_detected: bool,
    pub canary_or_honey_credential_activated: bool,
    pub controlled_release_policy_bypass_detected: bool,
    pub policy_hash_mismatch: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Runtime {
    pub authoritative_now: String,
    pub verifier_id: String,
    pub time_source_ok: bool,
    pub current_mode: String,
    pub attestation_snapshot: Value,
    pub revocation_snapshot: Value,
    pub resource_policy: Value,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct PolicyInput {
    pub witness: Witness,
    pub preflight: Preflight,
    pub events: Events,
    pub runtime_request: RuntimeRequest,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct RuntimeRequest {
    pub attestation_snapshot: Value,
    pub cross_domain: bool,
    pub current_mode: String,
    pub destination_domain: String,
    pub now: String,
    pub payload_hash: String,
    pub pop_proof: Value,
    pub requested_resource: String,
    pub requested_tool: String,
    pub resource_policy: Value,
    pub revocation_snapshot: Value,
    pub rp_initiated: bool,
    pub session_nonce: String,
    pub source_domain: String,
    pub time_source_ok: bool,
    pub verifier_id: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct AuditRecord {
    pub version: String,
    pub record_type: String,
    pub event_time: String,
    pub authoritative_time_source: String,
    pub trace: String,
    pub jti: String,
    pub effect: String,
    pub subject: String,
    pub act_for: String,
    pub domain: String,
    pub source_domain: String,
    pub destination_domain: String,
    pub tool: String,
    pub resource: String,
    pub current_mode: String,
    pub witness_sha256: String,
    pub policy_input_sha256: String,
    pub deny_reasons: Vec<String>,
    pub burn_reasons: Vec<String>,
    pub labels: AuditLabels,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct AuditLabels {
    pub conf_label: Value,
    pub integ_label: Value,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct ModeState {
    pub version: String,
    pub current_mode: String,
    pub updated_at: String,
    pub epoch: String,
    #[serde(default)]
    pub last_command_id: Option<String>,
    #[serde(default)]
    pub cut_set: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct Decision {
    pub effect: String,
    pub allow: bool,
    pub burn: bool,
    pub trace: Option<String>,
    pub jti: Option<String>,
    pub deny_reasons: Vec<String>,
    pub burn_reasons: Vec<String>,
    pub effective_authority: Option<EffectiveAuthority>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct EffectiveAuthority {
    pub tool: String,
    pub resource: String,
    pub conf_label: Value,
    pub integ_label: Value,
    pub ttl_s: u64,
    pub egress_policy: Value,
    pub output_policy: Value,
    pub approval_mode: String,
    pub constraints: Value,
}

#[derive(Clone, Debug, PartialEq)]
pub struct AuthorizeOutcome {
    pub decision: Decision,
    pub policy_input: PolicyInput,
    pub audit_record: AuditRecord,
}

#[derive(Clone, Debug)]
struct LocalRuntimeState {
    mode_state: ModeState,
    active_burn_reason: Option<String>,
}

#[derive(Clone, Debug)]
pub struct LocalApiState {
    provider_results: ProviderResults,
    runtime: Arc<RwLock<LocalRuntimeState>>,
    authoritative_time_source: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct ModeCommand {
    pub version: String,
    pub operation: String,
    pub command_id: String,
    pub trace: String,
    pub requested_by: String,
    pub reason_code: String,
    #[serde(default)]
    pub cut_set: Vec<String>,
    pub approval_mode: String,
    pub approval_evidence: ApprovalEvidence,
    #[serde(default)]
    pub ticket: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct ApprovalEvidence {
    pub quorum: u64,
    pub approvers: Vec<Approver>,
    #[serde(default)]
    pub ticket: Option<String>,
    #[serde(default)]
    pub basis: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct Approver {
    pub id: String,
    pub role: String,
    pub approved_at: String,
    #[serde(default)]
    pub authn_strength: Option<String>,
}

impl Witness {
    fn object(&self) -> Result<&serde_json::Map<String, Value>, String> {
        self.raw
            .as_object()
            .ok_or_else(|| "witness must be a JSON object".to_string())
    }

    fn required_string(&self, key: &str) -> Result<String, String> {
        let value = self
            .object()?
            .get(key)
            .ok_or_else(|| format!("witness missing required field `{key}`"))?;
        value
            .as_str()
            .map(ToOwned::to_owned)
            .ok_or_else(|| format!("witness field `{key}` must be a string"))
    }

    fn string_or_default(&self, key: &str) -> Result<String, String> {
        match self.object()?.get(key) {
            None => Ok(String::new()),
            Some(value) => value
                .as_str()
                .map(ToOwned::to_owned)
                .ok_or_else(|| format!("witness field `{key}` must be a string")),
        }
    }

    fn clone_value(&self, key: &str) -> Result<Value, String> {
        self.object()?
            .get(key)
            .cloned()
            .ok_or_else(|| format!("witness missing required field `{key}`"))
    }

    fn required_u64(&self, key: &str) -> Result<u64, String> {
        let value = self
            .object()?
            .get(key)
            .ok_or_else(|| format!("witness missing required field `{key}`"))?;
        value
            .as_u64()
            .ok_or_else(|| format!("witness field `{key}` must be an unsigned integer"))
    }

    pub fn sub(&self) -> Result<String, String> {
        self.required_string("sub")
    }

    pub fn act_for(&self) -> Result<String, String> {
        self.string_or_default("act_for")
    }

    pub fn domain(&self) -> Result<String, String> {
        self.required_string("domain")
    }

    pub fn tool(&self) -> Result<String, String> {
        self.required_string("tool")
    }

    pub fn resource(&self) -> Result<String, String> {
        self.required_string("resource")
    }

    pub fn trace(&self) -> Result<String, String> {
        self.required_string("trace")
    }

    pub fn jti(&self) -> Result<String, String> {
        self.required_string("jti")
    }

    pub fn conf_label(&self) -> Result<Value, String> {
        self.clone_value("conf_label")
    }

    pub fn integ_label(&self) -> Result<Value, String> {
        self.clone_value("integ_label")
    }

    pub fn ttl_s(&self) -> Result<u64, String> {
        self.required_u64("ttl_s")
    }

    pub fn approval_mode(&self) -> Result<String, String> {
        self.required_string("approval_mode")
    }

    pub fn egress_policy(&self) -> Result<Value, String> {
        self.clone_value("egress_policy")
    }

    pub fn output_policy(&self) -> Result<Value, String> {
        self.clone_value("output_policy")
    }

    pub fn constraints(&self) -> Result<Value, String> {
        self.clone_value("constraints")
    }
}

impl LocalApiState {
    pub fn new(
        provider_results: ProviderResults,
        mode_state: ModeState,
        authoritative_time_source: String,
    ) -> Self {
        Self {
            provider_results,
            runtime: Arc::new(RwLock::new(LocalRuntimeState {
                mode_state,
                active_burn_reason: None,
            })),
            authoritative_time_source,
        }
    }

    pub fn from_files(
        provider_results_path: &Path,
        mode_state_path: &Path,
        authoritative_time_source: String,
    ) -> Result<Self, String> {
        Ok(Self::new(
            load_json_file(provider_results_path)?,
            load_json_file(mode_state_path)?,
            authoritative_time_source,
        ))
    }

    pub fn mode_state(&self) -> Result<ModeState, String> {
        self.runtime
            .read()
            .map_err(|_| "local runtime state lock poisoned".to_string())
            .map(|state| state.mode_state.clone())
    }

    pub fn authorize(&self, request: AuthorizeRequest) -> Result<AuthorizeOutcome, String> {
        let runtime = self
            .runtime
            .read()
            .map_err(|_| "local runtime state lock poisoned".to_string())?;
        authorize_with_state(
            request,
            &self.provider_results,
            &runtime.mode_state,
            runtime.active_burn_reason.as_deref(),
            &self.authoritative_time_source,
        )
    }

    pub fn burn(&self, command: ModeCommand) -> Result<ModeState, String> {
        self.apply_mode_command(command, "burn")
    }

    pub fn restore(&self, command: ModeCommand) -> Result<ModeState, String> {
        self.apply_mode_command(command, "restore")
    }

    fn apply_mode_command(
        &self,
        command: ModeCommand,
        expected_operation: &str,
    ) -> Result<ModeState, String> {
        validate_mode_command(&command, expected_operation)?;
        let updated_at = command_updated_at(&command)?;
        let mut runtime = self
            .runtime
            .write()
            .map_err(|_| "local runtime state lock poisoned".to_string())?;

        runtime.mode_state.updated_at = updated_at;
        runtime.mode_state.last_command_id = Some(command.command_id.clone());

        match expected_operation {
            "burn" => {
                runtime.mode_state.current_mode = "safe".to_string();
                runtime.mode_state.cut_set = command.cut_set.clone();
                runtime.active_burn_reason = Some(command.reason_code);
            }
            "restore" => {
                runtime.mode_state.current_mode = "normal".to_string();
                runtime.mode_state.cut_set.clear();
                runtime.active_burn_reason = None;
            }
            _ => return Err(format!("unsupported mode operation `{expected_operation}`")),
        }

        Ok(runtime.mode_state.clone())
    }
}

pub fn load_json_file<T>(path: &Path) -> Result<T, String>
where
    T: for<'de> Deserialize<'de>,
{
    let text = fs::read_to_string(path)
        .map_err(|err| format!("failed to read {}: {err}", path.display()))?;
    serde_json::from_str(&text).map_err(|err| format!("failed to parse {}: {err}", path.display()))
}

pub fn write_json_file<T>(path: &Path, value: &T) -> Result<(), String>
where
    T: Serialize,
{
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|err| format!("failed to create {}: {err}", parent.display()))?;
    }
    let text = serde_json::to_string_pretty(value)
        .map_err(|err| format!("failed to serialize {}: {err}", path.display()))?;
    fs::write(path, format!("{text}\n"))
        .map_err(|err| format!("failed to write {}: {err}", path.display()))
}

pub fn assemble(
    authorize_request: AuthorizeRequest,
    provider_results: ProviderResults,
) -> Result<PolicyInput, String> {
    let destination_domain = authorize_request
        .call
        .destination_domain
        .clone()
        .unwrap_or_else(|| authorize_request.call.source_domain.clone());

    Ok(PolicyInput {
        witness: authorize_request.witness,
        preflight: provider_results.preflight,
        events: provider_results.events,
        runtime_request: RuntimeRequest {
            attestation_snapshot: provider_results.runtime.attestation_snapshot,
            cross_domain: compute_cross_domain(&authorize_request.call),
            current_mode: provider_results.runtime.current_mode,
            destination_domain,
            now: provider_results.runtime.authoritative_now,
            payload_hash: authorize_request.call.payload_hash.unwrap_or_default(),
            pop_proof: authorize_request.call.pop_proof,
            requested_resource: authorize_request.call.requested_resource,
            requested_tool: authorize_request.call.requested_tool,
            resource_policy: provider_results.runtime.resource_policy,
            revocation_snapshot: provider_results.runtime.revocation_snapshot,
            rp_initiated: authorize_request.call.rp_initiated,
            session_nonce: authorize_request.call.session_nonce,
            source_domain: authorize_request.call.source_domain,
            time_source_ok: provider_results.runtime.time_source_ok,
            verifier_id: provider_results.runtime.verifier_id,
        },
    })
}

pub fn audit_stub(
    policy_input: &PolicyInput,
    authoritative_time_source: &str,
) -> Result<AuditRecord, String> {
    Ok(AuditRecord {
        version: "0.2".to_string(),
        record_type: "authorize".to_string(),
        event_time: policy_input.runtime_request.now.clone(),
        authoritative_time_source: authoritative_time_source.to_string(),
        trace: policy_input.witness.trace()?,
        jti: policy_input.witness.jti()?,
        effect: "error".to_string(),
        subject: policy_input.witness.sub()?,
        act_for: policy_input.witness.act_for()?,
        domain: policy_input.witness.domain()?,
        source_domain: policy_input.runtime_request.source_domain.clone(),
        destination_domain: policy_input.runtime_request.destination_domain.clone(),
        tool: policy_input.witness.tool()?,
        resource: policy_input.witness.resource()?,
        current_mode: policy_input.runtime_request.current_mode.clone(),
        witness_sha256: sha256_hex(&policy_input.witness)?,
        policy_input_sha256: sha256_hex(policy_input)?,
        deny_reasons: Vec::new(),
        burn_reasons: Vec::new(),
        labels: AuditLabels {
            conf_label: policy_input.witness.conf_label()?,
            integ_label: policy_input.witness.integ_label()?,
        },
    })
}

pub fn authorize_with_state(
    authorize_request: AuthorizeRequest,
    provider_results: &ProviderResults,
    mode_state: &ModeState,
    active_burn_reason: Option<&str>,
    authoritative_time_source: &str,
) -> Result<AuthorizeOutcome, String> {
    let mut synchronized_provider_results = provider_results.clone();
    synchronized_provider_results.runtime.current_mode = mode_state.current_mode.clone();

    let policy_input = assemble(authorize_request, synchronized_provider_results)?;
    let decision = match active_burn_reason {
        Some(reason_code) => forced_burn_decision(&policy_input, reason_code)?,
        None => decision_for_policy_input(&policy_input)?,
    };
    let audit_record = audit_stub(&policy_input, authoritative_time_source)?;

    Ok(AuthorizeOutcome {
        decision,
        policy_input,
        audit_record,
    })
}

pub fn decision_for_policy_input(policy_input: &PolicyInput) -> Result<Decision, String> {
    let mut deny_reasons = Vec::new();
    push_if_false(
        &mut deny_reasons,
        policy_input.preflight.schema_valid,
        "schema_valid",
    );
    push_if_false(
        &mut deny_reasons,
        policy_input.preflight.signature_valid,
        "signature_valid",
    );
    push_if_false(
        &mut deny_reasons,
        policy_input.preflight.issuer_not_revoked,
        "issuer_not_revoked",
    );
    push_if_false(
        &mut deny_reasons,
        policy_input.preflight.jti_not_revoked,
        "jti_not_revoked",
    );
    push_if_false(
        &mut deny_reasons,
        policy_input.preflight.replay_cache_absent,
        "replay_cache_absent",
    );
    push_if_false(
        &mut deny_reasons,
        policy_input.preflight.pop_valid,
        "pop_valid",
    );
    push_if_false(
        &mut deny_reasons,
        policy_input.preflight.posture_match,
        "posture_match",
    );
    push_if_false(
        &mut deny_reasons,
        policy_input.preflight.subject_allowed,
        "subject_allowed",
    );
    push_if_false(
        &mut deny_reasons,
        policy_input.preflight.delegated_actor_allowed,
        "delegated_actor_allowed",
    );
    push_if_false(
        &mut deny_reasons,
        policy_input.preflight.materialize_only_at_execution_leaf,
        "materialize_only_at_execution_leaf",
    );
    push_if_false(
        &mut deny_reasons,
        policy_input.preflight.evidence_emit_ok,
        "evidence_emit_ok",
    );
    push_if_false(
        &mut deny_reasons,
        policy_input.preflight.release_basis_allowed,
        "release_basis_allowed",
    );
    push_if_false(
        &mut deny_reasons,
        policy_input.preflight.release_review_chain_complete,
        "release_review_chain_complete",
    );

    let mut burn_reasons = Vec::new();
    if policy_input.runtime_request.current_mode == "burn" {
        burn_reasons.push("CURRENT_MODE_BURN".to_string());
    }
    push_if_true(
        &mut burn_reasons,
        policy_input.events.bridge_host_attestation_failed,
        "BRIDGE_HOST_ATTESTATION_FAILED",
    );
    push_if_true(
        &mut burn_reasons,
        policy_input.events.issuer_compromise_detected,
        "ISSUER_COMPROMISE_DETECTED",
    );
    push_if_true(
        &mut burn_reasons,
        policy_input.events.audit_tamper_detected,
        "AUDIT_TAMPER_DETECTED",
    );
    push_if_true(
        &mut burn_reasons,
        policy_input.events.canary_or_honey_credential_activated,
        "CANARY_OR_HONEY_CREDENTIAL_ACTIVATED",
    );
    push_if_true(
        &mut burn_reasons,
        policy_input
            .events
            .controlled_release_policy_bypass_detected,
        "CONTROLLED_RELEASE_POLICY_BYPASS_DETECTED",
    );
    push_if_true(
        &mut burn_reasons,
        policy_input.events.policy_hash_mismatch,
        "POLICY_HASH_MISMATCH",
    );

    let effect = if !burn_reasons.is_empty() {
        "burn"
    } else if deny_reasons.is_empty() {
        "accept"
    } else {
        "deny"
    };

    Ok(Decision {
        effect: effect.to_string(),
        allow: effect == "accept",
        burn: effect == "burn",
        trace: Some(policy_input.witness.trace()?),
        jti: Some(policy_input.witness.jti()?),
        deny_reasons,
        burn_reasons,
        effective_authority: if effect == "deny" {
            None
        } else {
            Some(effective_authority_from_policy_input(policy_input)?)
        },
    })
}

pub fn build_router(state: LocalApiState) -> Router {
    Router::new()
        .route("/v1/authorize", post(authorize_handler))
        .route("/v1/state/mode", get(mode_state_handler))
        .route("/v1/admin/burn", post(burn_handler))
        .route("/v1/admin/restore", post(restore_handler))
        .with_state(state)
}

fn effective_authority_from_policy_input(
    policy_input: &PolicyInput,
) -> Result<EffectiveAuthority, String> {
    let witness_constraints = policy_input.witness.constraints()?;
    let witness_constraints = value_object(&witness_constraints, "witness.constraints")?;
    let resource_policy = value_object(
        &policy_input.runtime_request.resource_policy,
        "runtime_request.resource_policy",
    )?;

    let mut integ_label = serde_json::Map::new();
    integ_label.insert(
        "level".to_string(),
        Value::String(object_string(resource_policy, "required_integ_level")?),
    );
    let integ_tags = object_array(resource_policy, "required_integ_tags")?;
    if !integ_tags.is_empty() {
        integ_label.insert("tags".to_string(), Value::Array(integ_tags));
    }

    let mut egress_policy = serde_json::Map::new();
    egress_policy.insert(
        "mode".to_string(),
        Value::String(object_string(resource_policy, "egress_mode")?),
    );
    egress_policy.insert(
        "destinations".to_string(),
        Value::Array(object_array(resource_policy, "egress_allowlist")?),
    );

    let mut output_policy = serde_json::Map::new();
    output_policy.insert(
        "redaction_profile".to_string(),
        Value::String(object_string(
            resource_policy,
            "required_redaction_profile",
        )?),
    );
    output_policy.insert(
        "max_response_bytes".to_string(),
        Value::Number(object_u64(resource_policy, "max_response_bytes")?.into()),
    );
    output_policy.insert(
        "allow_secrets_in_output".to_string(),
        Value::Bool(object_bool(
            value_object(
                &policy_input.witness.output_policy()?,
                "witness.output_policy",
            )?,
            "allow_secrets_in_output",
        )?),
    );
    output_policy.insert(
        "return_to_model".to_string(),
        Value::Bool(object_bool(resource_policy, "return_to_model_allowed")?),
    );
    output_policy.insert(
        "strip_html".to_string(),
        Value::Bool(object_bool(resource_policy, "strip_html")?),
    );
    output_policy.insert(
        "classify_output".to_string(),
        Value::Bool(object_bool(resource_policy, "classify_output")?),
    );

    let mut constraints = serde_json::Map::new();
    constraints.insert(
        "verb_class".to_string(),
        Value::String(object_string(witness_constraints, "verb_class")?),
    );
    constraints.insert(
        "rows_max".to_string(),
        Value::Number(
            object_u64(witness_constraints, "rows_max")?
                .min(object_u64(resource_policy, "rows_max")?)
                .into(),
        ),
    );
    constraints.insert(
        "max_bytes".to_string(),
        Value::Number(
            object_u64(witness_constraints, "max_bytes")?
                .min(object_u64(resource_policy, "max_bytes")?)
                .into(),
        ),
    );
    constraints.insert(
        "rate_per_min".to_string(),
        Value::Number(
            object_u64(witness_constraints, "rate_per_min")?
                .min(object_u64(resource_policy, "rate_per_min")?)
                .into(),
        ),
    );
    constraints.insert(
        "single_use".to_string(),
        Value::Bool(
            object_bool(witness_constraints, "single_use")?
                || object_bool(resource_policy, "require_single_use")?,
        ),
    );
    constraints.insert(
        "human_review_required".to_string(),
        Value::Bool(
            object_bool(witness_constraints, "human_review_required")?
                || object_bool(resource_policy, "human_review_required")?,
        ),
    );
    constraints.insert(
        "max_secret_materializations".to_string(),
        Value::Number(
            object_u64(witness_constraints, "max_secret_materializations")?
                .min(object_u64(resource_policy, "max_secret_materializations")?)
                .into(),
        ),
    );

    Ok(EffectiveAuthority {
        tool: policy_input.witness.tool()?,
        resource: policy_input.witness.resource()?,
        conf_label: policy_input.witness.conf_label()?,
        integ_label: Value::Object(integ_label),
        ttl_s: policy_input
            .witness
            .ttl_s()?
            .min(object_u64(resource_policy, "max_ttl_s")?),
        egress_policy: Value::Object(egress_policy),
        output_policy: Value::Object(output_policy),
        approval_mode: object_string(resource_policy, "required_approval_mode")?,
        constraints: Value::Object(constraints),
    })
}

fn value_object<'a>(
    value: &'a Value,
    context: &str,
) -> Result<&'a serde_json::Map<String, Value>, String> {
    value
        .as_object()
        .ok_or_else(|| format!("{context} must be a JSON object"))
}

fn object_string(object: &serde_json::Map<String, Value>, key: &str) -> Result<String, String> {
    object
        .get(key)
        .ok_or_else(|| format!("missing required field `{key}`"))?
        .as_str()
        .map(ToOwned::to_owned)
        .ok_or_else(|| format!("field `{key}` must be a string"))
}

fn object_u64(object: &serde_json::Map<String, Value>, key: &str) -> Result<u64, String> {
    object
        .get(key)
        .ok_or_else(|| format!("missing required field `{key}`"))?
        .as_u64()
        .ok_or_else(|| format!("field `{key}` must be an unsigned integer"))
}

fn object_bool(object: &serde_json::Map<String, Value>, key: &str) -> Result<bool, String> {
    object
        .get(key)
        .ok_or_else(|| format!("missing required field `{key}`"))?
        .as_bool()
        .ok_or_else(|| format!("field `{key}` must be a boolean"))
}

fn object_array(object: &serde_json::Map<String, Value>, key: &str) -> Result<Vec<Value>, String> {
    object
        .get(key)
        .ok_or_else(|| format!("missing required field `{key}`"))?
        .as_array()
        .cloned()
        .ok_or_else(|| format!("field `{key}` must be an array"))
}

fn push_if_false(reasons: &mut Vec<String>, value: bool, reason: &str) {
    if !value {
        reasons.push(reason.to_string());
    }
}

fn push_if_true(reasons: &mut Vec<String>, value: bool, reason: &str) {
    if value {
        reasons.push(reason.to_string());
    }
}

fn decision_status(decision: &Decision) -> StatusCode {
    if decision.burn {
        StatusCode::CONFLICT
    } else {
        StatusCode::OK
    }
}

async fn authorize_handler(
    State(state): State<LocalApiState>,
    payload: Result<Json<AuthorizeRequest>, JsonRejection>,
) -> Result<impl IntoResponse, (StatusCode, String)> {
    let Json(request) = payload.map_err(|err| (StatusCode::BAD_REQUEST, err.body_text()))?;
    let outcome = state
        .authorize(request)
        .map_err(|err| (StatusCode::BAD_REQUEST, err))?;

    Ok((decision_status(&outcome.decision), Json(outcome.decision)))
}

async fn mode_state_handler(
    State(state): State<LocalApiState>,
) -> Result<Json<ModeState>, (StatusCode, String)> {
    Ok(Json(
        state
            .mode_state()
            .map_err(|err| (StatusCode::INTERNAL_SERVER_ERROR, err))?,
    ))
}

async fn burn_handler(
    State(state): State<LocalApiState>,
    payload: Result<Json<ModeCommand>, JsonRejection>,
) -> Result<impl IntoResponse, (StatusCode, String)> {
    let Json(command) = payload.map_err(|err| (StatusCode::BAD_REQUEST, err.body_text()))?;
    let mode_state = state
        .burn(command)
        .map_err(|err| (StatusCode::BAD_REQUEST, err))?;

    Ok((StatusCode::ACCEPTED, Json(mode_state)))
}

async fn restore_handler(
    State(state): State<LocalApiState>,
    payload: Result<Json<ModeCommand>, JsonRejection>,
) -> Result<impl IntoResponse, (StatusCode, String)> {
    let Json(command) = payload.map_err(|err| (StatusCode::BAD_REQUEST, err.body_text()))?;
    let mode_state = state
        .restore(command)
        .map_err(|err| (StatusCode::BAD_REQUEST, err))?;

    Ok((StatusCode::ACCEPTED, Json(mode_state)))
}

fn validate_mode_command(command: &ModeCommand, expected_operation: &str) -> Result<(), String> {
    if command.version != "0.2" {
        return Err(format!(
            "mode command version must be `0.2`, got `{}`",
            command.version
        ));
    }
    if command.operation != expected_operation {
        return Err(format!(
            "mode command operation `{}` does not match endpoint `{expected_operation}`",
            command.operation
        ));
    }
    if command.approval_mode != "dual" {
        return Err(format!(
            "mode command approval_mode must be `dual`, got `{}`",
            command.approval_mode
        ));
    }
    if command.approval_evidence.approvers.len() < command.approval_evidence.quorum as usize {
        return Err(format!(
            "mode command quorum {} exceeds provided approvers {}",
            command.approval_evidence.quorum,
            command.approval_evidence.approvers.len()
        ));
    }
    Ok(())
}

fn command_updated_at(command: &ModeCommand) -> Result<String, String> {
    command
        .approval_evidence
        .approvers
        .iter()
        .map(|approver| approver.approved_at.as_str())
        .max()
        .map(ToOwned::to_owned)
        .ok_or_else(|| "mode command must include at least one approver".to_string())
}

fn forced_burn_decision(policy_input: &PolicyInput, reason_code: &str) -> Result<Decision, String> {
    Ok(Decision {
        effect: "burn".to_string(),
        allow: false,
        burn: true,
        trace: Some(policy_input.witness.trace()?),
        jti: Some(policy_input.witness.jti()?),
        deny_reasons: Vec::new(),
        burn_reasons: vec![reason_code.to_ascii_uppercase()],
        effective_authority: Some(effective_authority_from_policy_input(policy_input)?),
    })
}

pub fn canonical_json_bytes<T>(value: &T) -> Result<Vec<u8>, String>
where
    T: Serialize,
{
    let value = serde_json::to_value(value)
        .map_err(|err| format!("failed to convert value into canonical JSON: {err}"))?;
    Ok(canonicalize_value(&value).into_bytes())
}

pub fn sha256_hex<T>(value: &T) -> Result<String, String>
where
    T: Serialize,
{
    let bytes = canonical_json_bytes(value)?;
    let digest = Sha256::digest(bytes);
    Ok(hex_digest(&digest))
}

fn compute_cross_domain(call: &Call) -> bool {
    if let Some(explicit) = call.cross_domain {
        return explicit;
    }

    call.destination_domain
        .as_ref()
        .map(|destination| destination != &call.source_domain)
        .unwrap_or(false)
}

fn canonicalize_value(value: &Value) -> String {
    let mut out = String::new();
    write_canonical_value(value, &mut out);
    out
}

fn write_canonical_value(value: &Value, out: &mut String) {
    match value {
        Value::Null => out.push_str("null"),
        Value::Bool(boolean) => out.push_str(if *boolean { "true" } else { "false" }),
        Value::Number(number) => out.push_str(&number.to_string()),
        Value::String(string) => {
            let encoded = serde_json::to_string(string).expect("serialize canonical string");
            out.push_str(&encoded);
        }
        Value::Array(items) => {
            out.push('[');
            for (index, item) in items.iter().enumerate() {
                if index > 0 {
                    out.push(',');
                }
                write_canonical_value(item, out);
            }
            out.push(']');
        }
        Value::Object(map) => {
            out.push('{');
            let mut keys = map.keys().collect::<Vec<_>>();
            keys.sort();
            for (index, key) in keys.iter().enumerate() {
                if index > 0 {
                    out.push(',');
                }
                let encoded = serde_json::to_string(key).expect("serialize canonical object key");
                out.push_str(&encoded);
                out.push(':');
                write_canonical_value(&map[*key], out);
            }
            out.push('}');
        }
    }
}

fn hex_digest(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        let _ = write!(out, "{byte:02x}");
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const AUTHORIZE_REQUEST_ACCEPT: &str = include_str!(
        "../../../design/adjuncts/bridge-adapter/examples/example.authorize-request.json"
    );
    const PROVIDER_RESULTS_ACCEPT: &str = include_str!(
        "../../../design/adjuncts/bridge-adapter/examples/example.provider-results.accept.json"
    );
    const PROVIDER_RESULTS_BURN: &str = include_str!(
        "../../../design/adjuncts/bridge-adapter/examples/example.provider-results.burn.json"
    );
    const GENERATED_POLICY_INPUT: &str = include_str!(
        "../../../design/adjuncts/bridge-adapter/examples/generated.policy-input.json"
    );
    const GENERATED_AUDIT_RECORD: &str = include_str!(
        "../../../design/adjuncts/bridge-adapter/examples/generated.audit-record.json"
    );
    const DECISION_ACCEPT: &str = include_str!(
        "../../../design/adjuncts/bridge-adapter/examples/example.decision.accept.json"
    );
    const DECISION_BURN: &str =
        include_str!("../../../design/adjuncts/bridge-adapter/examples/example.decision.burn.json");
    const MODE_COMMAND_BURN: &str = include_str!(
        "../../../design/adjuncts/bridge-adapter/examples/example.mode-command.burn.json"
    );
    const POLICY_INPUT_BURN: &str = include_str!(
        "../../../design/adjuncts/bridge-adapter/examples/example.policy-input.burn.json"
    );
    const MODE_STATE: &str =
        include_str!("../../../design/adjuncts/bridge-adapter/examples/example.mode-state.json");

    #[test]
    fn accept_fixture_matches_generated_policy_input() {
        let request: AuthorizeRequest = serde_json::from_str(AUTHORIZE_REQUEST_ACCEPT).unwrap();
        let provider_results: ProviderResults =
            serde_json::from_str(PROVIDER_RESULTS_ACCEPT).unwrap();
        let assembled = assemble(request, provider_results).unwrap();

        let actual = serde_json::to_value(assembled).unwrap();
        let expected: Value = serde_json::from_str(GENERATED_POLICY_INPUT).unwrap();

        assert_eq!(actual, expected);
    }

    #[test]
    fn burn_fixture_matches_expected_policy_input() {
        let request: AuthorizeRequest = serde_json::from_str(AUTHORIZE_REQUEST_ACCEPT).unwrap();
        let provider_results: ProviderResults =
            serde_json::from_str(PROVIDER_RESULTS_BURN).unwrap();
        let assembled = assemble(request, provider_results).unwrap();

        let actual = serde_json::to_value(assembled).unwrap();
        let expected: Value = serde_json::from_str(POLICY_INPUT_BURN).unwrap();

        assert_eq!(actual, expected);
    }

    #[test]
    fn accept_fixture_matches_generated_audit_stub() {
        let request: AuthorizeRequest = serde_json::from_str(AUTHORIZE_REQUEST_ACCEPT).unwrap();
        let provider_results: ProviderResults =
            serde_json::from_str(PROVIDER_RESULTS_ACCEPT).unwrap();
        let assembled = assemble(request, provider_results).unwrap();
        let audit = audit_stub(&assembled, "time-authority://core/ntp-primary").unwrap();

        let actual = serde_json::to_value(audit).unwrap();
        let expected: Value = serde_json::from_str(GENERATED_AUDIT_RECORD).unwrap();

        assert_eq!(actual, expected);
    }

    #[test]
    fn accept_decision_matches_expected_contract() {
        let request: AuthorizeRequest = serde_json::from_str(AUTHORIZE_REQUEST_ACCEPT).unwrap();
        let provider_results: ProviderResults =
            serde_json::from_str(PROVIDER_RESULTS_ACCEPT).unwrap();
        let mode_state: ModeState = serde_json::from_str(MODE_STATE).unwrap();
        let outcome = authorize_with_state(
            request,
            &provider_results,
            &mode_state,
            None,
            "time-authority://core/ntp-primary",
        )
        .unwrap();

        let actual = serde_json::to_value(outcome.decision).unwrap();
        let expected: Value = serde_json::from_str(DECISION_ACCEPT).unwrap();

        assert_eq!(actual, expected);
    }

    #[test]
    fn burn_fixture_yields_burn_effect() {
        let request: AuthorizeRequest = serde_json::from_str(AUTHORIZE_REQUEST_ACCEPT).unwrap();
        let provider_results: ProviderResults =
            serde_json::from_str(PROVIDER_RESULTS_BURN).unwrap();
        let mode_state: ModeState = serde_json::from_str(MODE_STATE).unwrap();
        let outcome = authorize_with_state(
            request,
            &provider_results,
            &mode_state,
            None,
            "time-authority://core/ntp-primary",
        )
        .unwrap();

        let actual = serde_json::to_value(outcome.decision).unwrap();
        let expected: Value = serde_json::from_str(DECISION_BURN).unwrap();

        assert_eq!(actual, expected);
    }

    #[tokio::test]
    async fn router_authorize_returns_expected_accept_decision() {
        use axum::body::{Body, to_bytes};
        use axum::http::{Request, StatusCode};
        use tower::util::ServiceExt as _;

        let provider_results: ProviderResults =
            serde_json::from_str(PROVIDER_RESULTS_ACCEPT).unwrap();
        let mode_state: ModeState = serde_json::from_str(MODE_STATE).unwrap();
        let state = LocalApiState::new(
            provider_results,
            mode_state,
            "time-authority://core/ntp-primary".to_string(),
        );
        let app = build_router(state);

        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/v1/authorize")
                    .header("content-type", "application/json")
                    .body(Body::from(AUTHORIZE_REQUEST_ACCEPT))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        let actual: Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(actual["effect"], "accept");
        assert_eq!(actual["allow"], true);
        assert_eq!(actual["burn"], false);
    }

    #[tokio::test]
    async fn router_mode_state_returns_fixture_contract() {
        use axum::body::{Body, to_bytes};
        use axum::http::{Request, StatusCode};
        use tower::util::ServiceExt as _;

        let provider_results: ProviderResults =
            serde_json::from_str(PROVIDER_RESULTS_ACCEPT).unwrap();
        let mode_state: ModeState = serde_json::from_str(MODE_STATE).unwrap();
        let expected = serde_json::to_value(&mode_state).unwrap();
        let state = LocalApiState::new(
            provider_results,
            mode_state,
            "time-authority://core/ntp-primary".to_string(),
        );
        let app = build_router(state);

        let response = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/v1/state/mode")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        let actual: Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(actual, expected);
    }

    #[tokio::test]
    async fn router_authorize_maps_burn_decision_to_conflict() {
        use axum::body::Body;
        use axum::http::{Request, StatusCode};
        use tower::util::ServiceExt as _;

        let provider_results: ProviderResults =
            serde_json::from_str(PROVIDER_RESULTS_BURN).unwrap();
        let mode_state: ModeState = serde_json::from_str(MODE_STATE).unwrap();
        let state = LocalApiState::new(
            provider_results,
            mode_state,
            "time-authority://core/ntp-primary".to_string(),
        );
        let app = build_router(state);

        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/v1/authorize")
                    .header("content-type", "application/json")
                    .body(Body::from(AUTHORIZE_REQUEST_ACCEPT))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::CONFLICT);
    }

    #[test]
    fn burn_command_updates_mode_state() {
        let provider_results: ProviderResults =
            serde_json::from_str(PROVIDER_RESULTS_ACCEPT).unwrap();
        let mode_state: ModeState = serde_json::from_str(MODE_STATE).unwrap();
        let command: ModeCommand = serde_json::from_str(MODE_COMMAND_BURN).unwrap();
        let state = LocalApiState::new(
            provider_results,
            mode_state,
            "time-authority://core/ntp-primary".to_string(),
        );

        let updated = state.burn(command).unwrap();

        assert_eq!(updated.current_mode, "safe");
        assert_eq!(
            updated.last_command_id.as_deref(),
            Some("cmd-burn-2026-04-11-0001")
        );
        assert_eq!(
            updated.cut_set,
            vec![
                "domain:acme.prod.analytics".to_string(),
                "issuer:bridge-issuer-2026-q2".to_string()
            ]
        );
        assert_eq!(updated.updated_at, "2026-04-11T14:01:10Z");
    }

    #[tokio::test]
    async fn router_burn_then_restore_updates_mode_and_authorize_behavior() {
        use axum::body::{Body, to_bytes};
        use axum::http::{Request, StatusCode};
        use tower::util::ServiceExt as _;

        let provider_results: ProviderResults =
            serde_json::from_str(PROVIDER_RESULTS_ACCEPT).unwrap();
        let mode_state: ModeState = serde_json::from_str(MODE_STATE).unwrap();
        let burn_command: ModeCommand = serde_json::from_str(MODE_COMMAND_BURN).unwrap();
        let restore_command = ModeCommand {
            operation: "restore".to_string(),
            command_id: "cmd-restore-2026-04-12-0001".to_string(),
            trace: "trace-restore-2026-04-12-0001".to_string(),
            requested_by: "user:security-operator@example.com".to_string(),
            reason_code: "RESTORE_AUTHORIZED".to_string(),
            cut_set: Vec::new(),
            approval_mode: "dual".to_string(),
            approval_evidence: burn_command.approval_evidence.clone(),
            ticket: Some("INC-2026-0411-17".to_string()),
            version: "0.2".to_string(),
        };
        let state = LocalApiState::new(
            provider_results,
            mode_state,
            "time-authority://core/ntp-primary".to_string(),
        );
        let app = build_router(state);

        let burn_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/v1/admin/burn")
                    .header("content-type", "application/json")
                    .body(Body::from(serde_json::to_vec(&burn_command).unwrap()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(burn_response.status(), StatusCode::ACCEPTED);

        let authorize_after_burn = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/v1/authorize")
                    .header("content-type", "application/json")
                    .body(Body::from(AUTHORIZE_REQUEST_ACCEPT))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(authorize_after_burn.status(), StatusCode::CONFLICT);
        let authorize_after_burn_body = to_bytes(authorize_after_burn.into_body(), usize::MAX)
            .await
            .unwrap();
        let authorize_after_burn_json: Value =
            serde_json::from_slice(&authorize_after_burn_body).unwrap();
        assert_eq!(
            authorize_after_burn_json["burn_reasons"],
            serde_json::json!(["AUDIT_TAMPER_DETECTED"])
        );

        let mode_after_burn = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/v1/state/mode")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let mode_after_burn_body = to_bytes(mode_after_burn.into_body(), usize::MAX)
            .await
            .unwrap();
        let mode_after_burn_json: Value = serde_json::from_slice(&mode_after_burn_body).unwrap();
        assert_eq!(mode_after_burn_json["current_mode"], "safe");

        let restore_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/v1/admin/restore")
                    .header("content-type", "application/json")
                    .body(Body::from(serde_json::to_vec(&restore_command).unwrap()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(restore_response.status(), StatusCode::ACCEPTED);

        let mode_after_restore = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/v1/state/mode")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let mode_after_restore_body = to_bytes(mode_after_restore.into_body(), usize::MAX)
            .await
            .unwrap();
        let mode_after_restore_json: Value =
            serde_json::from_slice(&mode_after_restore_body).unwrap();
        assert_eq!(mode_after_restore_json["current_mode"], "normal");
        assert_eq!(mode_after_restore_json["cut_set"], serde_json::json!([]));

        let authorize_after_restore = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/v1/authorize")
                    .header("content-type", "application/json")
                    .body(Body::from(AUTHORIZE_REQUEST_ACCEPT))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(authorize_after_restore.status(), StatusCode::OK);
    }
}
