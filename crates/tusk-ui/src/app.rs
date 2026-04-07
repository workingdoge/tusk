use std::time::{Duration, Instant};

use anyhow::Result;
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

use crate::protocol::ProtocolClient;
use crate::theme::now_label;
use crate::types::{
    BoardIssue, BoardStatus, ClaimIssuePayload, FinishLanePayload, LaneEntry, LaunchLanePayload,
    OperatorSnapshot, PingStatus, ReceiptsStatus, TrackerStatus,
};
use crate::viewmodel::{
    BoardViewModel, HomeViewModel, ReceiptsViewModel, TrackerViewModel, board_viewmodel,
    home_viewmodel, receipts_viewmodel, tracker_viewmodel,
};

#[derive(Debug)]
pub(crate) struct App {
    pub(crate) client: ProtocolClient,
    refresh_interval: Duration,
    pub(crate) default_base_rev: String,
    last_refresh_started: Instant,
    pub(crate) status_line: String,
    pub(crate) should_quit: bool,
    pub(crate) view: ViewMode,
    pub(crate) selected_board_item_id: Option<String>,
    pub(crate) home: PanelState<OperatorSnapshot>,
    pub(crate) tracker: PanelState<TrackerStatus>,
    pub(crate) board: PanelState<BoardStatus>,
    pub(crate) receipts: PanelState<ReceiptsStatus>,
}

impl App {
    pub(crate) fn new(
        client: ProtocolClient,
        refresh_interval: Duration,
        default_base_rev: String,
    ) -> Self {
        Self {
            client,
            refresh_interval,
            default_base_rev,
            last_refresh_started: Instant::now() - refresh_interval,
            status_line: "press r to refresh, o for home, b for board, q to quit".to_owned(),
            should_quit: false,
            view: ViewMode::Home,
            selected_board_item_id: None,
            home: PanelState::default(),
            tracker: PanelState::default(),
            board: PanelState::default(),
            receipts: PanelState::default(),
        }
    }

    pub(crate) fn should_refresh(&self) -> bool {
        self.last_refresh_started.elapsed() >= self.refresh_interval
    }

    pub(crate) fn time_until_refresh(&self) -> Duration {
        self.refresh_interval
            .saturating_sub(self.last_refresh_started.elapsed())
    }

    pub(crate) fn refresh(&mut self) {
        self.last_refresh_started = Instant::now();
        self.home = PanelState::from_result(self.client.operator_snapshot());
        self.tracker = PanelState::from_result(self.client.tracker_status());
        self.board = PanelState::from_result(self.client.board_status());
        self.receipts = PanelState::from_result(self.client.receipts_status());
        self.sync_board_selection();

        self.status_line = format!(
            "refreshed {} from {}",
            now_label(),
            self.client.socket_path.display()
        );
    }

    pub(crate) fn ping(&mut self) {
        match self.client.ping() {
            Ok(PingStatus { timestamp }) => {
                self.status_line = format!("ping ok at {timestamp}");
            }
            Err(error) => {
                self.status_line = format!("ping failed: {error:#}");
            }
        }
    }

    pub(crate) fn home_viewmodel(&self) -> Option<HomeViewModel> {
        self.home.value.as_ref().map(home_viewmodel)
    }

    pub(crate) fn tracker_viewmodel(&self) -> Option<TrackerViewModel> {
        self.tracker.value.as_ref().map(tracker_viewmodel)
    }

    pub(crate) fn board_viewmodel(&self) -> Option<BoardViewModel> {
        self.board
            .value
            .as_ref()
            .map(|board| board_viewmodel(board, self.selected_board_item_id.as_deref()))
    }

    pub(crate) fn receipts_viewmodel(&self) -> Option<ReceiptsViewModel> {
        self.receipts.value.as_ref().map(receipts_viewmodel)
    }

    fn sync_board_selection(&mut self) {
        let Some(board) = self.board.value.as_ref() else {
            self.selected_board_item_id = None;
            return;
        };

        self.selected_board_item_id =
            normalized_board_selection(board, self.selected_board_item_id.as_deref());
    }

