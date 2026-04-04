use std::env;
use std::io::{self, Read, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, anyhow, bail};
use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use crossterm::execute;
use crossterm::terminal::{
    EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode,
};
use ratatui::backend::CrosstermBackend;
use ratatui::layout::{Constraint, Direction, Layout};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, List, ListItem, Paragraph, Wrap};
use ratatui::{Frame, Terminal};
use serde::Deserialize;
use serde::de::DeserializeOwned;
use serde_json::{Value, json};

const DEFAULT_REFRESH_MS: u64 = 5_000;
const DEFAULT_BASE_REV: &str = "main";

fn main() -> Result<()> {
    let cli = Cli::parse(env::args_os())?;
    let repo_root = canonical_repo_root(cli.repo.as_deref())?;
    let socket_path = cli
        .socket
        .unwrap_or_else(|| default_socket_path(&repo_root));
    let client = ProtocolClient::new(repo_root, socket_path);
    let mut app = App::new(client, Duration::from_millis(cli.refresh_ms), cli.base_rev);
    app.refresh();
    run_tui(app)
}

fn run_tui(mut app: App) -> Result<()> {
    enable_raw_mode().context("enable raw mode")?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen).context("enter alternate screen")?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend).context("create terminal backend")?;

    let result = run_loop(&mut terminal, &mut app);

    disable_raw_mode().context("disable raw mode")?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen).context("leave alternate screen")?;
    terminal.show_cursor().context("show cursor")?;

    result
}

fn run_loop(terminal: &mut Terminal<CrosstermBackend<io::Stdout>>, app: &mut App) -> Result<()> {
    while !app.should_quit {
        terminal.draw(|frame| render(frame, app))?;

        let timeout = app.time_until_refresh();
        if event::poll(timeout)? {
            if let Event::Key(key) = event::read()? {
                if key.kind == KeyEventKind::Press {
                    app.handle_key(key);
                }
            }
        }

        if app.should_refresh() {
            app.refresh();
        }
    }

    Ok(())
}

#[derive(Debug)]
struct Cli {
    repo: Option<PathBuf>,
    socket: Option<PathBuf>,
    refresh_ms: u64,
    base_rev: String,
}

impl Cli {
    fn parse<I>(args: I) -> Result<Self>
    where
        I: IntoIterator,
        I::Item: Into<std::ffi::OsString>,
    {
        let mut repo = None;
        let mut socket = None;
        let mut refresh_ms = DEFAULT_REFRESH_MS;
        let mut base_rev = DEFAULT_BASE_REV.to_owned();

        let mut values = args.into_iter().map(Into::into);
        let _program = values.next();

        while let Some(arg) = values.next() {
            match arg.to_string_lossy().as_ref() {
                "--repo" => {
                    let value = values.next().context("--repo requires a path")?;
                    repo = Some(PathBuf::from(value));
                }
                "--socket" => {
                    let value = values.next().context("--socket requires a path")?;
                    socket = Some(PathBuf::from(value));
                }
                "--refresh-ms" => {
                    let value = values.next().context("--refresh-ms requires a number")?;
                    refresh_ms = value
                        .to_string_lossy()
                        .parse()
                        .context("parse --refresh-ms")?;
                }
                "--base-rev" => {
                    let value = values.next().context("--base-rev requires a revision")?;
                    base_rev = value.to_string_lossy().into_owned();
                }
                "-h" | "--help" | "help" => {
                    print_help();
                    std::process::exit(0);
                }
                other => bail!("unknown argument: {other}"),
            }
        }

        Ok(Self {
            repo,
            socket,
            refresh_ms,
            base_rev,
        })
    }
}

fn print_help() {
    println!(
        "\
Usage:
  tusk-ui [--repo PATH] [--socket PATH] [--refresh-ms N] [--base-rev REV]

Keys:
  q            quit
  r            refresh all panes
  p            ping the service
  Tab          focus next pane
  Shift+Tab    focus previous pane
  t / b / e    focus tracker, board, or receipts
  j / k        move actionable-issue selection in the board
  Up / Down    move actionable-issue selection in the board
  c            claim the selected ready issue from the board
  l            launch a lane for the selected claimed issue
"
    );
}

fn canonical_repo_root(path: Option<&Path>) -> Result<PathBuf> {
    let cwd = match path {
        Some(path) => path.to_path_buf(),
        None => env::current_dir().context("resolve current directory")?,
    };

    let output = Command::new("git")
        .current_dir(&cwd)
        .args(["rev-parse", "--show-toplevel"])
        .output();

    match output {
        Ok(output) if output.status.success() => {
            let root = String::from_utf8(output.stdout).context("decode git output")?;
            Ok(PathBuf::from(root.trim()))
        }
        _ => Ok(cwd.canonicalize().unwrap_or(cwd)),
    }
}

fn default_socket_path(repo_root: &Path) -> PathBuf {
    repo_root.join(".beads").join("tuskd").join("tuskd.sock")
}

#[derive(Debug, Clone)]
struct ProtocolClient {
    repo_root: PathBuf,
    socket_path: PathBuf,
}

