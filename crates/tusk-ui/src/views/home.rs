use std::path::Path;

use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::text::Line;
use ratatui::widgets::{Paragraph, Wrap};
use ratatui::Frame;
use serde_json::Value;

use crate::app::App;
use crate::theme::{error_lines, kv_line, title_line};
use crate::types::{OperatorIssueRef, OperatorReceipt, OperatorSnapshot};

use super::board::summary_lines;
use super::render_lines_panel;

pub(crate) fn render_home(frame: &mut Frame, area: Rect, app: &App) {
    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(area);
    let top = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(rows[0]);
    let bottom = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(rows[1]);

    match (&app.home.value, &app.home.error) {
        (Some(home), _) => {
            render_lines_panel(frame, top[0], "Now", home_now_lines(home));
            render_lines_panel(frame, top[1], "Next", home_next_lines(home));
            render_lines_panel(frame, bottom[0], "History", home_history_lines(home));
            render_lines_panel(frame, bottom[1], "Context", home_context_lines(home));
        }
        (_, Some(error)) => {
            render_lines_panel(frame, area, "Home", error_lines(error));
        }
        _ => {
            frame.render_widget(
                Paragraph::new(vec![Line::from("waiting for operator snapshot")])
                    .block(crate::theme::pane_block("Home", false))
                    .wrap(Wrap { trim: false }),
                area,
            );
        }
    }
}

pub(crate) fn home_now_lines(snapshot: &OperatorSnapshot) -> Vec<Line<'static>> {
    let mut lines = vec![
        title_line(snapshot.briefing.headline.clone()),
        Line::from(snapshot.briefing.summary.clone()),
        kv_line("updated", snapshot.generated_at.clone()),
    ];

    if let Some(focus) = &snapshot.briefing.focus_issue {
        lines.push(Line::from(""));
        lines.push(title_line("focus"));
        lines.push(Line::from(format!("{} {}", focus.id, focus.title)));
        let mut meta = Vec::new();
        if let Some(status) = &focus.status {
            meta.push(format!("status {status}"));
        }
        if let Some(parent) = &focus.parent {
            meta.push(format!("parent {parent}"));
        }
        if let Some(dependent_count) = focus.dependent_count {
            meta.push(format!("unlocks {dependent_count}"));
        }
        if let Some(dependency_count) = focus.dependency_count {
            meta.push(format!("upstream {dependency_count}"));
        }
        if !meta.is_empty() {
            lines.push(Line::from(format!("  {}", meta.join(" | "))));
        }
    }

    if !snapshot.briefing.narrative.is_empty() {
        lines.push(Line::from(""));
        lines.push(title_line("why now"));
        for line in snapshot.briefing.narrative.iter().take(4) {
            lines.push(Line::from(line.clone()));
        }
    }

    if !snapshot.now.active_lanes.is_empty() {
        lines.push(Line::from(""));
        lines.push(title_line("live lanes"));
        for lane in snapshot.now.active_lanes.iter().take(4) {
            lines.push(Line::from(format!(
                "{} {}",
                lane.issue_id,
                lane.issue_title
                    .clone()
                    .unwrap_or_else(|| lane.status.clone().unwrap_or_else(|| "lane".to_owned()))
            )));
            let mut details = Vec::new();
            if let Some(status) = &lane.status {
                details.push(format!("status {status}"));
            }
            if let Some(observed_status) = &lane.observed_status {
                if lane.status.as_ref() != Some(observed_status) {
                    details.push(format!("observed {observed_status}"));
                }
            }
            if let Some(workspace_name) = &lane.workspace_name {
                details.push(format!("ws {workspace_name}"));
            }
            if let Some(workspace_exists) = lane.workspace_exists {
                details.push(if workspace_exists {
                    "workspace live".to_owned()
                } else {
                    "workspace missing".to_owned()
                });
            }
            if !details.is_empty() {
                lines.push(Line::from(format!("  {}", details.join(" | "))));
            }
        }
    }

    if !snapshot.now.claimed_issues.is_empty() {
        lines.push(Line::from(""));
        lines.push(title_line("waiting claims"));
        for issue in snapshot.now.claimed_issues.iter().take(4) {
            lines.push(Line::from(format!("{} {}", issue.id, issue.title)));
        }
    }

    if !snapshot.now.stale_lanes.is_empty() {
        lines.push(Line::from(""));
        lines.push(title_line("stale lanes"));
        for lane in snapshot.now.stale_lanes.iter().take(3) {
            lines.push(Line::from(format!(
                "{} {}",
                lane.issue_id,
                lane.issue_title
                    .clone()
                    .unwrap_or_else(|| "workspace missing".to_owned())
            )));
        }
    }

    if !snapshot.now.obstructions.is_empty() {
        lines.push(Line::from(""));
        lines.push(title_line("obstructions"));
        for obstruction in snapshot.now.obstructions.iter().take(3) {
            let issue = obstruction
                .issue_id
                .as_deref()
                .map(|value| format!("{value}: "))
                .unwrap_or_default();
            lines.push(Line::from(format!(
                "{}[{}] {}",
                issue, obstruction.kind, obstruction.message
            )));
        }
    }

    lines
}

