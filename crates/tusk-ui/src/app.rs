use std::time::{Duration, Instant};

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

use crate::action::{Direction, UiAction};
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
use crate::worker::{RefreshSet, RefreshUpdate, RefreshWorker};

#[derive(Debug)]
pub(crate) struct App {
    pub(crate) client: ProtocolClient,
    refresh_interval: Duration,
    pub(crate) default_base_rev: String,
    worker: RefreshWorker,
    last_refresh_requested: Instant,
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
        let worker = RefreshWorker::start(client.clone());
        let mut app = Self {
            client,
            refresh_interval,
            default_base_rev,
            worker,
            last_refresh_requested: Instant::now() - refresh_interval,
            status_line: "press r to refresh, o for home, b for board, q to quit".to_owned(),
            should_quit: false,
            view: ViewMode::Home,
            selected_board_item_id: None,
            home: PanelState::default(),
            tracker: PanelState::default(),
            board: PanelState::default(),
            receipts: PanelState::default(),
        };
        app.request_full_refresh("loading cockpit");
        app
    }

    pub(crate) fn refresh_interval(&self) -> Duration {
        self.refresh_interval
    }

    pub(crate) fn should_refresh(&self) -> bool {
        self.last_refresh_requested.elapsed() >= self.refresh_interval
    }

    pub(crate) fn time_until_refresh(&self) -> Duration {
        self.refresh_interval
            .saturating_sub(self.last_refresh_requested.elapsed())
    }

    pub(crate) fn request_full_refresh(&mut self, reason: &str) {
        self.request_refresh(RefreshSet::all(), reason);
    }

    pub(crate) fn request_view_refresh(&mut self, reason: &str) {
        self.request_refresh(self.refresh_set_for_view(), reason);
    }

    pub(crate) fn drain_refresh_updates(&mut self) {
        let mut refreshed = RefreshSet::default();
        let mut failures = Vec::new();

        for update in self.worker.drain() {
            match update {
                RefreshUpdate::Home(result) => {
                    if apply_panel_update(&mut self.home, result, "home", &mut failures) {
                        refreshed.home = true;
                    }
                }
                RefreshUpdate::Tracker(result) => {
                    if apply_panel_update(&mut self.tracker, result, "tracker", &mut failures) {
                        refreshed.tracker = true;
                    }
                }
                RefreshUpdate::Board(result) => {
                    if apply_panel_update(&mut self.board, result, "board", &mut failures) {
                        refreshed.board = true;
                        self.sync_board_selection();
                    }
                }
                RefreshUpdate::Receipts(result) => {
                    if apply_panel_update(&mut self.receipts, result, "receipts", &mut failures) {
                        refreshed.receipts = true;
                    }
                }
            }
        }

        if let Some(message) = failures.into_iter().next() {
            self.status_line = message;
        } else if refreshed.any() {
            self.status_line = format!("updated {} at {}", refreshed.describe(), now_label());
        }
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

    pub(crate) fn handle_key(&mut self, key: KeyEvent) {
        match self.action_for_key(key) {
            Ok(Some(action)) => self.dispatch_action(action),
            Ok(None) => {}
            Err(message) => self.status_line = message,
        }
    }

    pub(crate) fn action_for_key(
        &self,
        key: KeyEvent,
    ) -> std::result::Result<Option<UiAction>, String> {
        let action = match key.code {
            KeyCode::Char('q') => Some(UiAction::Quit),
            KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                Some(UiAction::Quit)
            }
            KeyCode::Char('c') if self.view == ViewMode::Board => Some(self.claim_action()?),
            KeyCode::Char('f') if self.view == ViewMode::Board => Some(self.finish_action()?),
            KeyCode::Char('l') if self.view == ViewMode::Board => Some(self.launch_action()?),
            KeyCode::Char('r') => Some(UiAction::Refresh),
            KeyCode::Char('p') => Some(UiAction::Ping),
            KeyCode::Char('o') => Some(UiAction::SwitchView(ViewMode::Home)),
            KeyCode::Char('t') => Some(UiAction::SwitchView(ViewMode::Tracker)),
            KeyCode::Char('b') => Some(UiAction::SwitchView(ViewMode::Board)),
            KeyCode::Char('e') => Some(UiAction::SwitchView(ViewMode::Receipts)),
            KeyCode::Char('j') | KeyCode::Down if self.view == ViewMode::Board => {
                Some(UiAction::MoveBoardSelection(1))
            }
            KeyCode::Char('k') | KeyCode::Up if self.view == ViewMode::Board => {
                Some(UiAction::MoveBoardSelection(-1))
            }
            KeyCode::Tab => Some(UiAction::CycleView(Direction::Forward)),
            KeyCode::BackTab => Some(UiAction::CycleView(Direction::Backward)),
            _ => None,
        };

        Ok(action)
    }

    pub(crate) fn dispatch_action(&mut self, action: UiAction) {
        match action {
            UiAction::Quit => self.should_quit = true,
            UiAction::Refresh => self.request_full_refresh("manual refresh"),
            UiAction::Ping => self.ping(),
            UiAction::SwitchView(view) => {
                self.view = view;
                self.request_view_refresh("view refresh");
            }
            UiAction::CycleView(Direction::Forward) => {
                self.view = self.view.next();
                self.request_view_refresh("view refresh");
            }
            UiAction::CycleView(Direction::Backward) => {
                self.view = self.view.previous();
                self.request_view_refresh("view refresh");
            }
            UiAction::MoveBoardSelection(delta) => self.move_board_selection(delta),
            UiAction::Claim(issue_id) => self.claim_issue(&issue_id),
            UiAction::Launch(issue_id, base_rev) => self.launch_issue(&issue_id, &base_rev),
            UiAction::Finish(issue_id) => self.finish_lane(&issue_id),
            UiAction::Inspect(issue_id) => {
                self.status_line = format!("inspection is not available yet for {issue_id}");
            }
            UiAction::ShowHelp => {
                self.status_line = "help overlay is not available yet".to_owned();
            }
            UiAction::DismissOverlay => {}
        }
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

    fn claim_action(&self) -> std::result::Result<UiAction, String> {
        let issue_id = self
            .selected_board_item_id
            .clone()
            .ok_or_else(|| "no ready issue selected to claim".to_owned())?;
        let board = self
            .board
            .value
            .as_ref()
            .ok_or_else(|| "board data is unavailable".to_owned())?;
        let item = selected_board_item(board, Some(issue_id.as_str()))
            .ok_or_else(|| "selected board item is no longer available".to_owned())?;
        if item.kind() != BoardItemKind::ReadyIssue {
            return Err(format!("selected issue {issue_id} is not ready to claim"));
        }

        Ok(UiAction::Claim(issue_id))
    }

    fn claim_issue(&mut self, issue_id: &str) {
        let Some(board) = self.board.value.as_ref() else {
            self.status_line = "board data is unavailable".to_owned();
            return;
        };
        let Some(item) = selected_board_item(board, Some(issue_id)) else {
            self.status_line = "selected board item is no longer available".to_owned();
            return;
        };
        if item.kind() != BoardItemKind::ReadyIssue {
            self.status_line = format!("selected issue {issue_id} is not ready to claim");
            return;
        }

        match self.client.claim_issue(issue_id) {
            Ok(ClaimIssuePayload { issue_id }) => {
                self.request_full_refresh(&format!(
                    "claimed {issue_id}; launch base is {}",
                    self.default_base_rev
                ));
            }
            Err(error) => {
                self.status_line = format!("claim failed for {issue_id}: {error:#}");
            }
        }
    }

    fn launch_action(&self) -> std::result::Result<UiAction, String> {
        let issue_id = self
            .selected_board_item_id
            .clone()
            .ok_or_else(|| "no claimed issue selected to launch".to_owned())?;
        let board = self
            .board
            .value
            .as_ref()
            .ok_or_else(|| "board data is unavailable".to_owned())?;
        let item = selected_board_item(board, Some(issue_id.as_str()))
            .ok_or_else(|| "selected board item is no longer available".to_owned())?;
        if item.kind() != BoardItemKind::ClaimedIssue {
            return Err(format!("selected issue {issue_id} is not claimed yet"));
        }

        Ok(UiAction::Launch(issue_id, self.default_base_rev.clone()))
    }

    fn launch_issue(&mut self, issue_id: &str, base_rev: &str) {
        let Some(board) = self.board.value.as_ref() else {
            self.status_line = "board data is unavailable".to_owned();
            return;
        };
        let Some(item) = selected_board_item(board, Some(issue_id)) else {
            self.status_line = "selected board item is no longer available".to_owned();
            return;
        };
        if item.kind() != BoardItemKind::ClaimedIssue {
            self.status_line = format!("selected issue {issue_id} is not claimed yet");
            return;
        }

        match self.client.launch_lane(issue_id, base_rev) {
            Ok(LaunchLanePayload {
                issue_id,
                workspace_name,
                base_rev,
            }) => {
                self.request_full_refresh(&format!(
                    "launched {issue_id} in {workspace_name} from {base_rev}"
                ));
            }
            Err(error) => {
                self.status_line = format!("launch failed for {issue_id}: {error:#}");
            }
        }
    }

    fn finish_action(&self) -> std::result::Result<UiAction, String> {
        let issue_id = self
            .selected_board_item_id
            .clone()
            .ok_or_else(|| "no active lane selected to finish".to_owned())?;
        let board = self
            .board
            .value
            .as_ref()
            .ok_or_else(|| "board data is unavailable".to_owned())?;
        let item = selected_board_item(board, Some(issue_id.as_str()))
            .ok_or_else(|| "selected board item is no longer available".to_owned())?;
        if item.kind() != BoardItemKind::ActiveLane {
            return Err(format!("selected item {issue_id} is not an active lane"));
        }

        Ok(UiAction::Finish(issue_id))
    }

    fn finish_lane(&mut self, issue_id: &str) {
        let Some(board) = self.board.value.as_ref() else {
            self.status_line = "board data is unavailable".to_owned();
            return;
        };
        let Some(item) = selected_board_item(board, Some(issue_id)) else {
            self.status_line = "selected board item is no longer available".to_owned();
            return;
        };
        if item.kind() != BoardItemKind::ActiveLane {
            self.status_line = format!("selected item {issue_id} is not an active lane");
            return;
        }

        match self.client.finish_lane(issue_id, "completed") {
            Ok(FinishLanePayload { issue_id, outcome }) => {
                self.request_full_refresh(&format!("finished {issue_id} as {outcome}"));
            }
            Err(error) => {
                self.status_line = format!("finish failed for {issue_id}: {error:#}");
            }
        }
    }

    fn request_refresh(&mut self, requested: RefreshSet, reason: &str) {
        let queued = self.begin_refresh(requested);
        self.last_refresh_requested = Instant::now();

        if !queued.any() {
            self.status_line = format!("{reason}; refresh already in flight");
            return;
        }

        match self.worker.request(queued) {
            Ok(()) => {
                self.status_line = format!("{reason}; updating {}", queued.describe());
            }
            Err(error) => {
                self.cancel_refresh(queued);
                self.status_line = format!("{reason}; {error}");
            }
        }
    }

    fn begin_refresh(&mut self, requested: RefreshSet) -> RefreshSet {
        RefreshSet {
            home: requested.home && self.home.begin_refresh(),
            tracker: requested.tracker && self.tracker.begin_refresh(),
            board: requested.board && self.board.begin_refresh(),
            receipts: requested.receipts && self.receipts.begin_refresh(),
        }
    }

    fn cancel_refresh(&mut self, queued: RefreshSet) {
        if queued.home {
            self.home.cancel_refresh();
        }
        if queued.tracker {
            self.tracker.cancel_refresh();
        }
        if queued.board {
            self.board.cancel_refresh();
        }
        if queued.receipts {
            self.receipts.cancel_refresh();
        }
    }

    fn refresh_set_for_view(&self) -> RefreshSet {
        match self.view {
            ViewMode::Home => RefreshSet {
                home: true,
                ..RefreshSet::default()
            },
            ViewMode::Tracker => RefreshSet {
                tracker: true,
                ..RefreshSet::default()
            },
            ViewMode::Board => RefreshSet {
                board: true,
                ..RefreshSet::default()
            },
            ViewMode::Receipts => RefreshSet {
                receipts: true,
                ..RefreshSet::default()
            },
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
    last_success_at: Option<Instant>,
    refresh_in_flight: bool,
}

impl<T> Default for PanelState<T> {
    fn default() -> Self {
        Self {
            value: None,
            error: None,
            last_success_at: None,
            refresh_in_flight: false,
        }
    }
}

impl<T> PanelState<T> {
    pub(crate) fn begin_refresh(&mut self) -> bool {
        if self.refresh_in_flight {
            return false;
        }
        self.refresh_in_flight = true;
        true
    }

    pub(crate) fn cancel_refresh(&mut self) {
        self.refresh_in_flight = false;
    }

    pub(crate) fn apply_result(
        &mut self,
        result: std::result::Result<T, String>,
    ) -> PanelApplyOutcome {
        self.refresh_in_flight = false;
        match result {
            Ok(value) => {
                self.value = Some(value);
                self.error = None;
                self.last_success_at = Some(Instant::now());
                PanelApplyOutcome::Updated
            }
            Err(error) => {
                let stale = self.value.is_some();
                self.error = Some(error.clone());
                if stale {
                    PanelApplyOutcome::Stale(error)
                } else {
                    PanelApplyOutcome::Failed(error)
                }
            }
        }
    }

    pub(crate) fn is_refreshing(&self) -> bool {
        self.refresh_in_flight
    }

    pub(crate) fn has_value(&self) -> bool {
        self.value.is_some()
    }

    pub(crate) fn age(&self) -> Option<Duration> {
        self.last_success_at.map(|instant| instant.elapsed())
    }

    pub(crate) fn stale_message(&self) -> Option<&str> {
        self.error.as_deref().filter(|_| self.value.is_some())
    }
}

#[derive(Debug)]
pub(crate) enum PanelApplyOutcome {
    Updated,
    Stale(String),
    Failed(String),
}

fn apply_panel_update<T>(
    panel: &mut PanelState<T>,
    result: std::result::Result<T, String>,
    panel_name: &str,
    failures: &mut Vec<String>,
) -> bool {
    match panel.apply_result(result) {
        PanelApplyOutcome::Updated => true,
        PanelApplyOutcome::Stale(error) => {
            failures.push(format!(
                "{panel_name} refresh failed: {error}; showing last good data"
            ));
            false
        }
        PanelApplyOutcome::Failed(error) => {
            failures.push(format!("{panel_name} refresh failed: {error}"));
            false
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
    let observed_status = lane
        .observed_status
        .as_deref()
        .unwrap_or(lane.status.as_str());
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
    items.extend(
        active_lanes(board)
            .into_iter()
            .map(BoardItemRef::ActiveLane),
    );
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
    use std::path::PathBuf;

    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

    use super::{App, ViewMode, normalized_board_selection, step_board_selection};
    use crate::action::{Direction, UiAction};
    use crate::protocol::ProtocolClient;
    use crate::types::{BoardIssue, BoardStatus, LaneEntry};

    fn board_fixture() -> BoardStatus {
        BoardStatus {
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
        }
    }

    fn test_app() -> App {
        App::new(
            ProtocolClient::new(
                PathBuf::from("/tmp/repo"),
                PathBuf::from("/tmp/repo/.beads/tuskd/tuskd.sock"),
            ),
            std::time::Duration::from_secs(60),
            "main".to_owned(),
        )
    }

    #[test]
    fn selection_helpers_follow_board_item_order() {
        let board = board_fixture();

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

    #[test]
    fn action_for_key_maps_board_intents_to_typed_actions() {
        let mut app = test_app();
        app.view = ViewMode::Board;
        app.board.value = Some(board_fixture());

        app.selected_board_item_id = Some("tusk-a".to_owned());
        assert_eq!(
            app.action_for_key(KeyEvent::new(KeyCode::Char('c'), KeyModifiers::NONE)),
            Ok(Some(UiAction::Claim("tusk-a".to_owned())))
        );

        app.selected_board_item_id = Some("tusk-c".to_owned());
        assert_eq!(
            app.action_for_key(KeyEvent::new(KeyCode::Char('l'), KeyModifiers::NONE)),
            Ok(Some(UiAction::Launch(
                "tusk-c".to_owned(),
                "main".to_owned()
            )))
        );

        app.selected_board_item_id = Some("tusk-d".to_owned());
        assert_eq!(
            app.action_for_key(KeyEvent::new(KeyCode::Char('f'), KeyModifiers::NONE)),
            Ok(Some(UiAction::Finish("tusk-d".to_owned())))
        );
    }

    #[test]
    fn dispatch_action_updates_view_and_selection_without_rendering() {
        let mut app = test_app();
        app.board.value = Some(board_fixture());
        app.selected_board_item_id = Some("tusk-a".to_owned());

        app.dispatch_action(UiAction::SwitchView(ViewMode::Board));
        assert_eq!(app.view, ViewMode::Board);

        app.dispatch_action(UiAction::MoveBoardSelection(1));
        assert_eq!(app.selected_board_item_id.as_deref(), Some("tusk-b"));

        app.dispatch_action(UiAction::CycleView(Direction::Forward));
        assert_eq!(app.view, ViewMode::Receipts);
    }
}