impl ProtocolClient {
    fn new(repo_root: PathBuf, socket_path: PathBuf) -> Self {
        Self {
            repo_root,
            socket_path,
        }
    }

    fn tracker_status(&self) -> Result<TrackerStatus> {
        self.query("tracker_status")
    }

    fn board_status(&self) -> Result<BoardStatus> {
        self.query("board_status")
    }

    fn receipts_status(&self) -> Result<ReceiptsStatus> {
        self.query("receipts_status")
    }

    fn ping(&self) -> Result<PingStatus> {
        self.query("ping")
    }

    fn claim_issue(&self, issue_id: &str) -> Result<ClaimIssuePayload> {
        self.query_with_payload("claim_issue", json!({ "issue_id": issue_id }))
    }

    fn launch_lane(&self, issue_id: &str, base_rev: &str) -> Result<LaunchLanePayload> {
        self.query_with_payload(
            "launch_lane",
            json!({ "issue_id": issue_id, "base_rev": base_rev }),
        )
    }

    fn query<T>(&self, kind: &str) -> Result<T>
    where
        T: DeserializeOwned,
    {
        self.query_with_payload(kind, Value::Null)
    }

    fn query_with_payload<T>(&self, kind: &str, payload: Value) -> Result<T>
    where
        T: DeserializeOwned,
    {
        let mut stream = UnixStream::connect(&self.socket_path)
            .with_context(|| format!("connect to {}", self.socket_path.display()))?;
        stream
            .set_read_timeout(Some(Duration::from_secs(2)))
            .context("set read timeout")?;
        stream
            .set_write_timeout(Some(Duration::from_secs(2)))
            .context("set write timeout")?;

        let request = json!({
            "request_id": request_id(),
            "kind": kind,
            "payload": payload,
        });
        let mut body = serde_json::to_vec(&request).context("serialize request")?;
        body.push(b'\n');
        stream.write_all(&body).context("write request")?;

        let mut response = String::new();
        stream
            .read_to_string(&mut response)
            .context("read response from socket")?;

        let decoded: Response<T> =
            serde_json::from_str(&response).context("decode protocol response")?;
        if decoded.ok {
            decoded.payload.context("missing response payload")
        } else {
            let message = decoded
                .error
                .map(|error| error.message)
                .unwrap_or_else(|| "unknown protocol error".to_owned());
            Err(anyhow!("{kind} failed: {message}"))
        }
    }
}

fn request_id() -> String {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    format!("req-{millis}")
}

fn now_label() -> String {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    format!("epoch:{seconds}")
}

#[derive(Debug)]
struct App {
    client: ProtocolClient,
    refresh_interval: Duration,
    default_base_rev: String,
    last_refresh_started: Instant,
    status_line: String,
    should_quit: bool,
    focus: Focus,
    selected_action_issue_id: Option<String>,
    tracker: PanelState<TrackerStatus>,
    board: PanelState<BoardStatus>,
    receipts: PanelState<ReceiptsStatus>,
}

impl App {
    fn new(client: ProtocolClient, refresh_interval: Duration, default_base_rev: String) -> Self {
        Self {
            client,
            refresh_interval,
            default_base_rev,
            last_refresh_started: Instant::now() - refresh_interval,
            status_line: "press r to refresh, b to focus the board, q to quit".to_owned(),
            should_quit: false,
            focus: Focus::Tracker,
            selected_action_issue_id: None,
            tracker: PanelState::default(),
            board: PanelState::default(),
            receipts: PanelState::default(),
        }
    }

    fn should_refresh(&self) -> bool {
        self.last_refresh_started.elapsed() >= self.refresh_interval
    }

    fn time_until_refresh(&self) -> Duration {
        self.refresh_interval
            .saturating_sub(self.last_refresh_started.elapsed())
    }

