use ratatui::text::Line;
use ratatui::{Frame, layout::Rect};

use crate::app::{App, ViewMode};
use crate::theme::{error_lines, kv_line, title_line};
use crate::viewmodel::{WorkerItem, WorkersViewModel};

use super::{panel_title, prepend_panel_notice, render_scrolled_lines_panel};

pub(crate) fn render_workers(frame: &mut Frame, area: Rect, app: &App) {
    let lines = match (app.workers_viewmodel(), &app.home.error) {
        (Some(workers), _) => {
            let mut lines = workers_lines(&workers);
            prepend_panel_notice(&mut lines, &app.home);
            lines
        }
        (_, Some(error)) => error_lines(error),
        _ => vec![Line::from("waiting for worker sessions")],
    };

    render_scrolled_lines_panel(
        frame,
        area,
        panel_title("Workers", &app.home, app.refresh_interval()),
        lines,
        app.view == ViewMode::Workers,
        app.current_scroll_offset(),
    );
}

pub(crate) fn workers_lines(workers: &WorkersViewModel) -> Vec<Line<'static>> {
    let mut lines = vec![
        kv_line("repo", workers.repo_root.clone()),
        kv_line("updated", workers.updated_at.clone()),
        Line::from(""),
        title_line("summary"),
        kv_line("total", workers.summary.total.to_string()),
        kv_line("active", workers.summary.active.to_string()),
        kv_line("running", workers.summary.running.to_string()),
        kv_line("stale", workers.summary.stale.to_string()),
        kv_line("blocked", workers.summary.blocked.to_string()),
        kv_line("exited", workers.summary.exited.to_string()),
        Line::from(""),
    ];

    append_worker_section(&mut lines, "needs attention", &workers.attention);
    lines.push(Line::from(""));
    append_worker_section(&mut lines, "live sessions", &workers.live);
    lines.push(Line::from(""));
    append_worker_section(&mut lines, "recent exits", &workers.recent_exits);

    lines
}

fn append_worker_section(lines: &mut Vec<Line<'static>>, title: &str, workers: &[WorkerItem]) {
    lines.push(title_line(title));

    if workers.is_empty() {
        lines.push(Line::from("none"));
        return;
    }

    for worker in workers {
        lines.extend(worker_lines(worker));
    }
}

fn worker_lines(worker: &WorkerItem) -> Vec<Line<'static>> {
    let issue = worker.issue_id.as_deref().unwrap_or("detached");
    let issue_title = worker.issue_title.as_deref().unwrap_or(issue);
    let workspace = worker.workspace_name.as_deref().unwrap_or("unknown");

    let mut lines = vec![
        Line::from(format!(
            "{} {} [{}]",
            worker.runtime_kind, worker.id, worker.status
        )),
        Line::from(format!("  issue {} — {}", issue, issue_title)),
        Line::from(format!("  ws {}", workspace)),
    ];

    let mut details = Vec::new();
    if let Some(lane_status) = &worker.lane_status {
        details.push(format!("lane {lane_status}"));
    }
    if let Some(reported_status) = &worker.reported_status {
        details.push(format!("reported {reported_status}"));
    }
    if let Some(pid) = worker.pid {
        let liveness = if worker.pid_live { "live" } else { "dead" };
        details.push(format!("pid {pid} ({liveness})"));
    }
    if let Some(last_seen_at) = &worker.last_seen_at {
        details.push(format!("last seen {last_seen_at}"));
    } else if let Some(heartbeat_at) = &worker.heartbeat_at {
        details.push(format!("heartbeat {heartbeat_at}"));
    }
    if let Some(exit_code) = worker.exit_code {
        details.push(format!("exit {exit_code}"));
    }
    if !details.is_empty() {
        lines.push(Line::from(format!("  {}", details.join(" | "))));
    }

    if !worker.obstructions.is_empty() {
        lines.push(Line::from(format!(
            "  attention {}",
            worker.obstructions.join(" | ")
        )));
    }

    lines.push(Line::from(""));
    lines
}

#[cfg(test)]
mod tests {
    use super::workers_lines;
    use crate::types::sample_operator_snapshot;
    use crate::viewmodel::workers_viewmodel;

    #[test]
    fn workers_lines_surface_attention_and_live_sessions() {
        let rendered = workers_lines(&workers_viewmodel(&sample_operator_snapshot()))
            .into_iter()
            .map(|line| line.to_string())
            .collect::<Vec<_>>()
            .join("\n");

        assert!(rendered.contains("needs attention"));
        assert!(rendered.contains("session-stale"));
        assert!(rendered.contains("heartbeat is stale since 2026-04-07T19:58:00Z"));
        assert!(rendered.contains("live sessions"));
        assert!(rendered.contains("session-running"));
        assert!(rendered.contains("recent exits"));
        assert!(rendered.contains("session-exited"));
    }
}
