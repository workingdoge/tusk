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

#[cfg(test)]
pub(crate) fn sample_operator_snapshot() -> OperatorSnapshot {
    use serde_json::json;

    OperatorSnapshot {
        generated_at: "2026-04-07T20:00:00Z".to_owned(),
        briefing: OperatorBriefing {
            headline: "Launch tusk-ready next.".to_owned(),
            summary: "Runtime is healthy. 1 active lane, 1 claimed issue, and 1 ready issue."
                .to_owned(),
            focus_issue: Some(OperatorFocusIssue {
                id: "tusk-ready".to_owned(),
                title: "ready issue".to_owned(),
                status: Some("in_progress".to_owned()),
                parent: Some("tusk-ux".to_owned()),
                dependency_count: Some(1),
                dependent_count: Some(2),
            }),
            narrative: vec![
                "No active lanes are currently moving claimed work.".to_owned(),
                "It unlocks 2 downstream items.".to_owned(),
            ],
        },
        now: OperatorNow {
            runtime: OperatorRuntime {
                health: Some("healthy".to_owned()),
                mode: Some("idle".to_owned()),
                pid: Some(42),
                backend: Some(OperatorBackend {
                    running: Some(true),
                    pid: Some(75075),
                    port: Some(32642),
                    data_dir: Some("/tmp/repo/.beads/dolt".to_owned()),
                }),
            },
            active_lanes: vec![OperatorLane {
                issue_id: "tusk-live".to_owned(),
                issue_title: Some("live lane".to_owned()),
                status: Some("handoff".to_owned()),
                observed_status: Some("handoff".to_owned()),
                workspace_name: Some("tusk-live-lane".to_owned()),
                workspace_exists: Some(true),
            }],
            claimed_issues: vec![BoardIssue {
                id: "tusk-claim".to_owned(),
                title: "claimed issue".to_owned(),
                status: Some("in_progress".to_owned()),
            }],
            stale_lanes: vec![OperatorLane {
                issue_id: "tusk-stale".to_owned(),
                issue_title: Some("stale lane".to_owned()),
                status: Some("handoff".to_owned()),
                observed_status: Some("stale".to_owned()),
                workspace_name: Some("tusk-stale-lane".to_owned()),
                workspace_exists: Some(false),
            }],
            obstructions: vec![OperatorObstruction {
                kind: "stale_lane".to_owned(),
                message: "lane workspace is missing from disk".to_owned(),
                issue_id: Some("tusk-stale".to_owned()),
            }],
            counts: OperatorNowCounts {
                active_lanes: 1,
                claimed_issues: 1,
                stale_lanes: 1,
                obstructions: 1,
            },
        },
        next: OperatorNext {
            primary_action: Some(OperatorRecommendation {
                kind: "claim_ready_issue".to_owned(),
                message: "Claim tusk-ready next.".to_owned(),
                issue_id: Some("tusk-ready".to_owned()),
                title: Some("ready issue".to_owned()),
                status: Some("open".to_owned()),
                command: Some("tuskd claim-issue --repo /tmp/repo --issue-id tusk-ready".to_owned()),
                rationale: vec![
                    "Claiming it unlocks 2 downstream items.".to_owned(),
                    "No claimed issue is currently waiting for launch.".to_owned(),
                ],
                dependencies: vec![OperatorIssueRef {
                    id: "tusk-parent".to_owned(),
                    title: Some("parent issue".to_owned()),
                    status: Some("open".to_owned()),
                    dependency_type: Some("blocks".to_owned()),
                }],
                dependents: vec![OperatorIssueRef {
                    id: "tusk-child".to_owned(),
                    title: Some("child issue".to_owned()),
                    status: Some("open".to_owned()),
                    dependency_type: Some("blocks".to_owned()),
                }],
            }),
            ready_issues: vec![BoardIssue {
                id: "tusk-ready".to_owned(),
                title: "ready issue".to_owned(),
                status: Some("open".to_owned()),
            }],
            blocked_issues: vec![BoardIssue {
                id: "tusk-blocked".to_owned(),
                title: "blocked issue".to_owned(),
                status: Some("open".to_owned()),
            }],
            deferred_issues: vec![BoardIssue {
                id: "tusk-deferred".to_owned(),
                title: "deferred issue".to_owned(),
                status: Some("deferred".to_owned()),
            }],
            recommended_actions: vec![OperatorRecommendation {
                kind: "claim_ready_issue".to_owned(),
                message: "ready work is available to claim".to_owned(),
                issue_id: Some("tusk-ready".to_owned()),
                title: Some("ready issue".to_owned()),
                status: Some("open".to_owned()),
                command: None,
                rationale: vec![],
                dependencies: vec![],
                dependents: vec![],
            }],
            counts: OperatorNextCounts {
                ready_issues: 1,
                blocked_issues: 1,
                deferred_issues: 1,
                recommended_actions: 1,
            },
        },
        history: OperatorHistory {
            recent_transitions: vec![OperatorReceipt {
                timestamp: Some("2026-04-07T19:59:00Z".to_owned()),
                kind: Some("issue.claim".to_owned()),
                issue_id: Some("tusk-ready".to_owned()),
                details: Some(json!({"reason": "demo"})),
            }],
            narrative: vec!["1m ago: claimed tusk-ready".to_owned()],
            counts: OperatorHistoryCounts {
                recent_transitions: 1,
                available_receipts: 3,
            },
        },
        context: OperatorContext {
            repo_root: "/tmp/repo".to_owned(),
            checkout_root: "/tmp/repo".to_owned(),
            tracker_root: "/tmp/repo".to_owned(),
            protocol: TrackerProtocol {
                endpoint: "/tmp/repo/.beads/tuskd/tuskd.sock".to_owned(),
            },
            service: TuskdState {
                mode: "idle".to_owned(),
                pid: None,
            },
            backend_endpoint: Some(OperatorBackendEndpoint {
                host: Some("127.0.0.1".to_owned()),
                port: Some(32642),
            }),
            summary: Some(BoardSummary {
                total_issues: Some(10),
                open_issues: Some(3),
                in_progress_issues: Some(2),
                closed_issues: Some(5),
                blocked_issues: Some(1),
                deferred_issues: Some(1),
                ready_issues: Some(1),
            }),
            workspaces: vec![WorkspaceEntry {
                name: "default".to_owned(),
                change_id: Some("abc123".to_owned()),
                commit_id: Some("def456".to_owned()),
                empty: true,
                description: Some("(no description set)".to_owned()),
                raw: "default: abc123 def456 (empty) (no description set)".to_owned(),
            }],
            counts: OperatorContextCounts { workspaces: 1 },
        },
    }
}