    fn refresh(&mut self) {
        self.last_refresh_started = Instant::now();
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

    fn ping(&mut self) {
        match self.client.ping() {
            Ok(ping) => {
                self.status_line = format!("ping ok at {}", ping.timestamp);
            }
            Err(error) => {
                self.status_line = format!("ping failed: {error:#}");
            }
        }
    }

    fn sync_board_selection(&mut self) {
        let Some(board) = self.board.value.as_ref() else {
            self.selected_action_issue_id = None;
            return;
        };

        self.selected_action_issue_id =
            normalized_action_selection(board, self.selected_action_issue_id.as_deref());
    }

    fn move_board_selection(&mut self, delta: isize) {
        let Some(board) = self.board.value.as_ref() else {
            self.status_line = "board data is unavailable".to_owned();
            return;
        };

        let Some(next) =
            step_action_selection(board, self.selected_action_issue_id.as_deref(), delta)
        else {
            self.selected_action_issue_id = None;
            self.status_line = "no actionable issues to select".to_owned();
            return;
        };

        self.selected_action_issue_id = Some(next.clone());
        self.status_line = format!("selected {next}");
    }

    fn claim_selected_issue(&mut self) {
        let Some(issue_id) = self.selected_action_issue_id.clone() else {
            self.status_line = "no ready issue selected to claim".to_owned();
            return;
        };
        let Some(board) = self.board.value.as_ref() else {
            self.status_line = "board data is unavailable".to_owned();
            return;
        };
        let Some(actionable) = selected_actionable_issue(board, Some(issue_id.as_str())) else {
            self.status_line = "selected issue is no longer actionable".to_owned();
            return;
        };
        if actionable.bucket != ActionableBucket::Ready {
            self.status_line = format!("selected issue {issue_id} is not ready to claim");
            return;
        }

        match self.client.claim_issue(&issue_id) {
            Ok(payload) => {
                self.refresh();
                self.status_line = format!(
                    "claimed {}; launch base is {}",
                    payload.issue_id, self.default_base_rev
                );
            }
            Err(error) => {
                self.status_line = format!("claim failed for {issue_id}: {error:#}");
            }
        }
    }

    fn launch_selected_issue(&mut self) {
        let Some(issue_id) = self.selected_action_issue_id.clone() else {
            self.status_line = "no claimed issue selected to launch".to_owned();
            return;
        };
        let Some(board) = self.board.value.as_ref() else {
            self.status_line = "board data is unavailable".to_owned();
            return;
        };
        let Some(actionable) = selected_actionable_issue(board, Some(issue_id.as_str())) else {
            self.status_line = "selected issue is no longer actionable".to_owned();
            return;
        };
        if actionable.bucket != ActionableBucket::Claimed {
            self.status_line = format!("selected issue {issue_id} is not claimed yet");
            return;
        }

        match self.client.launch_lane(&issue_id, &self.default_base_rev) {
            Ok(payload) => {
                self.refresh();
                self.status_line = format!(
                    "launched {} in {} from {}",
                    payload.issue_id, payload.workspace_name, payload.base_rev
                );
            }
            Err(error) => {
                self.status_line = format!("launch failed for {issue_id}: {error:#}");
            }
        }
    }

    fn handle_key(&mut self, key: KeyEvent) {
        match key.code {
            KeyCode::Char('q') => self.should_quit = true,
            KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                self.should_quit = true
            }
            KeyCode::Char('c') if self.focus == Focus::Board => self.claim_selected_issue(),
            KeyCode::Char('l') if self.focus == Focus::Board => self.launch_selected_issue(),
            KeyCode::Char('r') => self.refresh(),
            KeyCode::Char('p') => self.ping(),
            KeyCode::Char('t') => self.focus = Focus::Tracker,
            KeyCode::Char('b') => self.focus = Focus::Board,
            KeyCode::Char('e') => self.focus = Focus::Receipts,
            KeyCode::Char('j') | KeyCode::Down if self.focus == Focus::Board => {
                self.move_board_selection(1)
            }
            KeyCode::Char('k') | KeyCode::Up if self.focus == Focus::Board => {
                self.move_board_selection(-1)
            }
            KeyCode::Tab => self.focus = self.focus.next(),
            KeyCode::BackTab => self.focus = self.focus.previous(),
            _ => {}
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Focus {
    Tracker,
    Board,
    Receipts,
}

impl Focus {
    fn next(self) -> Self {
        match self {
            Self::Tracker => Self::Board,
            Self::Board => Self::Receipts,
            Self::Receipts => Self::Tracker,
        }
    }

    fn previous(self) -> Self {
        match self {
            Self::Tracker => Self::Receipts,
            Self::Board => Self::Tracker,
            Self::Receipts => Self::Board,
        }
    }
}

#[derive(Debug)]
struct PanelState<T> {
    value: Option<T>,
    error: Option<String>,
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
    fn from_result(result: Result<T>) -> Self {
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

#[derive(Debug, Deserialize)]
struct Response<T> {
    ok: bool,
    payload: Option<T>,
    error: Option<ProtocolError>,
}

#[derive(Debug, Deserialize)]
struct ProtocolError {
    message: String,
}

#[derive(Debug, Deserialize)]
struct ClaimIssuePayload {
    issue_id: String,
}

#[derive(Debug, Deserialize)]
struct LaunchLanePayload {
    issue_id: String,
    workspace_name: String,
    base_rev: String,
}

#[derive(Debug, Deserialize)]
struct TrackerStatus {
    repo_root: String,
    protocol: TrackerProtocol,
    tuskd: TuskdState,
    health: HealthStatus,
    #[serde(default)]
    active_leases: Vec<Value>,
}

#[derive(Debug, Deserialize)]
struct TrackerProtocol {
    endpoint: String,
}

#[derive(Debug, Deserialize)]
struct TuskdState {
    mode: String,
    pid: Option<i64>,
}

#[derive(Debug, Deserialize)]
struct HealthStatus {
    status: String,
    checked_at: String,
    backend: Option<BackendStatus>,
    summary: Option<BoardSummary>,
}

#[derive(Debug, Deserialize)]
struct BackendStatus {
    running: Option<bool>,
    pid: Option<i64>,
    port: Option<i64>,
    data_dir: Option<String>,
}

#[derive(Debug, Deserialize)]
struct BoardStatus {
    repo_root: String,
    generated_at: String,
    summary: Option<BoardSummary>,
    #[serde(default)]
    ready_issues: Vec<BoardIssue>,
    #[serde(default)]
    claimed_issues: Vec<BoardIssue>,
    #[serde(default)]
    blocked_issues: Vec<BoardIssue>,
    #[serde(default)]
    deferred_issues: Vec<BoardIssue>,
    #[serde(default)]
    lanes: Vec<LaneEntry>,
    #[serde(default)]
    workspaces: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct BoardSummary {
    total_issues: Option<u64>,
    open_issues: Option<u64>,
    in_progress_issues: Option<u64>,
    closed_issues: Option<u64>,
    blocked_issues: Option<u64>,
    deferred_issues: Option<u64>,
    ready_issues: Option<u64>,
}

#[derive(Debug, Deserialize)]
struct BoardIssue {
    id: String,
    title: String,
    status: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct LaneEntry {
    issue_id: String,
    issue_title: String,
    status: String,
    observed_status: Option<String>,
    workspace_exists: Option<bool>,
    outcome: Option<String>,
    workspace_name: Option<String>,
}

#[derive(Debug, Deserialize)]
struct ReceiptsStatus {
    repo_root: String,
    generated_at: String,
    receipts_path: String,
    #[serde(default)]
    receipts: Vec<ReceiptEntry>,
}

#[derive(Debug, Deserialize)]
struct ReceiptEntry {
    timestamp: Option<String>,
    kind: Option<String>,
    payload: Option<Value>,
    invalid_line: Option<String>,
}

#[derive(Debug, Deserialize)]
struct PingStatus {
    timestamp: String,
}

fn render(frame: &mut Frame, app: &App) {
    let vertical = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(8),
            Constraint::Length(3),
        ])
        .split(frame.area());

    let panes = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(34),
            Constraint::Percentage(33),
            Constraint::Percentage(33),
        ])
        .split(vertical[1]);

    let header = Paragraph::new(Line::from(vec![
        Span::styled("tusk-ui  ", Style::default().add_modifier(Modifier::BOLD)),
        Span::raw(app.client.repo_root.display().to_string()),
        Span::raw("  "),
        Span::styled(
            app.client.socket_path.display().to_string(),
            Style::default().fg(Color::DarkGray),
        ),
    ]))
    .block(
        Block::default()
            .borders(Borders::ALL)
            .title("Control Plane"),
    );
    frame.render_widget(header, vertical[0]);

    render_tracker(frame, panes[0], app);
    render_board(frame, panes[1], app);
    render_receipts(frame, panes[2], app);

    let footer = Paragraph::new(vec![
        Line::from(vec![
            Span::styled("focus: ", Style::default().add_modifier(Modifier::BOLD)),
            Span::raw(match app.focus {
                Focus::Tracker => "tracker",
                Focus::Board => "board",
                Focus::Receipts => "receipts",
            }),
            Span::raw("  "),
            Span::styled(
                "t/b/e focus  Tab cycle  j/k move  c claim  l launch  r refresh  p ping  q quit",
                Style::default().fg(Color::DarkGray),
            ),
        ]),
        Line::from(app.status_line.clone()),
    ])
    .block(Block::default().borders(Borders::ALL).title("Actions"))
    .wrap(Wrap { trim: false });
    frame.render_widget(footer, vertical[2]);
}

fn render_tracker(frame: &mut Frame, area: ratatui::layout::Rect, app: &App) {
    let block = pane_block("Tracker Service", app.focus == Focus::Tracker);
    let lines = match (&app.tracker.value, &app.tracker.error) {
        (Some(tracker), _) => tracker_lines(tracker),
        (_, Some(error)) => error_lines(error),
        _ => vec![Line::from("waiting for tracker data")],
    };

    frame.render_widget(
        Paragraph::new(lines)
            .block(block)
            .wrap(Wrap { trim: false }),
        area,
    );
}

fn render_board(frame: &mut Frame, area: ratatui::layout::Rect, app: &App) {
    let block = pane_block("Board", app.focus == Focus::Board);
    let lines = match (&app.board.value, &app.board.error) {
        (Some(board), _) => board_lines(board, app.selected_action_issue_id.as_deref()),
        (_, Some(error)) => error_lines(error),
        _ => vec![Line::from("waiting for board data")],
    };

    frame.render_widget(
        Paragraph::new(lines)
            .block(block)
            .wrap(Wrap { trim: false }),
        area,
    );
}

fn render_receipts(frame: &mut Frame, area: ratatui::layout::Rect, app: &App) {
    let block = pane_block("Receipts", app.focus == Focus::Receipts);
    match (&app.receipts.value, &app.receipts.error) {
        (Some(receipts), _) => {
            let items = receipt_items(receipts);
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

fn pane_block(title: &'static str, focused: bool) -> Block<'static> {
    let style = if focused {
        Style::default()
            .fg(Color::Cyan)
            .add_modifier(Modifier::BOLD)
    } else {
        Style::default()
    };

    Block::default()
        .borders(Borders::ALL)
        .border_style(style)
        .title(title)
}

fn tracker_lines(tracker: &TrackerStatus) -> Vec<Line<'static>> {
    let mut lines = vec![
        kv_line("repo", tracker.repo_root.clone()),
        kv_line("socket", tracker.protocol.endpoint.clone()),
        kv_line("mode", tracker.tuskd.mode.clone()),
        kv_line(
            "pid",
            tracker
                .tuskd
                .pid
                .map(|value| value.to_string())
                .unwrap_or_else(|| "none".to_owned()),
        ),
        kv_line("health", tracker.health.status.clone()),
        kv_line("checked", tracker.health.checked_at.clone()),
        kv_line("leases", tracker.active_leases.len().to_string()),
    ];

    if let Some(summary) = &tracker.health.summary {
        lines.push(Line::from(""));
        lines.push(title_line("issue summary"));
        lines.extend(summary_lines(summary));
    }

    if let Some(backend) = &tracker.health.backend {
        lines.push(Line::from(""));
        lines.push(title_line("backend"));
        if let Some(running) = backend.running {
            lines.push(kv_line("running", running.to_string()));
        }
        if let Some(pid) = backend.pid {
            lines.push(kv_line("backend pid", pid.to_string()));
        }
        if let Some(port) = backend.port {
            lines.push(kv_line("port", port.to_string()));
        }
        if let Some(path) = &backend.data_dir {
            lines.push(kv_line("data", path.clone()));
        }
    }

    lines
}

fn board_lines(board: &BoardStatus, selected_action_issue_id: Option<&str>) -> Vec<Line<'static>> {
    let mut lines = vec![
        kv_line("repo", board.repo_root.clone()),
        kv_line("updated", board.generated_at.clone()),
    ];

    if let Some(summary) = &board.summary {
        lines.push(Line::from(""));
        lines.push(title_line("summary"));
        lines.extend(summary_lines(summary));
    }

    lines.push(Line::from(""));
    append_issue_section(
        &mut lines,
        "ready issues",
        &board.ready_issues,
        selected_action_issue_id,
    );

    lines.push(Line::from(""));
    append_issue_section(
        &mut lines,
        "claimed issues",
        &board.claimed_issues,
        selected_action_issue_id,
    );

    lines.push(Line::from(""));
    append_issue_section(&mut lines, "blocked issues", &board.blocked_issues, None);

    lines.push(Line::from(""));
    append_issue_section(&mut lines, "deferred issues", &board.deferred_issues, None);

    lines.push(Line::from(""));
    lines.push(title_line("lanes"));
    lines.extend(lane_lines(&board.lanes));

    lines.push(Line::from(""));
    lines.push(title_line("workspaces"));
    if board.workspaces.is_empty() {
        lines.push(Line::from("none"));
    } else {
        lines.extend(board.workspaces.iter().take(6).cloned().map(Line::from));
    }

    lines
}

fn append_issue_section(
    lines: &mut Vec<Line<'static>>,
    title: &str,
    issues: &[BoardIssue],
    selected_issue_id: Option<&str>,
) {
    lines.push(title_line(title));

    if issues.is_empty() {
        lines.push(Line::from("none"));
        return;
    }

    for issue in issues {
        lines.push(issue_line(issue, selected_issue_id));
    }
}

fn issue_line(issue: &BoardIssue, selected_issue_id: Option<&str>) -> Line<'static> {
    let suffix = issue
        .status
        .as_deref()
        .map(|status| format!(" [{status}]"))
        .unwrap_or_default();
    let selected = selected_issue_id == Some(issue.id.as_str());
    let prefix = if selected { "> " } else { "  " };
    let text = format!("{}{} {}{}", prefix, issue.id, issue.title, suffix);
    let style = if selected {
        Style::default()
            .fg(Color::Cyan)
            .add_modifier(Modifier::BOLD)
    } else {
        Style::default()
    };

    Line::from(Span::styled(text, style))
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ActionableBucket {
    Ready,
    Claimed,
}

#[derive(Clone, Copy, Debug)]
struct ActionableIssueRef<'a> {
    bucket: ActionableBucket,
    issue: &'a BoardIssue,
}

fn actionable_issues(board: &BoardStatus) -> Vec<ActionableIssueRef<'_>> {
    let mut issues = Vec::with_capacity(board.ready_issues.len() + board.claimed_issues.len());
    issues.extend(board.ready_issues.iter().map(|issue| ActionableIssueRef {
        bucket: ActionableBucket::Ready,
        issue,
    }));
    issues.extend(board.claimed_issues.iter().map(|issue| ActionableIssueRef {
        bucket: ActionableBucket::Claimed,
        issue,
    }));
    issues
}

fn selected_actionable_issue<'a>(
    board: &'a BoardStatus,
    selected_issue_id: Option<&str>,
) -> Option<ActionableIssueRef<'a>> {
    let selected_issue_id = selected_issue_id?;
    actionable_issues(board)
        .into_iter()
        .find(|actionable| actionable.issue.id == selected_issue_id)
}

fn normalized_action_selection(
    board: &BoardStatus,
    selected_issue_id: Option<&str>,
) -> Option<String> {
    let actionable = actionable_issues(board);
    if actionable.is_empty() {
        return None;
    }

    if let Some(selected) = selected_actionable_issue(board, selected_issue_id) {
        return Some(selected.issue.id.clone());
    }

    Some(actionable[0].issue.id.clone())
}

fn step_action_selection(
    board: &BoardStatus,
    selected_issue_id: Option<&str>,
    delta: isize,
) -> Option<String> {
    let actionable = actionable_issues(board);
    if actionable.is_empty() {
        return None;
    }

    let current_index = selected_issue_id
        .and_then(|selected| {
            actionable
                .iter()
                .position(|issue| issue.issue.id == selected)
        })
        .unwrap_or(0);

    let step = delta.unsigned_abs();
    let max_index = actionable.len().saturating_sub(1);
    let next_index = if delta.is_negative() {
        current_index.saturating_sub(step)
    } else {
        current_index.saturating_add(step).min(max_index)
    };

    Some(actionable[next_index].issue.id.clone())
}

fn summary_lines(summary: &BoardSummary) -> Vec<Line<'static>> {
    vec![
        kv_line(
            "total",
            summary.total_issues.unwrap_or_default().to_string(),
        ),
        kv_line("open", summary.open_issues.unwrap_or_default().to_string()),
        kv_line(
            "in progress",
            summary.in_progress_issues.unwrap_or_default().to_string(),
        ),
        kv_line(
            "ready",
            summary.ready_issues.unwrap_or_default().to_string(),
        ),
        kv_line(
            "blocked",
            summary.blocked_issues.unwrap_or_default().to_string(),
        ),
        kv_line(
            "deferred",
            summary.deferred_issues.unwrap_or_default().to_string(),
        ),
        kv_line(
            "closed",
            summary.closed_issues.unwrap_or_default().to_string(),
        ),
    ]
}

