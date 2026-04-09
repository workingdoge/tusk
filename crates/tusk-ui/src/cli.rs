use std::env;
use std::path::{Path, PathBuf};
use std::process::Command;

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
  o / w / t / b / e
               focus home, workers, tracker, board, or receipts
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

Lane Discipline:
  From the canonical root/default checkout, claim an issue and launch a lane from main.
  tuskd launch-lane --repo PATH --issue-id <id> --base-rev main
"
    );
}

pub(crate) fn canonical_repo_root(path: Option<&Path>) -> Result<PathBuf> {
    if let Some(path) = path {
        return root_from_candidate(path);
    }

    for candidate in [
        env::var_os("TUSK_TRACKER_ROOT"),
        env::var_os("BEADS_WORKSPACE_ROOT"),
        env::var_os("TUSK_CHECKOUT_ROOT"),
        env::var_os("DEVENV_ROOT"),
        env::var_os("TUSK_FLAKE_ROOT"),
    ]
    .into_iter()
    .flatten()
    {
        let candidate = PathBuf::from(candidate);
        if !candidate.as_os_str().is_empty() {
            return root_from_candidate(&candidate);
        }
    }

    root_from_candidate(&env::current_dir().context("resolve current directory")?)
}

pub(crate) fn default_socket_path(repo_root: &Path) -> PathBuf {
    repo_root.join(".beads").join("tuskd").join("tuskd.sock")
}

fn root_from_candidate(path: &Path) -> Result<PathBuf> {
    let candidate = candidate_dir(path);
    let output = Command::new("git")
        .current_dir(&candidate)
        .args(["rev-parse", "--show-toplevel"])
        .output();

    match output {
        Ok(output) if output.status.success() => {
            let root = String::from_utf8(output.stdout).context("decode git output")?;
            Ok(PathBuf::from(root.trim()))
        }
        _ => Ok(candidate.canonicalize().unwrap_or(candidate)),
    }
}

fn candidate_dir(path: &Path) -> PathBuf {
    if path.is_dir() {
        path.to_path_buf()
    } else {
        path.parent()
            .map(Path::to_path_buf)
            .unwrap_or_else(|| path.to_path_buf())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::sync::{Mutex, OnceLock};
    use std::time::{SystemTime, UNIX_EPOCH};

    fn env_lock() -> &'static Mutex<()> {
        static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
        LOCK.get_or_init(|| Mutex::new(()))
    }

    fn unique_temp_dir(prefix: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = env::temp_dir().join(format!("{prefix}-{nanos}"));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn canonical_repo_root_prefers_tracker_env_over_cwd() {
        let _guard = env_lock().lock().unwrap_or_else(|error| error.into_inner());
        let cwd = env::current_dir().unwrap();
        let temp_dir = unique_temp_dir("tusk-ui-cli-cwd");
        let tracker_root = unique_temp_dir("tusk-ui-cli-tracker");

        let old_tracker_root = env::var_os("TUSK_TRACKER_ROOT");
        let old_beads_root = env::var_os("BEADS_WORKSPACE_ROOT");
        let old_checkout_root = env::var_os("TUSK_CHECKOUT_ROOT");
        let old_devenv_root = env::var_os("DEVENV_ROOT");
        let old_flake_root = env::var_os("TUSK_FLAKE_ROOT");

        env::set_current_dir(&temp_dir).unwrap();
        unsafe {
            env::set_var("TUSK_TRACKER_ROOT", &tracker_root);
            env::remove_var("BEADS_WORKSPACE_ROOT");
            env::remove_var("TUSK_CHECKOUT_ROOT");
            env::remove_var("DEVENV_ROOT");
            env::remove_var("TUSK_FLAKE_ROOT");
        }

        let resolved = canonical_repo_root(None).unwrap();
        assert_eq!(resolved, tracker_root.canonicalize().unwrap());

        env::set_current_dir(cwd).unwrap();
        restore_env("TUSK_TRACKER_ROOT", old_tracker_root);
        restore_env("BEADS_WORKSPACE_ROOT", old_beads_root);
        restore_env("TUSK_CHECKOUT_ROOT", old_checkout_root);
        restore_env("DEVENV_ROOT", old_devenv_root);
        restore_env("TUSK_FLAKE_ROOT", old_flake_root);
    }

    #[test]
    fn canonical_repo_root_prefers_explicit_repo_arg() {
        let _guard = env_lock().lock().unwrap_or_else(|error| error.into_inner());
        let explicit_root = unique_temp_dir("tusk-ui-cli-explicit");
        let nested_dir = explicit_root.join("nested");
        let nested_file = nested_dir.join("config.toml");
        let old_tracker_root = env::var_os("TUSK_TRACKER_ROOT");

        fs::create_dir_all(&nested_dir).unwrap();
        fs::write(&nested_file, "ok").unwrap();
        unsafe {
            env::set_var("TUSK_TRACKER_ROOT", unique_temp_dir("tusk-ui-cli-ignored"));
        }

        let resolved = canonical_repo_root(Some(&nested_file)).unwrap();
        assert_eq!(resolved, nested_dir.canonicalize().unwrap());

        restore_env("TUSK_TRACKER_ROOT", old_tracker_root);
    }

    fn restore_env(key: &str, value: Option<std::ffi::OsString>) {
        unsafe {
            match value {
                Some(value) => env::set_var(key, value),
                None => env::remove_var(key),
            }
        }
    }
}
