pub(crate) mod board;
pub(crate) mod home;
pub(crate) mod receipts;
pub(crate) mod tracker;

use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Paragraph, Wrap};
use ratatui::Frame;

use crate::app::{App, ViewMode};
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
        Span::styled(
            match app.view {
                ViewMode::Home => "home",
                ViewMode::Tracker => "tracker",
                ViewMode::Board => "board",
                ViewMode::Receipts => "receipts",
            },
            Style::default().fg(Color::Yellow),
        ),
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

    let footer = Paragraph::new(vec![
        Line::from(vec![
            Span::styled("view: ", Style::default().add_modifier(Modifier::BOLD)),
            Span::raw(match app.view {
                ViewMode::Home => "home",
                ViewMode::Tracker => "tracker",
                ViewMode::Board => "board",
                ViewMode::Receipts => "receipts",
            }),
            Span::raw("  "),
            Span::styled(
                match app.view {
                    ViewMode::Home => {
                        "o/t/b/e view  Tab cycle  b board  r refresh  p ping  q quit"
                    }
                    ViewMode::Board => {
                        "o/t/b/e view  Tab cycle  j/k move  c claim  l launch  f finish  r refresh  p ping  q quit"
                    }
                    _ => "o/t/b/e view  Tab cycle  r refresh  p ping  q quit",
                },
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

pub(crate) fn render_lines_panel(
    frame: &mut Frame,
    area: Rect,
    title: &'static str,
    lines: Vec<Line<'static>>,
) {
    frame.render_widget(
        Paragraph::new(lines)
            .block(pane_block(title, false))
            .wrap(Wrap { trim: false }),
        area,
    );
}
