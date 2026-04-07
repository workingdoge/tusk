use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Paragraph, Wrap};
use ratatui::{Frame, layout::Rect};

use crate::app::{App, LaneGroup, ViewMode, lane_group};
use crate::theme::{error_lines, kv_line, pane_block, title_line};
use crate::types::{BoardIssue, BoardStatus, BoardSummary, LaneEntry};

pub(crate) fn render_board(frame: &mut Frame, area: Rect, app: &App) {
    let block = pane_block("Board", app.view == ViewMode::Board);
    let lines = match (&app.board.value, &app.board.error) {
        (Some(board), _) => board_lines(board, app.selected_board_item_id.as_deref()),
        (_, Some(error)) => error_lines(error),
        _ => vec![Line::from("waiting for board data")],
    };

    frame.render_widget(
        Paragraph::new(lines)
            .block(block)
            .wrap(Wrap { trim: false }),
        area,
    );
}

pub(crate) fn board_lines(
    board: &BoardStatus,
    selected_board_item_id: Option<&str>,
) -> Vec<Line<'static>> {
    let mut lines = vec![
        kv_line("repo", board.repo_root.clone()),
        kv_line("updated", board.generated_at.clone()),
    ];

    if let Some(summary) = &board.summary {
        lines.push(Line::from(""));
        lines.push(title_line("summary"));
        lines.extend(summary_lines(summary));
    }

    lines.push(Line::from(""));
    append_issue_section(
        &mut lines,
        "ready issues",
        &board.ready_issues,
        selected_board_item_id,
    );

    lines.push(Line::from(""));
    append_issue_section(
        &mut lines,
        "claimed issues",
        &board.claimed_issues,
        selected_board_item_id,
    );

    lines.push(Line::from(""));
    append_issue_section(&mut lines, "blocked issues", &board.blocked_issues, None);

    lines.push(Line::from(""));
    append_issue_section(&mut lines, "deferred issues", &board.deferred_issues, None);

    lines.push(Line::from(""));
    lines.push(title_line("lanes"));
    lines.extend(lane_lines(&board.lanes, selected_board_item_id));

    lines.push(Line::from(""));
    lines.push(title_line("workspaces"));
    if board.workspaces.is_empty() {
        lines.push(Line::from("none"));
    } else {
        lines.extend(board.workspaces.iter().take(6).cloned().map(Line::from));
    }

    lines
}

fn append_issue_section(
    lines: &mut Vec<Line<'static>>,
    title: &str,
    issues: &[BoardIssue],
    selected_issue_id: Option<&str>,
) {
    lines.push(title_line(title));

    if issues.is_empty() {
        lines.push(Line::from("none"));
        return;
    }

    for issue in issues {
        lines.push(issue_line(issue, selected_issue_id));
    }
}

fn issue_line(issue: &BoardIssue, selected_issue_id: Option<&str>) -> Line<'static> {
    let suffix = issue
        .status
        .as_deref()
        .map(|status| format!(" [{status}]"))
        .unwrap_or_default();
    let selected = selected_issue_id == Some(issue.id.as_str());
    let prefix = if selected { "> " } else { "  " };
    let text = format!("{}{} {}{}", prefix, issue.id, issue.title, suffix);
    let style = if selected {
        Style::default()
            .fg(Color::Cyan)
            .add_modifier(Modifier::BOLD)
    } else {
        Style::default()
    };

    Line::from(Span::styled(text, style))
}

pub(crate) fn summary_lines(summary: &BoardSummary) -> Vec<Line<'static>> {
    vec![
        kv_line(
            "total",
            summary.total_issues.unwrap_or_default().to_string(),
        ),
        kv_line("open", summary.open_issues.unwrap_or_default().to_string()),
        kv_line(
            "in progress",
            summary.in_progress_issues.unwrap_or_default().to_string(),
        ),
        kv_line(
            "ready",
            summary.ready_issues.unwrap_or_default().to_string(),
        ),
        kv_line(
            "blocked",
            summary.blocked_issues.unwrap_or_default().to_string(),
        ),
        kv_line(
            "deferred",
            summary.deferred_issues.unwrap_or_default().to_string(),
        ),
        kv_line(
            "closed",
            summary.closed_issues.unwrap_or_default().to_string(),
        ),
    ]
}

fn lane_lines(lanes: &[LaneEntry], selected_board_item_id: Option<&str>) -> Vec<Line<'static>> {
    if lanes.is_empty() {
        return vec![Line::from("none")];
    }

    let mut active = Vec::new();
    let mut finished = Vec::new();
    let mut stale = Vec::new();

    let mut ordered = lanes.to_vec();
    ordered.sort_by(|left, right| left.issue_id.cmp(&right.issue_id));

    for lane in ordered {
        match lane_group(&lane) {
            LaneGroup::Active => active.push(lane),
            LaneGroup::Finished => finished.push(lane),
            LaneGroup::Stale => stale.push(lane),
        }
    }

    let mut lines = Vec::new();
    if !active.is_empty() {
        append_lane_section(&mut lines, "active lanes", &active, selected_board_item_id);
    }
    if !finished.is_empty() {
        if !lines.is_empty() {
            lines.push(Line::from(""));
        }
        append_lane_section(&mut lines, "finished lanes", &finished, None);
    }
    if !stale.is_empty() {
        if !lines.is_empty() {
            lines.push(Line::from(""));
        }
        append_lane_section(&mut lines, "stale lanes", &stale, None);
    }
    lines
}

