use std::path::Path;

use crate::types::{
    BoardIssue, BoardStatus, BoardSummary, LaneEntry, OperatorContext, OperatorFocusIssue,
    OperatorHistory, OperatorIssueRef, OperatorLane, OperatorReceipt, OperatorRecommendation,
    OperatorSnapshot, ReceiptEntry, ReceiptsStatus, TrackerStatus, WorkspaceEntry,
};

#[allow(dead_code)]
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) enum Source {
    Authoritative,
    Heuristic,
    Enriched,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct IssueRef {
    pub(crate) id: String,
    pub(crate) title: Option<String>,
    pub(crate) status: Option<String>,
    pub(crate) dependency_type: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct FocusNarrative {
    pub(crate) issue_id: String,
    pub(crate) title: String,
    pub(crate) status: Option<String>,
    pub(crate) parent: Option<String>,
    pub(crate) blockers: Vec<IssueRef>,
    pub(crate) upstream: Vec<IssueRef>,
    pub(crate) unlocks: Vec<IssueRef>,
    pub(crate) dependents: Vec<IssueRef>,
    pub(crate) rationale: Vec<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct IssueItem {
    pub(crate) id: String,
    pub(crate) title: String,
    pub(crate) status: Option<String>,
    pub(crate) selected: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct LaneItem {
    pub(crate) issue_id: String,
    pub(crate) title: String,
    pub(crate) status: Option<String>,
    pub(crate) observed_status: Option<String>,
    pub(crate) workspace_name: Option<String>,
    pub(crate) workspace_exists: Option<bool>,
    pub(crate) outcome: Option<String>,
    pub(crate) selected: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct ObstructionItem {
    pub(crate) kind: String,
    pub(crate) message: String,
    pub(crate) issue_id: Option<String>,
    pub(crate) source: Source,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct ActionItem {
    pub(crate) kind: String,
    pub(crate) message: String,
    pub(crate) issue_id: Option<String>,
    pub(crate) title: Option<String>,
    pub(crate) command: Option<String>,
    pub(crate) narrative: Option<FocusNarrative>,
    pub(crate) source: Source,
    pub(crate) confidence: Option<String>,
    pub(crate) obstructions: Vec<String>,
    pub(crate) rationale: Vec<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct HistoryItem {
    pub(crate) timestamp: Option<String>,
    pub(crate) kind: String,
    pub(crate) issue_id: Option<String>,
    pub(crate) narrative: String,
    pub(crate) consequence: Option<String>,
    pub(crate) source: Source,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct WorkspaceItem {
    pub(crate) name: String,
    pub(crate) description: String,
    pub(crate) details: Vec<String>,
}

#[allow(dead_code)]
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) enum ContextAnomaly {
    RootMismatch { checkout: String, tracker: String },
    BackendUnhealthy { message: String },
    StaleWorkspaces { count: u64 },
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct ContextSummary {
    pub(crate) repo_name: String,
    pub(crate) mode: String,
    pub(crate) workspace_count: u64,
    pub(crate) repo_root: String,
    pub(crate) checkout_root: String,
    pub(crate) tracker_root: String,
    pub(crate) socket_path: String,
    pub(crate) backend: Option<String>,
    pub(crate) anomalies: Vec<ContextAnomaly>,
    pub(crate) summary: Option<SummaryView>,
    pub(crate) workspaces: Vec<WorkspaceItem>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct SummaryView {
    pub(crate) total: u64,
    pub(crate) open: u64,
    pub(crate) in_progress: u64,
    pub(crate) ready: u64,
    pub(crate) blocked: u64,
    pub(crate) deferred: u64,
    pub(crate) closed: u64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct BackendView {
    pub(crate) running: Option<bool>,
    pub(crate) pid: Option<i64>,
    pub(crate) port: Option<i64>,
    pub(crate) data_dir: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct HomeViewModel {
    pub(crate) headline: String,
    pub(crate) summary: String,
    pub(crate) updated_at: String,
    pub(crate) focus: Option<FocusNarrative>,
    pub(crate) active_lanes: Vec<LaneItem>,
    pub(crate) claimed: Vec<IssueItem>,
    pub(crate) stale: Vec<LaneItem>,
    pub(crate) obstructions: Vec<ObstructionItem>,
    pub(crate) primary_action: Option<ActionItem>,
    pub(crate) ready_queue: Vec<IssueItem>,
    pub(crate) blocked_queue: Vec<IssueItem>,
    pub(crate) deferred_queue: Vec<IssueItem>,
    pub(crate) history: Vec<HistoryItem>,
    pub(crate) recent_count: u64,
    pub(crate) available_receipts: u64,
    pub(crate) context: ContextSummary,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct TrackerViewModel {
    pub(crate) repo_root: String,
    pub(crate) socket_path: String,
    pub(crate) mode: String,
    pub(crate) pid: String,
    pub(crate) health: String,
    pub(crate) checked_at: String,
    pub(crate) lease_count: usize,
    pub(crate) summary: Option<SummaryView>,
    pub(crate) backend: Option<BackendView>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct BoardViewModel {
    pub(crate) repo_root: String,
    pub(crate) updated_at: String,
    pub(crate) summary: Option<SummaryView>,
    pub(crate) ready_issues: Vec<IssueItem>,
    pub(crate) claimed_issues: Vec<IssueItem>,
    pub(crate) blocked_issues: Vec<IssueItem>,
    pub(crate) deferred_issues: Vec<IssueItem>,
    pub(crate) active_lanes: Vec<LaneItem>,
    pub(crate) finished_lanes: Vec<LaneItem>,
    pub(crate) stale_lanes: Vec<LaneItem>,
    pub(crate) workspaces: Vec<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct ReceiptItem {
    pub(crate) label: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct ReceiptsViewModel {
    pub(crate) repo_root: String,
    pub(crate) updated_at: String,
    pub(crate) receipts_path: String,
    pub(crate) receipts: Vec<ReceiptItem>,
}

pub(crate) fn home_viewmodel(snapshot: &OperatorSnapshot) -> HomeViewModel {
    let focus = build_focus_narrative(
        snapshot.briefing.focus_issue.as_ref(),
        snapshot.next.primary_action.as_ref(),
        &snapshot.briefing.narrative,
    );

    HomeViewModel {
        headline: snapshot.briefing.headline.clone(),
        summary: snapshot.briefing.summary.clone(),
        updated_at: snapshot.generated_at.clone(),
        focus,
        active_lanes: snapshot
            .now
            .active_lanes
            .iter()
            .map(|lane| lane_item_from_operator_lane(lane, false))
            .collect(),
        claimed: snapshot
            .now
            .claimed_issues
            .iter()
            .map(|issue| issue_item(issue, false))
            .collect(),
        stale: snapshot
            .now
            .stale_lanes
            .iter()
            .map(|lane| lane_item_from_operator_lane(lane, false))
            .collect(),
        obstructions: snapshot
            .now
            .obstructions
            .iter()
            .map(|obstruction| ObstructionItem {
                kind: obstruction.kind.clone(),
                message: obstruction.message.clone(),
                issue_id: obstruction.issue_id.clone(),
                source: Source::Authoritative,
            })
            .collect(),
        primary_action: snapshot.next.primary_action.as_ref().map(action_item),
        ready_queue: snapshot
            .next
            .ready_issues
            .iter()
            .map(|issue| issue_item(issue, false))
            .collect(),
        blocked_queue: snapshot
            .next
            .blocked_issues
            .iter()
            .map(|issue| issue_item(issue, false))
            .collect(),
        deferred_queue: snapshot
            .next
            .deferred_issues
            .iter()
            .map(|issue| issue_item(issue, false))
            .collect(),
        history: history_items(&snapshot.history),
        recent_count: snapshot.history.counts.recent_transitions,
        available_receipts: snapshot.history.counts.available_receipts,
        context: context_summary(&snapshot.context),
    }
}

pub(crate) fn tracker_viewmodel(tracker: &TrackerStatus) -> TrackerViewModel {
    TrackerViewModel {
        repo_root: tracker.repo_root.clone(),
        socket_path: tracker.protocol.endpoint.clone(),
        mode: tracker.tuskd.mode.clone(),
        pid: tracker
            .tuskd
            .pid
            .map(|value| value.to_string())
            .unwrap_or_else(|| "none".to_owned()),
        health: tracker.health.status.clone(),
        checked_at: tracker.health.checked_at.clone(),
        lease_count: tracker.active_leases.len(),
        summary: tracker.health.summary.as_ref().map(summary_view),
        backend: tracker.health.backend.as_ref().map(|backend| BackendView {
            running: backend.running,
            pid: backend.pid,
            port: backend.port,
            data_dir: backend.data_dir.clone(),
        }),
    }
}

pub(crate) fn board_viewmodel(
    board: &BoardStatus,
    selected_board_item_id: Option<&str>,
) -> BoardViewModel {
    let mut active_lanes = Vec::new();
    let mut finished_lanes = Vec::new();
    let mut stale_lanes = Vec::new();

    let mut ordered = board.lanes.clone();
    ordered.sort_by(|left, right| left.issue_id.cmp(&right.issue_id));

    for lane in ordered {
        let selected = selected_board_item_id == Some(lane.issue_id.as_str());
        match lane_group(&lane) {
            LaneGroup::Active => active_lanes.push(lane_item_from_lane(&lane, selected)),
            LaneGroup::Finished => finished_lanes.push(lane_item_from_lane(&lane, false)),
            LaneGroup::Stale => stale_lanes.push(lane_item_from_lane(&lane, false)),
        }
    }

    BoardViewModel {
        repo_root: board.repo_root.clone(),
        updated_at: board.generated_at.clone(),
        summary: board.summary.as_ref().map(summary_view),
        ready_issues: board
            .ready_issues
            .iter()
            .map(|issue| issue_item(issue, selected_board_item_id == Some(issue.id.as_str())))
            .collect(),
        claimed_issues: board
            .claimed_issues
            .iter()
            .map(|issue| issue_item(issue, selected_board_item_id == Some(issue.id.as_str())))
            .collect(),
        blocked_issues: board
            .blocked_issues
            .iter()
            .map(|issue| issue_item(issue, false))
            .collect(),
        deferred_issues: board
            .deferred_issues
            .iter()
            .map(|issue| issue_item(issue, false))
            .collect(),
        active_lanes,
        finished_lanes,
        stale_lanes,
        workspaces: board.workspaces.clone(),
    }
}

pub(crate) fn receipts_viewmodel(receipts: &ReceiptsStatus) -> ReceiptsViewModel {
    ReceiptsViewModel {
        repo_root: receipts.repo_root.clone(),
        updated_at: receipts.generated_at.clone(),
        receipts_path: receipts.receipts_path.clone(),
        receipts: receipts
            .receipts
            .iter()
            .rev()
            .take(10)
            .map(|receipt| ReceiptItem {
                label: receipt_label(receipt),
            })
            .collect(),
    }
}

fn build_focus_narrative(
    focus: Option<&OperatorFocusIssue>,
    action: Option<&OperatorRecommendation>,
    rationale: &[String],
) -> Option<FocusNarrative> {
    let focus = focus?;
    let blockers: Vec<IssueRef> = action
        .map(|value| value.dependencies.iter().map(issue_ref).collect())
        .unwrap_or_default();
    let dependents: Vec<IssueRef> = action
        .map(|value| value.dependents.iter().map(issue_ref).collect())
        .unwrap_or_default();

    Some(FocusNarrative {
        issue_id: focus.id.clone(),
        title: focus.title.clone(),
        status: focus.status.clone(),
        parent: focus.parent.clone(),
        blockers: blockers.clone(),
        upstream: blockers,
        unlocks: dependents.clone(),
        dependents,
        rationale: rationale.to_vec(),
    })
}

fn action_item(action: &OperatorRecommendation) -> ActionItem {
    let narrative = action.issue_id.as_ref().map(|issue_id| FocusNarrative {
        issue_id: issue_id.clone(),
        title: action
            .title
            .clone()
            .unwrap_or_else(|| action.message.clone()),
        status: action.status.clone(),
        parent: None,
        blockers: action.dependencies.iter().map(issue_ref).collect(),
        upstream: action.dependencies.iter().map(issue_ref).collect(),
        unlocks: action.dependents.iter().map(issue_ref).collect(),
        dependents: action.dependents.iter().map(issue_ref).collect(),
        rationale: action.rationale.clone(),
    });

    ActionItem {
        kind: action.kind.clone(),
        message: action.message.clone(),
        issue_id: action.issue_id.clone(),
        title: action.title.clone(),
        command: action.command.clone(),
        narrative,
        source: Source::Heuristic,
        confidence: Some(if action.dependents.is_empty() {
            "heuristic".to_owned()
        } else {
            "strong".to_owned()
        }),
        obstructions: Vec::new(),
        rationale: action.rationale.clone(),
    }
}

fn history_items(history: &OperatorHistory) -> Vec<HistoryItem> {
    if !history.narrative.is_empty() {
        return history
            .narrative
            .iter()
            .enumerate()
            .map(|(index, narrative)| HistoryItem {
                timestamp: history
                    .recent_transitions
                    .get(index)
                    .and_then(|receipt| receipt.timestamp.clone()),
                kind: history
                    .recent_transitions
                    .get(index)
                    .and_then(|receipt| receipt.kind.clone())
                    .unwrap_or_else(|| "transition".to_owned()),
                issue_id: history
                    .recent_transitions
                    .get(index)
                    .and_then(|receipt| receipt.issue_id.clone()),
                narrative: narrative.clone(),
                consequence: None,
                source: Source::Authoritative,
            })
            .collect();
    }

    history
        .recent_transitions
        .iter()
        .map(|receipt| HistoryItem {
            timestamp: receipt.timestamp.clone(),
            kind: receipt
                .kind
                .clone()
                .unwrap_or_else(|| "transition".to_owned()),
            issue_id: receipt.issue_id.clone(),
            narrative: operator_receipt_label(receipt),
            consequence: None,
            source: Source::Authoritative,
        })
        .collect()
}

fn context_summary(context: &OperatorContext) -> ContextSummary {
    let repo_name = Path::new(&context.repo_root)
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or(&context.repo_root)
        .to_owned();

    let backend = context.backend_endpoint.as_ref().map(|endpoint| {
        let host = endpoint
            .host
            .clone()
            .unwrap_or_else(|| "127.0.0.1".to_owned());
        let port = endpoint
            .port
            .map(|value| value.to_string())
            .unwrap_or_else(|| "unknown".to_owned());
        format!("{host}:{port}")
    });

    let mut anomalies = Vec::new();
    if context.checkout_root != context.tracker_root {
        anomalies.push(ContextAnomaly::RootMismatch {
            checkout: context.checkout_root.clone(),
            tracker: context.tracker_root.clone(),
        });
    }

    ContextSummary {
        repo_name,
        mode: context.service.mode.clone(),
        workspace_count: context.counts.workspaces,
        repo_root: context.repo_root.clone(),
        checkout_root: context.checkout_root.clone(),
        tracker_root: context.tracker_root.clone(),
        socket_path: context.protocol.endpoint.clone(),
        backend,
        anomalies,
        summary: context.summary.as_ref().map(summary_view),
        workspaces: context.workspaces.iter().map(workspace_item).collect(),
    }
}

fn summary_view(summary: &BoardSummary) -> SummaryView {
    SummaryView {
        total: summary.total_issues.unwrap_or_default(),
        open: summary.open_issues.unwrap_or_default(),
        in_progress: summary.in_progress_issues.unwrap_or_default(),
        ready: summary.ready_issues.unwrap_or_default(),
        blocked: summary.blocked_issues.unwrap_or_default(),
        deferred: summary.deferred_issues.unwrap_or_default(),
        closed: summary.closed_issues.unwrap_or_default(),
    }
}

fn issue_item(issue: &BoardIssue, selected: bool) -> IssueItem {
    IssueItem {
        id: issue.id.clone(),
        title: issue.title.clone(),
        status: issue.status.clone(),
        selected,
    }
}

fn lane_item_from_operator_lane(lane: &OperatorLane, selected: bool) -> LaneItem {
    LaneItem {
        issue_id: lane.issue_id.clone(),
        title: lane
            .issue_title
            .clone()
            .or_else(|| lane.status.clone())
            .unwrap_or_else(|| "lane".to_owned()),
        status: lane.status.clone(),
        observed_status: lane.observed_status.clone(),
        workspace_name: lane.workspace_name.clone(),
        workspace_exists: lane.workspace_exists,
        outcome: None,
        selected,
    }
}

fn lane_item_from_lane(lane: &LaneEntry, selected: bool) -> LaneItem {
    LaneItem {
        issue_id: lane.issue_id.clone(),
        title: lane.issue_title.clone(),
        status: Some(lane.status.clone()),
        observed_status: lane.observed_status.clone(),
        workspace_name: lane.workspace_name.clone(),
        workspace_exists: lane.workspace_exists,
        outcome: lane.outcome.clone(),
        selected,
    }
}

fn workspace_item(workspace: &WorkspaceEntry) -> WorkspaceItem {
    let description = workspace
        .description
        .clone()
        .unwrap_or_else(|| workspace.raw.clone());
    let mut details = Vec::new();
    if let Some(change_id) = &workspace.change_id {
        details.push(change_id.clone());
    }
    if let Some(commit_id) = &workspace.commit_id {
        details.push(commit_id.clone());
    }
    if workspace.empty {
        details.push("empty".to_owned());
    }

    WorkspaceItem {
        name: workspace.name.clone(),
        description,
        details,
    }
}

fn issue_ref(reference: &OperatorIssueRef) -> IssueRef {
    IssueRef {
        id: reference.id.clone(),
        title: reference.title.clone(),
        status: reference.status.clone(),
        dependency_type: reference.dependency_type.clone(),
    }
}

fn receipt_label(receipt: &ReceiptEntry) -> String {
    if let Some(invalid) = &receipt.invalid_line {
        return format!("invalid {invalid}");
    }

    let timestamp = receipt
        .timestamp
        .clone()
        .unwrap_or_else(|| "unknown-time".to_owned());
    let kind = receipt
        .kind
        .clone()
        .unwrap_or_else(|| "unknown-kind".to_owned());
    let payload_hint = receipt
        .payload
        .as_ref()
        .and_then(|payload| payload.as_object())
        .map(|object| {
            format!(
                " ({})",
                object.keys().cloned().collect::<Vec<_>>().join(",")
            )
        })
        .unwrap_or_default();

    format!("{timestamp} {kind}{payload_hint}")
}

fn operator_receipt_label(receipt: &OperatorReceipt) -> String {
    let timestamp = receipt
        .timestamp
        .clone()
        .unwrap_or_else(|| "unknown-time".to_owned());
    let kind = receipt
        .kind
        .clone()
        .unwrap_or_else(|| "unknown-kind".to_owned());
    let issue = receipt
        .issue_id
        .clone()
        .map(|value| format!(" {value}"))
        .unwrap_or_default();

    format!("{timestamp} {kind}{issue}")
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum LaneGroup {
    Active,
    Finished,
    Stale,
}

fn lane_group(lane: &LaneEntry) -> LaneGroup {
    let observed_status = lane
        .observed_status
        .as_deref()
        .unwrap_or(lane.status.as_str());
    if observed_status == "stale" {
        LaneGroup::Stale
    } else if lane.status == "finished" || observed_status == "finished" {
        LaneGroup::Finished
    } else {
        LaneGroup::Active
    }
}

#[cfg(test)]
mod tests {
    use super::home_viewmodel;
    use crate::types::golden_operator_snapshot;

    #[test]
    fn home_viewmodel_keeps_dependency_narrative_structured() {
        let model = home_viewmodel(&golden_operator_snapshot());

        assert_eq!(model.headline, "Launch tusk-ready next.");
        assert_eq!(
            model.focus.as_ref().map(|focus| focus.issue_id.as_str()),
            Some("tusk-ready")
        );
        assert_eq!(
            model.focus.as_ref().map(|focus| focus.unlocks.len()),
            Some(1)
        );
        assert_eq!(
            model
                .primary_action
                .as_ref()
                .and_then(|action| action.narrative.as_ref())
                .map(|narrative| narrative.blockers.len()),
            Some(1)
        );
        assert_eq!(model.context.repo_name, "repo");
    }
}
