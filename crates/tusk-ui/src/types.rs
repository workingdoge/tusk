use serde::Deserialize;
use serde_json::Value;

#[derive(Debug, Deserialize)]
pub(crate) struct Response<T> {
    pub(crate) ok: bool,
    pub(crate) payload: Option<T>,
    pub(crate) error: Option<ProtocolError>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct ProtocolError {
    pub(crate) message: String,
}

#[derive(Debug, Deserialize)]
pub(crate) struct ClaimIssuePayload {
    pub(crate) issue_id: String,
}

#[derive(Debug, Deserialize)]
pub(crate) struct LaunchLanePayload {
    pub(crate) issue_id: String,
    pub(crate) workspace_name: String,
    pub(crate) base_rev: String,
}

#[derive(Debug, Deserialize)]
pub(crate) struct FinishLanePayload {
    pub(crate) issue_id: String,
    pub(crate) outcome: String,
}

#[derive(Debug, Deserialize)]
pub(crate) struct TrackerStatus {
    pub(crate) repo_root: String,
    pub(crate) protocol: TrackerProtocol,
    pub(crate) tuskd: TuskdState,
    pub(crate) health: HealthStatus,
    #[serde(default)]
    pub(crate) active_leases: Vec<Value>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct TrackerProtocol {
    pub(crate) endpoint: String,
}

#[derive(Debug, Deserialize)]
pub(crate) struct TuskdState {
    pub(crate) mode: String,
    pub(crate) pid: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct HealthStatus {
    pub(crate) status: String,
    pub(crate) checked_at: String,
    pub(crate) backend: Option<BackendStatus>,
    pub(crate) summary: Option<BoardSummary>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct BackendStatus {
    pub(crate) running: Option<bool>,
    pub(crate) pid: Option<i64>,
    pub(crate) port: Option<i64>,
    pub(crate) data_dir: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct BoardStatus {
    pub(crate) repo_root: String,
    pub(crate) generated_at: String,
    pub(crate) summary: Option<BoardSummary>,
    #[serde(default)]
    pub(crate) ready_issues: Vec<BoardIssue>,
    #[serde(default)]
    pub(crate) claimed_issues: Vec<BoardIssue>,
    #[serde(default)]
    pub(crate) blocked_issues: Vec<BoardIssue>,
    #[serde(default)]
    pub(crate) deferred_issues: Vec<BoardIssue>,
    #[serde(default)]
    pub(crate) lanes: Vec<LaneEntry>,
    #[serde(default)]
    pub(crate) workspaces: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct BoardSummary {
    pub(crate) total_issues: Option<u64>,
    pub(crate) open_issues: Option<u64>,
    pub(crate) in_progress_issues: Option<u64>,
    pub(crate) closed_issues: Option<u64>,
    pub(crate) blocked_issues: Option<u64>,
    pub(crate) deferred_issues: Option<u64>,
    pub(crate) ready_issues: Option<u64>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct BoardIssue {
    pub(crate) id: String,
    pub(crate) title: String,
    pub(crate) status: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct LaneEntry {
    pub(crate) issue_id: String,
    pub(crate) issue_title: String,
    pub(crate) status: String,
    pub(crate) observed_status: Option<String>,
    pub(crate) workspace_exists: Option<bool>,
    pub(crate) outcome: Option<String>,
    pub(crate) workspace_name: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct ReceiptsStatus {
    pub(crate) repo_root: String,
    pub(crate) generated_at: String,
    pub(crate) receipts_path: String,
    #[serde(default)]
    pub(crate) receipts: Vec<ReceiptEntry>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct ReceiptEntry {
    pub(crate) timestamp: Option<String>,
    pub(crate) kind: Option<String>,
    pub(crate) payload: Option<Value>,
    pub(crate) invalid_line: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct PingStatus {
    pub(crate) timestamp: String,
}

#[derive(Debug, Deserialize)]
pub(crate) struct OperatorSnapshot {
    pub(crate) generated_at: String,
    pub(crate) briefing: OperatorBriefing,
    pub(crate) now: OperatorNow,
    pub(crate) next: OperatorNext,
    pub(crate) history: OperatorHistory,
    pub(crate) context: OperatorContext,
}

#[derive(Debug, Deserialize)]
pub(crate) struct OperatorBriefing {
    pub(crate) headline: String,
    pub(crate) summary: String,
    pub(crate) focus_issue: Option<OperatorFocusIssue>,
    #[serde(default)]
    pub(crate) narrative: Vec<String>,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub(crate) struct OperatorFocusIssue {
    pub(crate) id: String,
    pub(crate) title: String,
    pub(crate) status: Option<String>,
    pub(crate) parent: Option<String>,
    pub(crate) dependency_count: Option<u64>,
    pub(crate) dependent_count: Option<u64>,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub(crate) struct OperatorNow {
    pub(crate) runtime: OperatorRuntime,
    #[serde(default)]
    pub(crate) active_lanes: Vec<OperatorLane>,
    #[serde(default)]
    pub(crate) claimed_issues: Vec<BoardIssue>,
    #[serde(default)]
    pub(crate) stale_lanes: Vec<OperatorLane>,
    #[serde(default)]
    pub(crate) obstructions: Vec<OperatorObstruction>,
    pub(crate) counts: OperatorNowCounts,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub(crate) struct OperatorRuntime {
    pub(crate) health: Option<String>,
    pub(crate) mode: Option<String>,
    pub(crate) pid: Option<i64>,
    pub(crate) backend: Option<OperatorBackend>,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub(crate) struct OperatorBackend {
    pub(crate) running: Option<bool>,
    pub(crate) pid: Option<i64>,
    pub(crate) port: Option<i64>,
    pub(crate) data_dir: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct OperatorLane {
    pub(crate) issue_id: String,
    pub(crate) issue_title: Option<String>,
    pub(crate) status: Option<String>,
    pub(crate) observed_status: Option<String>,
    pub(crate) workspace_name: Option<String>,
    pub(crate) workspace_exists: Option<bool>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct OperatorObstruction {
    pub(crate) kind: String,
    pub(crate) message: String,
    pub(crate) issue_id: Option<String>,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub(crate) struct OperatorNowCounts {
    pub(crate) active_lanes: u64,
    pub(crate) claimed_issues: u64,
    pub(crate) stale_lanes: u64,
    pub(crate) obstructions: u64,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub(crate) struct OperatorNext {
    pub(crate) primary_action: Option<OperatorRecommendation>,
    #[serde(default)]
    pub(crate) ready_issues: Vec<BoardIssue>,
    #[serde(default)]
    pub(crate) blocked_issues: Vec<BoardIssue>,
    #[serde(default)]
    pub(crate) deferred_issues: Vec<BoardIssue>,
    #[serde(default)]
    pub(crate) recommended_actions: Vec<OperatorRecommendation>,
    pub(crate) counts: OperatorNextCounts,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub(crate) struct OperatorRecommendation {
    pub(crate) kind: String,
    pub(crate) message: String,
    pub(crate) issue_id: Option<String>,
    pub(crate) title: Option<String>,
    pub(crate) status: Option<String>,
    pub(crate) command: Option<String>,
    #[serde(default)]
    pub(crate) rationale: Vec<String>,
    #[serde(default)]
    pub(crate) dependencies: Vec<OperatorIssueRef>,
    #[serde(default)]
    pub(crate) dependents: Vec<OperatorIssueRef>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct OperatorIssueRef {
    pub(crate) id: String,
    pub(crate) title: Option<String>,
    pub(crate) status: Option<String>,
    pub(crate) dependency_type: Option<String>,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub(crate) struct OperatorNextCounts {
    pub(crate) ready_issues: u64,
    pub(crate) blocked_issues: u64,
    pub(crate) deferred_issues: u64,
    pub(crate) recommended_actions: u64,
}

#[derive(Debug, Deserialize)]
pub(crate) struct OperatorHistory {
    #[serde(default)]
    pub(crate) recent_transitions: Vec<OperatorReceipt>,
    #[serde(default)]
    pub(crate) narrative: Vec<String>,
    pub(crate) counts: OperatorHistoryCounts,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub(crate) struct OperatorReceipt {
    pub(crate) timestamp: Option<String>,
    pub(crate) kind: Option<String>,
    pub(crate) issue_id: Option<String>,
    pub(crate) details: Option<Value>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct OperatorHistoryCounts {
    pub(crate) recent_transitions: u64,
    pub(crate) available_receipts: u64,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub(crate) struct OperatorContext {
    pub(crate) repo_root: String,
    pub(crate) checkout_root: String,
    pub(crate) tracker_root: String,
    pub(crate) protocol: TrackerProtocol,
    pub(crate) service: TuskdState,
    pub(crate) backend_endpoint: Option<OperatorBackendEndpoint>,
    pub(crate) summary: Option<BoardSummary>,
    #[serde(default)]
    pub(crate) workspaces: Vec<WorkspaceEntry>,
    pub(crate) counts: OperatorContextCounts,
}

#[derive(Debug, Deserialize)]
pub(crate) struct OperatorBackendEndpoint {
    pub(crate) host: Option<String>,
    pub(crate) port: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct WorkspaceEntry {
    pub(crate) name: String,
    pub(crate) change_id: Option<String>,
    pub(crate) commit_id: Option<String>,
    pub(crate) empty: bool,
    pub(crate) description: Option<String>,
    pub(crate) raw: String,
}

#[derive(Debug, Deserialize)]
pub(crate) struct OperatorContextCounts {
    pub(crate) workspaces: u64,
}

#[derive(Debug, Deserialize)]
pub(crate) struct IssueInspection {
    pub(crate) repo_root: String,
    pub(crate) issue: InspectedIssue,
    #[serde(default)]
    pub(crate) dependencies: Vec<OperatorIssueRef>,
    #[serde(default)]
    pub(crate) dependents: Vec<OperatorIssueRef>,
    pub(crate) lane: Option<InspectLane>,
    #[serde(default)]
    pub(crate) recent_receipts: Vec<OperatorReceipt>,
    pub(crate) available_receipts: Option<u64>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct InspectedIssue {
    pub(crate) id: String,
    pub(crate) title: String,
    pub(crate) status: Option<String>,
    pub(crate) priority: Option<String>,
    pub(crate) issue_type: Option<String>,
    pub(crate) parent: Option<String>,
    pub(crate) dependency_count: Option<u64>,
    pub(crate) dependent_count: Option<u64>,
    pub(crate) created_at: Option<String>,
    pub(crate) updated_at: Option<String>,
    pub(crate) closed_at: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct InspectLane {
    pub(crate) issue_id: String,
    pub(crate) issue_title: Option<String>,
    pub(crate) status: String,
    pub(crate) observed_status: Option<String>,
    pub(crate) workspace_path: Option<String>,
    pub(crate) workspace_name: Option<String>,
    pub(crate) workspace_exists: Option<bool>,
    pub(crate) base_rev: Option<String>,
    pub(crate) revision: Option<String>,
    pub(crate) outcome: Option<String>,
    pub(crate) note: Option<String>,
    pub(crate) created_at: Option<String>,
    pub(crate) updated_at: Option<String>,
    pub(crate) handoff_at: Option<String>,
    pub(crate) finished_at: Option<String>,
}

#[cfg(test)]
pub(crate) const GOLDEN_OPERATOR_SNAPSHOT_FIXTURE_JSON: &str =
    crate::fixtures::GOLDEN_OPERATOR_SNAPSHOT_FIXTURE_JSON;

#[cfg(test)]
pub(crate) const GOLDEN_ISSUE_INSPECTION_FIXTURE_JSON: &str =
    crate::fixtures::GOLDEN_ISSUE_INSPECTION_FIXTURE_JSON;

#[cfg(test)]
pub(crate) fn golden_operator_snapshot() -> OperatorSnapshot {
    serde_json::from_str(GOLDEN_OPERATOR_SNAPSHOT_FIXTURE_JSON)
        .expect("golden operator snapshot fixture should deserialize")
}

#[cfg(test)]
pub(crate) fn sample_operator_snapshot() -> OperatorSnapshot {
    golden_operator_snapshot()
}

#[cfg(test)]
pub(crate) fn golden_issue_inspection() -> IssueInspection {
    serde_json::from_str(GOLDEN_ISSUE_INSPECTION_FIXTURE_JSON)
        .expect("golden issue inspection fixture should deserialize")
}

#[cfg(test)]
mod tests {
    use super::{
        GOLDEN_ISSUE_INSPECTION_FIXTURE_JSON, GOLDEN_OPERATOR_SNAPSHOT_FIXTURE_JSON,
        IssueInspection, OperatorSnapshot,
    };

    #[test]
    fn operator_snapshot_fixture_deserializes() {
        let snapshot: OperatorSnapshot =
            serde_json::from_str(GOLDEN_OPERATOR_SNAPSHOT_FIXTURE_JSON)
                .expect("fixture should deserialize");

        assert_eq!(snapshot.briefing.headline, "Launch tusk-ready next.");
        assert_eq!(
            snapshot
                .next
                .primary_action
                .as_ref()
                .and_then(|action| action.issue_id.as_deref()),
            Some("tusk-ready")
        );
        assert_eq!(
            snapshot.history.narrative.first().map(String::as_str),
            Some("1m ago: claimed tusk-ready")
        );
    }

    #[test]
    fn issue_inspection_fixture_deserializes() {
        let inspection: IssueInspection =
            serde_json::from_str(GOLDEN_ISSUE_INSPECTION_FIXTURE_JSON)
                .expect("fixture should deserialize");

        assert_eq!(inspection.issue.id, "tusk-ready");
        assert_eq!(inspection.dependencies.len(), 1);
        assert_eq!(inspection.dependents.len(), 1);
        assert_eq!(
            inspection
                .lane
                .as_ref()
                .and_then(|lane| lane.base_rev.as_deref()),
            Some("main")
        );
    }
}