fn append_lane_section(
    lines: &mut Vec<Line<'static>>,
    title: &str,
    lanes: &[LaneEntry],
    selected_issue_id: Option<&str>,
) {
    lines.push(title_line(title));

    if lanes.is_empty() {
        lines.push(Line::from("none"));
        return;
    }

    for lane in lanes {
        let mut detail_parts = vec![format!("status {}", lane.status)];
        let selected = selected_issue_id == Some(lane.issue_id.as_str());
        let prefix = if selected { "> " } else { "  " };
        let style = if selected {
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD)
        } else {
            Style::default()
        };
        if let Some(observed_status) = &lane.observed_status {
            if observed_status != &lane.status {
                detail_parts.push(format!("observed {}", observed_status));
            }
        }
        if let Some(outcome) = &lane.outcome {
            detail_parts.push(format!("outcome {}", outcome));
        }
        detail_parts.push(if lane.workspace_exists.unwrap_or(false) {
            "workspace live".to_owned()
        } else {
            "workspace missing".to_owned()
        });

        lines.push(Line::from(Span::styled(
            format!("{}{} {}", prefix, lane.issue_id, lane.issue_title),
            style,
        )));
        lines.push(Line::from(format!("  {}", detail_parts.join(" | "))));

        if let Some(workspace_name) = &lane.workspace_name {
            lines.push(Line::from(format!("  ws {}", workspace_name)));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::board_lines;
    use crate::types::{BoardIssue, BoardStatus, LaneEntry};

    #[test]
    fn board_lines_include_ready_issue_titles() {
        let board = BoardStatus {
            repo_root: "/tmp/repo".to_owned(),
            generated_at: "2026-03-26T00:00:00Z".to_owned(),
            summary: Some(crate::types::BoardSummary {
                total_issues: Some(10),
                open_issues: Some(2),
                in_progress_issues: Some(1),
                closed_issues: Some(7),
                blocked_issues: Some(1),
                deferred_issues: Some(0),
                ready_issues: Some(1),
            }),
            ready_issues: vec![BoardIssue {
                id: "tusk-demo".to_owned(),
                title: "demo ready issue".to_owned(),
                status: Some("open".to_owned()),
            }],
            claimed_issues: vec![],
            blocked_issues: vec![],
            deferred_issues: vec![],
            lanes: vec![],
            workspaces: vec!["default".to_owned()],
        };

        let rendered = board_lines(&board, None)
            .into_iter()
            .map(|line| line.to_string())
            .collect::<Vec<_>>()
            .join("\n");

        assert!(rendered.contains("demo ready issue"));
        assert!(rendered.contains("default"));
    }

    #[test]
    fn board_lines_include_claimed_blocked_and_deferred_sections() {
        let board = BoardStatus {
            repo_root: "/tmp/repo".to_owned(),
            generated_at: "2026-03-26T00:00:00Z".to_owned(),
            summary: None,
            ready_issues: vec![],
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
            deferred_issues: vec![BoardIssue {
                id: "tusk-deferred".to_owned(),
                title: "deferred issue".to_owned(),
                status: Some("deferred".to_owned()),
            }],
            lanes: vec![],
            workspaces: vec![],
        };

        let rendered = board_lines(&board, None)
            .into_iter()
            .map(|line| line.to_string())
            .collect::<Vec<_>>()
            .join("\n");

        assert!(rendered.contains("claimed issues"));
        assert!(rendered.contains("blocked issues"));
        assert!(rendered.contains("deferred issues"));
        assert!(rendered.contains("tusk-claim claimed issue [in_progress]"));
        assert!(rendered.contains("tusk-blocked blocked issue [open]"));
        assert!(rendered.contains("tusk-deferred deferred issue [deferred]"));
    }

    #[test]
    fn board_lines_include_lane_groups_and_outcomes() {
        let board = BoardStatus {
            repo_root: "/tmp/repo".to_owned(),
            generated_at: "2026-03-26T00:00:00Z".to_owned(),
            summary: None,
            ready_issues: vec![],
            claimed_issues: vec![],
            blocked_issues: vec![],
            deferred_issues: vec![],
            lanes: vec![
                LaneEntry {
                    issue_id: "tusk-live".to_owned(),
                    issue_title: "live lane".to_owned(),
                    status: "handoff".to_owned(),
                    observed_status: Some("handoff".to_owned()),
                    workspace_exists: Some(true),
                    outcome: None,
                    workspace_name: Some("tusk-live-lane".to_owned()),
                },
                LaneEntry {
                    issue_id: "tusk-done".to_owned(),
                    issue_title: "finished lane".to_owned(),
                    status: "finished".to_owned(),
                    observed_status: Some("finished".to_owned()),
                    workspace_exists: Some(false),
                    outcome: Some("completed".to_owned()),
                    workspace_name: Some("tusk-done-lane".to_owned()),
                },
                LaneEntry {
                    issue_id: "tusk-stale".to_owned(),
                    issue_title: "stale lane".to_owned(),
                    status: "handoff".to_owned(),
                    observed_status: Some("stale".to_owned()),
                    workspace_exists: Some(false),
                    outcome: None,
                    workspace_name: Some("tusk-stale-lane".to_owned()),
                },
            ],
            workspaces: vec![],
        };

        let rendered = board_lines(&board, None)
            .into_iter()
            .map(|line| line.to_string())
            .collect::<Vec<_>>()
            .join("\n");

        assert!(rendered.contains("active lanes"));
        assert!(rendered.contains("finished lanes"));
        assert!(rendered.contains("stale lanes"));
        assert!(rendered.contains("tusk-live live lane"));
        assert!(rendered.contains("status handoff"));
        assert!(rendered.contains("workspace live"));
        assert!(rendered.contains("tusk-done finished lane"));
        assert!(rendered.contains("outcome completed"));
        assert!(rendered.contains("workspace missing"));
        assert!(rendered.contains("tusk-stale stale lane"));
        assert!(rendered.contains("observed stale"));
    }

    #[test]
    fn board_lines_mark_selected_actionable_issue() {
        let board = BoardStatus {
            repo_root: "/tmp/repo".to_owned(),
            generated_at: "2026-03-26T00:00:00Z".to_owned(),
            summary: None,
            ready_issues: vec![
                BoardIssue {
                    id: "tusk-a".to_owned(),
                    title: "first ready issue".to_owned(),
                    status: Some("open".to_owned()),
                },
                BoardIssue {
                    id: "tusk-b".to_owned(),
                    title: "second ready issue".to_owned(),
                    status: Some("open".to_owned()),
                },
            ],
            claimed_issues: vec![],
            blocked_issues: vec![],
            deferred_issues: vec![],
            lanes: vec![],
            workspaces: vec![],
        };

        let rendered = board_lines(&board, Some("tusk-b"))
            .into_iter()
            .map(|line| line.to_string())
            .collect::<Vec<_>>()
            .join("\n");

        assert!(rendered.contains("> tusk-b second ready issue [open]"));
        assert!(rendered.contains("  tusk-a first ready issue [open]"));
    }

    #[test]
    fn board_lines_mark_selected_claimed_issue() {
        let board = BoardStatus {
            repo_root: "/tmp/repo".to_owned(),
            generated_at: "2026-03-26T00:00:00Z".to_owned(),
            summary: None,
            ready_issues: vec![BoardIssue {
                id: "tusk-a".to_owned(),
                title: "first ready issue".to_owned(),
                status: Some("open".to_owned()),
            }],
            claimed_issues: vec![BoardIssue {
                id: "tusk-b".to_owned(),
                title: "claimed issue".to_owned(),
                status: Some("in_progress".to_owned()),
            }],
            blocked_issues: vec![],
            deferred_issues: vec![],
            lanes: vec![],
            workspaces: vec![],
        };

        let rendered = board_lines(&board, Some("tusk-b"))
            .into_iter()
            .map(|line| line.to_string())
            .collect::<Vec<_>>()
            .join("\n");

        assert!(rendered.contains("> tusk-b claimed issue [in_progress]"));
        assert!(rendered.contains("  tusk-a first ready issue [open]"));
    }

    #[test]
    fn board_lines_mark_selected_active_lane() {
        let board = BoardStatus {
            repo_root: "/tmp/repo".to_owned(),
            generated_at: "2026-03-26T00:00:00Z".to_owned(),
            summary: None,
            ready_issues: vec![],
            claimed_issues: vec![],
            blocked_issues: vec![],
            deferred_issues: vec![],
            lanes: vec![LaneEntry {
                issue_id: "tusk-live".to_owned(),
                issue_title: "live lane".to_owned(),
                status: "launched".to_owned(),
                observed_status: Some("launched".to_owned()),
                workspace_exists: Some(true),
                outcome: None,
                workspace_name: Some("tusk-live-lane".to_owned()),
            }],
            workspaces: vec![],
        };

        let rendered = board_lines(&board, Some("tusk-live"))
            .into_iter()
            .map(|line| line.to_string())
            .collect::<Vec<_>>()
            .join("\n");

        assert!(rendered.contains("> tusk-live live lane"));
    }
}
