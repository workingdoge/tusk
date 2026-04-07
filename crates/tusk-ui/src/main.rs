mod action;
mod app;
mod cli;
#[cfg(test)]
mod fixtures;
mod protocol;
mod theme;
mod types;
mod viewmodel;
mod views;

use std::io;

use anyhow::{Context, Result};
use crossterm::event::{self, Event, KeyEventKind};
use crossterm::execute;
use crossterm::terminal::{
    EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode,
};
use ratatui::Terminal;
use ratatui::backend::CrosstermBackend;

use crate::app::App;
use crate::cli::{Cli, canonical_repo_root, default_socket_path};
use crate::protocol::ProtocolClient;
use crate::views::render;

fn main() -> Result<()> {
    let cli = Cli::parse(std::env::args_os())?;
    let repo_root = canonical_repo_root(cli.repo.as_deref())?;
    let socket_path = cli
        .socket
        .unwrap_or_else(|| default_socket_path(&repo_root));
    let client = ProtocolClient::new(repo_root, socket_path);
    let mut app = App::new(client, std::time::Duration::from_millis(cli.refresh_ms), cli.base_rev);
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
