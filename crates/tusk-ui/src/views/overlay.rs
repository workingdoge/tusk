use ratatui::Frame;
use ratatui::layout::{Alignment, Constraint, Direction, Flex, Layout, Rect};
use ratatui::text::Line;
use ratatui::widgets::{Clear, Paragraph, Wrap};

use crate::app::App;
use crate::theme::{muted_style, overlay_block};
use crate::viewmodel::{IssueInspectViewModel, IssueRef, Source};

pub(crate) fn render_overlay(frame: &mut Frame, area: Rect, app: &App) {
    let Some(overlay) = app.overlay() else {
        return;
    };

    let popup = centered_rect(area, overlay.body.len() as u16 + 4);
    frame.render_widget(Clear, popup);

    let mut lines = overlay
        .body
        .iter()
        .cloned()
        .map(Line::from)
        .collect::<Vec<_>>();
    lines.push(Line::from(""));
    lines.push(Line::from(ratatui::text::Span::styled(
        overlay.footer_hint(),
        muted_style(),
    )));

    frame.render_widget(
        Paragraph::new(lines)
            .alignment(Alignment::Left)
            .block(overlay_block(&overlay.title))
            .wrap(Wrap { trim: false }),
        popup,
    );
}

pub(crate) fn issue_inspection_lines(model: &IssueInspectViewModel) -> Vec<String> {
    let mut lines = vec![
        format!("fact: {} — {}", model.issue_id, model.title),
        format!("fact: repo {}", model.repo_root),
    ];

    let mut meta = Vec::new();
    if let Some(status) = &model.status {
        meta.push(format!("status {status}"));
    }
    if let Some(issue_type) = &model.issue_type {
        meta.push(format!("type {issue_type}"));
    }
    if let Some(priority) = &model.priority {
        meta.push(format!("priority {priority}"));
    }
    if let Some(parent) = &model.parent {
        meta.push(format!("parent {parent}"));
    }
    if let Some(created_at) = &model.created_at {
        meta.push(format!("created {created_at}"));
    }
    if let Some(updated_at) = &model.updated_at {
        meta.push(format!("updated {updated_at}"));
    }
    if let Some(closed_at) = &model.closed_at {
        meta.push(format!("closed {closed_at}"));
    }
    if !meta.is_empty() {
        lines.push(format!("fact: {}", meta.join(" | ")));
    }

    lines.push(format!(
        "fact: upstream {} | downstream {}",
        model.dependency_count, model.dependent_count
    ));

    if let Some(action) = &model.recommendation {
        lines.push(String::new());
        lines.push(source_line(
            &action.source,
            format!("current recommendation: {}", action.message),
        ));
        if !action.rationale.is_empty() {
            for line in action.rationale.iter().take(3) {
                lines.push(source_line(&action.source, line.clone()));
            }
        }
    } else if !model.focus_rationale.is_empty() {
        lines.push(String::new());
        lines.push(source_line(
            &Source::Heuristic,
            "current focus rationale".to_owned(),
        ));
        for line in model.focus_rationale.iter().take(3) {
            lines.push(source_line(&Source::Heuristic, line.clone()));
        }
    }

    lines.push(String::new());
    lines.push("authoritative dependency context".to_owned());
    if model.dependencies.is_empty() {
        lines.push("  upstream: none".to_owned());
    } else {
        lines.push("  upstream".to_owned());
        for issue in model.dependencies.iter().take(4) {
            lines.push(format!("    {}", issue_ref_label(issue)));
        }
    }
    if model.dependents.is_empty() {
        lines.push("  downstream: none".to_owned());
    } else {
        lines.push("  downstream".to_owned());
        for issue in model.dependents.iter().take(4) {
            lines.push(format!("    {}", issue_ref_label(issue)));
        }
    }

    lines.push(String::new());
    lines.push("authoritative runtime".to_owned());
    match &model.lane {
        Some(lane) => {
            if let Some(issue_title) = &lane.issue_title {
                lines.push(format!("  {} — {}", lane.issue_id, issue_title));
            }
            let mut detail = vec![format!("status {}", lane.status)];
            if let Some(observed_status) = &lane.observed_status {
                if observed_status != &lane.status {
                    detail.push(format!("observed {observed_status}"));
                }
            }
            if let Some(base_rev) = &lane.base_rev {
                detail.push(format!("base {base_rev}"));
            }
            if let Some(revision) = &lane.revision {
                detail.push(format!("rev {revision}"));
            }
            lines.push(format!("  {}", detail.join(" | ")));
            if let Some(workspace_name) = &lane.workspace_name {
                let exists = lane
                    .workspace_exists
                    .map(|value| if value { "live" } else { "missing" })
                    .unwrap_or("unknown");
                lines.push(format!("  workspace {} ({exists})", workspace_name));
            }
            if let Some(workspace_path) = &lane.workspace_path {
                lines.push(format!("  path {workspace_path}"));
            }
            if let Some(created_at) = &lane.created_at {
                lines.push(format!("  created {created_at}"));
            }
            if let Some(updated_at) = &lane.updated_at {
                lines.push(format!("  updated {updated_at}"));
            }
            if let Some(handoff_at) = &lane.handoff_at {
                lines.push(format!("  handoff {handoff_at}"));
            }
            if let Some(finished_at) = &lane.finished_at {
                lines.push(format!("  finished {finished_at}"));
            }
            if let Some(note) = &lane.note {
                lines.push(format!("  note {note}"));
            }
        }
        None => lines.push("  no lane is currently recorded for this issue".to_owned()),
    }

    lines.push(String::new());
    lines.push(format!(
        "authoritative receipts ({})",
        model.available_receipts.max(model.recent_receipts.len() as u64)
    ));
    if model.recent_receipts.is_empty() {
        lines.push("  none".to_owned());
    } else {
        for receipt in model.recent_receipts.iter().take(5) {
            lines.push(format!("  {}", receipt.narrative));
            if let Some(consequence) = &receipt.consequence {
                lines.push(format!("    detail {consequence}"));
            }
        }
    }

    lines
}

fn centered_rect(area: Rect, desired_height: u16) -> Rect {
    let height = desired_height
        .max(8)
        .min(area.height.saturating_sub(2).max(8));
    let width = area.width.saturating_sub(8).clamp(56, 72);

    let vertical = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage(20),
            Constraint::Length(height),
            Constraint::Percentage(20),
        ])
        .flex(Flex::Center)
        .split(area);
    Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Min(0),
            Constraint::Length(width),
            Constraint::Min(0),
        ])
        .flex(Flex::Center)
        .split(vertical[1])[1]
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

fn source_line(source: &Source, text: String) -> String {
    let prefix = match source {
        Source::Authoritative => "fact",
        Source::Heuristic => "heuristic",
        Source::Enriched => "enriched",
    };
    format!("{prefix}: {text}")
}
