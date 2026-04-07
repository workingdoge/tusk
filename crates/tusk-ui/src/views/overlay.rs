use ratatui::Frame;
use ratatui::layout::{Alignment, Constraint, Direction, Flex, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Clear, Paragraph, Wrap};

use crate::app::App;

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
    lines.push(Line::from(Span::styled(
        overlay.footer_hint(),
        Style::default().fg(Color::DarkGray),
    )));

    frame.render_widget(
        Paragraph::new(lines)
            .alignment(Alignment::Left)
            .block(overlay_block(&overlay.title))
            .wrap(Wrap { trim: false }),
        popup,
    );
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

fn overlay_block(title: &str) -> Block<'static> {
    Block::default()
        .title(Line::from(vec![
            Span::styled(
                title.to_owned(),
                Style::default().add_modifier(Modifier::BOLD),
            ),
            Span::raw("  "),
            Span::styled("overlay", Style::default().fg(Color::Yellow)),
        ]))
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Cyan))
}
