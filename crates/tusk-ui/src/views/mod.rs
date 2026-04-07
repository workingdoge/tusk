pub(crate) mod board;
pub(crate) mod home;
pub(crate) mod overlay;
pub(crate) mod receipts;
pub(crate) mod tracker;

use std::time::Duration;

use ratatui::Frame;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Paragraph, Wrap};

use crate::app::{App, PanelState, ViewMode};
use crate::theme::pane_block;

pub(crate) fn render(frame: &mut Frame, app: &App) {
    let vertical = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(8),
            Constraint::Length(3),
        ])
        .split(frame.area());

    let header = Paragraph::new(Line::from(vec![
        Span::styled("tusk-ui  ", Style::default().add_modifier(Modifier::BOLD)),
        Span::raw(app.client.repo_root.display().to_string()),
        Span::raw("  "),
        Span::styled(
            app.client.socket_path.display().to_string(),
            Style::default().fg(Color::DarkGray),
        ),
        Span::raw("  "),
        Span::styled(app.view.label(), Style::default().fg(Color::Yellow)),
    ]))
    .block(
        ratatui::widgets::Block::default()
            .borders(ratatui::widgets::Borders::ALL)
            .title("Control Plane"),
    );
    frame.render_widget(header, vertical[0]);

    match app.view {
        ViewMode::Home => home::render_home(frame, vertical[1], app),
        ViewMode::Tracker => tracker::render_tracker(frame, vertical[1], app),
        ViewMode::Board => board::render_board(frame, vertical[1], app),
        ViewMode::Receipts => receipts::render_receipts(frame, vertical[1], app),
    }

    if app.overlay().is_some() {
        overlay::render_overlay(frame, vertical[1], app);
    }

    let footer = Paragraph::new(vec![
        Line::from(vec![
            Span::styled("view: ", Style::default().add_modifier(Modifier::BOLD)),
            Span::raw(app.view.label()),
            Span::raw("  "),
            Span::styled(
                app.overlay()
                    .map(|overlay| overlay.footer_hint())
                    .unwrap_or_else(|| match app.view {
                        ViewMode::Home => {
                            "o/t/b/e view  Tab cycle  ? help  b board  r refresh  p ping  q quit"
                        }
                        ViewMode::Board => {
                            "o/t/b/e view  Tab cycle  ? help  j/k move  c claim  l launch  f finish  r refresh  p ping  q quit"
                        }
                        _ => "o/t/b/e view  Tab cycle  ? help  r refresh  p ping  q quit",
                    }),
                Style::default().fg(Color::DarkGray),
            ),
        ]),
        Line::from(app.status_line.clone()),
    ])
    .block(
        ratatui::widgets::Block::default()
            .borders(ratatui::widgets::Borders::ALL)
            .title("Actions"),
    )
    .wrap(Wrap { trim: false });
    frame.render_widget(footer, vertical[2]);
}

pub(crate) fn panel_title<T>(
    title: &str,
    panel: &PanelState<T>,
    refresh_interval: Duration,
) -> Line<'static> {
    let mut spans = vec![Span::raw(title.to_owned())];

    if let Some((label, color)) = panel_freshness_label(panel, refresh_interval) {
        spans.push(Span::raw(" "));
        spans.push(Span::styled(
            format!("[{label}]"),
            Style::default().fg(color),
        ));
    }

    Line::from(spans)
}

pub(crate) fn prepend_panel_notice<T>(lines: &mut Vec<Line<'static>>, panel: &PanelState<T>) {
    let Some(line) = panel_notice(panel) else {
        return;
    };
    lines.insert(0, Line::from(""));
    lines.insert(0, line);
}

pub(crate) fn render_lines_panel(
    frame: &mut Frame,
    area: Rect,
    title: Line<'static>,
    lines: Vec<Line<'static>>,
    focused: bool,
) {
    frame.render_widget(
        Paragraph::new(lines)
            .block(pane_block(title, focused))
            .wrap(Wrap { trim: false }),
        area,
    );
}

fn panel_freshness_label<T>(
    panel: &PanelState<T>,
    refresh_interval: Duration,
) -> Option<(String, Color)> {
    if panel.is_refreshing() && !panel.has_value() {
        return Some(("loading".to_owned(), Color::Cyan));
    }

    if panel.is_refreshing() {
        let label = match panel.age() {
            Some(age) => format!("refreshing | {}", age_label(age)),
            None => "refreshing".to_owned(),
        };
        return Some((label, Color::Cyan));
    }

    if panel.stale_message().is_some() {
        let label = match panel.age() {
            Some(age) => format!("stale | {}", age_label(age)),
            None => "stale".to_owned(),
        };
        return Some((label, Color::Yellow));
    }

    if panel.error.is_some() {
        return Some(("error".to_owned(), Color::Red));
    }

    match panel.age() {
        Some(age) if age > stale_threshold(refresh_interval) => {
            Some((format!("stale | {}", age_label(age)), Color::Yellow))
        }
        Some(age) => Some((age_label(age), Color::DarkGray)),
        None => Some(("waiting".to_owned(), Color::DarkGray)),
    }
}

fn panel_notice<T>(panel: &PanelState<T>) -> Option<Line<'static>> {
    if let Some(error) = panel.stale_message() {
        return Some(Line::from(Span::styled(
            format!("latest refresh failed; showing last good data: {error}"),
            Style::default().fg(Color::Yellow),
        )));
    }

    if panel.is_refreshing() && panel.has_value() {
        return Some(Line::from(Span::styled(
            "refreshing in background",
            Style::default().fg(Color::Cyan),
        )));
    }

    None
}

fn stale_threshold(refresh_interval: Duration) -> Duration {
    refresh_interval.checked_mul(2).unwrap_or(refresh_interval)
}

fn age_label(age: Duration) -> String {
    let seconds = age.as_secs();
    if seconds >= 3_600 {
        format!("{}h", seconds / 3_600)
    } else if seconds >= 60 {
        format!("{}m", seconds / 60)
    } else {
        format!("{}s", seconds)
    }
}