pub(crate) fn home_next_lines(snapshot: &OperatorSnapshot) -> Vec<Line<'static>> {
    let mut lines = Vec::new();

    lines.push(title_line("primary move"));
    if let Some(action) = &snapshot.next.primary_action {
        lines.push(Line::from(action.message.clone()));
        if let Some(title) = &action.title {
            let subject = action
                .issue_id
                .clone()
                .unwrap_or_else(|| action.kind.clone());
            lines.push(Line::from(format!("{subject} — {title}")));
        }
        if let Some(command) = &action.command {
            lines.push(kv_line("command", command.clone()));
        }
        if !action.rationale.is_empty() {
            lines.push(Line::from(""));
            lines.push(title_line("rationale"));
            for line in action.rationale.iter().take(4) {
                lines.push(Line::from(line.clone()));
            }
        }
        if !action.dependents.is_empty() {
            lines.push(Line::from(""));
            lines.push(title_line("unlocks"));
            for issue in action.dependents.iter().take(4) {
                lines.push(Line::from(operator_issue_ref_label(issue)));
            }
        }
        if !action.dependencies.is_empty() {
            lines.push(Line::from(""));
            lines.push(title_line("upstream"));
            for issue in action.dependencies.iter().take(3) {
                lines.push(Line::from(operator_issue_ref_label(issue)));
            }
        }
    } else {
        lines.push(Line::from("No primary move is selected right now."));
    }

    lines.push(Line::from(""));
    lines.push(kv_line("ready", snapshot.next.counts.ready_issues.to_string()));
    lines.push(kv_line("blocked", snapshot.next.counts.blocked_issues.to_string()));
    lines.push(kv_line("deferred", snapshot.next.counts.deferred_issues.to_string()));

    lines.push(Line::from(""));
    lines.push(title_line("ready queue"));
    if snapshot.next.ready_issues.is_empty() {
        lines.push(Line::from("none"));
    } else {
        for issue in snapshot.next.ready_issues.iter().take(4) {
            lines.push(Line::from(format!("{} {}", issue.id, issue.title)));
        }
    }

    if !snapshot.next.blocked_issues.is_empty() {
        lines.push(Line::from(""));
        lines.push(title_line("blocked"));
        for issue in snapshot.next.blocked_issues.iter().take(3) {
            lines.push(Line::from(format!("{} {}", issue.id, issue.title)));
        }
    }

    if !snapshot.next.deferred_issues.is_empty() {
        lines.push(Line::from(""));
        lines.push(title_line("deferred"));
        for issue in snapshot.next.deferred_issues.iter().take(2) {
            lines.push(Line::from(format!("{} {}", issue.id, issue.title)));
        }
    }

    lines
}

pub(crate) fn home_history_lines(snapshot: &OperatorSnapshot) -> Vec<Line<'static>> {
    let mut lines = vec![
        kv_line(
            "recent",
            snapshot.history.counts.recent_transitions.to_string(),
        ),
        kv_line(
            "available",
            snapshot.history.counts.available_receipts.to_string(),
        ),
        Line::from(""),
        title_line("recent transitions"),
    ];

    if !snapshot.history.narrative.is_empty() {
        for item in snapshot.history.narrative.iter().take(8) {
            lines.push(Line::from(item.clone()));
        }
        return lines;
    }

    if snapshot.history.recent_transitions.is_empty() {
        lines.push(Line::from("none"));
        return lines;
    }

    for receipt in &snapshot.history.recent_transitions {
        lines.push(Line::from(operator_receipt_label(receipt)));
    }

    lines
}

