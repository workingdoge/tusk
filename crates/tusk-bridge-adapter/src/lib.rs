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
pub struct LocalApiState {
    provider_results: ProviderResults,
    mode_state: ModeState,
    authoritative_time_source: String,
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
    pub fn from_files(
        provider_results_path: &Path,
        mode_state_path: &Path,
        authoritative_time_source: String,
    ) -> Result<Self, String> {
        Ok(Self {
            provider_results: load_json_file(provider_results_path)?,
            mode_state: load_json_file(mode_state_path)?,
            authoritative_time_source,
        })
    }

    pub fn mode_state(&self) -> &ModeState {
        &self.mode_state
    }

    pub fn authorize(&self, request: AuthorizeRequest) -> Result<AuthorizeOutcome, String> {
        authorize_with_state(
            request,
            &self.provider_results,
            &self.mode_state,
            &self.authoritative_time_source,
        )
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
    authoritative_time_source: &str,
) -> Result<AuthorizeOutcome, String> {
    let mut synchronized_provider_results = provider_results.clone();
    synchronized_provider_results.runtime.current_mode = mode_state.current_mode.clone();

    let policy_input = assemble(authorize_request, synchronized_provider_results)?;
    let decision = decision_for_policy_input(&policy_input)?;
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
        burn_reasons.push("current_mode_burn".to_string());
    }
    push_if_true(
        &mut burn_reasons,
        policy_input.events.bridge_host_attestation_failed,
        "bridge_host_attestation_failed",
    );
    push_if_true(
        &mut burn_reasons,
        policy_input.events.issuer_compromise_detected,
        "issuer_compromise_detected",
    );
    push_if_true(
        &mut burn_reasons,
        policy_input.events.audit_tamper_detected,
        "audit_tamper_detected",
    );
    push_if_true(
        &mut burn_reasons,
        policy_input.events.canary_or_honey_credential_activated,
        "canary_or_honey_credential_activated",
    );
    push_if_true(
        &mut burn_reasons,
        policy_input
            .events
            .controlled_release_policy_bypass_detected,
        "controlled_release_policy_bypass_detected",
    );
    push_if_true(
        &mut burn_reasons,
        policy_input.events.policy_hash_mismatch,
        "policy_hash_mismatch",
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
        effective_authority: if effect == "accept" {
            Some(effective_authority_from_witness(&policy_input.witness)?)
        } else {
            None
        },
    })
}

pub fn build_router(state: LocalApiState) -> Router {
    Router::new()
        .route("/v1/authorize", post(authorize_handler))
        .route("/v1/state/mode", get(mode_state_handler))
        .with_state(state)
}

fn effective_authority_from_witness(witness: &Witness) -> Result<EffectiveAuthority, String> {
    Ok(EffectiveAuthority {
        tool: witness.tool()?,
        resource: witness.resource()?,
        conf_label: witness.conf_label()?,
        integ_label: witness.integ_label()?,
        ttl_s: witness.ttl_s()?,
        egress_policy: witness.egress_policy()?,
        output_policy: witness.output_policy()?,
        approval_mode: witness.approval_mode()?,
        constraints: witness.constraints()?,
    })
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

async fn mode_state_handler(State(state): State<LocalApiState>) -> Json<ModeState> {
    Json(state.mode_state().clone())
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
            "time-authority://core/ntp-primary",
        )
        .unwrap();

        let actual = serde_json::to_value(outcome.decision).unwrap();
        let expected = serde_json::json!({
            "effect": "accept",
            "allow": true,
            "burn": false,
            "trace": "ca14e9e0-1c8c-40bd-bc53-5d01e4876de8",
            "jti": "464e6650-b1b0-41f9-89da-47b9b43e8c2b",
            "deny_reasons": [],
            "burn_reasons": [],
            "effective_authority": {
                "tool": "db.query.readonly",
                "resource": "postgres://analytics/reporting",
                "conf_label": {
                    "level": "restricted",
                    "compartments": ["finance"],
                    "tags": ["reporting"],
                    "marking": "internal-need-to-know"
                },
                "integ_label": {
                    "level": "attested",
                    "tags": ["signed", "measured-boot"]
                },
                "ttl_s": 120,
                "egress_policy": {
                    "mode": "allowlist",
                    "destinations": ["postgres://analytics/reporting"]
                },
                "output_policy": {
                    "redaction_profile": "finance-summary-v1",
                    "max_response_bytes": 65536,
                    "allow_secrets_in_output": false,
                    "return_to_model": true,
                    "strip_html": true,
                    "classify_output": true
                },
                "approval_mode": "none",
                "constraints": {
                    "verb_class": "read",
                    "single_use": true,
                    "rows_max": 5000,
                    "max_bytes": 1048576,
                    "rate_per_min": 10,
                    "human_review_required": false,
                    "max_secret_materializations": 1
                }
            }
        });

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
            "time-authority://core/ntp-primary",
        )
        .unwrap();

        assert_eq!(outcome.decision.effect, "burn");
        assert!(outcome.decision.burn);
        assert_eq!(outcome.decision.burn_reasons, vec!["audit_tamper_detected"]);
        assert_eq!(outcome.decision.effective_authority, None);
    }

    #[tokio::test]
    async fn router_authorize_returns_expected_accept_decision() {
        use axum::body::{Body, to_bytes};
        use axum::http::{Request, StatusCode};
        use tower::util::ServiceExt as _;

        let provider_results: ProviderResults =
            serde_json::from_str(PROVIDER_RESULTS_ACCEPT).unwrap();
        let mode_state: ModeState = serde_json::from_str(MODE_STATE).unwrap();
        let state = LocalApiState {
            provider_results,
            mode_state,
            authoritative_time_source: "time-authority://core/ntp-primary".to_string(),
        };
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
        let state = LocalApiState {
            provider_results,
            mode_state,
            authoritative_time_source: "time-authority://core/ntp-primary".to_string(),
        };
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
        let state = LocalApiState {
            provider_results,
            mode_state,
            authoritative_time_source: "time-authority://core/ntp-primary".to_string(),
        };
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
}
