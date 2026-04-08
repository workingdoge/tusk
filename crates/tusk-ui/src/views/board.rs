use ratatui::text::{Line, Span};
use ratatui::{Frame, layout::Rect};

use super::{panel_title, prepend_panel_notice, render_scrolled_lines_panel};
use crate::app::{App, ViewMode};
use crate::theme::{error_lines, kv_line, selected_item_style, text_style, title_line};
use crate::viewmodel::{BoardViewModel, IssueItem, LaneItem, SummaryView};

pub(crate) fn render_board(frame: &mut Frame, area: Rect, app: &App) {
    let lines = match (app.board_viewmodel(), &app.board.error) {
        (Some(board), _) => {
            let mut lines = board_lines(&board);
            prepend_panel_notice(&mut lines, &app.board);
            lines
        }
        (_, Some(error)) => error_lines(error),
        _ => vec![Line::from("waiting for board data")],
    };

    render_scrolled_lines_panel(
        frame,
        area,
        panel_title("Board", &app.board, app.refresh_interval()),
        lines,
        app.view == ViewMode::Board,
        app.current_scroll_offset(),
    );
}

pub(crate) fn board_lines(board: &BoardViewModel) -> Vec<Line<'static>> {
    let mut lines = vec![
        kv_line("repo", board.repo_root.clone()),
        kv_line("updated", board.updated_at.clone()),
    ];

    if let Some(summary) = &board.summary {
        lines.push(Line::from(""));
        lines.push(title_line("summary"));
        lines.extend(summary_lines(summary));
    }

    lines.push(Line::from(""));
    append_issue_section(&mut lines, "ready issues", &board.ready_issues);

    lines.push(Line::from(""));
    append_issue_section(&mut lines, "claimed issues", &board.claimed_issues);

    lines.push(Line::from(""));
    append_issue_section(&mut lines, "blocked issues", &board.blocked_issues);

    lines.push(Line::from(""));
    append_issue_section(&mut lines, "deferred issues", &board.deferred_issues);

    lines.push(Line::from(""));
    lines.push(title_line("lanes"));
    lines.extend(lane_lines(board));

    lines.push(Line::from(""));
    lines.push(title_line("workspaces"));
    if board.workspaces.is_empty() {
        lines.push(Line::from("none"));
    } else {
        lines.extend(board.workspaces.iter().take(6).cloned().map(Line::from));
    }

    lines
}

fn append_issue_section(lines: &mut Vec<Line<'static>>, title: &str, issues: &[IssueItem]) {
    lines.push(title_line(title));

    if issues.is_empty() {
        lines.push(Line::from("none"));
        return;
    }

    for issue in issues {
        lines.push(issue_line(issue));
    }
}

fn issue_line(issue: &IssueItem) -> Line<'static> {
    let suffix = issue
        .status
        .as_deref()
        .map(|status| format!(" [{status}]"))
        .unwrap_or_default();
    let prefix = if issue.selected { "> " } else { "  " };
    let text = format!("{}{} {}{}", prefix, issue.id, issue.title, suffix);
    let style = if issue.selected {
        selected_item_style()
    } else {
        text_style()
    };

    Line::from(Span::styled(text, style))
}

pub(crate) fn summary_lines(summary: &SummaryView) -> Vec<Line<'static>> {
    vec![
        kv_line("total", summary.total.to_string()),
        kv_line("open", summary.open.to_string()),
        kv_line("in progress", summary.in_progress.to_string()),
        kv_line("ready", summary.ready.to_string()),
        kv_line("blocked", summary.blocked.to_string()),
        kv_line("deferred", summary.deferred.to_string()),
        kv_line("closed", summary.closed.to_string()),
    ]
}

fn lane_lines(board: &BoardViewModel) -> Vec<Line<'static>> {
    if board.active_lanes.is_empty()
        && board.finished_lanes.is_empty()
        && board.stale_lanes.is_empty()
    {
        return vec![Line::from("none")];
    }

    let mut lines = Vec::new();
    if !board.active_lanes.is_empty() {
        append_lane_section(&mut lines, "active lanes", &board.active_lanes);
    }
    if !board.finished_lanes.is_empty() {
        if !lines.is_empty() {
            lines.push(Line::from(""));
        }
        append_lane_section(&mut lines, "finished lanes", &board.finished_lanes);
    }
    if !board.stale_lanes.is_empty() {
        if !lines.is_empty() {
            lines.push(Line::from(""));
        }
        append_lane_section(&mut lines, "stale lanes", &board.stale_lanes);
    }
    lines
}