fn lane_lines(lanes: &[LaneEntry]) -> Vec<Line<'static>> {
    if lanes.is_empty() {
        return vec![Line::from("none")];
    }

    let mut active = Vec::new();
    let mut finished = Vec::new();
    let mut stale = Vec::new();

    let mut ordered = lanes.to_vec();
    ordered.sort_by(|left, right| left.issue_id.cmp(&right.issue_id));

    for lane in ordered {
        let observed_status = lane
            .observed_status
            .clone()
            .unwrap_or_else(|| lane.status.clone());

        if observed_status == "stale" {
            stale.push(lane);
        } else if lane.status == "finished" || observed_status == "finished" {
            finished.push(lane);
        } else {
            active.push(lane);
        }
    }

    let mut lines = Vec::new();
    if !active.is_empty() {
        append_lane_section(&mut lines, "active lanes", &active);
    }
    if !finished.is_empty() {
        if !lines.is_empty() {
            lines.push(Line::from(""));
        }
        append_lane_section(&mut lines, "finished lanes", &finished);
    }
    if !stale.is_empty() {
        if !lines.is_empty() {
            lines.push(Line::from(""));
        }
        append_lane_section(&mut lines, "stale lanes", &stale);
    }
    lines
}

fn append_lane_section(lines: &mut Vec<Line<'static>>, title: &str, lanes: &[LaneEntry]) {
    lines.push(title_line(title));

    if lanes.is_empty() {
        lines.push(Line::from("none"));
        return;
    }

    for lane in lanes {
        let mut detail_parts = vec![format!("status {}", lane.status)];
        if let Some(observed_status) = &lane.observed_status {
            if observed_status != &lane.status {
                detail_parts.push(format!("observed {}", observed_status));
            }
        }
        if let Some(outcome) = &lane.outcome {
            detail_parts.push(format!("outcome {}", outcome));
        }
        detail_parts.push(if lane.workspace_exists.unwrap_or(false) {
            "workspace live".to_owned()
        } else {
            "workspace missing".to_owned()
        });

        lines.push(Line::from(format!(
            "{} {}",
            lane.issue_id, lane.issue_title
        )));
        lines.push(Line::from(format!("  {}", detail_parts.join(" | "))));

        if let Some(workspace_name) = &lane.workspace_name {
            lines.push(Line::from(format!("  ws {}", workspace_name)));
        }
    }
}