#[cfg(test)]
mod tests {
    use super::OperatorSnapshot;

    const OPERATOR_SNAPSHOT_FIXTURE_JSON: &str = r#"{
  "generated_at": "2026-04-07T20:00:00Z",
  "briefing": {
    "headline": "Launch tusk-ready next.",
    "summary": "Runtime is healthy. 1 active lane, 1 claimed issue, and 1 ready issue.",
    "focus_issue": {
      "id": "tusk-ready",
      "title": "ready issue",
      "status": "in_progress",
      "parent": "tusk-ux",
      "dependency_count": 1,
      "dependent_count": 2
    },
    "narrative": [
      "No active lanes are currently moving claimed work.",
      "It unlocks 2 downstream items."
    ]
  },
  "now": {
    "runtime": {
      "health": "healthy",
      "mode": "idle",
      "pid": 42,
      "backend": {
        "running": true,
        "pid": 75075,
        "port": 32642,
        "data_dir": "/tmp/repo/.beads/dolt"
      }
    },
    "active_lanes": [
      {
        "issue_id": "tusk-live",
        "issue_title": "live lane",
        "status": "handoff",
        "observed_status": "handoff",
        "workspace_name": "tusk-live-lane",
        "workspace_exists": true
      }
    ],
    "claimed_issues": [
      {
        "id": "tusk-claim",
        "title": "claimed issue",
        "status": "in_progress"
      }
    ],
    "stale_lanes": [
      {
        "issue_id": "tusk-stale",
        "issue_title": "stale lane",
        "status": "handoff",
        "observed_status": "stale",
        "workspace_name": "tusk-stale-lane",
        "workspace_exists": false
      }
    ],
    "obstructions": [
      {
        "kind": "stale_lane",
        "message": "lane workspace is missing from disk",
        "issue_id": "tusk-stale"
      }
    ],
    "counts": {
      "active_lanes": 1,
      "claimed_issues": 1,
      "stale_lanes": 1,
      "obstructions": 1
    }
  },
  "next": {
    "primary_action": {
      "kind": "claim_ready_issue",
      "message": "Claim tusk-ready next.",
      "issue_id": "tusk-ready",
      "title": "ready issue",
      "status": "open",
      "command": "tuskd claim-issue --repo /tmp/repo --issue-id tusk-ready",
      "rationale": [
        "Claiming it unlocks 2 downstream items.",
        "No claimed issue is currently waiting for launch."
      ],
      "dependencies": [
        {
          "id": "tusk-parent",
          "title": "parent issue",
          "status": "open",
          "dependency_type": "blocks"
        }
      ],
      "dependents": [
        {
          "id": "tusk-child",
          "title": "child issue",
          "status": "open",
          "dependency_type": "blocks"
        }
      ]
    },
    "ready_issues": [
      {
        "id": "tusk-ready",
        "title": "ready issue",
        "status": "open"
      }
    ],
    "blocked_issues": [
      {
        "id": "tusk-blocked",
        "title": "blocked issue",
        "status": "open"
      }
    ],
    "deferred_issues": [
      {
        "id": "tusk-deferred",
        "title": "deferred issue",
        "status": "deferred"
      }
    ],
    "recommended_actions": [
      {
        "kind": "claim_ready_issue",
        "message": "ready work is available to claim",
        "issue_id": "tusk-ready",
        "title": "ready issue",
        "status": "open",
        "command": null,
        "rationale": [],
        "dependencies": [],
        "dependents": []
      }
    ],
    "counts": {
      "ready_issues": 1,
      "blocked_issues": 1,
      "deferred_issues": 1,
      "recommended_actions": 1
    }
  },
  "history": {
    "recent_transitions": [
      {
        "timestamp": "2026-04-07T19:59:00Z",
        "kind": "issue.claim",
        "issue_id": "tusk-ready",
        "details": {
          "reason": "demo"
        }
      }
    ],
    "narrative": [
      "1m ago: claimed tusk-ready"
    ],
    "counts": {
      "recent_transitions": 1,
      "available_receipts": 3
    }
  },
  "context": {
    "repo_root": "/tmp/repo",
    "checkout_root": "/tmp/repo",
    "tracker_root": "/tmp/repo",
    "protocol": {
      "endpoint": "/tmp/repo/.beads/tuskd/tuskd.sock"
    },
    "service": {
      "mode": "idle",
      "pid": null
    },
    "backend_endpoint": {
      "host": "127.0.0.1",
      "port": 32642
    },
    "summary": {
      "total_issues": 10,
      "open_issues": 3,
      "in_progress_issues": 2,
      "closed_issues": 5,
      "blocked_issues": 1,
      "deferred_issues": 1,
      "ready_issues": 1
    },
    "workspaces": [
      {
        "name": "default",
        "change_id": "abc123",
        "commit_id": "def456",
        "empty": true,
        "description": "(no description set)",
        "raw": "default: abc123 def456 (empty) (no description set)"
      }
    ],
    "counts": {
      "workspaces": 1
    }
  }
}"#;

    #[test]
    fn operator_snapshot_fixture_deserializes() {
        let snapshot: OperatorSnapshot =
            serde_json::from_str(OPERATOR_SNAPSHOT_FIXTURE_JSON).expect("fixture should deserialize");

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
}
