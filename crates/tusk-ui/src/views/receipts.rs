use ratatui::text::Line;
use ratatui::widgets::{List, ListItem, Paragraph, Wrap};
use ratatui::{Frame, layout::Rect};

use crate::app::{App, ViewMode};
use crate::theme::{error_lines, pane_block};
use crate::viewmodel::ReceiptsViewModel;

pub(crate) fn render_receipts(frame: &mut Frame, area: Rect, app: &App) {
    let block = pane_block("Receipts", app.view == ViewMode::Receipts);
    match (app.receipts_viewmodel(), &app.receipts.error) {
        (Some(receipts), _) => {
            let items = receipt_items(&receipts);
            frame.render_widget(List::new(items).block(block), area);
        }
        (_, Some(error)) => {
            frame.render_widget(
                Paragraph::new(error_lines(error))
                    .block(block)
                    .wrap(Wrap { trim: false }),
                area,
            );
        }
        _ => {
            frame.render_widget(
                Paragraph::new(vec![Line::from("waiting for receipt data")])
                    .block(block)
                    .wrap(Wrap { trim: false }),
                area,
            );
        }
    }
}

fn receipt_items(receipts: &ReceiptsViewModel) -> Vec<ListItem<'static>> {
    let mut items = vec![
        ListItem::new(Line::from(vec![
            ratatui::text::Span::styled(
                "repo ",
                ratatui::style::Style::default()
                    .add_modifier(ratatui::style::Modifier::BOLD),
            ),
            ratatui::text::Span::raw(receipts.repo_root.clone()),
        ])),
        ListItem::new(Line::from(vec![
            ratatui::text::Span::styled(
                "updated ",
                ratatui::style::Style::default()
                    .add_modifier(ratatui::style::Modifier::BOLD),
            ),
            ratatui::text::Span::raw(receipts.updated_at.clone()),
        ])),
        ListItem::new(Line::from(vec![
            ratatui::text::Span::styled(
                "file ",
                ratatui::style::Style::default()
                    .add_modifier(ratatui::style::Modifier::BOLD),
            ),
            ratatui::text::Span::raw(receipts.receipts_path.clone()),
        ])),
    ];

    if receipts.receipts.is_empty() {
        items.push(ListItem::new(Line::from("no receipts yet")));
        return items;
    }

    items.extend(
        receipts
            .receipts
            .iter()
            .map(|receipt| ListItem::new(Line::from(receipt.label.clone()))),
    );

    items
}

#[cfg(test)]
mod tests {
    use crate::types::{ReceiptEntry, ReceiptsStatus};

    #[test]
    fn receipt_items_include_kind() {
        let receipts = ReceiptsStatus {
            repo_root: "/tmp/repo".to_owned(),
            generated_at: "2026-03-26T00:00:00Z".to_owned(),
            receipts_path: "/tmp/repo/.beads/tuskd/receipts.jsonl".to_owned(),
            receipts: vec![ReceiptEntry {
                timestamp: Some("2026-03-26T00:00:00Z".to_owned()),
                kind: Some("tracker.ensure".to_owned()),
                payload: Some(serde_json::json!({"service": {"mode": "idle"}})),
                invalid_line: None,
            }],
        };

        let rendered = crate::viewmodel::receipts_viewmodel(&receipts)
            .receipts
            .into_iter()
            .map(|item| item.label)
            .collect::<Vec<_>>()
            .join("\n");

        assert!(rendered.contains("tracker.ensure"));
    }
}
