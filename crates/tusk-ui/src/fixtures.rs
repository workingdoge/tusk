pub(crate) const GOLDEN_OPERATOR_SNAPSHOT_FIXTURE_JSON: &str = r#"{
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
  "sessions": {
    "summary": {
      "total_sessions": 3,
      "active_sessions": 2,
      "running_sessions": 1,
      "stale_sessions": 1,
      "blocked_sessions": 0,
      "exited_sessions": 1
    },
    "rows": [
      {
        "id": "session-stale",
        "runtime_kind": "codex",
        "launcher": "tusk-codex",
        "checkout_root": "/tmp/repo/.jj-workspaces/tusk-live-lane",
        "tracker_root": "/tmp/repo",
        "workspace_name": "tusk-live-lane",
        "workspace_path": "/tmp/repo/.jj-workspaces/tusk-live-lane",
        "workspace_exists": true,
        "issue_id": "tusk-live",
        "issue_title": "live lane",
        "lane_status": "launched",
        "reported_status": "running",
        "status": "stale",
        "pid": 31415,
        "pid_live": true,
        "handle": null,
        "launched_at": "2026-04-07T19:30:00Z",
        "heartbeat_at": "2026-04-07T19:58:00Z",
        "last_seen_at": "2026-04-07T19:58:00Z",
        "finished_at": null,
        "exit_code": null,
        "updated_at": "2026-04-07T19:58:00Z",
        "stale_after_seconds": 90
      },
      {
        "id": "session-running",
        "runtime_kind": "claude",
        "launcher": "tusk-claude",
        "checkout_root": "/tmp/repo/.jj-workspaces/tusk-ready-lane",
        "tracker_root": "/tmp/repo",
        "workspace_name": "tusk-ready-lane",
        "workspace_path": "/tmp/repo/.jj-workspaces/tusk-ready-lane",
        "workspace_exists": true,
        "issue_id": "tusk-ready",
        "issue_title": "ready issue",
        "lane_status": "launched",
        "reported_status": "running",
        "status": "running",
        "pid": 27182,
        "pid_live": true,
        "handle": null,
        "launched_at": "2026-04-07T19:45:00Z",
        "heartbeat_at": "2026-04-07T19:59:30Z",
        "last_seen_at": "2026-04-07T19:59:30Z",
        "finished_at": null,
        "exit_code": null,
        "updated_at": "2026-04-07T19:59:30Z",
        "stale_after_seconds": 90
      },
      {
        "id": "session-exited",
        "runtime_kind": "codex",
        "launcher": "tusk-codex",
        "checkout_root": "/tmp/repo",
        "tracker_root": "/tmp/repo",
        "workspace_name": "default",
        "workspace_path": "/tmp/repo",
        "workspace_exists": true,
        "issue_id": null,
        "issue_title": null,
        "lane_status": null,
        "reported_status": "exited",
        "status": "exited",
        "pid": 16180,
        "pid_live": false,
        "handle": null,
        "launched_at": "2026-04-07T19:10:00Z",
        "heartbeat_at": "2026-04-07T19:15:00Z",
        "last_seen_at": "2026-04-07T19:15:00Z",
        "finished_at": "2026-04-07T19:16:00Z",
        "exit_code": 0,
        "updated_at": "2026-04-07T19:16:00Z",
        "stale_after_seconds": 90
      }
    ]
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
    "dirty_tree": {
      "root": "/tmp/repo",
      "dirty": false,
      "changed_paths": 0
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

pub(crate) const GOLDEN_ISSUE_INSPECTION_FIXTURE_JSON: &str = r#"{
  "repo_root": "/tmp/repo",
  "issue": {
    "id": "tusk-ready",
    "title": "ready issue",
    "status": "open",
    "priority": "P2",
    "issue_type": "task",
    "parent": "tusk-ux",
    "dependency_count": 1,
    "dependent_count": 1,
    "created_at": "2026-04-07T19:00:00Z",
    "updated_at": "2026-04-07T20:00:00Z",
    "closed_at": null
  },
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
  ],
  "lane": {
    "issue_id": "tusk-ready",
    "issue_title": "ready issue",
    "status": "launched",
    "observed_status": "launched",
    "workspace_path": "/tmp/repo/.jj-workspaces/tusk-ready",
    "workspace_name": "tusk-ready",
    "workspace_exists": true,
    "base_rev": "main",
    "revision": "abc123",
    "outcome": null,
    "note": null,
    "created_at": "2026-04-07T19:30:00Z",
    "updated_at": "2026-04-07T20:00:00Z",
    "handoff_at": null,
    "finished_at": null
  },
  "recent_receipts": [
    {
      "timestamp": "2026-04-07T19:59:00Z",
      "kind": "issue.claim",
      "issue_id": "tusk-ready",
      "details": {
        "reason": "demo"
      }
    },
    {
      "timestamp": "2026-04-07T20:00:00Z",
      "kind": "lane.launch",
      "issue_id": "tusk-ready",
      "details": {
        "revision": "abc123"
      }
    }
  ],
  "available_receipts": 2
}"#;
