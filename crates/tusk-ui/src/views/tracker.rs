use ratatui::widgets::{Paragraph, Wrap};
use ratatui::{Frame, layout::Rect};

use crate::app::{App, ViewMode};
use crate::theme::{error_lines, kv_line, pane_block, title_line};
use crate::types::TrackerStatus;

use super::board::summary_lines;

pub(crate) fn render_tracker(frame: &mut Frame, area: Rect, app: &App) {
    let block = pane_block("Tracker Service", app.view == ViewMode::Tracker);
    let lines = match (&app.tracker.value, &app.tracker.error) {
        (Some(tracker), _) => tracker_lines(tracker),
        (_, Some(error)) => error_lines(error),
        _ => vec![ratatui::text::Line::from("waiting for tracker data")],
    };

    frame.render_widget(
        Paragraph::new(lines)
            .block(block)
            .wrap(Wrap { trim: false }),
        area,
    );
}

pub(crate) fn tracker_lines(tracker: &TrackerStatus) -> Vec<ratatui::text::Line<'static>> {
    let mut lines = vec![
        kv_line("repo", tracker.repo_root.clone()),
        kv_line("socket", tracker.protocol.endpoint.clone()),
        kv_line("mode", tracker.tuskd.mode.clone()),
        kv_line(
            "pid",
            tracker
                .tuskd
                .pid
                .map(|value| value.to_string())
                .unwrap_or_else(|| "none".to_owned()),
        ),
        kv_line("health", tracker.health.status.clone()),
        kv_line("checked", tracker.health.checked_at.clone()),
        kv_line("leases", tracker.active_leases.len().to_string()),
    ];

    if let Some(summary) = &tracker.health.summary {
        lines.push(ratatui::text::Line::from(""));
        lines.push(title_line("issue summary"));
        lines.extend(summary_lines(summary));
    }

    if let Some(backend) = &tracker.health.backend {
        lines.push(ratatui::text::Line::from(""));
        lines.push(title_line("backend"));
        if let Some(running) = backend.running {
            lines.push(kv_line("running", running.to_string()));
        }
        if let Some(pid) = backend.pid {
            lines.push(kv_line("backend pid", pid.to_string()));
        }
        if let Some(port) = backend.port {
            lines.push(kv_line("port", port.to_string()));
        }
        if let Some(path) = &backend.data_dir {
            lines.push(kv_line("data", path.clone()));
        }
    }

    lines
}
