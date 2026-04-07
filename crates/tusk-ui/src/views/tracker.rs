use ratatui::text::Line;
use ratatui::widgets::{Paragraph, Wrap};
use ratatui::{Frame, layout::Rect};

use crate::app::{App, ViewMode};
use crate::theme::{error_lines, kv_line, pane_block, title_line};
use crate::viewmodel::TrackerViewModel;

use super::board::summary_lines;
use super::{panel_title, prepend_panel_notice};

pub(crate) fn render_tracker(frame: &mut Frame, area: Rect, app: &App) {
    let block = pane_block(
        panel_title("Tracker Service", &app.tracker, app.refresh_interval()),
        app.view == ViewMode::Tracker,
    );
    let lines = match (app.tracker_viewmodel(), &app.tracker.error) {
        (Some(tracker), _) => {
            let mut lines = tracker_lines(&tracker);
            prepend_panel_notice(&mut lines, &app.tracker);
            lines
        }
        (_, Some(error)) => error_lines(error),
        _ => vec![Line::from("waiting for tracker data")],
    };

    frame.render_widget(
        Paragraph::new(lines)
            .block(block)
            .wrap(Wrap { trim: false }),
        area,
    );
}

pub(crate) fn tracker_lines(tracker: &TrackerViewModel) -> Vec<ratatui::text::Line<'static>> {
    let mut lines = vec![
        kv_line("repo", tracker.repo_root.clone()),
        kv_line("socket", tracker.socket_path.clone()),
        kv_line("mode", tracker.mode.clone()),
        kv_line("pid", tracker.pid.clone()),
        kv_line("health", tracker.health.clone()),
        kv_line("checked", tracker.checked_at.clone()),
        kv_line("leases", tracker.lease_count.to_string()),
    ];

    if let Some(summary) = &tracker.summary {
        lines.push(ratatui::text::Line::from(""));
        lines.push(title_line("issue summary"));
        lines.extend(summary_lines(summary));
    }

    if let Some(backend) = &tracker.backend {
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