pub(crate) fn home_context_lines(snapshot: &OperatorSnapshot) -> Vec<Line<'static>> {
    let repo_name = Path::new(&snapshot.context.repo_root)
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or(&snapshot.context.repo_root)
        .to_owned();
    let mut lines = vec![
        kv_line("repo", repo_name),
        kv_line("mode", snapshot.context.service.mode.clone()),
        kv_line("workspaces", snapshot.context.counts.workspaces.to_string()),
    ];

    if let Some(endpoint) = &snapshot.context.backend_endpoint {
        let host = endpoint
            .host
            .clone()
            .unwrap_or_else(|| "127.0.0.1".to_owned());
        let port = endpoint
            .port
            .map(|value| value.to_string())
            .unwrap_or_else(|| "unknown".to_owned());
        lines.push(kv_line("backend", format!("{host}:{port}")));
    }

    let root_alignment = if snapshot.context.checkout_root == snapshot.context.tracker_root {
        "checkout and tracker roots are aligned".to_owned()
    } else {
        format!(
            "checkout {} | tracker {}",
            snapshot.context.checkout_root, snapshot.context.tracker_root
        )
    };
    lines.push(Line::from(root_alignment));

    if let Some(summary) = &snapshot.context.summary {
        lines.push(Line::from(""));
        lines.push(title_line("summary"));
        lines.extend(summary_lines(summary));
    }

    lines.push(Line::from(""));
    lines.push(title_line("workspaces"));
    if snapshot.context.workspaces.is_empty() {
        lines.push(Line::from("none"));
    } else {
        for workspace in snapshot.context.workspaces.iter().take(4) {
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
            let suffix = if details.is_empty() {
                description
            } else {
                format!("{} ({})", description, details.join(" | "))
            };
            lines.push(Line::from(format!("{} {}", workspace.name, suffix)));
        }
    }

    lines
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
    let detail = receipt
        .details
        .as_ref()
        .and_then(Value::as_object)
        .map(|object| {
            let keys = object.keys().cloned().collect::<Vec<_>>();
            if keys.is_empty() {
                String::new()
            } else {
                format!(" ({})", keys.join(","))
            }
        })
        .unwrap_or_default();

    format!("{timestamp} {kind}{issue}{detail}")
}

fn operator_issue_ref_label(issue: &OperatorIssueRef) -> String {
    let title = issue.title.clone().unwrap_or_else(|| issue.id.clone());
    let mut suffix = Vec::new();
    if let Some(status) = &issue.status {
        suffix.push(status.clone());
    }
    if let Some(dependency_type) = &issue.dependency_type {
        suffix.push(dependency_type.clone());
    }
    if suffix.is_empty() {
        title
    } else {
        format!("{title} ({})", suffix.join(" | "))
    }
}

#[cfg(test)]
mod tests {
    use super::{
        home_context_lines, home_history_lines, home_next_lines, home_now_lines,
    };
    use crate::types::sample_operator_snapshot;

    #[test]
    fn home_now_lines_surface_live_and_stale_state() {
        let rendered = home_now_lines(&sample_operator_snapshot())
            .into_iter()
            .map(|line| line.to_string())
            .collect::<Vec<_>>()
            .join("\n");

        assert!(rendered.contains("Launch tusk-ready next."));
        assert!(rendered.contains("focus"));
        assert!(rendered.contains("ready issue"));
        assert!(rendered.contains("why now"));
    }

    #[test]
    fn home_context_lines_surface_workspace_and_backend_context() {
        let rendered = home_context_lines(&sample_operator_snapshot())
            .into_iter()
            .map(|line| line.to_string())
            .collect::<Vec<_>>()
            .join("\n");

        assert!(rendered.contains("repo"));
        assert!(rendered.contains("127.0.0.1:32642"));
        assert!(rendered.contains("default"));
        assert!(rendered.contains("abc123"));
    }

    #[test]
    fn home_next_lines_surface_primary_action_and_dependency_context() {
        let rendered = home_next_lines(&sample_operator_snapshot())
            .into_iter()
            .map(|line| line.to_string())
            .collect::<Vec<_>>()
            .join("\n");

        assert!(rendered.contains("primary move"));
        assert!(rendered.contains("Claim tusk-ready next."));
        assert!(rendered.contains("child issue"));
        assert!(rendered.contains("parent issue"));
    }

    #[test]
    fn home_history_lines_prefer_humanized_narrative() {
        let rendered = home_history_lines(&sample_operator_snapshot())
            .into_iter()
            .map(|line| line.to_string())
            .collect::<Vec<_>>()
            .join("\n");

        assert!(rendered.contains("1m ago: claimed tusk-ready"));
    }
}