    fn move_board_selection(&mut self, delta: isize) {
        let Some(board) = self.board.value.as_ref() else {
            self.status_line = "board data is unavailable".to_owned();
            return;
        };

        let Some(next) = step_board_selection(board, self.selected_board_item_id.as_deref(), delta)
        else {
            self.selected_board_item_id = None;
            self.status_line = "no selectable board items".to_owned();
            return;
        };

        self.selected_board_item_id = Some(next.clone());
        self.status_line = format!("selected {next}");
    }

    fn claim_selected_issue(&mut self) {
        let Some(issue_id) = self.selected_board_item_id.clone() else {
            self.status_line = "no ready issue selected to claim".to_owned();
            return;
        };
        let Some(board) = self.board.value.as_ref() else {
            self.status_line = "board data is unavailable".to_owned();
            return;
        };
        let Some(item) = selected_board_item(board, Some(issue_id.as_str())) else {
            self.status_line = "selected board item is no longer available".to_owned();
            return;
        };
        if item.kind() != BoardItemKind::ReadyIssue {
            self.status_line = format!("selected issue {issue_id} is not ready to claim");
            return;
        }

        match self.client.claim_issue(&issue_id) {
            Ok(ClaimIssuePayload { issue_id }) => {
                self.refresh();
                self.status_line =
                    format!("claimed {issue_id}; launch base is {}", self.default_base_rev);
            }
            Err(error) => {
                self.status_line = format!("claim failed for {issue_id}: {error:#}");
            }
        }
    }

    fn launch_selected_issue(&mut self) {
        let Some(issue_id) = self.selected_board_item_id.clone() else {
            self.status_line = "no claimed issue selected to launch".to_owned();
            return;
        };
        let Some(board) = self.board.value.as_ref() else {
            self.status_line = "board data is unavailable".to_owned();
            return;
        };
        let Some(item) = selected_board_item(board, Some(issue_id.as_str())) else {
            self.status_line = "selected board item is no longer available".to_owned();
            return;
        };
        if item.kind() != BoardItemKind::ClaimedIssue {
            self.status_line = format!("selected issue {issue_id} is not claimed yet");
            return;
        }

        match self.client.launch_lane(&issue_id, &self.default_base_rev) {
            Ok(LaunchLanePayload {
                issue_id,
                workspace_name,
                base_rev,
            }) => {
                self.refresh();
                self.status_line = format!("launched {issue_id} in {workspace_name} from {base_rev}");
            }
            Err(error) => {
                self.status_line = format!("launch failed for {issue_id}: {error:#}");
            }
        }
    }

    fn finish_selected_lane(&mut self) {
        let Some(issue_id) = self.selected_board_item_id.clone() else {
            self.status_line = "no active lane selected to finish".to_owned();
            return;
        };
        let Some(board) = self.board.value.as_ref() else {
            self.status_line = "board data is unavailable".to_owned();
            return;
        };
        let Some(item) = selected_board_item(board, Some(issue_id.as_str())) else {
            self.status_line = "selected board item is no longer available".to_owned();
            return;
        };
        if item.kind() != BoardItemKind::ActiveLane {
            self.status_line = format!("selected item {issue_id} is not an active lane");
            return;
        }

        match self.client.finish_lane(&issue_id, "completed") {
            Ok(FinishLanePayload { issue_id, outcome }) => {
                self.refresh();
                self.status_line = format!("finished {issue_id} as {outcome}");
            }
            Err(error) => {
                self.status_line = format!("finish failed for {issue_id}: {error:#}");
            }
        }
    }

