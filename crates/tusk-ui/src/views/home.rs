use ratatui::Frame;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::text::Line;
use ratatui::widgets::{Paragraph, Wrap};

use crate::app::App;
use crate::theme::{error_lines, kv_line, pane_block, title_line};
use crate::viewmodel::{ContextAnomaly, HistoryItem, HomeViewModel, IssueRef};

use super::board::summary_lines;
use super::{panel_title, prepend_panel_notice, render_lines_panel};

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

    match (app.home_viewmodel(), &app.home.error) {
        (Some(home), _) => {
            let mut now_lines = home_now_lines(&home);
            prepend_panel_notice(&mut now_lines, &app.home);
            render_lines_panel(
                frame,
                top[0],
                panel_title("Now", &app.home, app.refresh_interval()),
                now_lines,
                false,
            );

            render_lines_panel(
                frame,
                top[1],
                panel_title("Next", &app.home, app.refresh_interval()),
                home_next_lines(&home),
                false,
            );

            render_lines_panel(
                frame,
                bottom[0],
                panel_title("History", &app.home, app.refresh_interval()),
                home_history_lines(&home),
                false,
            );

            render_lines_panel(
                frame,
                bottom[1],
                panel_title("Context", &app.home, app.refresh_interval()),
                home_context_lines(&home),
                false,
            );
        }
        (_, Some(error)) => {
            render_lines_panel(
                frame,
                area,
                panel_title("Home", &app.home, app.refresh_interval()),
                error_lines(error),
                false,
            );
        }
        _ => {
            frame.render_widget(
                Paragraph::new(vec![Line::from("waiting for operator snapshot")])
                    .block(pane_block(
                        panel_title("Home", &app.home, app.refresh_interval()),
                        false,
                    ))
                    .wrap(Wrap { trim: false }),
                area,
            );
        }
    }
}

