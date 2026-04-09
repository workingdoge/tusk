use std::path::Path;

use serde_json::Value;

use crate::types::{
    BoardIssue, BoardStatus, BoardSummary, InspectLane, IssueInspection, LaneEntry,
    OperatorFocusIssue, OperatorHistory, OperatorIssueRef, OperatorLane, OperatorReceipt,
    OperatorRecommendation, OperatorSnapshot, ReceiptEntry, ReceiptsStatus, SessionRow,
    SessionSummary, TrackerStatus, WorkspaceEntry,
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
pub(crate) struct WorkerSummary {
    pub(crate) total: u64,
    pub(crate) active: u64,
    pub(crate) running: u64,
    pub(crate) stale: u64,
    pub(crate) blocked: u64,
    pub(crate) exited: u64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct WorkerItem {
    pub(crate) id: String,
    pub(crate) runtime_kind: String,
    pub(crate) status: String,
    pub(crate) issue_id: Option<String>,
    pub(crate) issue_title: Option<String>,
    pub(crate) workspace_name: Option<String>,
    pub(crate) workspace_path: Option<String>,
    pub(crate) workspace_exists: Option<bool>,
    pub(crate) lane_status: Option<String>,
    pub(crate) reported_status: Option<String>,
    pub(crate) launcher: Option<String>,
    pub(crate) pid: Option<i64>,
    pub(crate) pid_live: bool,
    pub(crate) launched_at: Option<String>,
    pub(crate) heartbeat_at: Option<String>,
    pub(crate) last_seen_at: Option<String>,
    pub(crate) finished_at: Option<String>,
    pub(crate) exit_code: Option<i64>,
    pub(crate) obstructions: Vec<String>,
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
    RootMismatch {
        checkout: String,
        tracker: String,
    },
    AmbientRootCheckout {
        tracker: String,
        lane_workspaces: Vec<String>,
    },
    BackendUnhealthy {
        message: String,
    },
    StaleWorkspaces {
        count: u64,
    },
    DirtyTree {
        root: String,
        changed_paths: u64,
    },
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
    pub(crate) workers: WorkerSummary,
    pub(crate) attention_workers: Vec<WorkerItem>,
    pub(crate) live_workers: Vec<WorkerItem>,
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
pub(crate) struct WorkersViewModel {
    pub(crate) repo_root: String,
    pub(crate) updated_at: String,
    pub(crate) summary: WorkerSummary,
    pub(crate) attention: Vec<WorkerItem>,
    pub(crate) live: Vec<WorkerItem>,
    pub(crate) recent_exits: Vec<WorkerItem>,
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

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct InspectLaneView {
    pub(crate) issue_id: String,
    pub(crate) issue_title: Option<String>,
    pub(crate) status: String,
    pub(crate) observed_status: Option<String>,
    pub(crate) workspace_name: Option<String>,
    pub(crate) workspace_exists: Option<bool>,
    pub(crate) workspace_path: Option<String>,
    pub(crate) base_rev: Option<String>,
    pub(crate) revision: Option<String>,
    pub(crate) outcome: Option<String>,
    pub(crate) note: Option<String>,
    pub(crate) created_at: Option<String>,
    pub(crate) updated_at: Option<String>,
    pub(crate) handoff_at: Option<String>,
    pub(crate) finished_at: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct IssueInspectViewModel {
    pub(crate) repo_root: String,
    pub(crate) issue_id: String,
    pub(crate) title: String,
    pub(crate) status: Option<String>,
    pub(crate) priority: Option<String>,
    pub(crate) issue_type: Option<String>,
    pub(crate) parent: Option<String>,
    pub(crate) created_at: Option<String>,
    pub(crate) updated_at: Option<String>,
    pub(crate) closed_at: Option<String>,
    pub(crate) dependency_count: usize,
    pub(crate) dependent_count: usize,
    pub(crate) dependencies: Vec<IssueRef>,
    pub(crate) dependents: Vec<IssueRef>,
    pub(crate) lane: Option<InspectLaneView>,
    pub(crate) recent_receipts: Vec<HistoryItem>,
    pub(crate) available_receipts: u64,
    pub(crate) recommendation: Option<ActionItem>,
    pub(crate) focus_rationale: Vec<String>,
}

pub(crate) fn home_viewmodel(snapshot: &OperatorSnapshot) -> HomeViewModel {
    let focus = build_focus_narrative(
        snapshot.briefing.focus_issue.as_ref(),
        snapshot.next.primary_action.as_ref(),
        &snapshot.briefing.narrative,
    );
    let workers = workers_viewmodel(snapshot);

    HomeViewModel {
        headline: snapshot.briefing.headline.clone(),
        summary: snapshot.briefing.summary.clone(),
        updated_at: snapshot.generated_at.clone(),
        focus,
        workers: workers.summary.clone(),
        attention_workers: workers.attention.iter().take(4).cloned().collect(),
        live_workers: workers.live.iter().take(4).cloned().collect(),
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
        context: context_summary(snapshot),
    }
}

pub(crate) fn workers_viewmodel(snapshot: &OperatorSnapshot) -> WorkersViewModel {
    let mut attention = Vec::new();
    let mut live = Vec::new();
    let mut recent_exits = Vec::new();

    for row in &snapshot.sessions.rows {
        let item = worker_item(row);
        if needs_attention(&item) {
            attention.push(item.clone());
        }

        match item.status.as_str() {
            "exited" => recent_exits.push(item),
            _ => live.push(item),
        }
    }

    WorkersViewModel {
        repo_root: snapshot.context.repo_root.clone(),
        updated_at: snapshot.generated_at.clone(),
        summary: worker_summary(&snapshot.sessions.summary),
        attention,
        live,
        recent_exits,
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
    filter_query: Option<&str>,
) -> BoardViewModel {
    let mut active_lanes = Vec::new();
    let mut finished_lanes = Vec::new();
    let mut stale_lanes = Vec::new();
    let filter = normalized_filter_query(filter_query);

    let mut ordered = board.lanes.clone();
    ordered.sort_by(|left, right| left.issue_id.cmp(&right.issue_id));

    for lane in ordered {
        if !lane_matches_filter(&lane, filter.as_deref()) {
            continue;
        }
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
            .filter(|issue| board_issue_matches_filter(issue, filter.as_deref()))
            .map(|issue| issue_item(issue, selected_board_item_id == Some(issue.id.as_str())))
            .collect(),
        claimed_issues: board
            .claimed_issues
            .iter()
            .filter(|issue| board_issue_matches_filter(issue, filter.as_deref()))
            .map(|issue| issue_item(issue, selected_board_item_id == Some(issue.id.as_str())))
            .collect(),
        blocked_issues: board
            .blocked_issues
            .iter()
            .filter(|issue| board_issue_matches_filter(issue, filter.as_deref()))
            .map(|issue| issue_item(issue, false))
            .collect(),
        deferred_issues: board
            .deferred_issues
            .iter()
            .filter(|issue| board_issue_matches_filter(issue, filter.as_deref()))
            .map(|issue| issue_item(issue, false))
            .collect(),
        active_lanes,
        finished_lanes,
        stale_lanes,
        workspaces: board.workspaces.clone(),
    }
}

pub(crate) fn receipts_viewmodel(
    receipts: &ReceiptsStatus,
    filter_query: Option<&str>,
) -> ReceiptsViewModel {
    let filter = normalized_filter_query(filter_query);

    ReceiptsViewModel {
        repo_root: receipts.repo_root.clone(),
        updated_at: receipts.generated_at.clone(),
        receipts_path: receipts.receipts_path.clone(),
        receipts: receipts
            .receipts
            .iter()
            .rev()
            .filter(|receipt| receipt_matches_filter(receipt, filter.as_deref()))
            .take(10)
            .map(|receipt| ReceiptItem {
                label: receipt_label(receipt),
            })
            .collect(),
    }
}

pub(crate) fn issue_inspect_viewmodel(
    inspection: &IssueInspection,
    home: Option<&HomeViewModel>,
) -> IssueInspectViewModel {
    let recommendation = home
        .and_then(|home| home.primary_action.clone())
        .filter(|action| action.issue_id.as_deref() == Some(inspection.issue.id.as_str()));
    let focus_rationale = home
        .and_then(|home| home.focus.as_ref())
        .filter(|focus| focus.issue_id == inspection.issue.id)
        .map(|focus| focus.rationale.clone())
        .unwrap_or_default();

    IssueInspectViewModel {
        repo_root: inspection.repo_root.clone(),
        issue_id: inspection.issue.id.clone(),
        title: inspection.issue.title.clone(),
        status: inspection.issue.status.clone(),
        priority: inspection.issue.priority.clone(),
        issue_type: inspection.issue.issue_type.clone(),
        parent: inspection.issue.parent.clone(),
        created_at: inspection.issue.created_at.clone(),
        updated_at: inspection.issue.updated_at.clone(),
        closed_at: inspection.issue.closed_at.clone(),
        dependency_count: inspection
            .issue
            .dependency_count
            .unwrap_or(inspection.dependencies.len() as u64) as usize,
        dependent_count: inspection
            .issue
            .dependent_count
            .unwrap_or(inspection.dependents.len() as u64) as usize,
        dependencies: inspection.dependencies.iter().map(issue_ref).collect(),
        dependents: inspection.dependents.iter().map(issue_ref).collect(),
        lane: inspection.lane.as_ref().map(inspect_lane_view),
        recent_receipts: inspection
            .recent_receipts
            .iter()
            .map(|receipt| HistoryItem {
                timestamp: receipt.timestamp.clone(),
                kind: receipt
                    .kind
                    .clone()
                    .unwrap_or_else(|| "transition".to_owned()),
                issue_id: receipt.issue_id.clone(),
                narrative: operator_receipt_label(receipt),
                consequence: receipt
                    .details
                    .as_ref()
                    .and_then(|details| details.get("reason").and_then(Value::as_str))
                    .or_else(|| {
                        receipt
                            .details
                            .as_ref()
                            .and_then(|details| details.get("note").and_then(Value::as_str))
                    })
                    .or_else(|| {
                        receipt
                            .details
                            .as_ref()
                            .and_then(|details| details.get("outcome").and_then(Value::as_str))
                    })
                    .map(ToOwned::to_owned),
                source: Source::Authoritative,
            })
            .collect(),
        available_receipts: inspection.available_receipts.unwrap_or_default(),
        recommendation,
        focus_rationale,
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

fn context_summary(snapshot: &OperatorSnapshot) -> ContextSummary {
    let context = &snapshot.context;
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
    } else {
        let lane_workspaces = context
            .workspaces
            .iter()
            .filter(|workspace| workspace.name != "default")
            .map(|workspace| workspace.name.clone())
            .take(3)
            .collect::<Vec<_>>();
        if !lane_workspaces.is_empty() {
            anomalies.push(ContextAnomaly::AmbientRootCheckout {
                tracker: context.tracker_root.clone(),
                lane_workspaces,
            });
        }
    }
    if let Some(message) = snapshot
        .now
        .obstructions
        .iter()
        .find(|obstruction| obstruction.kind == "runtime_unhealthy")
        .map(|obstruction| obstruction.message.clone())
        .or_else(|| {
            snapshot
                .now
                .runtime
                .health
                .as_deref()
                .filter(|health| *health != "healthy")
                .map(|health| format!("tracker or backend health is {health}"))
        })
    {
        anomalies.push(ContextAnomaly::BackendUnhealthy { message });
    }
    let stale_workspace_count = snapshot.now.counts.stale_lanes.max(
        u64::try_from(snapshot.now.stale_lanes.len()).unwrap_or(snapshot.now.counts.stale_lanes),
    );
    if stale_workspace_count > 0 {
        anomalies.push(ContextAnomaly::StaleWorkspaces {
            count: stale_workspace_count,
        });
    }
    if let Some(dirty_tree) = context
        .dirty_tree
        .as_ref()
        .filter(|dirty_tree| dirty_tree.dirty)
    {
        anomalies.push(ContextAnomaly::DirtyTree {
            root: dirty_tree.root.clone(),
            changed_paths: dirty_tree.changed_paths,
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

fn worker_summary(summary: &SessionSummary) -> WorkerSummary {
    WorkerSummary {
        total: summary.total_sessions,
        active: summary.active_sessions,
        running: summary.running_sessions,
        stale: summary.stale_sessions,
        blocked: summary.blocked_sessions,
        exited: summary.exited_sessions,
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

fn worker_item(row: &SessionRow) -> WorkerItem {
    let mut obstructions = Vec::new();

    match row.status.as_str() {
        "blocked" => obstructions.push("session is blocked".to_owned()),
        "stale" => {
            let detail = row
                .last_seen_at
                .as_ref()
                .or(row.heartbeat_at.as_ref())
                .map(|timestamp| format!("heartbeat is stale since {timestamp}"))
                .unwrap_or_else(|| "heartbeat is stale".to_owned());
            obstructions.push(detail);
        }
        _ => {}
    }

    if row.workspace_exists == Some(false) {
        obstructions.push("workspace is missing from disk".to_owned());
    }
    if row.issue_id.is_none() && row.status != "exited" {
        obstructions.push("session is detached from issue work".to_owned());
    }
    if row
        .reported_status
        .as_ref()
        .is_some_and(|reported| reported != &row.status)
    {
        obstructions.push(format!(
            "reported {} but observed {}",
            row.reported_status.as_deref().unwrap_or("unknown"),
            row.status
        ));
    }

    WorkerItem {
        id: row.id.clone(),
        runtime_kind: row
            .runtime_kind
            .clone()
            .unwrap_or_else(|| "worker".to_owned()),
        status: row.status.clone(),
        issue_id: row.issue_id.clone(),
        issue_title: row.issue_title.clone(),
        workspace_name: row.workspace_name.clone(),
        workspace_path: row.workspace_path.clone(),
        workspace_exists: row.workspace_exists,
        lane_status: row.lane_status.clone(),
        reported_status: row.reported_status.clone(),
        launcher: row.launcher.clone(),
        pid: row.pid,
        pid_live: row.pid_live,
        launched_at: row.launched_at.clone(),
        heartbeat_at: row.heartbeat_at.clone(),
        last_seen_at: row.last_seen_at.clone(),
        finished_at: row.finished_at.clone(),
        exit_code: row.exit_code,
        obstructions,
    }
}

fn needs_attention(worker: &WorkerItem) -> bool {
    !worker.obstructions.is_empty() || matches!(worker.status.as_str(), "blocked" | "stale")
}

fn normalized_filter_query(query: Option<&str>) -> Option<String> {
    query
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value.to_lowercase())
}

fn contains_filter(haystack: &str, filter: Option<&str>) -> bool {
    match filter {
        Some(filter) => haystack.to_lowercase().contains(filter),
        None => true,
    }
}

fn board_issue_matches_filter(issue: &BoardIssue, filter: Option<&str>) -> bool {
    contains_filter(&format!("{} {}", issue.id, issue.title), filter)
}

fn lane_matches_filter(lane: &LaneEntry, filter: Option<&str>) -> bool {
    contains_filter(&format!("{} {}", lane.issue_id, lane.issue_title), filter)
}

fn receipt_matches_filter(receipt: &ReceiptEntry, filter: Option<&str>) -> bool {
    contains_filter(&receipt_label(receipt), filter)
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

fn inspect_lane_view(lane: &InspectLane) -> InspectLaneView {
    InspectLaneView {
        issue_id: lane.issue_id.clone(),
        issue_title: lane.issue_title.clone(),
        status: lane.status.clone(),
        observed_status: lane.observed_status.clone(),
        workspace_name: lane.workspace_name.clone(),
        workspace_exists: lane.workspace_exists,
        workspace_path: lane.workspace_path.clone(),
        base_rev: lane.base_rev.clone(),
        revision: lane.revision.clone(),
        outcome: lane.outcome.clone(),
        note: lane.note.clone(),
        created_at: lane.created_at.clone(),
        updated_at: lane.updated_at.clone(),
        handoff_at: lane.handoff_at.clone(),
        finished_at: lane.finished_at.clone(),
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
    use super::{
        board_viewmodel, home_viewmodel, issue_inspect_viewmodel, receipts_viewmodel,
        workers_viewmodel,
    };
    use crate::types::{
        BoardIssue, BoardStatus, LaneEntry, ReceiptEntry, ReceiptsStatus, golden_issue_inspection,
        golden_operator_snapshot,
    };

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
        assert_eq!(model.workers.total, 3);
        assert_eq!(model.attention_workers.len(), 1);
        assert_eq!(model.attention_workers[0].status, "stale");
    }

    #[test]
    fn workers_viewmodel_partitions_attention_live_and_recent_exits() {
        let model = workers_viewmodel(&golden_operator_snapshot());

        assert_eq!(model.summary.active, 2);
        assert_eq!(model.summary.stale, 1);
        assert_eq!(model.attention.len(), 1);
        assert_eq!(model.attention[0].id, "session-stale");
        assert_eq!(model.live.len(), 2);
        assert_eq!(model.recent_exits.len(), 1);
        assert_eq!(model.recent_exits[0].id, "session-exited");
    }

    #[test]
    fn home_viewmodel_flags_ambient_root_checkout_when_lane_workspaces_exist() {
        let mut snapshot = golden_operator_snapshot();
        snapshot
            .context
            .workspaces
            .push(crate::types::WorkspaceEntry {
                name: "tusk-asy.11.1-ui-recovery".to_owned(),
                change_id: Some("lane123".to_owned()),
                commit_id: Some("lane456".to_owned()),
                empty: false,
                description: Some("tusk-asy.11.1: wip".to_owned()),
                raw: "tusk-asy.11.1-ui-recovery: lane123 lane456 tusk-asy.11.1: wip".to_owned(),
            });

        let model = home_viewmodel(&snapshot);

        assert!(model.context.anomalies.iter().any(|anomaly| matches!(
            anomaly,
            super::ContextAnomaly::AmbientRootCheckout { tracker, lane_workspaces }
                if tracker == "/tmp/repo"
                    && lane_workspaces
                        == &vec!["tusk-asy.11.1-ui-recovery".to_owned()]
        )));
    }

    #[test]
    fn home_viewmodel_keeps_lane_checkout_quiet_when_roots_differ() {
        let mut snapshot = golden_operator_snapshot();
        snapshot.context.checkout_root =
            "/tmp/repo/.jj-workspaces/tusk-asy.11.2-guardrail".to_owned();
        snapshot
            .context
            .workspaces
            .push(crate::types::WorkspaceEntry {
                name: "tusk-asy.11.2-guardrail".to_owned(),
                change_id: Some("lane123".to_owned()),
                commit_id: Some("lane456".to_owned()),
                empty: false,
                description: Some("tusk-asy.11.2: wip".to_owned()),
                raw: "tusk-asy.11.2-guardrail: lane123 lane456 tusk-asy.11.2: wip".to_owned(),
            });

        let model = home_viewmodel(&snapshot);

        assert!(
            !model.context.anomalies.iter().any(|anomaly| matches!(
                anomaly,
                super::ContextAnomaly::AmbientRootCheckout { .. }
            ))
        );
        assert!(
            model
                .context
                .anomalies
                .iter()
                .any(|anomaly| matches!(anomaly, super::ContextAnomaly::RootMismatch { .. }))
        );
    }

    #[test]
    fn home_viewmodel_surfaces_runtime_stale_and_dirty_context_anomalies() {
        let mut snapshot = golden_operator_snapshot();
        snapshot.now.runtime.health = Some("unhealthy".to_owned());
        snapshot
            .now
            .obstructions
            .push(crate::types::OperatorObstruction {
                kind: "runtime_unhealthy".to_owned(),
                message: "tracker or backend health is not currently healthy".to_owned(),
                issue_id: None,
            });
        snapshot.context.dirty_tree = Some(crate::types::OperatorDirtyTree {
            root: "/tmp/repo".to_owned(),
            dirty: true,
            changed_paths: 2,
        });

        let model = home_viewmodel(&snapshot);

        assert!(model.context.anomalies.iter().any(|anomaly| matches!(
            anomaly,
            super::ContextAnomaly::BackendUnhealthy { message }
                if message == "tracker or backend health is not currently healthy"
        )));
        assert!(model.context.anomalies.iter().any(|anomaly| matches!(
            anomaly,
            super::ContextAnomaly::StaleWorkspaces { count } if *count == 1
        )));
        assert!(model.context.anomalies.iter().any(|anomaly| matches!(
            anomaly,
            super::ContextAnomaly::DirtyTree { root, changed_paths }
                if root == "/tmp/repo" && *changed_paths == 2
        )));
    }

    #[test]
    fn issue_inspect_viewmodel_carries_authoritative_and_heuristic_context() {
        let home = home_viewmodel(&golden_operator_snapshot());
        let model = issue_inspect_viewmodel(&golden_issue_inspection(), Some(&home));

        assert_eq!(model.issue_id, "tusk-ready");
        assert_eq!(model.dependencies.len(), 1);
        assert_eq!(model.dependents.len(), 1);
        assert_eq!(model.recent_receipts.len(), 2);
        assert_eq!(
            model
                .recommendation
                .as_ref()
                .and_then(|action| action.issue_id.as_deref()),
            Some("tusk-ready")
        );
    }

    #[test]
    fn board_viewmodel_filters_issue_and_lane_sections() {
        let board = BoardStatus {
            repo_root: "/tmp/repo".to_owned(),
            generated_at: "2026-04-07T20:00:00Z".to_owned(),
            summary: None,
            ready_issues: vec![BoardIssue {
                id: "tusk-ready".to_owned(),
                title: "ready issue".to_owned(),
                status: Some("open".to_owned()),
            }],
            claimed_issues: vec![BoardIssue {
                id: "tusk-claim".to_owned(),
                title: "claimed issue".to_owned(),
                status: Some("in_progress".to_owned()),
            }],
            blocked_issues: vec![BoardIssue {
                id: "tusk-blocked".to_owned(),
                title: "blocked issue".to_owned(),
                status: Some("open".to_owned()),
            }],
            deferred_issues: vec![],
            lanes: vec![LaneEntry {
                issue_id: "tusk-lane".to_owned(),
                issue_title: "live lane".to_owned(),
                status: "launched".to_owned(),
                observed_status: Some("launched".to_owned()),
                workspace_exists: Some(true),
                outcome: None,
                workspace_name: Some("tusk-lane".to_owned()),
            }],
            sessions: None,
            workspaces: vec![],
        };

        let model = board_viewmodel(&board, Some("tusk-lane"), Some("lane"));

        assert!(model.ready_issues.is_empty());
        assert!(model.claimed_issues.is_empty());
        assert_eq!(model.active_lanes.len(), 1);
        assert_eq!(model.active_lanes[0].issue_id, "tusk-lane");
        assert!(model.active_lanes[0].selected);
    }

    #[test]
    fn receipts_viewmodel_filters_by_label_text() {
        let receipts = ReceiptsStatus {
            repo_root: "/tmp/repo".to_owned(),
            generated_at: "2026-04-07T20:00:00Z".to_owned(),
            receipts_path: "/tmp/repo/.beads/tuskd/receipts.jsonl".to_owned(),
            receipts: vec![
                ReceiptEntry {
                    timestamp: Some("2026-04-07T19:59:00Z".to_owned()),
                    kind: Some("issue.claim".to_owned()),
                    payload: None,
                    invalid_line: None,
                },
                ReceiptEntry {
                    timestamp: Some("2026-04-07T20:00:00Z".to_owned()),
                    kind: Some("lane.launch".to_owned()),
                    payload: None,
                    invalid_line: None,
                },
            ],
        };

        let model = receipts_viewmodel(&receipts, Some("launch"));

        assert_eq!(model.receipts.len(), 1);
        assert!(model.receipts[0].label.contains("lane.launch"));
    }
}
