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

fn main() -> Result<()> {
    let cli = Cli::parse(env::args_os())?;
    let repo_root = canonical_repo_root(cli.repo.as_deref())?;
    let socket_path = cli
        .socket
        .unwrap_or_else(|| default_socket_path(&repo_root));
    let client = ProtocolClient::new(repo_root, socket_path);
    let mut app = App::new(client, Duration::from_millis(cli.refresh_ms));
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
        })
    }
}

fn print_help() {
    println!(
        "\
Usage:
  tusk-ui [--repo PATH] [--socket PATH] [--refresh-ms N]

Keys:
  q            quit
  r            refresh all panes
  p            ping the service
  Tab          focus next pane
  Shift+Tab    focus previous pane
  t / b / e    focus tracker, board, or receipts
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

    fn query<T>(&self, kind: &str) -> Result<T>
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
    last_refresh_started: Instant,
    status_line: String,
    should_quit: bool,
    focus: Focus,
    tracker: PanelState<TrackerStatus>,
    board: PanelState<BoardStatus>,
    receipts: PanelState<ReceiptsStatus>,
}

impl App {
    fn new(client: ProtocolClient, refresh_interval: Duration) -> Self {
        Self {
            client,
            refresh_interval,
            last_refresh_started: Instant::now() - refresh_interval,
            status_line: "press r to refresh, p to ping, q to quit".to_owned(),
            should_quit: false,
            focus: Focus::Tracker,
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

    fn handle_key(&mut self, key: KeyEvent) {
        match key.code {
            KeyCode::Char('q') => self.should_quit = true,
            KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                self.should_quit = true
            }
            KeyCode::Char('r') => self.refresh(),
            KeyCode::Char('p') => self.ping(),
            KeyCode::Char('t') => self.focus = Focus::Tracker,
            KeyCode::Char('b') => self.focus = Focus::Board,
            KeyCode::Char('e') => self.focus = Focus::Receipts,
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
    ready_issues: Vec<ReadyIssue>,
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
struct ReadyIssue {
    id: String,
    title: String,
    status: Option<String>,
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
                "t/b/e focus  Tab cycle  r refresh  p ping  q quit",
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
        (Some(board), _) => board_lines(board),
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

fn board_lines(board: &BoardStatus) -> Vec<Line<'static>> {
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
    lines.push(title_line("ready issues"));
    if board.ready_issues.is_empty() {
        lines.push(Line::from("none"));
    } else {
        lines.extend(board.ready_issues.iter().take(6).map(|issue| {
            let suffix = issue
                .status
                .as_deref()
                .map(|status| format!(" [{status}]"))
                .unwrap_or_default();
            Line::from(format!("{} {}{}", issue.id, issue.title, suffix))
        }));
    }

    lines.push(Line::from(""));
    lines.push(title_line("workspaces"));
    if board.workspaces.is_empty() {
        lines.push(Line::from("none"));
    } else {
        lines.extend(board.workspaces.iter().take(6).cloned().map(Line::from));
    }

    lines
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
            ready_issues: vec![ReadyIssue {
                id: "tusk-demo".to_owned(),
                title: "demo ready issue".to_owned(),
                status: Some("open".to_owned()),
            }],
            workspaces: vec!["default".to_owned()],
        };

        let rendered = board_lines(&board)
            .into_iter()
            .map(|line| line.to_string())
            .collect::<Vec<_>>()
            .join("\n");

        assert!(rendered.contains("demo ready issue"));
        assert!(rendered.contains("default"));
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