pub(crate) fn home_now_lines(snapshot: &HomeViewModel) -> Vec<Line<'static>> {
    let mut lines = vec![
        title_line(snapshot.headline.clone()),
        Line::from(snapshot.summary.clone()),
        kv_line("updated", snapshot.updated_at.clone()),
    ];

    if let Some(focus) = &snapshot.focus {
        lines.push(Line::from(""));
        lines.push(title_line("focus"));
        lines.push(Line::from(format!("{} {}", focus.issue_id, focus.title)));
        let mut meta = Vec::new();
        if let Some(status) = &focus.status {
            meta.push(format!("status {status}"));
        }
        if let Some(parent) = &focus.parent {
            meta.push(format!("parent {parent}"));
        }
        if !focus.unlocks.is_empty() {
            meta.push(format!("unlocks {}", focus.unlocks.len()));
        }
        if !focus.blockers.is_empty() {
            meta.push(format!("upstream {}", focus.blockers.len()));
        }
        if !meta.is_empty() {
            lines.push(Line::from(format!("  {}", meta.join(" | "))));
        }
    }

    if snapshot
        .focus
        .as_ref()
        .is_some_and(|focus| !focus.rationale.is_empty())
    {
        lines.push(Line::from(""));
        lines.push(title_line("why now"));
        for line in snapshot
            .focus
            .as_ref()
            .into_iter()
            .flat_map(|focus| focus.rationale.iter())
            .take(4)
        {
            lines.push(Line::from(line.clone()));
        }
    }

    if !snapshot.active_lanes.is_empty() {
        lines.push(Line::from(""));
        lines.push(title_line("live lanes"));
        for lane in snapshot.active_lanes.iter().take(4) {
            lines.push(Line::from(format!("{} {}", lane.issue_id, lane.title)));
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

    if !snapshot.claimed.is_empty() {
        lines.push(Line::from(""));
        lines.push(title_line("waiting claims"));
        for issue in snapshot.claimed.iter().take(4) {
            lines.push(Line::from(format!("{} {}", issue.id, issue.title)));
        }
    }

    if !snapshot.stale.is_empty() {
        lines.push(Line::from(""));
        lines.push(title_line("stale lanes"));
        for lane in snapshot.stale.iter().take(3) {
            lines.push(Line::from(format!("{} {}", lane.issue_id, lane.title)));
        }
    }

    if !snapshot.obstructions.is_empty() {
        lines.push(Line::from(""));
        lines.push(title_line("obstructions"));
        for obstruction in snapshot.obstructions.iter().take(3) {
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

pub(crate) fn home_next_lines(snapshot: &HomeViewModel) -> Vec<Line<'static>> {
    let mut lines = Vec::new();

    lines.push(title_line("primary move"));
    if let Some(action) = &snapshot.primary_action {
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
        if let Some(narrative) = &action.narrative {
            if !narrative.unlocks.is_empty() {
                lines.push(Line::from(""));
                lines.push(title_line("unlocks"));
                for issue in narrative.unlocks.iter().take(4) {
                    lines.push(Line::from(issue_ref_label(issue)));
                }
            }
            if !narrative.blockers.is_empty() {
                lines.push(Line::from(""));
                lines.push(title_line("upstream"));
                for issue in narrative.blockers.iter().take(3) {
                    lines.push(Line::from(issue_ref_label(issue)));
                }
            }
        }
    } else {
        lines.push(Line::from("No primary move is selected right now."));
    }

    lines.push(Line::from(""));
    lines.push(kv_line("ready", snapshot.ready_queue.len().to_string()));
    lines.push(kv_line("blocked", snapshot.blocked_queue.len().to_string()));
    lines.push(kv_line(
        "deferred",
        snapshot.deferred_queue.len().to_string(),
    ));

    lines.push(Line::from(""));
    lines.push(title_line("ready queue"));
    if snapshot.ready_queue.is_empty() {
        lines.push(Line::from("none"));
    } else {
        for issue in snapshot.ready_queue.iter().take(4) {
            lines.push(Line::from(format!("{} {}", issue.id, issue.title)));
        }
    }

    if !snapshot.blocked_queue.is_empty() {
        lines.push(Line::from(""));
        lines.push(title_line("blocked"));
        for issue in snapshot.blocked_queue.iter().take(3) {
            lines.push(Line::from(format!("{} {}", issue.id, issue.title)));
        }
    }

    if !snapshot.deferred_queue.is_empty() {
        lines.push(Line::from(""));
        lines.push(title_line("deferred"));
        for issue in snapshot.deferred_queue.iter().take(2) {
            lines.push(Line::from(format!("{} {}", issue.id, issue.title)));
        }
    }

    lines
}

pub(crate) fn home_history_lines(snapshot: &HomeViewModel) -> Vec<Line<'static>> {
    let mut lines = vec![
        kv_line("recent", snapshot.recent_count.to_string()),
        kv_line("available", snapshot.available_receipts.to_string()),
        Line::from(""),
        title_line("recent transitions"),
    ];

    if snapshot.history.is_empty() {
        lines.push(Line::from("none"));
        return lines;
    }

    for item in snapshot.history.iter().take(8) {
        lines.push(Line::from(history_label(item)));
    }

    lines
}

pub(crate) fn home_context_lines(snapshot: &HomeViewModel) -> Vec<Line<'static>> {
    let mut lines = vec![
        kv_line("repo", snapshot.context.repo_name.clone()),
        kv_line("mode", snapshot.context.mode.clone()),
        kv_line("workspaces", snapshot.context.workspace_count.to_string()),
    ];

    if let Some(backend) = &snapshot.context.backend {
        lines.push(kv_line("backend", backend.clone()));
    }

    if snapshot.context.anomalies.is_empty() {
        lines.push(Line::from("checkout and tracker roots are aligned"));
    } else {
        for anomaly in &snapshot.context.anomalies {
            match anomaly {
                ContextAnomaly::RootMismatch { checkout, tracker } => {
                    lines.push(Line::from(format!(
                        "checkout {} | tracker {}",
                        checkout, tracker
                    )));
                }
                ContextAnomaly::BackendUnhealthy { message } => {
                    lines.push(Line::from(message.clone()));
                }
                ContextAnomaly::StaleWorkspaces { count } => {
                    lines.push(Line::from(format!("{count} stale workspaces")));
                }
            }
        }
    }

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
            let suffix = if workspace.details.is_empty() {
                workspace.description.clone()
            } else {
                format!(
                    "{} ({})",
                    workspace.description,
                    workspace.details.join(" | ")
                )
            };
            lines.push(Line::from(format!("{} {}", workspace.name, suffix)));
        }
    }

    lines
}

fn history_label(item: &HistoryItem) -> String {
    item.narrative.clone()
}

fn issue_ref_label(issue: &IssueRef) -> String {
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
    use super::{home_context_lines, home_history_lines, home_next_lines, home_now_lines};
    use crate::types::sample_operator_snapshot;
    use crate::viewmodel::home_viewmodel;

    #[test]
    fn home_now_lines_surface_live_and_stale_state() {
        let rendered = home_now_lines(&home_viewmodel(&sample_operator_snapshot()))
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
        let rendered = home_context_lines(&home_viewmodel(&sample_operator_snapshot()))
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
        let rendered = home_next_lines(&home_viewmodel(&sample_operator_snapshot()))
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
        let rendered = home_history_lines(&home_viewmodel(&sample_operator_snapshot()))
            .into_iter()
            .map(|line| line.to_string())
            .collect::<Vec<_>>()
            .join("\n");

        assert!(rendered.contains("1m ago: claimed tusk-ready"));
    }
}