fn receipt_items(receipts: &ReceiptsStatus) -> Vec<ListItem<'static>> {
    let mut items = vec![
        ListItem::new(Line::from(vec![
            Span::styled("repo ", Style::default().add_modifier(Modifier::BOLD)),
            Span::raw(receipts.repo_root.clone()),
        ])),
        ListItem::new(Line::from(vec![
            Span::styled("updated ", Style::default().add_modifier(Modifier::BOLD)),
            Span::raw(receipts.generated_at.clone()),
        ])),
        ListItem::new(Line::from(vec![
            Span::styled("file ", Style::default().add_modifier(Modifier::BOLD)),
            Span::raw(receipts.receipts_path.clone()),
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
            .rev()
            .take(10)
            .map(|receipt| ListItem::new(Line::from(receipt_label(receipt)))),
    );

    items
}

fn receipt_label(receipt: &ReceiptEntry) -> String {
    if let Some(invalid) = &receipt.invalid_line {
        return format!("invalid {invalid}");
    }

    let timestamp = receipt
        .timestamp
        .clone()
        .unwrap_or_else(|| "unknown-time".to_owned());
    let kind = receipt
        .kind
        .clone()
        .unwrap_or_else(|| "unknown-kind".to_owned());
    let payload_hint = receipt
        .payload
        .as_ref()
        .and_then(|payload| payload.as_object())
        .map(|object| {
            format!(
                " ({})",
                object.keys().cloned().collect::<Vec<_>>().join(",")
            )
        })
        .unwrap_or_default();

    format!("{timestamp} {kind}{payload_hint}")
}

fn kv_line(label: impl Into<String>, value: impl Into<String>) -> Line<'static> {
    Line::from(vec![
        Span::styled(
            format!("{:>11}: ", label.into()),
            Style::default()
                .fg(Color::Blue)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw(value.into()),
    ])
}

fn title_line(title: impl Into<String>) -> Line<'static> {
    Line::from(Span::styled(
        title.into(),
        Style::default()
            .fg(Color::Yellow)
            .add_modifier(Modifier::BOLD),
    ))
}

fn error_lines(error: &str) -> Vec<Line<'static>> {
    vec![
        Line::from(Span::styled(
            "error",
            Style::default().fg(Color::Red).add_modifier(Modifier::BOLD),
        )),
        Line::from(error.to_owned()),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn board_lines_include_ready_issue_titles() {
        let board = BoardStatus {
            repo_root: "/tmp/repo".to_owned(),
            generated_at: "2026-03-26T00:00:00Z".to_owned(),
            summary: Some(BoardSummary {
                total_issues: Some(10),
                open_issues: Some(2),
                in_progress_issues: Some(1),
                closed_issues: Some(7),
                blocked_issues: Some(1),
                deferred_issues: Some(0),
                ready_issues: Some(1),
            }),
            ready_issues: vec![BoardIssue {
                id: "tusk-demo".to_owned(),
                title: "demo ready issue".to_owned(),
                status: Some("open".to_owned()),
            }],
            claimed_issues: vec![],
            blocked_issues: vec![],
            deferred_issues: vec![],
            lanes: vec![],
            workspaces: vec!["default".to_owned()],
        };

        let rendered = board_lines(&board, None)
            .into_iter()
            .map(|line| line.to_string())
            .collect::<Vec<_>>()
            .join("\n");

        assert!(rendered.contains("demo ready issue"));
        assert!(rendered.contains("default"));
    }

    #[test]
    fn board_lines_include_claimed_blocked_and_deferred_sections() {
        let board = BoardStatus {
            repo_root: "/tmp/repo".to_owned(),
            generated_at: "2026-03-26T00:00:00Z".to_owned(),
            summary: None,
            ready_issues: vec![],
            claimed_issues: vec![BoardIssue {
                id: "tusk-claim".to_owned(),
                title: "claimed issue".to_owned(),
                status: Some("in_progress".to_owned()),
            }],
            blocked_issues: vec![BoardIssue {
                id: "tusk-blocked".to_owned(),
                title: "blocked issue".to_owned(),
                status: Some("open".to_owned()),
            }],
            deferred_issues: vec![BoardIssue {
                id: "tusk-deferred".to_owned(),
                title: "deferred issue".to_owned(),
                status: Some("deferred".to_owned()),
            }],
            lanes: vec![],
            workspaces: vec![],
        };

        let rendered = board_lines(&board, None)
            .into_iter()
            .map(|line| line.to_string())
            .collect::<Vec<_>>()
            .join("\n");

        assert!(rendered.contains("claimed issues"));
        assert!(rendered.contains("blocked issues"));
        assert!(rendered.contains("deferred issues"));
        assert!(rendered.contains("tusk-claim claimed issue [in_progress]"));
        assert!(rendered.contains("tusk-blocked blocked issue [open]"));
        assert!(rendered.contains("tusk-deferred deferred issue [deferred]"));
    }

    #[test]
    fn board_lines_include_lane_groups_and_outcomes() {
        let board = BoardStatus {
            repo_root: "/tmp/repo".to_owned(),
            generated_at: "2026-03-26T00:00:00Z".to_owned(),
            summary: None,
            ready_issues: vec![],
            claimed_issues: vec![],
            blocked_issues: vec![],
            deferred_issues: vec![],
            lanes: vec![
                LaneEntry {
                    issue_id: "tusk-live".to_owned(),
                    issue_title: "live lane".to_owned(),
                    status: "handoff".to_owned(),
                    observed_status: Some("handoff".to_owned()),
                    workspace_exists: Some(true),
                    outcome: None,
                    workspace_name: Some("tusk-live-lane".to_owned()),
                },
                LaneEntry {
                    issue_id: "tusk-done".to_owned(),
                    issue_title: "finished lane".to_owned(),
                    status: "finished".to_owned(),
                    observed_status: Some("finished".to_owned()),
                    workspace_exists: Some(false),
                    outcome: Some("completed".to_owned()),
                    workspace_name: Some("tusk-done-lane".to_owned()),
                },
                LaneEntry {
                    issue_id: "tusk-stale".to_owned(),
                    issue_title: "stale lane".to_owned(),
                    status: "handoff".to_owned(),
                    observed_status: Some("stale".to_owned()),
                    workspace_exists: Some(false),
                    outcome: None,
                    workspace_name: Some("tusk-stale-lane".to_owned()),
                },
            ],
            workspaces: vec![],
        };

        let rendered = board_lines(&board, None)
            .into_iter()
            .map(|line| line.to_string())
            .collect::<Vec<_>>()
            .join("\n");

        assert!(rendered.contains("active lanes"));
        assert!(rendered.contains("finished lanes"));
        assert!(rendered.contains("stale lanes"));
        assert!(rendered.contains("tusk-live live lane"));
        assert!(rendered.contains("status handoff"));
        assert!(rendered.contains("workspace live"));
        assert!(rendered.contains("tusk-done finished lane"));
        assert!(rendered.contains("outcome completed"));
        assert!(rendered.contains("workspace missing"));
        assert!(rendered.contains("tusk-stale stale lane"));
        assert!(rendered.contains("observed stale"));
    }

    #[test]
    fn board_lines_mark_selected_actionable_issue() {
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
            claimed_issues: vec![],
            blocked_issues: vec![],
            deferred_issues: vec![],
            lanes: vec![],
            workspaces: vec![],
        };

        let rendered = board_lines(&board, Some("tusk-b"))
            .into_iter()
            .map(|line| line.to_string())
            .collect::<Vec<_>>()
            .join("\n");

        assert!(rendered.contains("> tusk-b second ready issue [open]"));
        assert!(rendered.contains("  tusk-a first ready issue [open]"));
    }

    #[test]
    fn board_lines_mark_selected_claimed_issue() {
        let board = BoardStatus {
            repo_root: "/tmp/repo".to_owned(),
            generated_at: "2026-03-26T00:00:00Z".to_owned(),
            summary: None,
            ready_issues: vec![BoardIssue {
                id: "tusk-a".to_owned(),
                title: "first ready issue".to_owned(),
                status: Some("open".to_owned()),
            }],
            claimed_issues: vec![BoardIssue {
                id: "tusk-b".to_owned(),
                title: "claimed issue".to_owned(),
                status: Some("in_progress".to_owned()),
            }],
            blocked_issues: vec![],
            deferred_issues: vec![],
            lanes: vec![],
            workspaces: vec![],
        };

        let rendered = board_lines(&board, Some("tusk-b"))
            .into_iter()
            .map(|line| line.to_string())
            .collect::<Vec<_>>()
            .join("\n");

        assert!(rendered.contains("> tusk-b claimed issue [in_progress]"));
        assert!(rendered.contains("  tusk-a first ready issue [open]"));
    }

    #[test]
    fn selection_helpers_follow_actionable_issue_order() {
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
            lanes: vec![],
            workspaces: vec![],
        };

        assert_eq!(
            normalized_action_selection(&board, None),
            Some("tusk-a".to_owned())
        );
        assert_eq!(
            step_action_selection(&board, Some("tusk-a"), 1),
            Some("tusk-b".to_owned())
        );
        assert_eq!(
            step_action_selection(&board, Some("tusk-b"), 1),
            Some("tusk-c".to_owned())
        );
        assert_eq!(
            step_action_selection(&board, Some("tusk-c"), 1),
            Some("tusk-c".to_owned())
        );
        assert_eq!(
            step_action_selection(&board, Some("tusk-c"), -1),
            Some("tusk-b".to_owned())
        );
        assert_eq!(
            step_action_selection(&board, Some("tusk-b"), -1),
            Some("tusk-a".to_owned())
        );
    }

    #[test]
    fn receipt_items_include_kind() {
        let receipts = ReceiptsStatus {
            repo_root: "/tmp/repo".to_owned(),
            generated_at: "2026-03-26T00:00:00Z".to_owned(),
            receipts_path: "/tmp/repo/.beads/tuskd/receipts.jsonl".to_owned(),
            receipts: vec![ReceiptEntry {
                timestamp: Some("2026-03-26T00:00:00Z".to_owned()),
                kind: Some("tracker.ensure".to_owned()),
                payload: Some(json!({"service": {"mode": "idle"}})),
                invalid_line: None,
            }],
        };

        let rendered = receipts
            .receipts
            .iter()
            .map(receipt_label)
            .collect::<Vec<_>>()
            .join("\n");

        assert!(rendered.contains("tracker.ensure"));
    }
}
