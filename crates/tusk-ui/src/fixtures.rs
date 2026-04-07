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