    pub(crate) fn handle_key(&mut self, key: KeyEvent) {
        match key.code {
            KeyCode::Char('q') => self.should_quit = true,
            KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                self.should_quit = true
            }
            KeyCode::Char('c') if self.view == ViewMode::Board => self.claim_selected_issue(),
            KeyCode::Char('f') if self.view == ViewMode::Board => self.finish_selected_lane(),
            KeyCode::Char('l') if self.view == ViewMode::Board => self.launch_selected_issue(),
            KeyCode::Char('r') => self.refresh(),
            KeyCode::Char('p') => self.ping(),
            KeyCode::Char('o') => self.view = ViewMode::Home,
            KeyCode::Char('t') => self.view = ViewMode::Tracker,
            KeyCode::Char('b') => self.view = ViewMode::Board,
            KeyCode::Char('e') => self.view = ViewMode::Receipts,
            KeyCode::Char('j') | KeyCode::Down if self.view == ViewMode::Board => {
                self.move_board_selection(1)
            }
            KeyCode::Char('k') | KeyCode::Up if self.view == ViewMode::Board => {
                self.move_board_selection(-1)
            }
            KeyCode::Tab => self.view = self.view.next(),
            KeyCode::BackTab => self.view = self.view.previous(),
            _ => {}
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum ViewMode {
    Home,
    Tracker,
    Board,
    Receipts,
}

impl ViewMode {
    pub(crate) fn next(self) -> Self {
        match self {
            Self::Home => Self::Tracker,
            Self::Tracker => Self::Board,
            Self::Board => Self::Receipts,
            Self::Receipts => Self::Home,
        }
    }

    pub(crate) fn previous(self) -> Self {
        match self {
            Self::Home => Self::Receipts,
            Self::Tracker => Self::Home,
            Self::Board => Self::Tracker,
            Self::Receipts => Self::Board,
        }
    }
}

#[derive(Debug)]
pub(crate) struct PanelState<T> {
    pub(crate) value: Option<T>,
    pub(crate) error: Option<String>,
}

impl<T> Default for PanelState<T> {
    fn default() -> Self {
        Self {
            value: None,
            error: None,
        }
    }
}

impl<T> PanelState<T> {
    pub(crate) fn from_result(result: Result<T>) -> Self {
        match result {
            Ok(value) => Self {
                value: Some(value),
                error: None,
            },
            Err(error) => Self {
                value: None,
                error: Some(format!("{error:#}")),
            },
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum BoardItemKind {
    ReadyIssue,
    ClaimedIssue,
    ActiveLane,
}

#[derive(Clone, Copy, Debug)]
enum BoardItemRef<'a> {
    ReadyIssue(&'a BoardIssue),
    ClaimedIssue(&'a BoardIssue),
    ActiveLane(&'a LaneEntry),
}

impl<'a> BoardItemRef<'a> {
    fn kind(self) -> BoardItemKind {
        match self {
            Self::ReadyIssue(_) => BoardItemKind::ReadyIssue,
            Self::ClaimedIssue(_) => BoardItemKind::ClaimedIssue,
            Self::ActiveLane(_) => BoardItemKind::ActiveLane,
        }
    }

    fn id(self) -> &'a str {
        match self {
            Self::ReadyIssue(issue) | Self::ClaimedIssue(issue) => issue.id.as_str(),
            Self::ActiveLane(lane) => lane.issue_id.as_str(),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum LaneGroup {
    Active,
    Finished,
    Stale,
}

pub(crate) fn lane_group(lane: &LaneEntry) -> LaneGroup {
    let observed_status = lane.observed_status.as_deref().unwrap_or(lane.status.as_str());
    if observed_status == "stale" {
        LaneGroup::Stale
    } else if lane.status == "finished" || observed_status == "finished" {
        LaneGroup::Finished
    } else {
        LaneGroup::Active
    }
}

pub(crate) fn active_lanes(board: &BoardStatus) -> Vec<&LaneEntry> {
    let mut lanes = board
        .lanes
        .iter()
        .filter(|lane| lane_group(lane) == LaneGroup::Active)
        .collect::<Vec<_>>();
    lanes.sort_by(|left, right| left.issue_id.cmp(&right.issue_id));
    lanes
}

fn board_items(board: &BoardStatus) -> Vec<BoardItemRef<'_>> {
    let mut items = Vec::with_capacity(
        board.ready_issues.len() + board.claimed_issues.len() + board.lanes.len(),
    );
    items.extend(board.ready_issues.iter().map(BoardItemRef::ReadyIssue));
    items.extend(board.claimed_issues.iter().map(BoardItemRef::ClaimedIssue));
    items.extend(active_lanes(board).into_iter().map(BoardItemRef::ActiveLane));
    items
}

fn selected_board_item<'a>(
    board: &'a BoardStatus,
    selected_board_item_id: Option<&str>,
) -> Option<BoardItemRef<'a>> {
    let selected_board_item_id = selected_board_item_id?;
    board_items(board)
        .into_iter()
        .find(|item| item.id() == selected_board_item_id)
}

pub(crate) fn normalized_board_selection(
    board: &BoardStatus,
    selected_board_item_id: Option<&str>,
) -> Option<String> {
    let items = board_items(board);
    if items.is_empty() {
        return None;
    }

    if let Some(selected) = selected_board_item(board, selected_board_item_id) {
        return Some(selected.id().to_owned());
    }

    Some(items[0].id().to_owned())
}

pub(crate) fn step_board_selection(
    board: &BoardStatus,
    selected_board_item_id: Option<&str>,
    delta: isize,
) -> Option<String> {
    let items = board_items(board);
    if items.is_empty() {
        return None;
    }

    let current_index = selected_board_item_id
        .and_then(|selected| items.iter().position(|item| item.id() == selected))
        .unwrap_or(0);

    let step = delta.unsigned_abs();
    let max_index = items.len().saturating_sub(1);
    let next_index = if delta.is_negative() {
        current_index.saturating_sub(step)
    } else {
        current_index.saturating_add(step).min(max_index)
    };

    Some(items[next_index].id().to_owned())
}

#[cfg(test)]
mod tests {
    use super::{normalized_board_selection, step_board_selection};
    use crate::types::{BoardIssue, BoardStatus, LaneEntry};

    #[test]
    fn selection_helpers_follow_board_item_order() {
        let board = BoardStatus {
            repo_root: "/tmp/repo".to_owned(),
            generated_at: "2026-03-26T00:00:00Z".to_owned(),
            summary: None,
            ready_issues: vec![
                BoardIssue {
                    id: "tusk-a".to_owned(),
                    title: "first ready issue".to_owned(),
                    status: Some("open".to_owned()),
                },
                BoardIssue {
                    id: "tusk-b".to_owned(),
                    title: "second ready issue".to_owned(),
                    status: Some("open".to_owned()),
                },
            ],
            claimed_issues: vec![BoardIssue {
                id: "tusk-c".to_owned(),
                title: "claimed issue".to_owned(),
                status: Some("in_progress".to_owned()),
            }],
            blocked_issues: vec![],
            deferred_issues: vec![],
            lanes: vec![LaneEntry {
                issue_id: "tusk-d".to_owned(),
                issue_title: "launched lane".to_owned(),
                status: "launched".to_owned(),
                observed_status: Some("launched".to_owned()),
                workspace_exists: Some(true),
                outcome: None,
                workspace_name: Some("tusk-d-lane".to_owned()),
            }],
            workspaces: vec![],
        };

        assert_eq!(
            normalized_board_selection(&board, None),
            Some("tusk-a".to_owned())
        );
        assert_eq!(
            step_board_selection(&board, Some("tusk-a"), 1),
            Some("tusk-b".to_owned())
        );
        assert_eq!(
            step_board_selection(&board, Some("tusk-b"), 1),
            Some("tusk-c".to_owned())
        );
        assert_eq!(
            step_board_selection(&board, Some("tusk-c"), 1),
            Some("tusk-d".to_owned())
        );
        assert_eq!(
            step_board_selection(&board, Some("tusk-d"), 1),
            Some("tusk-d".to_owned())
        );
        assert_eq!(
            step_board_selection(&board, Some("tusk-d"), -1),
            Some("tusk-c".to_owned())
        );
        assert_eq!(
            normalized_board_selection(&board, Some("tusk-d")),
            Some("tusk-d".to_owned())
        );
        assert_eq!(
            step_board_selection(&board, Some("tusk-c"), -1),
            Some("tusk-b".to_owned())
        );
        assert_eq!(
            step_board_selection(&board, Some("tusk-b"), -1),
            Some("tusk-a".to_owned())
        );
    }
}
