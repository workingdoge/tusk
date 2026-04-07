use ratatui::text::Line;
use ratatui::{Frame, layout::Rect};

use super::{panel_title, prepend_panel_notice, render_scrolled_lines_panel};
use crate::app::{App, ViewMode};
use crate::theme::{error_lines, kv_line};
use crate::viewmodel::ReceiptsViewModel;

pub(crate) fn render_receipts(frame: &mut Frame, area: Rect, app: &App) {
    let lines = match (app.receipts_viewmodel(), &app.receipts.error) {
        (Some(receipts), _) => {
            let mut lines = receipt_lines(&receipts, &app.receipts);
            prepend_panel_notice(&mut lines, &app.receipts);
            lines
        }
        (_, Some(error)) => error_lines(error),
        _ => vec![Line::from("waiting for receipt data")],
    };

    render_scrolled_lines_panel(
        frame,
        area,
        panel_title("Receipts", &app.receipts, app.refresh_interval()),
        lines,
        app.view == ViewMode::Receipts,
        app.current_scroll_offset(),
    );
}

pub(crate) fn receipt_lines(
    receipts: &ReceiptsViewModel,
    panel: &crate::app::PanelState<crate::types::ReceiptsStatus>,
) -> Vec<Line<'static>> {
    let mut lines = vec![
        kv_line("repo", receipts.repo_root.clone()),
        kv_line("updated", receipts.updated_at.clone()),
        kv_line("file", receipts.receipts_path.clone()),
    ];

    let mut notice_lines = Vec::new();
    prepend_panel_notice(&mut notice_lines, panel);
    lines.extend(notice_lines);

    if receipts.receipts.is_empty() {
        lines.push(Line::from("no receipts yet"));
        return lines;
    }

    lines.extend(
        receipts
            .receipts
            .iter()
            .map(|receipt| Line::from(receipt.label.clone())),
    );

    lines
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
