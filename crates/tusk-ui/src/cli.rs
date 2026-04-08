use std::env;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};

pub(crate) const DEFAULT_REFRESH_MS: u64 = 5_000;
pub(crate) const DEFAULT_BASE_REV: &str = "main";

#[derive(Debug)]
pub(crate) struct Cli {
    pub(crate) repo: Option<PathBuf>,
    pub(crate) socket: Option<PathBuf>,
    pub(crate) refresh_ms: u64,
    pub(crate) base_rev: String,
}

impl Cli {
    pub(crate) fn parse<I>(args: I) -> Result<Self>
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

pub(crate) fn print_help() {
    println!(
        "\
Usage:
  tusk-ui [--repo PATH] [--socket PATH] [--refresh-ms N] [--base-rev REV]

Keys:
  q            quit
  r            refresh all panes
  p            ping the service
  ? / h        open help overlay
  Tab          focus next view
  Shift+Tab    focus previous view
  o / t / b / e
               focus home, tracker, board, or receipts
  j / k        scroll the current panel, or move board selection on the board
  Up / Down    scroll the current panel, or move board selection on the board
  PageUp/Down  scroll the current panel by a page
  g / G        jump to the top or bottom of the current panel
  /            open the local filter on board or receipts
  i            inspect the home focus issue or selected board item
  c            claim the selected ready issue from the board
  l            launch a lane for the selected claimed issue
  f            finish the selected active lane as completed
  Enter / y    confirm an overlay action
  n / Esc      dismiss an overlay, or clear the active filter
"
    );
}

pub(crate) fn canonical_repo_root(path: Option<&Path>) -> Result<PathBuf> {
    let cwd = match path {
        Some(path) => path.to_path_buf(),
        None => env::current_dir().context("resolve current directory")?,
    };

    let output = std::process::Command::new("git")
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

pub(crate) fn default_socket_path(repo_root: &Path) -> PathBuf {
    repo_root.join(".beads").join("tuskd").join("tuskd.sock")
}
