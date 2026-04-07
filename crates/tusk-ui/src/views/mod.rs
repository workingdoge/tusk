pub(crate) mod board;
pub(crate) mod home;
pub(crate) mod overlay;
pub(crate) mod receipts;
pub(crate) mod tracker;

use std::time::Duration;

use ratatui::Frame;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::Style;
use ratatui::text::{Line, Span};
use ratatui::widgets::{Paragraph, Tabs, Wrap};

use crate::app::{App, PanelState, ViewMode};
use crate::theme::{
    active_tab_style, chrome_block, error_style, muted_style, pane_block, strong_style,
    subtle_style, success_style, tab_style, text_style, transport_style, warning_style,
};

pub(crate) fn render(frame: &mut Frame, app: &App) {
    let vertical = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(4),
            Constraint::Min(8),
            Constraint::Length(4),
        ])
        .split(frame.area());

    render_header(frame, vertical[0], app);

    match app.view {
        ViewMode::Home => home::render_home(frame, vertical[1], app),
        ViewMode::Tracker => tracker::render_tracker(frame, vertical[1], app),
        ViewMode::Board => board::render_board(frame, vertical[1], app),
        ViewMode::Receipts => receipts::render_receipts(frame, vertical[1], app),
    }

    if app.overlay().is_some() {
        overlay::render_overlay(frame, vertical[1], app);
    }

    render_footer(frame, vertical[2], app);
}

pub(crate) fn panel_title<T>(
    title: &str,
    panel: &PanelState<T>,
    refresh_interval: Duration,
) -> Line<'static> {
    let mut spans = vec![Span::raw(title.to_owned())];

    if let Some((label, style)) = panel_freshness_label(panel, refresh_interval) {
        spans.push(Span::raw(" "));
        spans.push(Span::styled(format!("[{label}]"), style));
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
) -> Option<(String, Style)> {
    if panel.is_refreshing() && !panel.has_value() {
        return Some(("loading".to_owned(), success_style()));
    }

    if panel.is_refreshing() {
        let label = match panel.age() {
            Some(age) => format!("refreshing | {}", age_label(age)),
            None => "refreshing".to_owned(),
        };
        return Some((label, success_style()));
    }

    if panel.stale_message().is_some() {
        let label = match panel.age() {
            Some(age) => format!("stale | {}", age_label(age)),
            None => "stale".to_owned(),
        };
        return Some((label, warning_style()));
    }

    if panel.error.is_some() {
        return Some(("error".to_owned(), error_style()));
    }

    match panel.age() {
        Some(age) if age > stale_threshold(refresh_interval) => {
            Some((format!("stale | {}", age_label(age)), warning_style()))
        }
        Some(age) => Some((age_label(age), muted_style())),
        None => Some(("waiting".to_owned(), subtle_style())),
    }
}

fn panel_notice<T>(panel: &PanelState<T>) -> Option<Line<'static>> {
    if let Some(error) = panel.stale_message() {
        return Some(Line::from(Span::styled(
            format!("latest refresh failed; showing last good data: {error}"),
            warning_style(),
        )));
    }

    if panel.is_refreshing() && panel.has_value() {
        return Some(Line::from(Span::styled(
            "refreshing in background",
            success_style(),
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

fn render_header(frame: &mut Frame, area: Rect, app: &App) {
    let block = chrome_block("Control Plane");
    let inner = block.inner(area);
    frame.render_widget(block, area);

    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(1), Constraint::Length(1)])
        .split(inner);
    let top = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Min(30), Constraint::Length(28)])
        .split(rows[0]);

    let title = Paragraph::new(Line::from(vec![
        Span::styled("tusk-ui", strong_style()),
        Span::raw("  "),
        Span::styled(app.repo_name(), text_style()),
        Span::raw("  "),
        Span::styled(app.client.repo_root.display().to_string(), subtle_style()),
    ]));
    frame.render_widget(title, top[0]);

    let transport = Paragraph::new(Line::from(vec![
        Span::styled(app.transport_label(), transport_style(app.socket_is_live())),
        Span::raw("  "),
        Span::styled(app.transport_detail(), subtle_style()),
    ]))
    .alignment(ratatui::layout::Alignment::Right);
    frame.render_widget(transport, top[1]);

    let titles = ["Home", "Tracker", "Board", "Receipts"];
    let selected = match app.view {
        ViewMode::Home => 0,
        ViewMode::Tracker => 1,
        ViewMode::Board => 2,
        ViewMode::Receipts => 3,
    };
    let tabs = Tabs::new(titles)
        .select(selected)
        .divider(" ")
        .highlight_style(active_tab_style())
        .style(tab_style());
    frame.render_widget(tabs, rows[1]);
}

fn render_footer(frame: &mut Frame, area: Rect, app: &App) {
    let block = chrome_block("Actions");
    let inner = block.inner(area);
    frame.render_widget(block, area);

    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(1), Constraint::Length(1)])
        .split(inner);
    let top = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Min(40), Constraint::Length(28)])
        .split(rows[0]);

    let hints = Paragraph::new(Line::from(vec![
        Span::styled("view: ", strong_style()),
        Span::styled(app.view.label(), text_style()),
        Span::raw("  "),
        Span::styled(app.footer_actions(), muted_style()),
    ]))
    .wrap(Wrap { trim: false });
    frame.render_widget(hints, top[0]);

    let meta = Paragraph::new(Line::from(vec![
        Span::styled(app.view.label(), strong_style()),
        Span::raw(" "),
        Span::styled(current_panel_label(app), muted_style()),
        Span::raw("  "),
        Span::styled(refresh_indicator(app), refresh_indicator_style(app)),
    ]))
    .alignment(ratatui::layout::Alignment::Right);
    frame.render_widget(meta, top[1]);

    frame.render_widget(
        Paragraph::new(Line::from(app.status_line.clone())).wrap(Wrap { trim: false }),
        rows[1],
    );
}

fn current_panel_label(app: &App) -> String {
    if app.current_panel_is_refreshing() && app.current_panel_age().is_none() {
        return "loading".to_owned();
    }

    match app.current_panel_age() {
        Some(age) => format!("updated {}", age_label(age)),
        None => "waiting".to_owned(),
    }
}

fn refresh_indicator(app: &App) -> String {
    if app.any_panel_refreshing() {
        spinner_frame()
    } else {
        "idle".to_owned()
    }
}

fn refresh_indicator_style(app: &App) -> Style {
    if app.any_panel_refreshing() {
        success_style()
    } else {
        muted_style()
    }
}

fn spinner_frame() -> String {
    const FRAMES: &[char] = &['-', '\\', '|', '/'];
    let millis = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    FRAMES[(millis / 100 % FRAMES.len() as u128) as usize].to_string()
}