fn append_lane_section(lines: &mut Vec<Line<'static>>, title: &str, lanes: &[LaneItem]) {
    lines.push(title_line(title));

    if lanes.is_empty() {
        lines.push(Line::from("none"));
        return;
    }

    for lane in lanes {
        let mut detail_parts = Vec::new();
        if let Some(status) = &lane.status {
            detail_parts.push(format!("status {status}"));
        }
        if let Some(observed_status) = &lane.observed_status {
            if lane.status.as_ref() != Some(observed_status) {
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

        let prefix = if lane.selected { "> " } else { "  " };
        let style = if lane.selected {
            selected_item_style()
        } else {
            text_style()
        };

        lines.push(Line::from(Span::styled(
            format!("{}{} {}", prefix, lane.issue_id, lane.title),
            style,
        )));
        if !detail_parts.is_empty() {
            lines.push(Line::from(format!("  {}", detail_parts.join(" | "))));
        }

        if let Some(workspace_name) = &lane.workspace_name {
            lines.push(Line::from(format!("  ws {}", workspace_name)));
        }
    }
}

pub(crate) fn selected_line_offset(board: &BoardViewModel) -> Option<usize> {
    let mut line = 0usize;
    line += 2;

    if let Some(summary) = &board.summary {
        line += 2 + summary_lines(summary).len();
    }

    if let Some(selected) = selected_issue_line(&board.ready_issues, line + 2) {
        return Some(selected);
    }
    line += 2 + issue_lines_len(&board.ready_issues);

    if let Some(selected) = selected_issue_line(&board.claimed_issues, line + 2) {
        return Some(selected);
    }
    line += 2 + issue_lines_len(&board.claimed_issues);

    if let Some(selected) = selected_issue_line(&board.blocked_issues, line + 2) {
        return Some(selected);
    }
    line += 2 + issue_lines_len(&board.blocked_issues);

    if let Some(selected) = selected_issue_line(&board.deferred_issues, line + 2) {
        return Some(selected);
    }
    line += 2 + issue_lines_len(&board.deferred_issues);

    line += 2;
    if let Some(selected) = selected_lane_line(&board.active_lanes, line) {
        return Some(selected);
    }
    line += lane_section_len(&board.active_lanes, !board.active_lanes.is_empty());
    if !board.active_lanes.is_empty() && !board.finished_lanes.is_empty() {
        line += 1;
    }
    if let Some(selected) = selected_lane_line(&board.finished_lanes, line) {
        return Some(selected);
    }
    line += lane_section_len(&board.finished_lanes, !board.finished_lanes.is_empty());
    if (!board.active_lanes.is_empty() || !board.finished_lanes.is_empty())
        && !board.stale_lanes.is_empty()
    {
        line += 1;
    }
    if let Some(selected) = selected_lane_line(&board.stale_lanes, line) {
        return Some(selected);
    }

    None
}

fn issue_lines_len(issues: &[IssueItem]) -> usize {
    if issues.is_empty() { 1 } else { issues.len() }
}

fn selected_issue_line(issues: &[IssueItem], start: usize) -> Option<usize> {
    issues
        .iter()
        .position(|issue| issue.selected)
        .map(|idx| start + idx)
}

fn lane_section_len(lanes: &[LaneItem], present: bool) -> usize {
    if !present {
        return 0;
    }
    if lanes.is_empty() {
        2
    } else {
        1 + lanes
            .iter()
            .map(|lane| 1 + usize::from(lane.workspace_name.is_some()) + 1)
            .sum::<usize>()
    }
}

fn selected_lane_line(lanes: &[LaneItem], start: usize) -> Option<usize> {
    let mut line = start;
    for lane in lanes {
        if lane.selected {
            return Some(line);
        }
        line += 1;
        line += 1;
        if lane.workspace_name.is_some() {
            line += 1;
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::board_lines;
    use crate::types::{BoardIssue, BoardStatus, LaneEntry};
    use crate::viewmodel::board_viewmodel;

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

        let rendered = board_lines(&board_viewmodel(&board, None, None))
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

        let rendered = board_lines(&board_viewmodel(&board, None, None))
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

        let rendered = board_lines(&board_viewmodel(&board, None, None))
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

        let rendered = board_lines(&board_viewmodel(&board, Some("tusk-b"), None))
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

        let rendered = board_lines(&board_viewmodel(&board, Some("tusk-b"), None))
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

        let rendered = board_lines(&board_viewmodel(&board, Some("tusk-live"), None))
            .into_iter()
            .map(|line| line.to_string())
            .collect::<Vec<_>>()
            .join("\n");

        assert!(rendered.contains("> tusk-live live lane"));
    }
}
