use std::time::{SystemTime, UNIX_EPOCH};

use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders};

use crate::viewmodel::Source;

const ROSEWATER: Color = Color::Rgb(245, 224, 220);
const MAUVE: Color = Color::Rgb(203, 166, 247);
const RED: Color = Color::Rgb(243, 139, 168);
const PEACH: Color = Color::Rgb(250, 179, 135);
const YELLOW: Color = Color::Rgb(249, 226, 175);
const GREEN: Color = Color::Rgb(166, 227, 161);
const TEAL: Color = Color::Rgb(148, 226, 213);
const SKY: Color = Color::Rgb(137, 220, 235);
const SAPPHIRE: Color = Color::Rgb(116, 199, 236);
const LAVENDER: Color = Color::Rgb(180, 190, 254);
const TEXT: Color = Color::Rgb(205, 214, 244);
const SUBTEXT0: Color = Color::Rgb(166, 173, 200);
const OVERLAY0: Color = Color::Rgb(108, 112, 134);
const SURFACE1: Color = Color::Rgb(69, 71, 90);

pub(crate) fn now_label() -> String {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    format!("epoch:{seconds}")
}

pub(crate) fn text_style() -> Style {
    Style::default().fg(TEXT)
}

pub(crate) fn muted_style() -> Style {
    Style::default().fg(SUBTEXT0)
}

pub(crate) fn subtle_style() -> Style {
    Style::default().fg(OVERLAY0)
}

pub(crate) fn strong_style() -> Style {
    text_style().add_modifier(Modifier::BOLD)
}

pub(crate) fn section_title_style() -> Style {
    Style::default().fg(MAUVE).add_modifier(Modifier::BOLD)
}

pub(crate) fn label_style() -> Style {
    Style::default().fg(LAVENDER).add_modifier(Modifier::BOLD)
}

pub(crate) fn success_style() -> Style {
    Style::default().fg(GREEN).add_modifier(Modifier::BOLD)
}

pub(crate) fn warning_style() -> Style {
    Style::default().fg(YELLOW).add_modifier(Modifier::BOLD)
}

pub(crate) fn error_style() -> Style {
    Style::default().fg(RED).add_modifier(Modifier::BOLD)
}

pub(crate) fn active_border_style() -> Style {
    Style::default().fg(SKY).add_modifier(Modifier::BOLD)
}

pub(crate) fn inactive_border_style() -> Style {
    Style::default().fg(SURFACE1)
}

pub(crate) fn selected_item_style() -> Style {
    Style::default().fg(TEAL).add_modifier(Modifier::BOLD)
}

pub(crate) fn transport_style(live: bool) -> Style {
    if live {
        success_style()
    } else {
        warning_style()
    }
}

pub(crate) fn tab_style() -> Style {
    muted_style()
}

pub(crate) fn active_tab_style() -> Style {
    Style::default().fg(SAPPHIRE).add_modifier(Modifier::BOLD)
}

pub(crate) fn chrome_block(title: &str) -> Block<'static> {
    Block::default()
        .borders(Borders::ALL)
        .border_style(inactive_border_style())
        .title(Span::styled(title.to_owned(), label_style()))
}

pub(crate) fn overlay_block(title: &str) -> Block<'static> {
    Block::default()
        .title(Line::from(vec![
            Span::styled(title.to_owned(), strong_style()),
            Span::raw("  "),
            Span::styled("overlay", section_title_style()),
        ]))
        .borders(Borders::ALL)
        .border_style(active_border_style())
}

pub(crate) fn source_style(source: &Source) -> Style {
    match source {
        Source::Authoritative => text_style(),
        Source::Heuristic => Style::default().fg(PEACH).add_modifier(Modifier::ITALIC),
        Source::Enriched => Style::default()
            .fg(ROSEWATER)
            .add_modifier(Modifier::ITALIC | Modifier::BOLD),
    }
}

pub(crate) fn source_line(source: &Source, text: impl Into<String>) -> Line<'static> {
    Line::from(Span::styled(text.into(), source_style(source)))
}

pub(crate) fn pane_block<'a>(title: Line<'a>, focused: bool) -> Block<'a> {
    let style = if focused {
        active_border_style()
    } else {
        inactive_border_style()
    };

    Block::default()
        .borders(Borders::ALL)
        .border_style(style)
        .title(title)
}

pub(crate) fn kv_line(label: impl Into<String>, value: impl Into<String>) -> Line<'static> {
    Line::from(vec![
        Span::styled(format!("{:>11}: ", label.into()), label_style()),
        Span::styled(value.into(), text_style()),
    ])
}

pub(crate) fn title_line(title: impl Into<String>) -> Line<'static> {
    Line::from(Span::styled(title.into(), section_title_style()))
}

pub(crate) fn error_lines(error: &str) -> Vec<Line<'static>> {
    vec![
        Line::from(Span::styled("error", error_style())),
        Line::from(Span::styled(error.to_owned(), text_style())),
    ]
}
