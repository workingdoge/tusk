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
    BoardViewModel, HomeViewModel, ReceiptsViewModel, TrackerViewModel, WorkersViewModel,
    board_viewmodel, home_viewmodel, issue_inspect_viewmodel, receipts_viewmodel,
    tracker_viewmodel, workers_viewmodel,
};
use crate::views::board::{board_lines, selected_line_offset};
use crate::views::home::{home_context_lines, home_history_lines, home_next_lines, home_now_lines};
use crate::views::overlay::issue_inspection_lines;
use crate::views::receipts::receipt_lines;
use crate::views::tracker::tracker_lines;
use crate::views::workers::workers_lines;
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
    input_mode: InputMode,
    filters: ViewFilters,
    scroll: ScrollOffsets,
    overlay: Option<OverlayState>,
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
            status_line: "press r to refresh, o for home, w for workers, b for board, q to quit"
                .to_owned(),
            should_quit: false,
            view: ViewMode::Home,
            selected_board_item_id: None,
            input_mode: InputMode::Normal,
            filters: ViewFilters::default(),
            scroll: ScrollOffsets::default(),
            overlay: None,
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

    pub(crate) fn workers_viewmodel(&self) -> Option<WorkersViewModel> {
        self.home.value.as_ref().map(workers_viewmodel)
    }

    pub(crate) fn board_viewmodel(&self) -> Option<BoardViewModel> {
        self.board.value.as_ref().map(|board| {
            board_viewmodel(
                board,
                self.selected_board_item_id.as_deref(),
                self.board_filter_query(),
            )
        })
    }

    pub(crate) fn receipts_viewmodel(&self) -> Option<ReceiptsViewModel> {
        self.receipts
            .value
            .as_ref()
            .map(|receipts| receipts_viewmodel(receipts, self.receipts_filter_query()))
    }

    pub(crate) fn overlay(&self) -> Option<&OverlayState> {
        self.overlay.as_ref()
    }

    pub(crate) fn filter_bar(&self) -> Option<FilterBarState> {
        if !matches!(self.view, ViewMode::Board | ViewMode::Receipts) {
            return None;
        }

        let query = self.active_filter_text();
        if !self.is_filter_mode() && query.is_empty() {
            return None;
        }

        let (scope, placeholder, visible_items) = match self.view {
            ViewMode::Board => (
                "board",
                "filter issues and lanes by id or title",
                self.board_viewmodel()
                    .map(|board| {
                        board.ready_issues.len()
                            + board.claimed_issues.len()
                            + board.blocked_issues.len()
                            + board.deferred_issues.len()
                            + board.active_lanes.len()
                            + board.finished_lanes.len()
                            + board.stale_lanes.len()
                    })
                    .unwrap_or_default(),
            ),
            ViewMode::Receipts => (
                "receipts",
                "filter receipts by kind or timestamp",
                self.receipts_viewmodel()
                    .map(|receipts| receipts.receipts.len())
                    .unwrap_or_default(),
            ),
            _ => return None,
        };

        Some(FilterBarState {
            scope: scope.to_owned(),
            query: query.to_owned(),
            placeholder: placeholder.to_owned(),
            editing: self.is_filter_mode(),
            visible_items,
        })
    }

    pub(crate) fn repo_name(&self) -> String {
        self.client
            .repo_root
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or("repo")
            .to_owned()
    }

    pub(crate) fn socket_is_live(&self) -> bool {
        self.client.socket_path.exists()
    }

    pub(crate) fn transport_label(&self) -> &'static str {
        if self.socket_is_live() {
            "socket"
        } else {
            "fallback"
        }
    }

    pub(crate) fn transport_detail(&self) -> String {
        if self.socket_is_live() {
            self.client.socket_path.display().to_string()
        } else {
            "tuskd respond".to_owned()
        }
    }

    pub(crate) fn footer_actions(&self) -> &'static str {
        if let Some(overlay) = self.overlay() {
            return overlay.footer_hint();
        }

        if self.is_filter_mode() {
            return "type to filter  Backspace delete  Enter keep query  Esc clear  q quit";
        }

        match self.view {
            ViewMode::Home => {
                "o/w/t/b/e view  Tab cycle  ? help  i inspect  j/k scroll  PgUp/PgDn page  g/G edge  b board  r refresh  p ping  q quit"
            }
            ViewMode::Workers => {
                "o/w/t/b/e view  Tab cycle  ? help  j/k scroll  PgUp/PgDn page  g/G edge  r refresh  p ping  q quit"
            }
            ViewMode::Board => {
                "o/w/t/b/e view  Tab cycle  ? help  / filter  i inspect  j/k move  PgUp/PgDn page  g/G edge  Esc clear  c claim  l launch  f finish  r refresh  p ping  q quit"
            }
            ViewMode::Receipts => {
                "o/w/t/b/e view  Tab cycle  ? help  / filter  j/k scroll  PgUp/PgDn page  g/G edge  Esc clear  r refresh  p ping  q quit"
            }
            _ => {
                "o/w/t/b/e view  Tab cycle  ? help  j/k scroll  PgUp/PgDn page  g/G edge  r refresh  p ping  q quit"
            }
        }
    }

    pub(crate) fn any_panel_refreshing(&self) -> bool {
        self.home.is_refreshing()
            || self.tracker.is_refreshing()
            || self.board.is_refreshing()
            || self.receipts.is_refreshing()
    }

    pub(crate) fn current_panel_age(&self) -> Option<Duration> {
        match self.view {
            ViewMode::Home => self.home.age(),
            ViewMode::Workers => self.home.age(),
            ViewMode::Tracker => self.tracker.age(),
            ViewMode::Board => self.board.age(),
            ViewMode::Receipts => self.receipts.age(),
        }
    }

    pub(crate) fn current_panel_is_refreshing(&self) -> bool {
        match self.view {
            ViewMode::Home => self.home.is_refreshing(),
            ViewMode::Workers => self.home.is_refreshing(),
            ViewMode::Tracker => self.tracker.is_refreshing(),
            ViewMode::Board => self.board.is_refreshing(),
            ViewMode::Receipts => self.receipts.is_refreshing(),
        }
    }

    pub(crate) fn current_scroll_offset(&self) -> u16 {
        match self.view {
            ViewMode::Home => self.scroll.home,
            ViewMode::Workers => self.scroll.workers,
            ViewMode::Tracker => self.scroll.tracker,
            ViewMode::Board => self.scroll.board,
            ViewMode::Receipts => self.scroll.receipts,
        }
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
        if self.overlay.is_some() {
            return Ok(self.overlay_action_for_key(key));
        }

        if self.is_filter_mode() {
            return Ok(self.filter_action_for_key(key));
        }

        let action = match key.code {
            KeyCode::Char('q') => Some(UiAction::Quit),
            KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                Some(UiAction::Quit)
            }
            KeyCode::Esc if self.has_active_filter() => Some(UiAction::ClearFilter),
            KeyCode::Char('/') if matches!(self.view, ViewMode::Board | ViewMode::Receipts) => {
                Some(UiAction::StartFilter)
            }
            KeyCode::Char('c') if self.view == ViewMode::Board => Some(self.claim_action()?),
            KeyCode::Char('f') if self.view == ViewMode::Board => Some(self.finish_action()?),
            KeyCode::Char('l') if self.view == ViewMode::Board => Some(self.launch_action()?),
            KeyCode::Char('r') => Some(UiAction::Refresh),
            KeyCode::Char('p') => Some(UiAction::Ping),
            KeyCode::Char('?') | KeyCode::Char('h') => Some(UiAction::ShowHelp),
            KeyCode::Char('i') if matches!(self.view, ViewMode::Home | ViewMode::Board) => {
                Some(self.inspect_action()?)
            }
            KeyCode::Char('j') | KeyCode::Down if self.view != ViewMode::Board => {
                Some(UiAction::Scroll(1))
            }
            KeyCode::Char('k') | KeyCode::Up if self.view != ViewMode::Board => {
                Some(UiAction::Scroll(-1))
            }
            KeyCode::Char('o') => Some(UiAction::SwitchView(ViewMode::Home)),
            KeyCode::Char('w') => Some(UiAction::SwitchView(ViewMode::Workers)),
            KeyCode::Char('t') => Some(UiAction::SwitchView(ViewMode::Tracker)),
            KeyCode::Char('b') => Some(UiAction::SwitchView(ViewMode::Board)),
            KeyCode::Char('e') => Some(UiAction::SwitchView(ViewMode::Receipts)),
            KeyCode::Char('j') | KeyCode::Down if self.view == ViewMode::Board => {
                Some(UiAction::MoveBoardSelection(1))
            }
            KeyCode::Char('k') | KeyCode::Up if self.view == ViewMode::Board => {
                Some(UiAction::MoveBoardSelection(-1))
            }
            KeyCode::PageDown => Some(UiAction::ScrollPage(10)),
            KeyCode::PageUp => Some(UiAction::ScrollPage(-10)),
            KeyCode::Char('g') => Some(UiAction::ScrollToTop),
            KeyCode::Char('G') => Some(UiAction::ScrollToBottom),
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
            UiAction::StartFilter => self.start_filter(),
            UiAction::FilterAppend(ch) => self.append_filter(ch),
            UiAction::FilterBackspace => self.backspace_filter(),
            UiAction::CommitFilter => self.commit_filter(),
            UiAction::ClearFilter => self.clear_filter(),
            UiAction::SwitchView(view) => {
                self.clear_all_filters();
                self.input_mode = InputMode::Normal;
                self.view = view;
                self.request_view_refresh("view refresh");
            }
            UiAction::CycleView(Direction::Forward) => {
                self.clear_all_filters();
                self.input_mode = InputMode::Normal;
                self.view = self.view.next();
                self.request_view_refresh("view refresh");
            }
            UiAction::CycleView(Direction::Backward) => {
                self.clear_all_filters();
                self.input_mode = InputMode::Normal;
                self.view = self.view.previous();
                self.request_view_refresh("view refresh");
            }
            UiAction::Scroll(delta) => self.scroll_current_view(delta),
            UiAction::ScrollPage(delta) => self.scroll_current_view(delta),
            UiAction::ScrollToTop => self.scroll_current_view_to_top(),
            UiAction::ScrollToBottom => self.scroll_current_view_to_bottom(),
            UiAction::MoveBoardSelection(delta) => self.move_board_selection(delta),
            UiAction::Claim(issue_id) => self.open_claim_overlay(&issue_id),
            UiAction::Launch(issue_id, base_rev) => self.open_launch_overlay(&issue_id, &base_rev),
            UiAction::Finish(issue_id) => self.open_finish_overlay(&issue_id),
            UiAction::Inspect(issue_id) => self.open_inspect_overlay(&issue_id),
            UiAction::ShowHelp => self.show_help_overlay(),
            UiAction::ConfirmOverlay => self.confirm_overlay(),
            UiAction::DismissOverlay => self.dismiss_overlay(),
        }
    }

    fn filter_action_for_key(&self, key: KeyEvent) -> Option<UiAction> {
        match key.code {
            KeyCode::Char('q') => Some(UiAction::Quit),
            KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                Some(UiAction::Quit)
            }
            KeyCode::Enter => Some(UiAction::CommitFilter),
            KeyCode::Esc => Some(UiAction::ClearFilter),
            KeyCode::Backspace => Some(UiAction::FilterBackspace),
            KeyCode::Char(ch)
                if !key
                    .modifiers
                    .intersects(KeyModifiers::CONTROL | KeyModifiers::ALT) =>
            {
                Some(UiAction::FilterAppend(ch))
            }
            _ => None,
        }
    }

    fn overlay_action_for_key(&self, key: KeyEvent) -> Option<UiAction> {
        match key.code {
            KeyCode::Char('q') => Some(UiAction::Quit),
            KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                Some(UiAction::Quit)
            }
            KeyCode::Esc => Some(UiAction::DismissOverlay),
            KeyCode::Char('?') | KeyCode::Char('h')
                if self.overlay.as_ref().is_some_and(OverlayState::is_help) =>
            {
                Some(UiAction::DismissOverlay)
            }
            KeyCode::Char('i') if self.overlay.as_ref().is_some_and(OverlayState::is_inspect) => {
                Some(UiAction::DismissOverlay)
            }
            KeyCode::Enter | KeyCode::Char('y')
                if self.overlay.as_ref().is_some_and(OverlayState::is_confirm) =>
            {
                Some(UiAction::ConfirmOverlay)
            }
            KeyCode::Char('n') if self.overlay.as_ref().is_some_and(OverlayState::is_confirm) => {
                Some(UiAction::DismissOverlay)
            }
            _ => None,
        }
    }

    fn sync_board_selection(&mut self) {
        let Some(board) = self.board.value.as_ref() else {
            self.selected_board_item_id = None;
            self.scroll.board = 0;
            return;
        };

        self.selected_board_item_id = normalized_board_selection(
            board,
            self.selected_board_item_id.as_deref(),
            self.board_filter_query(),
        );
        self.sync_board_scroll();
    }

    fn move_board_selection(&mut self, delta: isize) {
        let Some(board) = self.board.value.as_ref() else {
            self.status_line = "board data is unavailable".to_owned();
            return;
        };

        let Some(next) = step_board_selection(
            board,
            self.selected_board_item_id.as_deref(),
            delta,
            self.board_filter_query(),
        ) else {
            self.selected_board_item_id = None;
            self.status_line = "no selectable board items".to_owned();
            return;
        };

        self.selected_board_item_id = Some(next.clone());
        self.sync_board_scroll();
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

    fn inspect_action(&self) -> std::result::Result<UiAction, String> {
        match self.view {
            ViewMode::Home => {
                let home = self
                    .home_viewmodel()
                    .ok_or_else(|| "home snapshot is unavailable".to_owned())?;
                let issue_id = home
                    .primary_action
                    .as_ref()
                    .and_then(|action| action.issue_id.clone())
                    .or_else(|| home.focus.as_ref().map(|focus| focus.issue_id.clone()))
                    .ok_or_else(|| "no focus issue is available to inspect".to_owned())?;
                Ok(UiAction::Inspect(issue_id))
            }
            ViewMode::Board => {
                let issue_id = self
                    .selected_board_item_id
                    .clone()
                    .ok_or_else(|| "no board item is selected to inspect".to_owned())?;
                Ok(UiAction::Inspect(issue_id))
            }
            _ => Err("inspection is only available from home or board".to_owned()),
        }
    }

    fn start_filter(&mut self) {
        if !matches!(self.view, ViewMode::Board | ViewMode::Receipts) {
            self.status_line = "filtering is only available on board or receipts".to_owned();
            return;
        }

        self.input_mode = InputMode::Filter;
        self.status_line = format!("editing {} filter", self.view.label());
    }

    fn append_filter(&mut self, ch: char) {
        let Some(query) = self.active_filter_text_mut() else {
            self.status_line = "no active filter target".to_owned();
            return;
        };

        query.push(ch);
        self.apply_filter_change();
        self.status_line = format!(
            "{} filter: {}",
            self.view.label(),
            self.active_filter_text()
        );
    }

    fn backspace_filter(&mut self) {
        let Some(query) = self.active_filter_text_mut() else {
            self.status_line = "no active filter target".to_owned();
            return;
        };

        query.pop();
        self.apply_filter_change();
        self.status_line = if self.active_filter_text().is_empty() {
            format!("{} filter cleared", self.view.label())
        } else {
            format!(
                "{} filter: {}",
                self.view.label(),
                self.active_filter_text()
            )
        };
    }

    fn commit_filter(&mut self) {
        self.input_mode = InputMode::Normal;
        self.status_line = if self.has_active_filter() {
            format!(
                "{} filter locked: {}",
                self.view.label(),
                self.active_filter_text()
            )
        } else {
            format!("{} filter cleared", self.view.label())
        };
    }

    fn clear_filter(&mut self) {
        let cleared = self.clear_active_filter();
        self.input_mode = InputMode::Normal;
        if cleared {
            self.apply_filter_change();
            self.status_line = format!("cleared {} filter", self.view.label());
        } else {
            self.status_line = format!("{} filter already empty", self.view.label());
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
            ViewMode::Workers => RefreshSet {
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

    fn show_help_overlay(&mut self) {
        self.overlay = Some(OverlayState::help(self.view));
        self.status_line = "showing help overlay".to_owned();
    }

    fn open_inspect_overlay(&mut self, issue_id: &str) {
        match self.client.inspect_issue(issue_id) {
            Ok(inspection) => {
                let home = self.home_viewmodel();
                let model = issue_inspect_viewmodel(&inspection, home.as_ref());
                self.overlay = Some(OverlayState::inspect(
                    format!("Inspect — {}", model.issue_id),
                    issue_inspection_lines(&model),
                ));
                self.status_line = format!("inspecting {issue_id}");
            }
            Err(error) => {
                self.status_line = format!("inspect failed for {issue_id}: {error:#}");
            }
        }
    }

    fn dismiss_overlay(&mut self) {
        if self.overlay.take().is_some() {
            self.status_line = "dismissed overlay".to_owned();
        }
    }

    fn confirm_overlay(&mut self) {
        let Some(overlay) = self.overlay.take() else {
            return;
        };

        match overlay.kind {
            OverlayKind::Help => {
                self.status_line = "dismissed help overlay".to_owned();
            }
            OverlayKind::Confirm(action) => self.execute_pending_action(action),
            OverlayKind::Inspect => {
                self.status_line = "dismissed inspection overlay".to_owned();
            }
        }
    }

    fn execute_pending_action(&mut self, action: PendingAction) {
        match action {
            PendingAction::Claim { issue_id } => self.claim_issue(&issue_id),
            PendingAction::Launch { issue_id, base_rev } => self.launch_issue(&issue_id, &base_rev),
            PendingAction::Finish { issue_id } => self.finish_lane(&issue_id),
        }
    }

    fn open_claim_overlay(&mut self, issue_id: &str) {
        self.overlay = Some(OverlayState::confirm(
            format!("Claim {issue_id}?"),
            vec![
                self.issue_line(issue_id),
                format!("launch base after claim: {}", self.default_base_rev),
                "confirm to move this ready issue into claimed state".to_owned(),
            ],
            PendingAction::Claim {
                issue_id: issue_id.to_owned(),
            },
        ));
        self.status_line = format!("confirm claim for {issue_id}");
    }

    fn open_launch_overlay(&mut self, issue_id: &str, base_rev: &str) {
        self.overlay = Some(OverlayState::confirm(
            format!("Launch lane for {issue_id}?"),
            vec![
                self.issue_line(issue_id),
                format!("base revision: {base_rev}"),
                "confirm to create the workspace lane and move the issue into active work"
                    .to_owned(),
            ],
            PendingAction::Launch {
                issue_id: issue_id.to_owned(),
                base_rev: base_rev.to_owned(),
            },
        ));
        self.status_line = format!("confirm launch for {issue_id}");
    }

    fn open_finish_overlay(&mut self, issue_id: &str) {
        self.overlay = Some(OverlayState::confirm(
            format!("Finish lane for {issue_id}?"),
            vec![
                self.issue_line(issue_id),
                "outcome: completed".to_owned(),
                "confirm to finish the active lane and refresh cockpit state".to_owned(),
            ],
            PendingAction::Finish {
                issue_id: issue_id.to_owned(),
            },
        ));
        self.status_line = format!("confirm finish for {issue_id}");
    }

    fn issue_line(&self, issue_id: &str) -> String {
        match self.board_item_title(issue_id) {
            Some(title) => format!("{issue_id} — {title}"),
            None => issue_id.to_owned(),
        }
    }

    fn board_item_title(&self, issue_id: &str) -> Option<String> {
        let board = self.board.value.as_ref()?;
        selected_board_item(board, Some(issue_id)).map(|item| match item {
            BoardItemRef::ReadyIssue(issue) | BoardItemRef::ClaimedIssue(issue) => {
                issue.title.clone()
            }
            BoardItemRef::ActiveLane(lane) => lane.issue_title.clone(),
        })
    }

    fn is_filter_mode(&self) -> bool {
        self.input_mode == InputMode::Filter
    }

    fn has_active_filter(&self) -> bool {
        !self.active_filter_text().trim().is_empty()
    }

    fn board_filter_query(&self) -> Option<&str> {
        normalized_filter_query(self.filters.board.as_str())
    }

    fn receipts_filter_query(&self) -> Option<&str> {
        normalized_filter_query(self.filters.receipts.as_str())
    }

    fn active_filter_text(&self) -> &str {
        match self.view {
            ViewMode::Board => &self.filters.board,
            ViewMode::Receipts => &self.filters.receipts,
            _ => "",
        }
    }

    fn active_filter_text_mut(&mut self) -> Option<&mut String> {
        match self.view {
            ViewMode::Board => Some(&mut self.filters.board),
            ViewMode::Receipts => Some(&mut self.filters.receipts),
            _ => None,
        }
    }

    fn clear_active_filter(&mut self) -> bool {
        let Some(query) = self.active_filter_text_mut() else {
            return false;
        };
        let had_value = !query.is_empty();
        query.clear();
        had_value
    }

    fn clear_all_filters(&mut self) {
        self.filters = ViewFilters::default();
    }

    fn apply_filter_change(&mut self) {
        match self.view {
            ViewMode::Board => {
                self.sync_board_selection();
            }
            ViewMode::Receipts => {
                self.scroll.receipts = 0;
            }
            _ => {}
        }
    }

    fn current_scroll_offset_mut(&mut self) -> &mut u16 {
        match self.view {
            ViewMode::Home => &mut self.scroll.home,
            ViewMode::Workers => &mut self.scroll.workers,
            ViewMode::Tracker => &mut self.scroll.tracker,
            ViewMode::Board => &mut self.scroll.board,
            ViewMode::Receipts => &mut self.scroll.receipts,
        }
    }

    fn current_view_line_count(&self) -> usize {
        match self.view {
            ViewMode::Home => self
                .home_viewmodel()
                .map(|home| {
                    home_now_lines(&home).len()
                        + home_next_lines(&home).len()
                        + home_history_lines(&home).len()
                        + home_context_lines(&home).len()
                })
                .unwrap_or(1),
            ViewMode::Workers => self
                .workers_viewmodel()
                .map(|workers| workers_lines(&workers).len())
                .unwrap_or(1),
            ViewMode::Tracker => self
                .tracker_viewmodel()
                .map(|tracker| tracker_lines(&tracker).len())
                .unwrap_or(1),
            ViewMode::Board => self
                .board_viewmodel()
                .map(|board| board_lines(&board).len())
                .unwrap_or(1),
            ViewMode::Receipts => self
                .receipts_viewmodel()
                .map(|receipts| receipt_lines(&receipts, &self.receipts).len())
                .unwrap_or(1),
        }
    }

    fn scroll_current_view(&mut self, delta: isize) {
        let max_offset = self.current_view_line_count().saturating_sub(1) as u16;
        let current = *self.current_scroll_offset_mut();
        let next = if delta.is_negative() {
            current.saturating_sub(delta.unsigned_abs() as u16)
        } else {
            current.saturating_add(delta as u16).min(max_offset)
        };
        *self.current_scroll_offset_mut() = next;
        self.status_line = format!("{} scroll {}", self.view.label(), next);
    }

    fn scroll_current_view_to_top(&mut self) {
        *self.current_scroll_offset_mut() = 0;
        self.status_line = format!("{} scroll top", self.view.label());
    }

    fn scroll_current_view_to_bottom(&mut self) {
        let max_offset = self.current_view_line_count().saturating_sub(1) as u16;
        *self.current_scroll_offset_mut() = max_offset;
        self.status_line = format!("{} scroll {}", self.view.label(), max_offset);
    }

    fn sync_board_scroll(&mut self) {
        let Some(board) = self.board_viewmodel() else {
            return;
        };

        if let Some(line) = selected_line_offset(&board) {
            self.scroll.board = line.saturating_sub(2) as u16;
        }
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(crate) struct ScrollOffsets {
    home: u16,
    workers: u16,
    tracker: u16,
    board: u16,
    receipts: u16,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
enum InputMode {
    #[default]
    Normal,
    Filter,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
struct ViewFilters {
    board: String,
    receipts: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct FilterBarState {
    pub(crate) scope: String,
    pub(crate) query: String,
    pub(crate) placeholder: String,
    pub(crate) editing: bool,
    pub(crate) visible_items: usize,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum ViewMode {
    Home,
    Workers,
    Tracker,
    Board,
    Receipts,
}

impl ViewMode {
    pub(crate) fn label(self) -> &'static str {
        match self {
            Self::Home => "home",
            Self::Workers => "workers",
            Self::Tracker => "tracker",
            Self::Board => "board",
            Self::Receipts => "receipts",
        }
    }

    pub(crate) fn next(self) -> Self {
        match self {
            Self::Home => Self::Workers,
            Self::Workers => Self::Tracker,
            Self::Tracker => Self::Board,
            Self::Board => Self::Receipts,
            Self::Receipts => Self::Home,
        }
    }

    pub(crate) fn previous(self) -> Self {
        match self {
            Self::Home => Self::Receipts,
            Self::Workers => Self::Home,
            Self::Tracker => Self::Workers,
            Self::Board => Self::Tracker,
            Self::Receipts => Self::Board,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct OverlayState {
    pub(crate) title: String,
    pub(crate) body: Vec<String>,
    kind: OverlayKind,
}

impl OverlayState {
    fn help(view: ViewMode) -> Self {
        let mut body = vec![
            "Global".to_owned(),
            "  o / w / t / b / e  switch views".to_owned(),
            "  Tab / Shift+Tab cycle views".to_owned(),
            "  PageUp / PageDown scroll the current panel".to_owned(),
            "  g / G          jump to top or bottom of the current panel".to_owned(),
            "  r              refresh the cockpit".to_owned(),
            "  p              ping the service".to_owned(),
            "  q              quit tusk-ui".to_owned(),
            "  Esc            dismiss this overlay".to_owned(),
            "  Issue work     claim an issue, then launch a lane from main instead of editing default".to_owned(),
            "  tuskd launch-lane --repo <tracker-root> --issue-id <id> --base-rev main".to_owned(),
            "".to_owned(),
        ];

        match view {
            ViewMode::Home => {
                body.push("Home".to_owned());
                body.push("  j / k or Up / Down scroll the briefing".to_owned());
                body.push("  i              inspect the focus issue".to_owned());
                body.push("  Read the current briefing, next move, and recent history".to_owned());
                body.push("  Press b to jump into the board for action".to_owned());
            }
            ViewMode::Workers => {
                body.push("Workers".to_owned());
                body.push("  j / k or Up / Down scroll session state".to_owned());
                body.push("  Review live sessions, stale workers, and recent exits".to_owned());
                body.push("  Use this view when worker pressure matters more than lane counts".to_owned());
            }
            ViewMode::Tracker => {
                body.push("Tracker".to_owned());
                body.push("  j / k or Up / Down scroll tracker details".to_owned());
                body.push("  Inspect service health, leases, and backend state".to_owned());
            }
            ViewMode::Board => {
                body.push("Board".to_owned());
                body.push("  /                  edit the local board filter".to_owned());
                body.push("  j / k or Up / Down  move selection".to_owned());
                body.push(
                    "  PageUp / PageDown   scroll the board without changing selection".to_owned(),
                );
                body.push("  g / G               jump to top or bottom of the board".to_owned());
                body.push("  i                  inspect the selected issue or lane".to_owned());
                body.push("  c                  confirm claim for selected ready issue".to_owned());
                body.push(
                    "  l                  confirm lane launch for selected claimed issue"
                        .to_owned(),
                );
                body.push(
                    "  f                  confirm finish for selected active lane".to_owned(),
                );
            }
            ViewMode::Receipts => {
                body.push("Receipts".to_owned());
                body.push("  /                  edit the local receipts filter".to_owned());
                body.push("  j / k or Up / Down scroll recent receipts".to_owned());
                body.push("  Review recent authoritative transitions from tuskd".to_owned());
            }
        }

        Self {
            title: format!("Help — {}", view.label()),
            body,
            kind: OverlayKind::Help,
        }
    }

    fn confirm(title: String, body: Vec<String>, action: PendingAction) -> Self {
        Self {
            title,
            body,
            kind: OverlayKind::Confirm(action),
        }
    }

    fn inspect(title: String, body: Vec<String>) -> Self {
        Self {
            title,
            body,
            kind: OverlayKind::Inspect,
        }
    }

    pub(crate) fn is_help(&self) -> bool {
        matches!(self.kind, OverlayKind::Help)
    }

    pub(crate) fn is_confirm(&self) -> bool {
        matches!(self.kind, OverlayKind::Confirm(_))
    }

    pub(crate) fn is_inspect(&self) -> bool {
        matches!(self.kind, OverlayKind::Inspect)
    }

    pub(crate) fn footer_hint(&self) -> &'static str {
        match self.kind {
            OverlayKind::Help => "Esc dismiss  q quit",
            OverlayKind::Confirm(_) => "Enter/y confirm  n/Esc cancel  q quit",
            OverlayKind::Inspect => "i/Esc dismiss  q quit",
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum OverlayKind {
    Help,
    Confirm(PendingAction),
    Inspect,
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum PendingAction {
    Claim { issue_id: String },
    Launch { issue_id: String, base_rev: String },
    Finish { issue_id: String },
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

fn normalized_filter_query(query: &str) -> Option<&str> {
    let trimmed = query.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed)
    }
}

fn filter_matches(haystack: &str, filter_query: Option<&str>) -> bool {
    match filter_query {
        Some(filter) => haystack.to_lowercase().contains(&filter.to_lowercase()),
        None => true,
    }
}

fn board_issue_matches_filter(issue: &BoardIssue, filter_query: Option<&str>) -> bool {
    filter_matches(&format!("{} {}", issue.id, issue.title), filter_query)
}

fn lane_matches_filter(lane: &LaneEntry, filter_query: Option<&str>) -> bool {
    filter_matches(
        &format!("{} {}", lane.issue_id, lane.issue_title),
        filter_query,
    )
}

fn board_items<'a>(board: &'a BoardStatus, filter_query: Option<&str>) -> Vec<BoardItemRef<'a>> {
    let mut items = Vec::with_capacity(
        board.ready_issues.len() + board.claimed_issues.len() + board.lanes.len(),
    );
    items.extend(
        board
            .ready_issues
            .iter()
            .filter(|issue| board_issue_matches_filter(issue, filter_query))
            .map(BoardItemRef::ReadyIssue),
    );
    items.extend(
        board
            .claimed_issues
            .iter()
            .filter(|issue| board_issue_matches_filter(issue, filter_query))
            .map(BoardItemRef::ClaimedIssue),
    );
    items.extend(
        active_lanes(board)
            .into_iter()
            .filter(|lane| lane_matches_filter(lane, filter_query))
            .map(BoardItemRef::ActiveLane),
    );
    items
}

fn selected_board_item<'a>(
    board: &'a BoardStatus,
    selected_board_item_id: Option<&str>,
) -> Option<BoardItemRef<'a>> {
    let selected_board_item_id = selected_board_item_id?;
    board_items(board, None)
        .into_iter()
        .find(|item| item.id() == selected_board_item_id)
}

pub(crate) fn normalized_board_selection(
    board: &BoardStatus,
    selected_board_item_id: Option<&str>,
    filter_query: Option<&str>,
) -> Option<String> {
    let items = board_items(board, filter_query);
    if items.is_empty() {
        return None;
    }

    if let Some(selected_board_item_id) = selected_board_item_id {
        if items.iter().any(|item| item.id() == selected_board_item_id) {
            return Some(selected_board_item_id.to_owned());
        }
    }

    Some(items[0].id().to_owned())
}

pub(crate) fn step_board_selection(
    board: &BoardStatus,
    selected_board_item_id: Option<&str>,
    delta: isize,
    filter_query: Option<&str>,
) -> Option<String> {
    let items = board_items(board, filter_query);
    if items.is_empty() {
        return None;
    }

    let current_index: usize = selected_board_item_id
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

    use super::{App, OverlayState, ViewMode, normalized_board_selection, step_board_selection};
    use crate::action::{Direction, UiAction};
    use crate::protocol::ProtocolClient;
    use crate::types::{
        BackendStatus, BoardIssue, BoardStatus, HealthStatus, LaneEntry, TrackerProtocol,
        TuskdState, sample_operator_snapshot,
    };

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
            sessions: None,
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
            normalized_board_selection(&board, None, None),
            Some("tusk-a".to_owned())
        );
        assert_eq!(
            step_board_selection(&board, Some("tusk-a"), 1, None),
            Some("tusk-b".to_owned())
        );
        assert_eq!(
            step_board_selection(&board, Some("tusk-b"), 1, None),
            Some("tusk-c".to_owned())
        );
        assert_eq!(
            step_board_selection(&board, Some("tusk-c"), 1, None),
            Some("tusk-d".to_owned())
        );
        assert_eq!(
            step_board_selection(&board, Some("tusk-d"), 1, None),
            Some("tusk-d".to_owned())
        );
        assert_eq!(
            step_board_selection(&board, Some("tusk-d"), -1, None),
            Some("tusk-c".to_owned())
        );
        assert_eq!(
            normalized_board_selection(&board, Some("tusk-d"), None),
            Some("tusk-d".to_owned())
        );
        assert_eq!(
            step_board_selection(&board, Some("tusk-c"), -1, None),
            Some("tusk-b".to_owned())
        );
        assert_eq!(
            step_board_selection(&board, Some("tusk-b"), -1, None),
            Some("tusk-a".to_owned())
        );
    }

    #[test]
    fn selection_helpers_follow_filtered_board_order() {
        let board = board_fixture();

        assert_eq!(
            normalized_board_selection(&board, None, Some("claimed")),
            Some("tusk-c".to_owned())
        );
        assert_eq!(
            step_board_selection(&board, Some("tusk-c"), 1, Some("claimed")),
            Some("tusk-c".to_owned())
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
    fn action_for_key_maps_scroll_intents_outside_board() {
        let mut app = test_app();
        app.view = ViewMode::Home;

        assert_eq!(
            app.action_for_key(KeyEvent::new(KeyCode::Char('j'), KeyModifiers::NONE)),
            Ok(Some(UiAction::Scroll(1)))
        );
        assert_eq!(
            app.action_for_key(KeyEvent::new(KeyCode::PageDown, KeyModifiers::NONE)),
            Ok(Some(UiAction::ScrollPage(10)))
        );
        assert_eq!(
            app.action_for_key(KeyEvent::new(KeyCode::Char('g'), KeyModifiers::NONE)),
            Ok(Some(UiAction::ScrollToTop))
        );
        assert_eq!(
            app.action_for_key(KeyEvent::new(KeyCode::Char('G'), KeyModifiers::SHIFT)),
            Ok(Some(UiAction::ScrollToBottom))
        );
        assert_eq!(
            app.action_for_key(KeyEvent::new(KeyCode::Char('w'), KeyModifiers::NONE)),
            Ok(Some(UiAction::SwitchView(ViewMode::Workers)))
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
        assert!(app.scroll.board > 0);

        app.dispatch_action(UiAction::CycleView(Direction::Forward));
        assert_eq!(app.view, ViewMode::Receipts);

        app.dispatch_action(UiAction::CycleView(Direction::Backward));
        assert_eq!(app.view, ViewMode::Board);
    }

    #[test]
    fn dispatch_action_updates_scroll_state_without_rendering() {
        let mut app = test_app();
        app.view = ViewMode::Tracker;

        app.dispatch_action(UiAction::Scroll(3));
        assert_eq!(app.current_scroll_offset(), 0);

        app.tracker.value = Some(crate::types::TrackerStatus {
            repo_root: "/tmp/repo".to_owned(),
            protocol: TrackerProtocol {
                endpoint: "/tmp/repo/.beads/tuskd/tuskd.sock".to_owned(),
            },
            tuskd: TuskdState {
                mode: "idle".to_owned(),
                pid: None,
            },
            health: HealthStatus {
                status: "healthy".to_owned(),
                checked_at: "2026-03-26T00:00:00Z".to_owned(),
                backend: Some(BackendStatus {
                    running: Some(true),
                    pid: Some(1234),
                    port: Some(32642),
                    data_dir: Some("/tmp/repo/.beads/dolt".to_owned()),
                }),
                summary: None,
            },
            active_leases: vec![],
        });

        app.dispatch_action(UiAction::Scroll(3));
        assert_eq!(app.current_scroll_offset(), 3);

        app.dispatch_action(UiAction::ScrollToTop);
        assert_eq!(app.current_scroll_offset(), 0);
    }

    #[test]
    fn show_help_overlay_opens_and_dismisses_without_switching_views() {
        let mut app = test_app();

        assert_eq!(
            app.action_for_key(KeyEvent::new(KeyCode::Char('?'), KeyModifiers::NONE)),
            Ok(Some(UiAction::ShowHelp))
        );

        app.dispatch_action(UiAction::ShowHelp);
        assert!(app.overlay().is_some_and(|overlay| overlay.is_help()));
        assert_eq!(app.view, ViewMode::Home);

        assert_eq!(
            app.action_for_key(KeyEvent::new(KeyCode::Char('r'), KeyModifiers::NONE)),
            Ok(None)
        );
        assert_eq!(
            app.action_for_key(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE)),
            Ok(Some(UiAction::DismissOverlay))
        );

        app.dispatch_action(UiAction::DismissOverlay);
        assert!(app.overlay().is_none());
    }

    #[test]
    fn board_actions_open_confirmation_overlay_before_execution() {
        let mut app = test_app();
        app.view = ViewMode::Board;
        app.board.value = Some(board_fixture());
        app.selected_board_item_id = Some("tusk-a".to_owned());

        app.dispatch_action(UiAction::Claim("tusk-a".to_owned()));
        assert!(app.overlay().is_some_and(|overlay| overlay.is_confirm()));
        assert!(
            app.overlay()
                .is_some_and(|overlay| overlay.body.iter().any(|line| line.contains("tusk-a")))
        );

        assert_eq!(
            app.action_for_key(KeyEvent::new(KeyCode::Char('y'), KeyModifiers::NONE)),
            Ok(Some(UiAction::ConfirmOverlay))
        );
        assert_eq!(
            app.action_for_key(KeyEvent::new(KeyCode::Char('n'), KeyModifiers::NONE)),
            Ok(Some(UiAction::DismissOverlay))
        );
    }

    #[test]
    fn inspect_intent_maps_from_home_focus_and_board_selection() {
        let mut app = test_app();
        app.home.value = Some(sample_operator_snapshot());

        assert_eq!(
            app.action_for_key(KeyEvent::new(KeyCode::Char('i'), KeyModifiers::NONE)),
            Ok(Some(UiAction::Inspect("tusk-ready".to_owned())))
        );

        app.view = ViewMode::Board;
        app.board.value = Some(board_fixture());
        app.selected_board_item_id = Some("tusk-c".to_owned());

        assert_eq!(
            app.action_for_key(KeyEvent::new(KeyCode::Char('i'), KeyModifiers::NONE)),
            Ok(Some(UiAction::Inspect("tusk-c".to_owned())))
        );
    }

    #[test]
    fn inspect_overlay_dismisses_with_i_or_escape() {
        let mut app = test_app();
        app.overlay = Some(OverlayState::inspect(
            "Inspect".to_owned(),
            vec!["fact: demo".to_owned()],
        ));

        assert_eq!(
            app.action_for_key(KeyEvent::new(KeyCode::Char('i'), KeyModifiers::NONE)),
            Ok(Some(UiAction::DismissOverlay))
        );
        assert_eq!(
            app.action_for_key(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE)),
            Ok(Some(UiAction::DismissOverlay))
        );
        assert!(app.overlay().is_some_and(|overlay| overlay.is_inspect()));
    }

    #[test]
    fn board_filter_mode_edits_and_clears_query() {
        let mut app = test_app();
        app.view = ViewMode::Board;
        app.board.value = Some(board_fixture());
        app.sync_board_selection();

        assert_eq!(
            app.action_for_key(KeyEvent::new(KeyCode::Char('/'), KeyModifiers::NONE)),
            Ok(Some(UiAction::StartFilter))
        );

        app.dispatch_action(UiAction::StartFilter);
        assert!(app.is_filter_mode());

        for ch in ['c', 'l', 'a', 'i', 'm'] {
            app.handle_key(KeyEvent::new(KeyCode::Char(ch), KeyModifiers::NONE));
        }

        assert_eq!(app.active_filter_text(), "claim");
        assert_eq!(app.selected_board_item_id.as_deref(), Some("tusk-c"));

        app.handle_key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
        assert!(!app.is_filter_mode());
        assert_eq!(app.active_filter_text(), "claim");

        assert_eq!(
            app.action_for_key(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE)),
            Ok(Some(UiAction::ClearFilter))
        );

        app.dispatch_action(UiAction::ClearFilter);
        assert_eq!(app.active_filter_text(), "");
    }
}
