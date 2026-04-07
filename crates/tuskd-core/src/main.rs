use chrono::Utc;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::env;
use std::ffi::{OsStr, OsString};
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode, Stdio};
use std::thread;
use std::time::Duration;

const HELP: &str = "\
Usage:
  tuskd-core seam [--json]
  tuskd-core ensure --repo PATH [--socket PATH]
  tuskd-core status --repo PATH [--socket PATH]
  tuskd-core board-status --repo PATH
  tuskd-core receipts-status --repo PATH
  tuskd-core lane-state <upsert|remove> ...
  tuskd-core receipt append ...
  tuskd-core action-prepare --repo PATH [--socket PATH] --kind KIND --payload JSON
  tuskd-core action-run --repo PATH [--socket PATH] --kind KIND --payload JSON
  tuskd-core query --repo PATH [--socket PATH] --kind KIND [--request-id ID] [--payload JSON]
  tuskd-core respond --repo PATH [--socket PATH]
  tuskd-core help

Commands:
  seam            Print the first Rust-owned backend/service seam contract.
  ensure          Run the Rust-owned backend ensure and service publication path.
  status          Publish the current backend/service projection without repair.
  board-status    Publish the current board projection.
  receipts-status Publish the current receipt projection.
  lane-state      Mutate repo-local lane state through Rust-owned file updates.
  receipt         Append one receipt through the Rust-owned audit seam.
  action-prepare  Build one write-side carrier and admission result.
  action-run      Execute one write-side coordinator action through the Rust kernel.
  query           Render one read-side protocol response envelope.
  respond         Read one protocol request from stdin and answer it through the Rust protocol surface.
  help            Show this help text.
";

const SEAM_TEXT: &str = "\
tuskd core seam scaffold
  package: tuskd-core
  wrapper entrypoint: tuskd core-seam
  ensure entrypoint: tuskd ensure
  status entrypoint: tuskd status
  transition family: tracker.ensure
  scope:
    - backend ensure
    - live-server adoption
    - healthy service-record publication
  rust owns:
    - singleflight lock handling
    - backend probing and start/adoption
    - health snapshot assembly
    - service-record serialization and publication
    - tracker.ensure receipt emission
  shell remains:
    - CLI argument parsing
    - environment and path adaptation
    - compatibility wrapper over the Rust seam
";

const SEAM_JSON: &str = r#"{
  "kind": "backend-service-carrier",
  "status": "ported-first-seam",
  "package": "tuskd-core",
  "wrapper_entrypoint": "tuskd core-seam",
  "ensure_entrypoint": "tuskd ensure",
  "status_entrypoint": "tuskd status",
  "transition_family": "tracker.ensure",
  "scope": [
    "backend ensure",
    "live-server adoption",
    "healthy service-record publication"
  ],
  "rust_owns": [
    "singleflight lock handling",
    "backend probing and start/adoption",
    "health snapshot assembly",
    "service-record serialization and publication",
    "tracker.ensure receipt emission"
  ],
  "shell_remains": [
    "CLI argument parsing",
    "environment and path adaptation",
    "compatibility wrapper over the Rust seam"
  ]
}"#;

fn print_help() {
    print!("{HELP}");
}

fn print_seam(json_output: bool) {
    if json_output {
        println!("{SEAM_JSON}");
    } else {
        print!("{SEAM_TEXT}");
    }
}

fn fail(message: &str) -> ExitCode {
    eprintln!("tuskd-core: {message}");
    ExitCode::from(1)
}

fn now_iso8601() -> String {
    Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string()
}

fn current_pid() -> i32 {
    std::process::id() as i32
}

fn is_live_pid(pid: i32) -> bool {
    unsafe { libc::kill(pid, 0) == 0 }
}

fn repo_root_arg(path: &str) -> Result<PathBuf, String> {
    let path = PathBuf::from(path);
    if path.is_absolute() {
        Ok(path)
    } else {
        env::current_dir()
            .map_err(|err| format!("failed to read current directory: {err}"))
            .map(|cwd| cwd.join(path))
    }
}

fn state_root(repo_root: &Path) -> PathBuf {
    repo_root.join(".beads").join("tuskd")
}

fn service_path(repo_root: &Path) -> PathBuf {
    state_root(repo_root).join("service.json")
}

fn leases_path(repo_root: &Path) -> PathBuf {
    state_root(repo_root).join("leases.json")
}

fn receipts_path(repo_root: &Path) -> PathBuf {
    state_root(repo_root).join("receipts.jsonl")
}

fn lanes_path(repo_root: &Path) -> PathBuf {
    state_root(repo_root).join("lanes.json")
}

fn metadata_path(repo_root: &Path) -> PathBuf {
    repo_root.join(".beads").join("metadata.json")
}

fn local_backend_pid_path(repo_root: &Path) -> PathBuf {
    repo_root.join(".beads").join("dolt-server.pid")
}

fn local_backend_port_path(repo_root: &Path) -> PathBuf {
    repo_root.join(".beads").join("dolt-server.port")
}

fn backend_data_dir(repo_root: &Path) -> PathBuf {
    repo_root.join(".beads").join("dolt")
}

fn backend_host() -> &'static str {
    "127.0.0.1"
}

fn host_state_root() -> PathBuf {
    if let Some(path) = env::var_os("TUSK_HOST_STATE_ROOT") {
        return PathBuf::from(path);
    }

    if let Some(path) = env::var_os("XDG_STATE_HOME") {
        return PathBuf::from(path).join("tusk");
    }

    if cfg!(target_os = "macos") {
        if let Some(home) = env::var_os("HOME") {
            return PathBuf::from(home)
                .join("Library")
                .join("Caches")
                .join("tusk");
        }
    }

    if let Some(home) = env::var_os("HOME") {
        return PathBuf::from(home)
            .join(".local")
            .join("state")
            .join("tusk");
    }

    PathBuf::from("/tmp/tusk")
}

fn host_services_root() -> PathBuf {
    host_state_root().join("services")
}

fn host_locks_root() -> PathBuf {
    host_state_root().join("locks")
}

fn service_key(repo_root: &Path) -> String {
    let mut hasher = Sha256::new();
    hasher.update(b"bd-tracker:");
    hasher.update(repo_root.as_os_str().as_bytes());
    let digest = hasher.finalize();
    let mut key = String::new();
    for byte in digest.iter().take(8) {
        key.push_str(&format!("{byte:02x}"));
    }
    key
}

fn host_service_path(repo_root: &Path) -> PathBuf {
    host_services_root().join(format!("{}.json", service_key(repo_root)))
}

fn host_lock_dir(repo_root: &Path) -> PathBuf {
    host_locks_root().join(format!("{}.lock", service_key(repo_root)))
}

fn host_startup_lock_dir() -> PathBuf {
    host_locks_root().join("backend-startup.lock")
}

fn default_socket_path(repo_root: &Path) -> PathBuf {
    state_root(repo_root).join("tuskd.sock")
}

fn ensure_parent_dir(path: &Path) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|err| format!("failed to create {}: {err}", parent.display()))?;
    }
    Ok(())
}

fn atomic_write(path: &Path, bytes: &[u8]) -> Result<(), String> {
    ensure_parent_dir(path)?;
    let tmp_path = path.with_extension(format!("tmp.{}", current_pid()));
    fs::write(&tmp_path, bytes)
        .map_err(|err| format!("failed to write {}: {err}", tmp_path.display()))?;
    fs::rename(&tmp_path, path)
        .map_err(|err| format!("failed to rename {}: {err}", path.display()))?;
    Ok(())
}

fn read_trimmed(path: &Path) -> Option<String> {
    fs::read_to_string(path)
        .ok()
        .map(|text| text.trim().to_string())
}

fn read_json_file(path: &Path) -> Value {
    fs::read_to_string(path)
        .ok()
        .and_then(|text| serde_json::from_str::<Value>(&text).ok())
        .unwrap_or(Value::Null)
}

fn ensure_host_state_dirs() -> Result<(), String> {
    fs::create_dir_all(host_services_root())
        .map_err(|err| format!("failed to create host services root: {err}"))?;
    fs::create_dir_all(host_locks_root())
        .map_err(|err| format!("failed to create host locks root: {err}"))?;
    Ok(())
}

struct DirLock {
    path: PathBuf,
}

impl DirLock {
    fn acquire(path: PathBuf) -> Result<Self, String> {
        ensure_host_state_dirs()?;

        loop {
            match fs::create_dir(&path) {
                Ok(()) => {
                    fs::write(path.join("pid"), format!("{}\n", current_pid()))
                        .map_err(|err| format!("failed to write lock pid: {err}"))?;
                    fs::write(path.join("acquired_at"), format!("{}\n", now_iso8601()))
                        .map_err(|err| format!("failed to write lock timestamp: {err}"))?;
                    return Ok(Self { path });
                }
                Err(err) if err.kind() == std::io::ErrorKind::AlreadyExists => {
                    let holder_pid =
                        read_trimmed(&path.join("pid")).and_then(|value| value.parse::<i32>().ok());
                    if holder_pid.is_some_and(|pid| !is_live_pid(pid)) {
                        let _ = fs::remove_dir_all(&path);
                        continue;
                    }
                    thread::sleep(Duration::from_millis(100));
                }
                Err(err) => {
                    return Err(format!("failed to create lock {}: {err}", path.display()));
                }
            }
        }
    }
}

impl Drop for DirLock {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

fn local_backend_port(repo_root: &Path) -> Option<u16> {
    read_trimmed(&local_backend_port_path(repo_root)).and_then(|value| value.parse().ok())
}

fn local_backend_pid(repo_root: &Path) -> Option<i32> {
    read_trimmed(&local_backend_pid_path(repo_root)).and_then(|value| value.parse().ok())
}

fn host_service_record(repo_root: &Path) -> Value {
    read_json_file(&host_service_path(repo_root))
}

fn recorded_backend_port(repo_root: &Path) -> Option<u16> {
    host_service_record(repo_root)
        .get("backend_endpoint")
        .and_then(|value| value.get("port"))
        .and_then(Value::as_u64)
        .and_then(|value| value.try_into().ok())
}

fn recorded_backend_pid(repo_root: &Path) -> Option<i32> {
    host_service_record(repo_root)
        .get("backend_runtime")
        .and_then(|value| value.get("pid"))
        .and_then(Value::as_i64)
        .and_then(|value| value.try_into().ok())
}

fn port_owner_pid(port: u16) -> Option<i32> {
    let output = Command::new("lsof")
        .args(["-nP", &format!("-iTCP:{port}"), "-sTCP:LISTEN", "-t"])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    stdout
        .lines()
        .find_map(|line| line.trim().parse::<i32>().ok())
}

fn port_matches_pid(port: u16, pid: i32) -> bool {
    port_owner_pid(port).is_some_and(|owner| owner == pid)
}

fn reusable_recorded_port(repo_root: &Path) -> Option<u16> {
    let port = recorded_backend_port(repo_root)?;
    let pid = recorded_backend_pid(repo_root);

    if let Some(pid) = pid
        && is_live_pid(pid)
        && port_matches_pid(port, pid)
    {
        return Some(port);
    }

    if port_owner_pid(port).is_none() {
        return Some(port);
    }

    None
}

fn reusable_local_backend_port(repo_root: &Path) -> Option<u16> {
    let port = local_backend_port(repo_root)?;
    let pid = local_backend_pid(repo_root)?;

    if is_live_pid(pid) && port_matches_pid(port, pid) {
        Some(port)
    } else {
        None
    }
}

fn stable_backend_port(repo_root: &Path) -> u16 {
    let key = service_key(repo_root);
    let prefix = &key[..6];
    let offset = u32::from_str_radix(prefix, 16).unwrap_or(0) % 20000;
    (17000 + offset) as u16
}

fn select_backend_port(repo_root: &Path, skip_port: Option<u16>) -> Result<u16, String> {
    if let Some(port) = reusable_recorded_port(repo_root)
        && Some(port) != skip_port
    {
        return Ok(port);
    }

    if let Some(port) = reusable_local_backend_port(repo_root)
        && Some(port) != skip_port
    {
        return Ok(port);
    }

    let mut candidate = stable_backend_port(repo_root);
    for _ in 0..512 {
        if Some(candidate) != skip_port && port_owner_pid(candidate).is_none() {
            return Ok(candidate);
        }
        candidate = if candidate >= 36999 {
            17000
        } else {
            candidate + 1
        };
    }

    Err(format!(
        "unable to allocate a repo-scoped Dolt port for {}",
        repo_root.display()
    ))
}

fn run_in_repo_capture<I, S>(
    repo_root: &Path,
    program: &str,
    args: I,
) -> Result<(i32, String), String>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let output = Command::new(program)
        .args(args)
        .current_dir(repo_root)
        .env("BEADS_WORKSPACE_ROOT", repo_root)
        .env("DEVENV_ROOT", repo_root)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .map_err(|err| format!("failed to run {program}: {err}"))?;

    let mut combined = String::new();
    combined.push_str(&String::from_utf8_lossy(&output.stdout));
    combined.push_str(&String::from_utf8_lossy(&output.stderr));

    Ok((output.status.code().unwrap_or(1), combined))
}

fn extract_json_output(output: &str) -> Option<Value> {
    let trimmed = output.trim();
    if let Ok(value) = serde_json::from_str::<Value>(trimmed) {
        return Some(value);
    }

    let mut candidate = String::new();
    let mut capture = false;
    for line in output.lines() {
        let trimmed = line.trim_start();
        if !capture && (trimmed.starts_with('{') || trimmed.starts_with('[')) {
            capture = true;
        }
        if capture {
            candidate.push_str(line);
            candidate.push('\n');
        }
    }
    serde_json::from_str::<Value>(candidate.trim()).ok()
}

fn render_command_result(name: &str, exit_code: i32, output: &str) -> Value {
    let ok = exit_code == 0;
    if let Some(parsed) = extract_json_output(output) {
        json!({
            "name": name,
            "ok": ok,
            "exit_code": exit_code,
            "output": parsed,
        })
    } else {
        json!({
            "name": name,
            "ok": ok,
            "exit_code": exit_code,
            "output_text": output,
        })
    }
}

fn run_tracker_json_command_in_repo<I, S>(
    repo_root: &Path,
    name: &str,
    args: I,
) -> Result<Value, String>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let (exit_code, output) = run_in_repo_capture(repo_root, "tusk-tracker", args)?;
    Ok(render_command_result(name, exit_code, &output))
}

fn run_tracker_capture_in_repo<I, S>(repo_root: &Path, args: I) -> Result<(i32, String), String>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    run_in_repo_capture(repo_root, "tusk-tracker", args)
}

fn tracker_uses_server_mode(repo_root: &Path) -> bool {
    read_json_file(&metadata_path(repo_root))
        .get("dolt_mode")
        .and_then(Value::as_str)
        == Some("server")
}

fn configure_backend_endpoint(repo_root: &Path, port: u16) -> Result<(), String> {
    let port_string = port.to_string();
    let mut args: Vec<OsString> = vec![
        "backend".into(),
        "configure".into(),
        "--host".into(),
        backend_host().into(),
        "--port".into(),
        port_string.into(),
    ];
    if !tracker_uses_server_mode(repo_root) {
        args.push("--data-dir".into());
        args.push(backend_data_dir(repo_root).as_os_str().to_os_string());
    }
    let (exit_code, output) = run_tracker_capture_in_repo(repo_root, args)?;

    if exit_code == 0 {
        Ok(())
    } else {
        Err(format!("backend configure failed: {}", output.trim()))
    }
}

fn write_local_backend_runtime(
    repo_root: &Path,
    port: u16,
    pid: Option<i32>,
) -> Result<(), String> {
    ensure_parent_dir(&local_backend_port_path(repo_root))?;
    fs::write(local_backend_port_path(repo_root), format!("{port}\n"))
        .map_err(|err| format!("failed to write local backend port: {err}"))?;
    if let Some(pid) = pid {
        fs::write(local_backend_pid_path(repo_root), format!("{pid}\n"))
            .map_err(|err| format!("failed to write local backend pid: {err}"))?;
    } else if local_backend_pid_path(repo_root).exists() {
        fs::remove_file(local_backend_pid_path(repo_root))
            .map_err(|err| format!("failed to remove local backend pid: {err}"))?;
    }
    Ok(())
}

fn clear_local_backend_runtime(repo_root: &Path) {
    let _ = fs::remove_file(local_backend_pid_path(repo_root));
    let _ = fs::remove_file(local_backend_port_path(repo_root));
}

fn scrub_deprecated_backend_config(repo_root: &Path) -> Result<(), String> {
    let path = metadata_path(repo_root);
    if !path.exists() {
        return Ok(());
    }

    let mut value = read_json_file(&path);
    if let Value::Object(ref mut map) = value {
        map.remove("dolt_server_port");
        let bytes = serde_json::to_vec(&value)
            .map_err(|err| format!("failed to serialize metadata: {err}"))?;
        atomic_write(&path, &bytes)?;
    }
    Ok(())
}

fn configured_backend_port(repo_root: &Path) -> Option<u16> {
    run_tracker_json_command_in_repo(repo_root, "tracker_backend_show", ["backend", "show"])
        .ok()
        .and_then(|value| value.get("output").cloned())
        .and_then(|value| value.get("port").cloned())
        .and_then(|value| value.as_u64())
        .and_then(|value| value.try_into().ok())
}

fn effective_backend_port(repo_root: &Path) -> Option<u16> {
    reusable_local_backend_port(repo_root)
        .or_else(|| {
            let port = configured_backend_port(repo_root)?;
            if port_owner_pid(port).is_some() {
                Some(port)
            } else {
                None
            }
        })
        .or_else(|| local_backend_port(repo_root))
        .or_else(|| Some(stable_backend_port(repo_root)))
}

fn backend_runtime_snapshot(repo_root: &Path) -> Value {
    let port = effective_backend_port(repo_root);
    let pid = port.and_then(port_owner_pid);

    json!({
        "checked_at": now_iso8601(),
        "host": backend_host(),
        "data_dir": backend_data_dir(repo_root).to_string_lossy().into_owned(),
        "port": port,
        "pid": pid,
        "running": pid.is_some(),
    })
}

fn health_snapshot(
    repo_root: &Path,
    socket_path: &Path,
    allow_repair: bool,
) -> Result<Value, String> {
    let repair = if allow_repair {
        ensure_backend_connection(repo_root)?
    } else {
        Value::Null
    };

    let ready = run_tracker_json_command_in_repo(repo_root, "tracker_ready", ["ready"])?;
    let show =
        run_tracker_json_command_in_repo(repo_root, "tracker_backend_show", ["backend", "show"])?;
    let test =
        run_tracker_json_command_in_repo(repo_root, "tracker_backend_test", ["backend", "test"])?;
    let status = run_tracker_json_command_in_repo(
        repo_root,
        "tracker_backend_status",
        ["backend", "status"],
    )?;
    let tracker_status = run_tracker_json_command_in_repo(repo_root, "tracker_status", ["status"])?;

    let runtime = backend_runtime_snapshot(repo_root);
    let backend = if show.get("ok").and_then(Value::as_bool) == Some(true) {
        match show.get("output") {
            Some(Value::Object(object)) => {
                let mut merged = runtime.as_object().cloned().unwrap_or_default();
                for (key, value) in object {
                    merged.insert(key.clone(), value.clone());
                }
                Value::Object(merged)
            }
            _ => runtime,
        }
    } else {
        runtime
    };

    Ok(json!({
        "checked_at": now_iso8601(),
        "status": if test.get("ok").and_then(Value::as_bool) == Some(true)
            && show.get("ok").and_then(Value::as_bool) == Some(true)
            && tracker_status.get("ok").and_then(Value::as_bool) == Some(true)
            && test
                .get("output")
                .and_then(|value| value.get("connection_ok"))
                .and_then(Value::as_bool)
                == Some(true)
        {
            "healthy"
        } else {
            "unhealthy"
        },
        "checks": {
            "tracker_ready": ready,
            "tracker_backend_show": show,
            "tracker_backend_test": test,
            "tracker_backend_status": status,
            "tracker_status": tracker_status,
            "backend_repair": repair,
        },
        "backend": backend,
        "summary": tracker_status
            .get("output")
            .and_then(|value| value.get("summary"))
            .cloned()
            .unwrap_or(Value::Null),
        "protocol": {
            "kind": "unix",
            "endpoint": socket_path.to_string_lossy().into_owned(),
        },
    }))
}

fn current_leases(repo_root: &Path) -> Value {
    let path = leases_path(repo_root);
    if !path.exists() {
        return json!([]);
    }
    read_json_file(&path)
}

fn live_server_pid(repo_root: &Path) -> Option<i32> {
    read_json_file(&service_path(repo_root))
        .get("tuskd")
        .and_then(|value| value.get("pid"))
        .and_then(Value::as_i64)
        .and_then(|value| value.try_into().ok())
        .filter(|pid| is_live_pid(*pid))
}

fn receipt_record_json(repo_root: &Path, kind: &str, payload: Value) -> Value {
    json!({
        "timestamp": now_iso8601(),
        "kind": kind,
        "repo_root": repo_root.to_string_lossy().into_owned(),
        "payload": payload,
    })
}

fn append_receipt(repo_root: &Path, kind: &str, payload: Value) -> Result<Value, String> {
    ensure_parent_dir(&receipts_path(repo_root))?;
    let receipt = receipt_record_json(repo_root, kind, payload);
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(receipts_path(repo_root))
        .map_err(|err| format!("failed to open receipt log: {err}"))?;
    writeln!(
        file,
        "{}",
        serde_json::to_string(&receipt)
            .map_err(|err| format!("failed to encode receipt: {err}"))?
    )
    .map_err(|err| format!("failed to append receipt: {err}"))?;
    Ok(receipt)
}

fn write_service_record(
    repo_root: &Path,
    socket_path: &Path,
    mode: &str,
    pid: Option<i32>,
    health: &Value,
    leases: &Value,
) -> Result<Value, String> {
    let path = service_path(repo_root);
    let host_path = host_service_path(repo_root);
    ensure_host_state_dirs()?;

    let record = json!({
        "schema_version": 2,
        "generated_at": now_iso8601(),
        "service_kind": "bd-tracker",
        "service_key": service_key(repo_root),
        "repo_root": repo_root.to_string_lossy().into_owned(),
        "state_paths": {
            "root": state_root(repo_root).to_string_lossy().into_owned(),
            "service": path.to_string_lossy().into_owned(),
            "leases": leases_path(repo_root).to_string_lossy().into_owned(),
            "receipts": receipts_path(repo_root).to_string_lossy().into_owned(),
            "lanes": lanes_path(repo_root).to_string_lossy().into_owned(),
        },
        "host_registry": {
            "root": host_state_root().to_string_lossy().into_owned(),
            "service": host_path.to_string_lossy().into_owned(),
            "lock": host_lock_dir(repo_root).to_string_lossy().into_owned(),
        },
        "protocol": {
            "kind": "unix",
            "endpoint": socket_path.to_string_lossy().into_owned(),
        },
        "backend_endpoint": {
            "host": backend_host(),
            "port": health
                .get("backend")
                .and_then(|value| value.get("port"))
                .cloned()
                .unwrap_or(Value::Null),
            "data_dir": backend_data_dir(repo_root).to_string_lossy().into_owned(),
        },
        "backend_runtime": health.get("backend").cloned().unwrap_or(Value::Null),
        "tuskd": {
            "mode": mode,
            "pid": pid,
        },
        "health": health,
        "active_leases": leases,
    });

    let bytes = serde_json::to_vec(&record)
        .map_err(|err| format!("failed to encode service record: {err}"))?;
    atomic_write(&path, &bytes)?;
    atomic_write(&host_path, &bytes)?;
    Ok(record)
}

fn ensure_state_files(repo_root: &Path) -> Result<(), String> {
    fs::create_dir_all(state_root(repo_root))
        .map_err(|err| format!("failed to create state root: {err}"))?;

    for (path, default) in [
        (leases_path(repo_root), "[]\n"),
        (lanes_path(repo_root), "[]\n"),
    ] {
        if !path.exists() {
            fs::write(&path, default)
                .map_err(|err| format!("failed to initialize {}: {err}", path.display()))?;
        }
    }

    if !receipts_path(repo_root).exists() {
        File::create(receipts_path(repo_root))
            .map_err(|err| format!("failed to initialize receipts: {err}"))?;
    }

    Ok(())
}

fn ensure_backend_connection(repo_root: &Path) -> Result<Value, String> {
    let _startup_lock = DirLock::acquire(host_startup_lock_dir())?;
    let _service_lock = DirLock::acquire(host_lock_dir(repo_root))?;

    let mut attempt = 1;
    let max_attempts = 4;
    let mut skip_port: Option<u16> = None;
    let mut attempts = Vec::new();
    let mut ok = false;

    while attempt <= max_attempts {
        let selected_port = select_backend_port(repo_root, skip_port)?;
        configure_backend_endpoint(repo_root, selected_port)?;
        write_local_backend_runtime(repo_root, selected_port, None)?;
        scrub_deprecated_backend_config(repo_root)?;

        let (_, mut test_output) = run_tracker_capture_in_repo(repo_root, ["backend", "test"])?;
        let mut test_ok = extract_json_output(&test_output)
            .and_then(|value| value.get("connection_ok").and_then(Value::as_bool))
            .unwrap_or(false);
        let mut start_output = String::new();
        let mut start_ok = true;

        if !test_ok {
            let (start_exit, output) =
                run_tracker_capture_in_repo(repo_root, ["backend", "start"])?;
            start_ok = start_exit == 0;
            start_output = output;
            let (_, output) = run_tracker_capture_in_repo(repo_root, ["backend", "test"])?;
            test_output = output;
            test_ok = extract_json_output(&test_output)
                .and_then(|value| value.get("connection_ok").and_then(Value::as_bool))
                .unwrap_or(false);
        }

        let pid = port_owner_pid(selected_port);
        if test_ok {
            write_local_backend_runtime(repo_root, selected_port, pid)?;
            ok = true;
        }

        attempts.push(json!({
            "attempt": attempt,
            "port": selected_port,
            "test_ok": test_ok,
            "start_ok": start_ok,
            "pid": pid,
            "start_output": if start_output.trim().is_empty() {
                Value::Null
            } else {
                Value::String(start_output.trim().to_string())
            },
            "test_output": extract_json_output(&test_output).unwrap_or_else(|| Value::String(test_output.trim().to_string())),
        }));

        if ok {
            break;
        }

        skip_port = Some(selected_port);
        attempt += 1;
    }

    if !ok {
        clear_local_backend_runtime(repo_root);
    }

    Ok(json!({
        "ok": ok,
        "repo_root": repo_root.to_string_lossy().into_owned(),
        "attempts": attempts,
        "runtime": backend_runtime_snapshot(repo_root),
    }))
}

struct EnsuredService {
    record: Value,
    health: Value,
    leases: Value,
    mode: String,
    pid: Option<i32>,
}

fn perform_ensure(repo_root: &Path, socket_path: &Path) -> Result<EnsuredService, String> {
    ensure_state_files(repo_root)?;
    let health = health_snapshot(repo_root, socket_path, true)?;
    let leases = current_leases(repo_root);
    let server_pid = live_server_pid(repo_root);
    let (mode, pid) = if let Some(pid) = server_pid {
        ("serving".to_string(), Some(pid))
    } else {
        ("idle".to_string(), None)
    };

    let record =
        write_service_record(repo_root, socket_path, mode.as_str(), pid, &health, &leases)?;
    Ok(EnsuredService {
        record,
        health,
        leases,
        mode,
        pid,
    })
}

fn status_projection(repo_root: &Path, socket_path: &Path) -> Result<Value, String> {
    ensure_state_files(repo_root)?;
    let health = health_snapshot(repo_root, socket_path, false)?;
    let leases = current_leases(repo_root);
    let server_pid = live_server_pid(repo_root);
    let (mode, pid) = if let Some(pid) = server_pid {
        ("serving", Some(pid))
    } else {
        ("idle", None)
    };

    write_service_record(repo_root, socket_path, mode, pid, &health, &leases)
}

fn render_lines_result(name: &str, exit_code: i32, output: &str) -> Value {
    let ok = exit_code == 0;
    let lines = output
        .lines()
        .filter(|line| !line.is_empty())
        .map(|line| Value::String(line.to_string()))
        .collect::<Vec<_>>();

    json!({
        "name": name,
        "ok": ok,
        "exit_code": exit_code,
        "output": lines,
    })
}

fn run_lines_command_in_repo<I, S>(
    repo_root: &Path,
    name: &str,
    program: &str,
    args: I,
) -> Result<Value, String>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let (exit_code, output) = run_in_repo_capture(repo_root, program, args)?;
    Ok(render_lines_result(name, exit_code, &output))
}

fn current_lanes(repo_root: &Path) -> Value {
    match read_json_file(&lanes_path(repo_root)) {
        Value::Array(items) => Value::Array(items),
        _ => json!([]),
    }
}

fn write_json_value(path: &Path, value: &Value) -> Result<(), String> {
    let bytes = serde_json::to_vec(value)
        .map_err(|err| format!("failed to encode {}: {err}", path.display()))?;
    atomic_write(path, &bytes)
}

fn lane_state_upsert(repo_root: &Path, lane: Value) -> Result<Value, String> {
    ensure_state_files(repo_root)?;

    let issue_id = lane
        .get("issue_id")
        .and_then(Value::as_str)
        .ok_or("lane-state upsert requires lane_json.issue_id")?
        .to_string();

    let mut lanes = match current_lanes(repo_root) {
        Value::Array(items) => items,
        _ => Vec::new(),
    };
    lanes.retain(|existing| {
        existing.get("issue_id").and_then(Value::as_str) != Some(issue_id.as_str())
    });
    lanes.push(lane.clone());
    lanes.sort_by(|left, right| {
        let left_id = left.get("issue_id").and_then(Value::as_str).unwrap_or("");
        let right_id = right.get("issue_id").and_then(Value::as_str).unwrap_or("");
        left_id.cmp(right_id)
    });

    write_json_value(&lanes_path(repo_root), &Value::Array(lanes))?;
    Ok(json!({
        "repo_root": repo_root.to_string_lossy().into_owned(),
        "issue_id": issue_id,
        "lane": lane,
    }))
}

fn lane_state_remove(repo_root: &Path, issue_id: &str) -> Result<Value, String> {
    ensure_state_files(repo_root)?;
    if issue_id.is_empty() {
        return Err("lane-state remove requires --issue-id".to_string());
    }

    let mut removed_lane = Value::Null;
    let lanes = match current_lanes(repo_root) {
        Value::Array(items) => items,
        _ => Vec::new(),
    };
    let retained = lanes
        .into_iter()
        .filter(|existing| {
            let matches = existing.get("issue_id").and_then(Value::as_str) == Some(issue_id);
            if matches {
                removed_lane = existing.clone();
            }
            !matches
        })
        .collect::<Vec<_>>();

    write_json_value(&lanes_path(repo_root), &Value::Array(retained))?;
    Ok(json!({
        "repo_root": repo_root.to_string_lossy().into_owned(),
        "issue_id": issue_id,
        "removed_lane": removed_lane,
    }))
}

fn lane_state_projection(repo_root: &Path) -> Result<Value, String> {
    ensure_state_files(repo_root)?;
    let lanes = current_lanes(repo_root);
    let mut projected = Vec::new();

    if let Some(items) = lanes.as_array() {
        for lane in items {
            let mut lane_object = lane.as_object().cloned().unwrap_or_default();
            let workspace_path = lane_object
                .get("workspace_path")
                .and_then(Value::as_str)
                .unwrap_or("");
            let workspace_exists = !workspace_path.is_empty() && Path::new(workspace_path).is_dir();
            let stored_status = lane_object
                .get("status")
                .and_then(Value::as_str)
                .unwrap_or("launched");
            let observed_status = if workspace_exists || stored_status == "finished" {
                stored_status.to_string()
            } else {
                "stale".to_string()
            };

            lane_object.insert(
                "workspace_exists".to_string(),
                Value::Bool(workspace_exists),
            );
            lane_object.insert(
                "observed_status".to_string(),
                Value::String(observed_status),
            );
            projected.push(Value::Object(lane_object));
        }
    }

    Ok(Value::Array(projected))
}

fn board_status_projection(repo_root: &Path, socket_path: &Path) -> Result<Value, String> {
    let status_result = run_tracker_json_command_in_repo(repo_root, "tracker_status", ["status"])?;
    let ready_result = run_tracker_json_command_in_repo(repo_root, "tracker_ready", ["ready"])?;
    let board_issues_result =
        run_tracker_json_command_in_repo(repo_root, "tracker_board_issues", ["issues", "board"])?;
    let workspaces_result = run_lines_command_in_repo(
        repo_root,
        "jj_workspace_list",
        "jj",
        [
            "workspace",
            "list",
            "--ignore-working-copy",
            "--color",
            "never",
        ],
    )?;
    let lanes = lane_state_projection(repo_root)?;

    let summary = status_result
        .get("output")
        .filter(|value| value.is_object())
        .and_then(|value| value.get("summary"))
        .cloned()
        .unwrap_or(Value::Null);

    let ready_issues = ready_result
        .get("output")
        .filter(|value| value.is_array())
        .cloned()
        .unwrap_or_else(|| json!([]));

    let lane_ids = lanes
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|lane| lane.get("issue_id").and_then(Value::as_str))
        .map(|value| value.to_string())
        .collect::<HashSet<_>>();

    let board_output = board_issues_result
        .get("output")
        .cloned()
        .unwrap_or(Value::Null);
    let claimed_issues = board_output
        .get("claimed_issues")
        .and_then(Value::as_array)
        .map(|issues| {
            issues
                .iter()
                .filter(|issue| match issue.get("id").and_then(Value::as_str) {
                    Some(id) => !lane_ids.contains(id),
                    None => true,
                })
                .cloned()
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let blocked_issues = board_output
        .get("blocked_issues")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let deferred_issues = board_output
        .get("deferred_issues")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();

    let workspaces = workspaces_result
        .get("output")
        .filter(|value| value.is_array())
        .cloned()
        .unwrap_or_else(|| json!([]));

    Ok(json!({
        "repo_root": repo_root.to_string_lossy().into_owned(),
        "generated_at": now_iso8601(),
        "summary": summary,
        "ready_issues": ready_issues,
        "claimed_issues": claimed_issues,
        "blocked_issues": blocked_issues,
        "deferred_issues": deferred_issues,
        "lanes": lanes,
        "workspaces": workspaces,
        "checks": {
            "tracker_status": status_result,
            "tracker_ready": ready_result,
            "tracker_board_issues": board_issues_result,
            "jj_workspace_list": workspaces_result,
        },
        "protocol": {
            "kind": "unix",
            "endpoint": socket_path.to_string_lossy().into_owned(),
        },
    }))
}

fn receipts_status_projection(repo_root: &Path) -> Result<Value, String> {
    ensure_state_files(repo_root)?;
    let path = receipts_path(repo_root);
    let mut receipts = Vec::new();

    if let Ok(contents) = fs::read_to_string(&path) {
        let lines = contents
            .lines()
            .filter(|line| !line.is_empty())
            .map(|line| line.to_string())
            .collect::<Vec<_>>();
        let start = lines.len().saturating_sub(20);
        for line in &lines[start..] {
            match serde_json::from_str::<Value>(line) {
                Ok(value) => receipts.push(value),
                Err(_) => receipts.push(json!({ "invalid_line": line })),
            }
        }
    }

    Ok(json!({
        "repo_root": repo_root.to_string_lossy().into_owned(),
        "generated_at": now_iso8601(),
        "receipts_path": path.to_string_lossy().into_owned(),
        "receipts": receipts,
    }))
}

fn ping_payload(repo_root: &Path) -> Value {
    json!({
        "repo_root": repo_root.to_string_lossy().into_owned(),
        "timestamp": now_iso8601(),
        "status": "ok",
    })
}

fn read_payload_for_kind(
    repo_root: &Path,
    socket_path: &Path,
    kind: &str,
) -> Result<Option<Value>, String> {
    match kind {
        "tracker_status" => Ok(Some(status_projection(repo_root, socket_path)?)),
        "board_status" => Ok(Some(board_status_projection(repo_root, socket_path)?)),
        "receipts_status" => Ok(Some(receipts_status_projection(repo_root)?)),
        "ping" => Ok(Some(ping_payload(repo_root))),
        _ => Ok(None),
    }
}

fn query_response(
    repo_root: &Path,
    socket_path: &Path,
    request_id: &str,
    kind: &str,
) -> Result<Option<Value>, String> {
    let Some(payload) = read_payload_for_kind(repo_root, socket_path, kind)? else {
        return Ok(None);
    };

    Ok(Some(json!({
        "request_id": request_id,
        "ok": true,
        "kind": kind,
        "payload": payload,
    })))
}

#[derive(Clone, Copy)]
enum TransitionKind {
    Ensure,
    ClaimIssue,
    CloseIssue,
    LaunchLane,
    HandoffLane,
    FinishLane,
    ArchiveLane,
}

impl TransitionKind {
    fn parse(kind: &str) -> Option<Self> {
        match kind {
            "ensure" => Some(Self::Ensure),
            "claim_issue" => Some(Self::ClaimIssue),
            "close_issue" => Some(Self::CloseIssue),
            "launch_lane" => Some(Self::LaunchLane),
            "handoff_lane" => Some(Self::HandoffLane),
            "finish_lane" => Some(Self::FinishLane),
            "archive_lane" => Some(Self::ArchiveLane),
            _ => None,
        }
    }

    fn requires_service_lock(self) -> bool {
        !matches!(self, Self::Ensure)
    }
}

fn current_lanes_array(repo_root: &Path) -> Vec<Value> {
    match current_lanes(repo_root) {
        Value::Array(items) => items,
        _ => Vec::new(),
    }
}

fn current_lane_for_issue(repo_root: &Path, issue_id: &str) -> Value {
    current_lanes_array(repo_root)
        .into_iter()
        .find(|lane| lane.get("issue_id").and_then(Value::as_str) == Some(issue_id))
        .unwrap_or(Value::Null)
}

fn issue_receipt_refs(repo_root: &Path, issue_id: &str) -> Value {
    if issue_id.is_empty() {
        return json!([]);
    }

    let path = receipts_path(repo_root);
    let Ok(contents) = fs::read_to_string(path) else {
        return json!([]);
    };

    let mut refs = Vec::new();
    for line in contents.lines().filter(|line| !line.is_empty()) {
        let Ok(value) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        if value
            .get("payload")
            .and_then(|payload| payload.get("issue_id"))
            .and_then(Value::as_str)
            == Some(issue_id)
        {
            refs.push(json!({
                "timestamp": value.get("timestamp").cloned().unwrap_or(Value::Null),
                "kind": value.get("kind").cloned().unwrap_or(Value::Null),
            }));
        }
    }

    Value::Array(refs)
}

fn receipt_refs_by_kind(repo_root: &Path, kind: &str) -> Value {
    if kind.is_empty() {
        return json!([]);
    }

    let path = receipts_path(repo_root);
    let Ok(contents) = fs::read_to_string(path) else {
        return json!([]);
    };

    let mut refs = Vec::new();
    for line in contents.lines().filter(|line| !line.is_empty()) {
        let Ok(value) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        if value.get("kind").and_then(Value::as_str) == Some(kind) {
            refs.push(json!({
                "timestamp": value.get("timestamp").cloned().unwrap_or(Value::Null),
                "kind": value.get("kind").cloned().unwrap_or(Value::Null),
            }));
        }
    }

    Value::Array(refs)
}

fn issue_snapshot_from_result(result: &Value) -> Value {
    if result.get("ok").and_then(Value::as_bool) != Some(true) {
        return Value::Null;
    }

    result
        .get("output")
        .and_then(Value::as_array)
        .and_then(|items| items.first())
        .filter(|value| value.is_object())
        .cloned()
        .unwrap_or(Value::Null)
}

fn resolve_revision_commit(repo_root: &Path, revision: &str) -> Result<Value, String> {
    let repo_root_str = repo_root.to_string_lossy().into_owned();
    let (exit_code, output) = run_in_repo_capture(
        repo_root,
        "jj",
        [
            "--repository",
            repo_root_str.as_str(),
            "log",
            "-r",
            revision,
            "--no-graph",
            "-T",
            "commit_id ++ \"\\n\"",
        ],
    )?;

    let commit = output
        .lines()
        .find(|line| !line.trim().is_empty())
        .map(|line| line.trim().to_string())
        .unwrap_or_default();

    Ok(json!({
        "ok": exit_code == 0 && !commit.is_empty(),
        "revision": revision,
        "output": if output.is_empty() { Value::Null } else { Value::String(output) },
        "commit": if commit.is_empty() { Value::Null } else { Value::String(commit) },
    }))
}

fn workspace_root_dir(repo_root: &Path) -> PathBuf {
    repo_root.join(".jj-workspaces")
}

fn slugify_fragment(input: &str) -> String {
    let mut out = String::new();
    let mut last_dash = false;

    for ch in input.chars().flat_map(char::to_lowercase) {
        if ch.is_ascii_alphanumeric() {
            out.push(ch);
            last_dash = false;
        } else if !last_dash && !out.is_empty() {
            out.push('-');
            last_dash = true;
        }
    }

    while out.ends_with('-') {
        out.pop();
    }

    out
}

fn request_id_seed() -> String {
    format!("{}-{}", current_pid(), Utc::now().timestamp())
}

#[derive(Clone)]
struct TransitionProposal {
    kind: String,
    payload: Value,
}

#[derive(Clone)]
struct TransitionWitness {
    kind: String,
    ok: bool,
    message: Value,
    details: Value,
}

impl TransitionWitness {
    fn into_json(self) -> Value {
        json!({
            "kind": self.kind,
            "ok": self.ok,
            "message": self.message,
            "details": self.details,
        })
    }
}

#[derive(Clone)]
struct TransitionEnvelope {
    carrier: Value,
}

#[derive(Clone)]
struct PreparedTransition {
    kind: TransitionKind,
    envelope: TransitionEnvelope,
}

#[derive(Clone)]
struct AdmittedTransition {
    kind: TransitionKind,
    envelope: TransitionEnvelope,
}

impl TransitionEnvelope {
    fn new(repo_root: &Path, kind: &str, payload: Value) -> Self {
        Self {
            carrier: json!({
                "generated_at": now_iso8601(),
                "repo": {
                    "root": repo_root.to_string_lossy().into_owned(),
                    "service_key": service_key(repo_root),
                    "workspace_root": workspace_root_dir(repo_root).to_string_lossy().into_owned(),
                    "request_id": request_id_seed(),
                },
                "tracker": Value::Null,
                "service": Value::Null,
                "issue": Value::Null,
                "lane": Value::Null,
                "workspace": Value::Null,
                "witnesses": [],
                "intent": {
                    "kind": kind,
                    "payload": payload,
                },
                "admission": Value::Null,
                "realization": Value::Null,
                "receipts": {
                    "prior": [],
                    "emitted": Value::Null,
                },
            }),
        }
    }

    fn proposal(&self) -> TransitionProposal {
        let intent = self.carrier.get("intent").cloned().unwrap_or(Value::Null);
        TransitionProposal {
            kind: intent
                .get("kind")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string(),
            payload: intent.get("payload").cloned().unwrap_or(Value::Null),
        }
    }

    fn payload_string(&self, field: &str) -> String {
        payload_string(&self.proposal().payload, field)
    }

    fn set_field(&mut self, field: &str, value: Value) {
        if let Some(object) = self.carrier.as_object_mut() {
            object.insert(field.to_string(), value);
        }
    }

    fn set_tracker(&mut self, value: Value) {
        self.set_field("tracker", value);
    }

    fn set_service(&mut self, value: Value) {
        self.set_field("service", value);
    }

    fn set_issue(&mut self, value: Value) {
        self.set_field("issue", value);
    }

    fn set_lane(&mut self, value: Value) {
        self.set_field("lane", value);
    }

    fn set_workspace(&mut self, value: Value) {
        self.set_field("workspace", value);
    }

    fn set_application(&mut self, value: Value) {
        self.set_field("realization", value);
    }

    fn set_receipt_refs(&mut self, prior: Value) {
        if let Some(receipts) = self
            .carrier
            .get_mut("receipts")
            .and_then(Value::as_object_mut)
        {
            receipts.insert("prior".to_string(), prior);
        }
    }

    fn set_emitted_receipt(&mut self, receipt: Value) {
        if let Some(receipts) = self
            .carrier
            .get_mut("receipts")
            .and_then(Value::as_object_mut)
        {
            receipts.insert("emitted".to_string(), receipt);
        }
    }

    fn add_witness(&mut self, kind: &str, ok: bool, message: &str, details: Value) {
        if let Some(witnesses) = self
            .carrier
            .get_mut("witnesses")
            .and_then(Value::as_array_mut)
        {
            let witness = TransitionWitness {
                kind: kind.to_string(),
                ok,
                message: if message.is_empty() {
                    Value::Null
                } else {
                    Value::String(message.to_string())
                },
                details,
            };
            witnesses.push(witness.into_json());
        }
    }

    fn set_admission(&mut self, admitted: bool, reason: Option<&str>, consulted: &[&str]) {
        self.set_field(
            "admission",
            json!({
                "admitted": admitted,
                "reason": reason.map(Value::from).unwrap_or(Value::Null),
                "consulted": consulted,
            }),
        );
    }

    fn admitted(&self) -> bool {
        self.carrier
            .get("admission")
            .and_then(|admission| admission.get("admitted"))
            .and_then(Value::as_bool)
            == Some(true)
    }

    fn admission_reason(&self) -> Option<&str> {
        self.carrier
            .get("admission")
            .and_then(|admission| admission.get("reason"))
            .and_then(Value::as_str)
    }

    fn get(&self, field: &str) -> Option<&Value> {
        self.carrier.get(field)
    }

    fn into_json(self) -> Value {
        self.carrier
    }
}

impl PreparedTransition {
    fn admit(self) -> Result<AdmittedTransition, TransitionEnvelope> {
        if self.envelope.admitted() {
            Ok(AdmittedTransition {
                kind: self.kind,
                envelope: self.envelope,
            })
        } else {
            Err(self.envelope)
        }
    }
}

fn transition_service_snapshot(repo_root: &Path, socket_path: &Path) -> Value {
    json!({
        "socket_path": socket_path.to_string_lossy().into_owned(),
        "record": read_json_file(&service_path(repo_root)),
        "leases": current_leases(repo_root),
        "backend": backend_runtime_snapshot(repo_root),
    })
}

fn transition_workspace_snapshot(
    workspace_name: &str,
    workspace_path: &Path,
    base_rev: Option<&str>,
    base_commit: Option<&str>,
    revision: Option<&str>,
) -> Value {
    json!({
        "name": if workspace_name.is_empty() { Value::Null } else { Value::String(workspace_name.to_string()) },
        "path": if workspace_path.as_os_str().is_empty() { Value::Null } else { Value::String(workspace_path.to_string_lossy().into_owned()) },
        "exists": !workspace_path.as_os_str().is_empty() && workspace_path.exists(),
        "base_rev": base_rev.map(Value::from).unwrap_or(Value::Null),
        "base_commit": base_commit.map(Value::from).unwrap_or(Value::Null),
        "revision": revision.map(Value::from).unwrap_or(Value::Null),
    })
}

fn payload_string(payload: &Value, field: &str) -> String {
    payload
        .get(field)
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string()
}

fn build_claim_issue_carrier(
    repo_root: &Path,
    socket_path: &Path,
    payload: &Value,
) -> Result<TransitionEnvelope, String> {
    let issue_id = payload_string(payload, "issue_id");
    let mut carrier =
        TransitionEnvelope::new(repo_root, "claim_issue", json!({ "issue_id": issue_id }));
    carrier.set_service(transition_service_snapshot(repo_root, socket_path));
    carrier.set_receipt_refs(issue_receipt_refs(repo_root, &issue_id));

    let issue_show_result = if issue_id.is_empty() {
        Value::Null
    } else {
        run_tracker_json_command_in_repo(
            repo_root,
            "tracker_issue_show",
            ["issue", "show", issue_id.as_str()],
        )?
    };
    let ready_result = if issue_id.is_empty() {
        Value::Null
    } else {
        run_tracker_json_command_in_repo(repo_root, "tracker_ready", ["ready"])?
    };

    carrier.set_tracker(json!({ "issue_show": issue_show_result, "ready": ready_result }));

    let issue_json =
        issue_snapshot_from_result(carrier.get("tracker").unwrap().get("issue_show").unwrap());
    let issue_exists = !issue_json.is_null();
    let issue_status = issue_json
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    if issue_exists {
        carrier.set_issue(issue_json.clone());
    }

    let ready_claimable = carrier
        .get("tracker")
        .and_then(|tracker| tracker.get("ready"))
        .and_then(|ready| ready.get("ok"))
        .and_then(Value::as_bool)
        == Some(true)
        && carrier
            .get("tracker")
            .and_then(|tracker| tracker.get("ready"))
            .and_then(|ready| ready.get("output"))
            .and_then(Value::as_array)
            .map(|issues| {
                issues
                    .iter()
                    .any(|issue| issue.get("id").and_then(Value::as_str) == Some(issue_id.as_str()))
            })
            .unwrap_or(false);
    let ready_details = carrier
        .get("tracker")
        .and_then(|tracker| tracker.get("ready"))
        .cloned()
        .unwrap_or(Value::Null);

    carrier.add_witness(
        "issue_id",
        !issue_id.is_empty(),
        "issue_id is required",
        json!({ "issue_id": issue_id }),
    );
    carrier.add_witness(
        "issue_exists",
        issue_exists,
        "issue must exist",
        json!({ "issue": issue_json }),
    );
    carrier.add_witness(
        "issue_status_open",
        issue_status == "open",
        "issue must be open before claim",
        json!({ "status": issue_status }),
    );
    carrier.add_witness(
        "issue_ready",
        ready_claimable,
        "issue must be ready to claim",
        json!({ "ready": ready_details }),
    );

    let reason = if issue_id.is_empty() {
        Some("claim_issue requires issue_id")
    } else if !issue_exists {
        Some("claim_issue requires an existing issue")
    } else if issue_status != "open" {
        Some("claim_issue requires an open issue")
    } else if !ready_claimable {
        Some("claim_issue requires a ready issue")
    } else {
        None
    };

    carrier.set_admission(reason.is_none(), reason, &["structural", "runtime"]);
    Ok(carrier)
}

fn build_close_issue_carrier(
    repo_root: &Path,
    socket_path: &Path,
    payload: &Value,
) -> Result<TransitionEnvelope, String> {
    let issue_id = payload_string(payload, "issue_id");
    let reason = payload_string(payload, "reason");
    let mut carrier = TransitionEnvelope::new(
        repo_root,
        "close_issue",
        json!({ "issue_id": issue_id, "reason": reason }),
    );
    carrier.set_service(transition_service_snapshot(repo_root, socket_path));
    carrier.set_receipt_refs(issue_receipt_refs(repo_root, &issue_id));

    let issue_show_result = if issue_id.is_empty() {
        Value::Null
    } else {
        run_tracker_json_command_in_repo(
            repo_root,
            "tracker_issue_show",
            ["issue", "show", issue_id.as_str()],
        )?
    };
    let lane_json = if issue_id.is_empty() {
        Value::Null
    } else {
        current_lane_for_issue(repo_root, &issue_id)
    };

    carrier.set_tracker(json!({ "issue_show": issue_show_result }));
    let issue_json =
        issue_snapshot_from_result(carrier.get("tracker").unwrap().get("issue_show").unwrap());
    let issue_exists = !issue_json.is_null();
    let issue_status = issue_json
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    if issue_exists {
        carrier.set_issue(issue_json.clone());
    }
    let no_live_lane = lane_json.is_null();
    if !no_live_lane {
        carrier.set_lane(lane_json.clone());
    }

    carrier.add_witness(
        "issue_id",
        !issue_id.is_empty(),
        "issue_id is required",
        json!({ "issue_id": issue_id }),
    );
    carrier.add_witness(
        "close_reason",
        !reason.is_empty(),
        "close reason is required",
        json!({ "reason": reason }),
    );
    carrier.add_witness(
        "issue_exists",
        issue_exists,
        "issue must exist",
        json!({ "issue": issue_json }),
    );
    carrier.add_witness(
        "issue_not_closed",
        issue_status != "closed",
        "issue must not already be closed",
        json!({ "status": issue_status }),
    );
    carrier.add_witness(
        "no_live_lane",
        no_live_lane,
        "close_issue requires the live lane to be archived first",
        json!({ "lane": lane_json }),
    );

    let admission_reason = if issue_id.is_empty() {
        Some("close_issue requires issue_id")
    } else if reason.is_empty() {
        Some("close_issue requires reason")
    } else if !issue_exists {
        Some("close_issue requires an existing issue")
    } else if issue_status == "closed" {
        Some("close_issue requires an open or in-progress issue")
    } else if !no_live_lane {
        Some("close_issue requires the live lane to be archived first")
    } else {
        None
    };

    carrier.set_admission(
        admission_reason.is_none(),
        admission_reason,
        &["structural", "authority"],
    );
    Ok(carrier)
}

fn build_launch_lane_carrier(
    repo_root: &Path,
    socket_path: &Path,
    payload: &Value,
) -> Result<TransitionEnvelope, String> {
    let issue_id = payload_string(payload, "issue_id");
    let base_rev = payload_string(payload, "base_rev");
    let slug_arg = payload_string(payload, "slug");
    let mut carrier = TransitionEnvelope::new(
        repo_root,
        "launch_lane",
        json!({ "issue_id": issue_id, "base_rev": base_rev, "slug": slug_arg }),
    );
    carrier.set_service(transition_service_snapshot(repo_root, socket_path));
    carrier.set_receipt_refs(issue_receipt_refs(repo_root, &issue_id));

    let issue_show_result = if issue_id.is_empty() {
        Value::Null
    } else {
        run_tracker_json_command_in_repo(
            repo_root,
            "tracker_issue_show",
            ["issue", "show", issue_id.as_str()],
        )?
    };
    let lane_json = if issue_id.is_empty() {
        Value::Null
    } else {
        current_lane_for_issue(repo_root, &issue_id)
    };

    let issue_json = issue_snapshot_from_result(&issue_show_result);
    let issue_exists = !issue_json.is_null();
    let issue_status = issue_json
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let issue_title = issue_json
        .get("title")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    if issue_exists {
        carrier.set_issue(issue_json.clone());
    }

    let no_live_lane = lane_json.is_null();
    if !no_live_lane {
        carrier.set_lane(lane_json.clone());
    }

    let mut slug = slug_arg.clone();
    if slug.is_empty() {
        slug = slugify_fragment(&issue_title);
    }
    if slug.is_empty() {
        slug = "lane".to_string();
    }

    let workspace_name = format!("{issue_id}-{slug}");
    let workspace_path = workspace_root_dir(repo_root).join(&workspace_name);
    let workspace_absent = !workspace_path.exists();

    let base_lookup_json = if base_rev.is_empty() {
        Value::Null
    } else {
        resolve_revision_commit(repo_root, &base_rev)?
    };
    let base_commit = base_lookup_json
        .get("commit")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();

    carrier.set_tracker(json!({ "issue_show": issue_show_result }));
    carrier.set_workspace(transition_workspace_snapshot(
        &workspace_name,
        &workspace_path,
        if base_rev.is_empty() {
            None
        } else {
            Some(base_rev.as_str())
        },
        if base_commit.is_empty() {
            None
        } else {
            Some(base_commit.as_str())
        },
        None,
    ));

    carrier.add_witness(
        "issue_id",
        !issue_id.is_empty(),
        "issue_id is required",
        json!({ "issue_id": issue_id }),
    );
    carrier.add_witness(
        "base_rev",
        !base_rev.is_empty(),
        "base_rev is required",
        json!({ "base_rev": base_rev }),
    );
    carrier.add_witness(
        "issue_exists",
        issue_exists,
        "issue must exist",
        json!({ "issue": issue_json }),
    );
    carrier.add_witness(
        "issue_in_progress",
        issue_status == "in_progress",
        "launch_lane requires a claimed in_progress issue",
        json!({ "status": issue_status }),
    );
    carrier.add_witness(
        "no_live_lane",
        no_live_lane,
        "launch_lane requires no existing live lane",
        json!({ "lane": lane_json }),
    );
    carrier.add_witness(
        "base_rev_resolves",
        base_lookup_json.get("ok").and_then(Value::as_bool) == Some(true),
        "base_rev must resolve to a commit",
        json!({ "base_lookup": base_lookup_json }),
    );
    carrier.add_witness(
        "workspace_absent",
        workspace_absent,
        "workspace path must be absent before launch",
        json!({ "workspace_name": workspace_name, "workspace_path": workspace_path.to_string_lossy().into_owned() }),
    );

    let admission_reason = if issue_id.is_empty() {
        Some("launch_lane requires issue_id")
    } else if base_rev.is_empty() {
        Some("launch_lane requires base_rev")
    } else if !issue_exists {
        Some("launch_lane requires an existing issue")
    } else if issue_status != "in_progress" {
        Some("launch_lane requires a claimed in_progress issue")
    } else if !no_live_lane {
        Some("launch_lane requires no existing live lane")
    } else if base_lookup_json.get("ok").and_then(Value::as_bool) != Some(true) {
        Some("base_rev did not resolve to a commit")
    } else if !workspace_absent {
        Some("workspace path already exists")
    } else {
        None
    };

    carrier.set_admission(
        admission_reason.is_none(),
        admission_reason,
        &["structural", "runtime"],
    );
    Ok(carrier)
}

fn build_handoff_lane_carrier(
    repo_root: &Path,
    socket_path: &Path,
    payload: &Value,
) -> Result<TransitionEnvelope, String> {
    let issue_id = payload_string(payload, "issue_id");
    let revision = payload_string(payload, "revision");
    let note = payload_string(payload, "note");
    let mut carrier = TransitionEnvelope::new(
        repo_root,
        "handoff_lane",
        json!({ "issue_id": issue_id, "revision": revision, "note": note }),
    );
    carrier.set_service(transition_service_snapshot(repo_root, socket_path));
    carrier.set_receipt_refs(issue_receipt_refs(repo_root, &issue_id));

    let lane_json = if issue_id.is_empty() {
        Value::Null
    } else {
        current_lane_for_issue(repo_root, &issue_id)
    };
    let lane_exists = !lane_json.is_null();
    let stored_status = lane_json
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    if lane_exists {
        carrier.set_lane(lane_json.clone());
    }

    let revision_lookup_json = if revision.is_empty() {
        Value::Null
    } else {
        resolve_revision_commit(repo_root, &revision)?
    };
    let workspace_path = lane_json
        .get("workspace_path")
        .and_then(Value::as_str)
        .map(PathBuf::from)
        .unwrap_or_default();
    let revision_commit = revision_lookup_json
        .get("commit")
        .and_then(Value::as_str)
        .unwrap_or("");
    carrier.set_workspace(transition_workspace_snapshot(
        "",
        &workspace_path,
        None,
        None,
        if revision_commit.is_empty() {
            None
        } else {
            Some(revision_commit)
        },
    ));

    carrier.add_witness(
        "issue_id",
        !issue_id.is_empty(),
        "issue_id is required",
        json!({ "issue_id": issue_id }),
    );
    carrier.add_witness(
        "revision",
        !revision.is_empty(),
        "revision is required",
        json!({ "revision": revision }),
    );
    carrier.add_witness(
        "lane_exists",
        lane_exists,
        "handoff_lane requires an existing lane record",
        json!({ "lane": lane_json }),
    );
    carrier.add_witness(
        "lane_handoffable",
        stored_status != "finished",
        "handoff_lane requires a non-finished lane",
        json!({ "status": stored_status }),
    );
    carrier.add_witness(
        "revision_resolves",
        revision_lookup_json.get("ok").and_then(Value::as_bool) == Some(true),
        "revision must resolve to a commit",
        json!({ "revision_lookup": revision_lookup_json }),
    );

    let admission_reason = if issue_id.is_empty() {
        Some("handoff_lane requires issue_id")
    } else if revision.is_empty() {
        Some("handoff_lane requires revision")
    } else if !lane_exists {
        Some("handoff_lane requires an existing lane record")
    } else if stored_status == "finished" {
        Some("handoff_lane requires a non-finished lane")
    } else if revision_lookup_json.get("ok").and_then(Value::as_bool) != Some(true) {
        Some("revision did not resolve to a commit")
    } else {
        None
    };

    carrier.set_admission(
        admission_reason.is_none(),
        admission_reason,
        &["structural", "runtime"],
    );
    Ok(carrier)
}

fn build_finish_lane_carrier(
    repo_root: &Path,
    socket_path: &Path,
    payload: &Value,
) -> Result<TransitionEnvelope, String> {
    let issue_id = payload_string(payload, "issue_id");
    let outcome = payload_string(payload, "outcome");
    let note = payload_string(payload, "note");
    let mut carrier = TransitionEnvelope::new(
        repo_root,
        "finish_lane",
        json!({ "issue_id": issue_id, "outcome": outcome, "note": note }),
    );
    carrier.set_service(transition_service_snapshot(repo_root, socket_path));
    carrier.set_receipt_refs(issue_receipt_refs(repo_root, &issue_id));

    let lane_json = if issue_id.is_empty() {
        Value::Null
    } else {
        current_lane_for_issue(repo_root, &issue_id)
    };
    let lane_exists = !lane_json.is_null();
    let stored_status = lane_json
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let finishable = stored_status == "launched" || stored_status == "handoff";
    if lane_exists {
        carrier.set_lane(lane_json.clone());
    }

    carrier.add_witness(
        "issue_id",
        !issue_id.is_empty(),
        "issue_id is required",
        json!({ "issue_id": issue_id }),
    );
    carrier.add_witness(
        "outcome",
        !outcome.is_empty(),
        "outcome is required",
        json!({ "outcome": outcome }),
    );
    carrier.add_witness(
        "lane_exists",
        lane_exists,
        "finish_lane requires an existing lane record",
        json!({ "lane": lane_json }),
    );
    carrier.add_witness(
        "lane_finishable",
        finishable,
        "finish_lane requires a launched or handed-off lane",
        json!({ "status": stored_status }),
    );

    let admission_reason = if issue_id.is_empty() {
        Some("finish_lane requires issue_id")
    } else if outcome.is_empty() {
        Some("finish_lane requires outcome")
    } else if !lane_exists {
        Some("finish_lane requires an existing lane record")
    } else if !finishable {
        Some("finish_lane requires a launched or handed-off lane")
    } else {
        None
    };

    carrier.set_admission(
        admission_reason.is_none(),
        admission_reason,
        &["structural", "runtime"],
    );
    Ok(carrier)
}

fn build_archive_lane_carrier(
    repo_root: &Path,
    socket_path: &Path,
    payload: &Value,
) -> Result<TransitionEnvelope, String> {
    let issue_id = payload_string(payload, "issue_id");
    let note = payload_string(payload, "note");
    let mut carrier = TransitionEnvelope::new(
        repo_root,
        "archive_lane",
        json!({ "issue_id": issue_id, "note": note }),
    );
    carrier.set_service(transition_service_snapshot(repo_root, socket_path));
    carrier.set_receipt_refs(issue_receipt_refs(repo_root, &issue_id));

    let lane_json = if issue_id.is_empty() {
        Value::Null
    } else {
        current_lane_for_issue(repo_root, &issue_id)
    };
    let lane_exists = !lane_json.is_null();
    let stored_status = lane_json
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let workspace_path = lane_json
        .get("workspace_path")
        .and_then(Value::as_str)
        .map(PathBuf::from)
        .unwrap_or_default();
    let workspace_removed = workspace_path.as_os_str().is_empty() || !workspace_path.is_dir();
    if lane_exists {
        carrier.set_lane(lane_json.clone());
    }

    carrier.set_workspace(transition_workspace_snapshot(
        "",
        &workspace_path,
        None,
        None,
        None,
    ));

    carrier.add_witness(
        "issue_id",
        !issue_id.is_empty(),
        "issue_id is required",
        json!({ "issue_id": issue_id }),
    );
    carrier.add_witness(
        "lane_exists",
        lane_exists,
        "archive_lane requires an existing lane record",
        json!({ "lane": lane_json }),
    );
    carrier.add_witness(
        "lane_finished",
        stored_status == "finished",
        "archive_lane requires a finished lane",
        json!({ "status": stored_status }),
    );
    carrier.add_witness(
        "workspace_removed",
        workspace_removed,
        "archive_lane requires the lane workspace to be removed first",
        json!({ "workspace_path": workspace_path.to_string_lossy().into_owned() }),
    );

    let admission_reason = if issue_id.is_empty() {
        Some("archive_lane requires issue_id")
    } else if !lane_exists {
        Some("archive_lane requires an existing lane record")
    } else if stored_status != "finished" {
        Some("archive_lane requires a finished lane")
    } else if !workspace_removed {
        Some("archive_lane requires the lane workspace to be removed first")
    } else {
        None
    };

    carrier.set_admission(
        admission_reason.is_none(),
        admission_reason,
        &["structural", "runtime", "replay"],
    );
    Ok(carrier)
}

fn build_ensure_carrier(
    repo_root: &Path,
    socket_path: &Path,
    payload: &Value,
) -> Result<TransitionEnvelope, String> {
    let mut carrier = TransitionEnvelope::new(repo_root, "ensure", payload.clone());
    let service_snapshot = transition_service_snapshot(repo_root, socket_path);
    let preflight = health_snapshot(repo_root, socket_path, false)?;

    carrier.set_service(service_snapshot.clone());
    carrier.set_tracker(json!({ "preflight": preflight.clone() }));
    carrier.set_receipt_refs(receipt_refs_by_kind(repo_root, "tracker.ensure"));

    carrier.add_witness(
        "backend_observed",
        preflight.get("backend").is_some(),
        "backend observation should be available before ensure",
        json!({ "backend": preflight.get("backend").cloned().unwrap_or(Value::Null) }),
    );
    carrier.add_witness(
        "tracker_checks_observed",
        preflight.get("checks").is_some(),
        "tracker checks should be available before ensure",
        json!({ "checks": preflight.get("checks").cloned().unwrap_or(Value::Null) }),
    );
    carrier.add_witness(
        "service_snapshot_observed",
        true,
        "",
        json!({
            "record": service_snapshot.get("record").cloned().unwrap_or(Value::Null),
            "backend": service_snapshot.get("backend").cloned().unwrap_or(Value::Null),
        }),
    );
    carrier.set_admission(true, None, &["runtime"]);
    Ok(carrier)
}

fn build_transition_carrier(
    repo_root: &Path,
    socket_path: &Path,
    transition_kind: TransitionKind,
    payload: &Value,
) -> Result<TransitionEnvelope, String> {
    match transition_kind {
        TransitionKind::Ensure => build_ensure_carrier(repo_root, socket_path, payload),
        TransitionKind::ClaimIssue => build_claim_issue_carrier(repo_root, socket_path, payload),
        TransitionKind::CloseIssue => build_close_issue_carrier(repo_root, socket_path, payload),
        TransitionKind::LaunchLane => build_launch_lane_carrier(repo_root, socket_path, payload),
        TransitionKind::HandoffLane => build_handoff_lane_carrier(repo_root, socket_path, payload),
        TransitionKind::FinishLane => build_finish_lane_carrier(repo_root, socket_path, payload),
        TransitionKind::ArchiveLane => build_archive_lane_carrier(repo_root, socket_path, payload),
    }
}

fn transition_prepare(
    repo_root: &Path,
    socket_path: &Path,
    kind: &str,
    payload: &Value,
) -> Result<Option<PreparedTransition>, String> {
    let Some(transition_kind) = TransitionKind::parse(kind) else {
        return Ok(None);
    };
    let carrier = build_transition_carrier(repo_root, socket_path, transition_kind, payload)?;
    Ok(Some(PreparedTransition {
        kind: transition_kind,
        envelope: carrier,
    }))
}

fn transition_prepare_result(
    repo_root: &Path,
    socket_path: &Path,
    kind: &str,
    payload: &Value,
) -> Result<Option<Value>, String> {
    let Some(prepared) = transition_prepare(repo_root, socket_path, kind, payload)? else {
        return Ok(None);
    };
    let proposal_kind = prepared.envelope.proposal().kind;

    if prepared.envelope.admitted() {
        Ok(Some(json!({
            "ok": true,
            "delegate": {
                "kind": proposal_kind,
                "carrier": prepared.envelope.clone().into_json(),
            },
        })))
    } else {
        let message = prepared
            .envelope
            .admission_reason()
            .unwrap_or("transition rejected");
        Ok(Some(json!({
            "ok": false,
            "error": {
                "message": message,
                "carrier": prepared.envelope.into_json(),
            },
        })))
    }
}

fn action_protocol_response(request_id: &str, kind: &str, prepared: Value) -> Value {
    if prepared.get("ok").and_then(Value::as_bool) == Some(true) {
        json!({
            "request_id": request_id,
            "ok": true,
            "kind": kind,
            "payload": prepared.get("payload").cloned().unwrap_or(Value::Null),
        })
    } else {
        let message = prepared
            .get("error")
            .and_then(|error| error.get("message"))
            .and_then(Value::as_str)
            .unwrap_or("request failed");
        json!({
            "request_id": request_id,
            "ok": false,
            "kind": kind,
            "error": {
                "message": message,
                "details": prepared,
            },
        })
    }
}

fn transition_rejected_result(envelope: TransitionEnvelope) -> Value {
    let message = envelope.admission_reason().unwrap_or("transition rejected");
    json!({
        "ok": false,
        "error": {
            "message": message,
            "carrier": envelope.into_json(),
        },
    })
}

fn transition_failure_result(envelope: TransitionEnvelope, message: &str, details: Value) -> Value {
    json!({
        "ok": false,
        "error": {
            "message": message,
            "carrier": envelope.into_json(),
            "details": details,
        },
    })
}

fn transition_success_result(envelope: TransitionEnvelope, projection: Value) -> Value {
    json!({
        "ok": true,
        "carrier": envelope.into_json(),
        "payload": projection,
    })
}

fn refresh_transition_board(repo_root: &Path, socket_path: &Path) -> Result<Value, String> {
    board_status_projection(repo_root, socket_path)
}

fn restore_lane_state_snapshot(repo_root: &Path, lane: &Value) -> Result<(), String> {
    if lane.is_null() {
        return Ok(());
    }
    lane_state_upsert(repo_root, lane.clone()).map(|_| ())
}

fn rollback_launch_artifacts(
    repo_root: &Path,
    issue_id: &str,
    workspace_name: &str,
    workspace_path: &Path,
) -> Value {
    let mut remove_lane_exit = 0;
    if !issue_id.is_empty() && lane_state_remove(repo_root, issue_id).is_err() {
        remove_lane_exit = 1;
    }

    let repo_root_str = repo_root.to_string_lossy().into_owned();
    let (forget_exit, forget_output) = if workspace_name.is_empty() {
        (0, String::new())
    } else {
        match run_in_repo_capture(
            repo_root,
            "jj",
            [
                "--repository",
                repo_root_str.as_str(),
                "workspace",
                "forget",
                workspace_name,
            ],
        ) {
            Ok((exit_code, output)) => (exit_code, output),
            Err(err) => (1, err),
        }
    };

    let (remove_exit, remove_output) =
        if workspace_path.as_os_str().is_empty() || !workspace_path.exists() {
            (0, String::new())
        } else {
            match fs::remove_dir_all(workspace_path) {
                Ok(()) => (0, String::new()),
                Err(err) => (1, err.to_string()),
            }
        };

    json!({
        "issue_id": issue_id,
        "workspace_name": workspace_name,
        "workspace_path": if workspace_path.as_os_str().is_empty() {
            Value::Null
        } else {
            Value::String(workspace_path.to_string_lossy().into_owned())
        },
        "remove_lane_exit": remove_lane_exit,
        "forget_workspace": {
            "exit_code": forget_exit,
            "output": if forget_output.is_empty() { Value::Null } else { Value::String(forget_output) },
        },
        "remove_workspace": {
            "exit_code": remove_exit,
            "output": if remove_output.is_empty() { Value::Null } else { Value::String(remove_output) },
        },
    })
}

fn tracker_issue_result_valid(result: &Value, issue_id: &str, require_closed: bool) -> bool {
    let Some(issue) = result
        .get("output")
        .and_then(Value::as_array)
        .and_then(|items| items.first())
    else {
        return false;
    };

    let status_ok = if require_closed {
        issue.get("status").and_then(Value::as_str) == Some("closed")
    } else {
        true
    };

    result.get("ok").and_then(Value::as_bool) == Some(true)
        && issue.is_object()
        && issue.get("id").and_then(Value::as_str) == Some(issue_id)
        && status_ok
}

fn realize_ensure_transition(
    repo_root: &Path,
    socket_path: &Path,
    mut envelope: TransitionEnvelope,
) -> Result<Value, String> {
    let ensured = perform_ensure(repo_root, socket_path)?;

    envelope.set_service(json!({
        "socket_path": socket_path.to_string_lossy().into_owned(),
        "record": ensured.record.clone(),
        "leases": ensured.leases.clone(),
        "backend": ensured.health.get("backend").cloned().unwrap_or(Value::Null),
    }));
    envelope.set_application(json!({
        "kind": "tracker.ensure",
        "mode": ensured.mode,
        "pid": ensured.pid,
        "health": ensured.health.clone(),
        "service_record": ensured.record.clone(),
    }));

    let receipt = append_receipt(
        repo_root,
        "tracker.ensure",
        json!({
            "service": ensured.record.clone(),
            "health": ensured.health.clone(),
        }),
    )?;
    envelope.set_emitted_receipt(receipt);

    Ok(transition_success_result(envelope, ensured.record))
}

fn realize_claim_issue_transition(
    repo_root: &Path,
    socket_path: &Path,
    mut envelope: TransitionEnvelope,
) -> Result<Value, String> {
    let issue_id = envelope.payload_string("issue_id");
    let claim_result = run_tracker_json_command_in_repo(
        repo_root,
        "tracker_issue_claim",
        ["issue", "claim", issue_id.as_str()],
    )?;
    if !tracker_issue_result_valid(&claim_result, &issue_id, false) {
        envelope.set_application(json!({ "kind": "tracker_issue_claim", "tracker": claim_result }));
        return Ok(transition_failure_result(
            envelope,
            "tracker issue claim failed",
            json!({ "tracker": claim_result }),
        ));
    }

    let issue = claim_result
        .get("output")
        .and_then(Value::as_array)
        .and_then(|items| items.first())
        .cloned()
        .unwrap_or(Value::Null);
    envelope.set_issue(issue.clone());
    envelope.set_application(json!({ "kind": "tracker_issue_claim", "tracker": claim_result }));

    let board = refresh_transition_board(repo_root, socket_path)?;
    let board_summary = board.get("summary").cloned().unwrap_or(Value::Null);
    let receipt = append_receipt(
        repo_root,
        "issue.claim",
        json!({ "issue_id": issue_id, "issue": issue, "board_summary": board_summary }),
    )?;
    envelope.set_emitted_receipt(receipt);

    Ok(transition_success_result(
        envelope,
        json!({
            "repo_root": repo_root.to_string_lossy().into_owned(),
            "issue_id": issue_id,
            "issue": issue,
            "board_summary": board_summary,
        }),
    ))
}

fn realize_close_issue_transition(
    repo_root: &Path,
    socket_path: &Path,
    mut envelope: TransitionEnvelope,
) -> Result<Value, String> {
    let issue_id = envelope.payload_string("issue_id");
    let reason = envelope.payload_string("reason");
    let close_result = run_tracker_json_command_in_repo(
        repo_root,
        "tracker_issue_close",
        [
            "issue",
            "close",
            issue_id.as_str(),
            "--reason",
            reason.as_str(),
        ],
    )?;
    if !tracker_issue_result_valid(&close_result, &issue_id, true) {
        envelope.set_application(json!({ "kind": "tracker_issue_close", "tracker": close_result }));
        return Ok(transition_failure_result(
            envelope,
            "tracker issue close failed",
            json!({ "tracker": close_result }),
        ));
    }

    let issue = close_result
        .get("output")
        .and_then(Value::as_array)
        .and_then(|items| items.first())
        .cloned()
        .unwrap_or(Value::Null);
    envelope.set_issue(issue.clone());
    envelope.set_application(json!({ "kind": "tracker_issue_close", "tracker": close_result }));

    let board = refresh_transition_board(repo_root, socket_path)?;
    let board_summary = board.get("summary").cloned().unwrap_or(Value::Null);
    let receipt = append_receipt(
        repo_root,
        "issue.close",
        json!({ "issue_id": issue_id, "reason": reason, "issue": issue, "board_summary": board_summary }),
    )?;
    envelope.set_emitted_receipt(receipt);

    Ok(transition_success_result(
        envelope,
        json!({
            "repo_root": repo_root.to_string_lossy().into_owned(),
            "issue_id": issue_id,
            "reason": reason,
            "issue": issue,
            "board_summary": board_summary,
        }),
    ))
}

fn realize_launch_lane_transition(
    repo_root: &Path,
    socket_path: &Path,
    mut envelope: TransitionEnvelope,
) -> Result<Value, String> {
    let issue_id = envelope.payload_string("issue_id");
    let base_rev = envelope.payload_string("base_rev");
    let issue = envelope.get("issue").cloned().unwrap_or(Value::Null);
    let issue_title = issue
        .get("title")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let workspace = envelope.get("workspace").cloned().unwrap_or(Value::Null);
    let workspace_name = workspace
        .get("name")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let workspace_path = workspace
        .get("path")
        .and_then(Value::as_str)
        .map(PathBuf::from)
        .unwrap_or_default();
    let workspace_path_str = workspace_path.to_string_lossy().into_owned();
    let base_commit = workspace
        .get("base_commit")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let repo_root_str = repo_root.to_string_lossy().into_owned();

    fs::create_dir_all(workspace_root_dir(repo_root))
        .map_err(|err| format!("failed to create workspace root: {err}"))?;

    let (add_exit, add_output) = run_in_repo_capture(
        repo_root,
        "jj",
        [
            "--repository",
            repo_root_str.as_str(),
            "workspace",
            "add",
            workspace_path_str.as_str(),
            "--name",
            workspace_name.as_str(),
            "-r",
            base_rev.as_str(),
        ],
    )?;
    if add_exit != 0 {
        envelope.set_application(json!({
            "kind": "jj_workspace_add",
            "workspace_name": workspace_name,
            "workspace_path": workspace_path_str,
            "base_rev": base_rev,
            "output": add_output,
        }));
        return Ok(transition_failure_result(
            envelope,
            "jj workspace add failed",
            json!({
                "workspace_name": workspace_name,
                "workspace_path": workspace_path_str,
                "base_rev": base_rev,
                "output": add_output,
            }),
        ));
    }

    if env::var("TUSKD_TEST_FAIL_PHASE").ok().as_deref() == Some("launch_lane:after_workspace_add")
    {
        let rollback =
            rollback_launch_artifacts(repo_root, &issue_id, &workspace_name, &workspace_path);
        envelope.set_application(json!({
            "kind": "launch_lane",
            "workspace_name": workspace_name,
            "workspace_path": workspace_path_str,
            "base_rev": base_rev,
            "add_output": add_output,
            "rollback": rollback,
            "injected_failure_phase": "after_workspace_add",
        }));
        return Ok(transition_failure_result(
            envelope,
            "injected transition failure after workspace add",
            json!({
                "workspace_name": workspace_name,
                "workspace_path": workspace_path_str,
                "rollback": rollback,
            }),
        ));
    }

    let describe_message = format!("{issue_id}: wip");
    let (describe_exit, describe_output) = run_in_repo_capture(
        repo_root,
        "jj",
        [
            "--repository",
            workspace_path_str.as_str(),
            "describe",
            "-m",
            describe_message.as_str(),
        ],
    )?;
    if describe_exit != 0 {
        let rollback =
            rollback_launch_artifacts(repo_root, &issue_id, &workspace_name, &workspace_path);
        envelope.set_application(json!({
            "kind": "launch_lane",
            "workspace_name": workspace_name,
            "workspace_path": workspace_path_str,
            "base_rev": base_rev,
            "add_output": add_output,
            "describe_output": describe_output,
            "rollback": rollback,
        }));
        return Ok(transition_failure_result(
            envelope,
            "jj describe failed after workspace creation",
            json!({
                "workspace_name": workspace_name,
                "workspace_path": workspace_path_str,
                "output": describe_output,
                "rollback": rollback,
            }),
        ));
    }

    let lane = json!({
        "issue_id": issue_id,
        "issue_title": issue_title,
        "status": "launched",
        "workspace_name": workspace_name,
        "workspace_path": workspace_path_str,
        "base_rev": base_rev,
        "base_commit": base_commit,
        "launched_at": now_iso8601(),
    });
    if lane_state_upsert(repo_root, lane.clone()).is_err() {
        let rollback =
            rollback_launch_artifacts(repo_root, &issue_id, &workspace_name, &workspace_path);
        envelope
            .set_application(json!({ "kind": "launch_lane", "lane": lane, "rollback": rollback }));
        return Ok(transition_failure_result(
            envelope,
            "failed to persist lane state",
            json!({ "lane": lane, "rollback": rollback }),
        ));
    }

    let board = refresh_transition_board(repo_root, socket_path)?;
    let board_summary = board.get("summary").cloned().unwrap_or(Value::Null);
    let lanes = board.get("lanes").cloned().unwrap_or_else(|| json!([]));
    let receipt = match append_receipt(
        repo_root,
        "lane.launch",
        json!({
            "issue_id": issue_id,
            "issue_title": issue_title,
            "workspace_name": workspace_name,
            "workspace_path": workspace_path_str,
            "base_rev": base_rev,
            "base_commit": base_commit,
            "issue": issue,
            "board_summary": board_summary,
        }),
    ) {
        Ok(receipt) => receipt,
        Err(err) => {
            let rollback =
                rollback_launch_artifacts(repo_root, &issue_id, &workspace_name, &workspace_path);
            envelope.set_application(
                json!({ "kind": "launch_lane", "lane": lane, "rollback": rollback }),
            );
            return Ok(transition_failure_result(
                envelope,
                "failed to append lane.launch receipt",
                json!({ "rollback": rollback, "error": err }),
            ));
        }
    };

    envelope.set_lane(lane.clone());
    envelope.set_application(json!({
        "kind": "launch_lane",
        "workspace_name": workspace_name,
        "workspace_path": workspace_path_str,
        "base_rev": base_rev,
        "base_commit": base_commit,
        "add_output": add_output,
        "describe_output": describe_output,
    }));
    envelope.set_emitted_receipt(receipt);

    Ok(transition_success_result(
        envelope,
        json!({
            "repo_root": repo_root.to_string_lossy().into_owned(),
            "issue_id": issue_id,
            "issue_title": issue_title,
            "issue": issue,
            "workspace_name": workspace_name,
            "workspace_path": workspace_path_str,
            "base_rev": base_rev,
            "base_commit": base_commit,
            "lanes": lanes,
            "board_summary": board_summary,
        }),
    ))
}

fn set_optional_string_field(value: &mut Value, key: &str, field_value: &str) {
    if let Some(object) = value.as_object_mut() {
        if field_value.is_empty() {
            object.remove(key);
        } else {
            object.insert(key.to_string(), Value::String(field_value.to_string()));
        }
    }
}

fn realize_handoff_lane_transition(
    repo_root: &Path,
    socket_path: &Path,
    mut envelope: TransitionEnvelope,
) -> Result<Value, String> {
    let issue_id = envelope.payload_string("issue_id");
    let note = envelope.payload_string("note");
    let previous_lane = envelope.get("lane").cloned().unwrap_or(Value::Null);
    let resolved_revision = envelope
        .get("workspace")
        .and_then(|workspace| workspace.get("revision"))
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();

    let mut updated_lane = previous_lane.clone();
    if let Some(object) = updated_lane.as_object_mut() {
        object.insert("status".to_string(), Value::String("handoff".to_string()));
        object.insert(
            "handoff_revision".to_string(),
            Value::String(resolved_revision.clone()),
        );
        object.insert("handed_off_at".to_string(), Value::String(now_iso8601()));
    }
    set_optional_string_field(&mut updated_lane, "handoff_note", &note);

    if lane_state_upsert(repo_root, updated_lane.clone()).is_err() {
        envelope.set_application(json!({ "kind": "handoff_lane", "lane": updated_lane }));
        return Ok(transition_failure_result(
            envelope,
            "failed to persist handed-off lane state",
            json!({ "lane": updated_lane }),
        ));
    }

    let board = refresh_transition_board(repo_root, socket_path)?;
    let board_summary = board.get("summary").cloned().unwrap_or(Value::Null);
    let lanes = board.get("lanes").cloned().unwrap_or_else(|| json!([]));
    let receipt = match append_receipt(
        repo_root,
        "lane.handoff",
        json!({
            "issue_id": issue_id,
            "revision": resolved_revision,
            "note": note,
            "lane": updated_lane,
            "board_summary": board_summary,
        }),
    ) {
        Ok(receipt) => receipt,
        Err(err) => {
            let _ = restore_lane_state_snapshot(repo_root, &previous_lane);
            envelope.set_application(
                json!({ "kind": "handoff_lane", "lane": updated_lane, "restored_lane": previous_lane }),
            );
            return Ok(transition_failure_result(
                envelope,
                "failed to append lane.handoff receipt",
                json!({ "restored_lane": previous_lane, "error": err }),
            ));
        }
    };

    envelope.set_lane(updated_lane.clone());
    envelope.set_application(
        json!({ "kind": "handoff_lane", "revision": resolved_revision, "note": note }),
    );
    envelope.set_emitted_receipt(receipt);

    Ok(transition_success_result(
        envelope,
        json!({
            "repo_root": repo_root.to_string_lossy().into_owned(),
            "issue_id": issue_id,
            "revision": resolved_revision,
            "note": note,
            "lane": updated_lane,
            "lanes": lanes,
            "board_summary": board_summary,
        }),
    ))
}

fn realize_finish_lane_transition(
    repo_root: &Path,
    socket_path: &Path,
    mut envelope: TransitionEnvelope,
) -> Result<Value, String> {
    let issue_id = envelope.payload_string("issue_id");
    let outcome = envelope.payload_string("outcome");
    let note = envelope.payload_string("note");
    let previous_lane = envelope.get("lane").cloned().unwrap_or(Value::Null);

    let mut updated_lane = previous_lane.clone();
    if let Some(object) = updated_lane.as_object_mut() {
        object.insert("status".to_string(), Value::String("finished".to_string()));
        object.insert("outcome".to_string(), Value::String(outcome.clone()));
        object.insert("finished_at".to_string(), Value::String(now_iso8601()));
    }
    set_optional_string_field(&mut updated_lane, "finish_note", &note);

    if lane_state_upsert(repo_root, updated_lane.clone()).is_err() {
        envelope.set_application(json!({ "kind": "finish_lane", "lane": updated_lane }));
        return Ok(transition_failure_result(
            envelope,
            "failed to persist finished lane state",
            json!({ "lane": updated_lane }),
        ));
    }

    let board = refresh_transition_board(repo_root, socket_path)?;
    let board_summary = board.get("summary").cloned().unwrap_or(Value::Null);
    let lanes = board.get("lanes").cloned().unwrap_or_else(|| json!([]));
    let receipt = match append_receipt(
        repo_root,
        "lane.finish",
        json!({
            "issue_id": issue_id,
            "outcome": outcome,
            "note": note,
            "lane": updated_lane,
            "board_summary": board_summary,
        }),
    ) {
        Ok(receipt) => receipt,
        Err(err) => {
            let _ = restore_lane_state_snapshot(repo_root, &previous_lane);
            envelope.set_application(
                json!({ "kind": "finish_lane", "lane": updated_lane, "restored_lane": previous_lane }),
            );
            return Ok(transition_failure_result(
                envelope,
                "failed to append lane.finish receipt",
                json!({ "restored_lane": previous_lane, "error": err }),
            ));
        }
    };

    envelope.set_lane(updated_lane.clone());
    envelope.set_application(json!({ "kind": "finish_lane", "outcome": outcome, "note": note }));
    envelope.set_emitted_receipt(receipt);

    Ok(transition_success_result(
        envelope,
        json!({
            "repo_root": repo_root.to_string_lossy().into_owned(),
            "issue_id": issue_id,
            "outcome": outcome,
            "note": note,
            "lane": updated_lane,
            "lanes": lanes,
            "board_summary": board_summary,
        }),
    ))
}

fn realize_archive_lane_transition(
    repo_root: &Path,
    socket_path: &Path,
    mut envelope: TransitionEnvelope,
) -> Result<Value, String> {
    let issue_id = envelope.payload_string("issue_id");
    let note = envelope.payload_string("note");
    let archived_lane = envelope.get("lane").cloned().unwrap_or(Value::Null);

    if lane_state_remove(repo_root, &issue_id).is_err() {
        envelope.set_application(json!({ "kind": "archive_lane", "issue_id": issue_id }));
        return Ok(transition_failure_result(
            envelope,
            "failed to remove live lane state",
            json!({ "issue_id": issue_id }),
        ));
    }

    let board = refresh_transition_board(repo_root, socket_path)?;
    let board_summary = board.get("summary").cloned().unwrap_or(Value::Null);
    let lanes = board.get("lanes").cloned().unwrap_or_else(|| json!([]));
    let receipt = match append_receipt(
        repo_root,
        "lane.archive",
        json!({
            "issue_id": issue_id,
            "note": note,
            "lane": archived_lane,
            "board_summary": board_summary,
        }),
    ) {
        Ok(receipt) => receipt,
        Err(err) => {
            let _ = restore_lane_state_snapshot(repo_root, &archived_lane);
            envelope.set_application(
                json!({ "kind": "archive_lane", "issue_id": issue_id, "restored_lane": archived_lane }),
            );
            return Ok(transition_failure_result(
                envelope,
                "failed to append lane.archive receipt",
                json!({ "restored_lane": archived_lane, "error": err }),
            ));
        }
    };

    envelope.set_application(json!({ "kind": "archive_lane", "issue_id": issue_id, "note": note }));
    envelope.set_emitted_receipt(receipt);

    Ok(transition_success_result(
        envelope,
        json!({
            "repo_root": repo_root.to_string_lossy().into_owned(),
            "issue_id": issue_id,
            "note": note,
            "archived_lane": archived_lane,
            "lanes": lanes,
            "board_summary": board_summary,
        }),
    ))
}

fn realize_transition(
    repo_root: &Path,
    socket_path: &Path,
    admitted: AdmittedTransition,
) -> Result<Value, String> {
    match admitted.kind {
        TransitionKind::Ensure => {
            realize_ensure_transition(repo_root, socket_path, admitted.envelope)
        }
        TransitionKind::ClaimIssue => {
            realize_claim_issue_transition(repo_root, socket_path, admitted.envelope)
        }
        TransitionKind::CloseIssue => {
            realize_close_issue_transition(repo_root, socket_path, admitted.envelope)
        }
        TransitionKind::LaunchLane => {
            realize_launch_lane_transition(repo_root, socket_path, admitted.envelope)
        }
        TransitionKind::HandoffLane => {
            realize_handoff_lane_transition(repo_root, socket_path, admitted.envelope)
        }
        TransitionKind::FinishLane => {
            realize_finish_lane_transition(repo_root, socket_path, admitted.envelope)
        }
        TransitionKind::ArchiveLane => {
            realize_archive_lane_transition(repo_root, socket_path, admitted.envelope)
        }
    }
}

fn transition_run_result(
    repo_root: &Path,
    socket_path: &Path,
    kind: &str,
    payload: &Value,
) -> Result<Option<Value>, String> {
    let Some(transition_kind) = TransitionKind::parse(kind) else {
        return Ok(None);
    };

    let run_under_current_state = || -> Result<Option<Value>, String> {
        let Some(prepared) = transition_prepare(repo_root, socket_path, kind, payload)? else {
            return Ok(None);
        };
        let admitted = match prepared.admit() {
            Ok(admitted) => admitted,
            Err(rejected) => return Ok(Some(transition_rejected_result(rejected))),
        };

        Ok(Some(realize_transition(repo_root, socket_path, admitted)?))
    };

    if transition_kind.requires_service_lock() {
        let _service_lock = DirLock::acquire(host_lock_dir(repo_root))?;
        run_under_current_state()
    } else {
        run_under_current_state()
    }
}

struct ProjectionArgs {
    repo_root: PathBuf,
    socket_path: PathBuf,
}

fn parse_projection_args(args: &[String], command_name: &str) -> Result<ProjectionArgs, String> {
    let mut repo_root: Option<PathBuf> = None;
    let mut socket_path: Option<PathBuf> = None;
    let mut index = 0;

    while index < args.len() {
        match args[index].as_str() {
            "--repo" => {
                let value = args.get(index + 1).ok_or("--repo requires a path")?;
                repo_root = Some(repo_root_arg(value)?);
                index += 2;
            }
            "--socket" => {
                let value = args.get(index + 1).ok_or("--socket requires a path")?;
                socket_path = Some(PathBuf::from(value));
                index += 2;
            }
            "--help" | "-h" => return Err("USAGE".to_string()),
            flag => return Err(format!("unknown {command_name} argument: {flag}")),
        }
    }

    let repo_root = repo_root.ok_or(format!("{command_name} requires --repo"))?;
    let socket_path = socket_path.unwrap_or_else(|| default_socket_path(&repo_root));

    Ok(ProjectionArgs {
        repo_root,
        socket_path,
    })
}

fn print_ensure_help() {
    println!("Usage:\n  tuskd-core ensure --repo PATH [--socket PATH]");
}

fn run_ensure(args: &[String]) -> ExitCode {
    let parsed = match parse_projection_args(args, "ensure") {
        Ok(parsed) => parsed,
        Err(message) if message == "USAGE" => {
            print_ensure_help();
            return ExitCode::SUCCESS;
        }
        Err(message) => return fail(&message),
    };

    match transition_run_result(&parsed.repo_root, &parsed.socket_path, "ensure", &json!({})) {
        Ok(Some(result)) => {
            if result.get("ok").and_then(Value::as_bool) != Some(true) {
                let message = result
                    .get("error")
                    .and_then(|value| value.get("message"))
                    .and_then(Value::as_str)
                    .unwrap_or("ensure transition failed");
                return fail(message);
            }

            let record = result.get("payload").cloned().unwrap_or(Value::Null);
            match serde_json::to_string_pretty(&record) {
                Ok(text) => println!("{text}"),
                Err(err) => return fail(&format!("failed to encode ensure projection: {err}")),
            }

            if record
                .get("health")
                .and_then(|value| value.get("status"))
                .and_then(Value::as_str)
                == Some("healthy")
            {
                ExitCode::SUCCESS
            } else {
                ExitCode::from(1)
            }
        }
        Ok(None) => fail("ensure transition was not available"),
        Err(message) => fail(&message),
    }
}

fn print_status_help() {
    println!("Usage:\n  tuskd-core status --repo PATH [--socket PATH]");
}

fn run_status(args: &[String]) -> ExitCode {
    let parsed = match parse_projection_args(args, "status") {
        Ok(parsed) => parsed,
        Err(message) if message == "USAGE" => {
            print_status_help();
            return ExitCode::SUCCESS;
        }
        Err(message) => return fail(&message),
    };

    match status_projection(&parsed.repo_root, &parsed.socket_path) {
        Ok(record) => {
            match serde_json::to_string_pretty(&record) {
                Ok(text) => println!("{text}"),
                Err(err) => return fail(&format!("failed to encode status projection: {err}")),
            }

            if record
                .get("health")
                .and_then(|value| value.get("status"))
                .and_then(Value::as_str)
                == Some("healthy")
            {
                ExitCode::SUCCESS
            } else {
                ExitCode::from(1)
            }
        }
        Err(message) => fail(&message),
    }
}

fn print_board_status_help() {
    println!("Usage:\n  tuskd-core board-status --repo PATH [--socket PATH]");
}

fn run_board_status(args: &[String]) -> ExitCode {
    let parsed = match parse_projection_args(args, "board-status") {
        Ok(parsed) => parsed,
        Err(message) if message == "USAGE" => {
            print_board_status_help();
            return ExitCode::SUCCESS;
        }
        Err(message) => return fail(&message),
    };

    match board_status_projection(&parsed.repo_root, &parsed.socket_path) {
        Ok(record) => match serde_json::to_string(&record) {
            Ok(text) => {
                println!("{text}");
                ExitCode::SUCCESS
            }
            Err(err) => fail(&format!("failed to encode board projection: {err}")),
        },
        Err(message) => fail(&message),
    }
}

fn print_receipts_status_help() {
    println!("Usage:\n  tuskd-core receipts-status --repo PATH");
}

fn run_receipts_status(args: &[String]) -> ExitCode {
    let parsed = match parse_projection_args(args, "receipts-status") {
        Ok(parsed) => parsed,
        Err(message) if message == "USAGE" => {
            print_receipts_status_help();
            return ExitCode::SUCCESS;
        }
        Err(message) => return fail(&message),
    };

    match receipts_status_projection(&parsed.repo_root) {
        Ok(record) => match serde_json::to_string(&record) {
            Ok(text) => {
                println!("{text}");
                ExitCode::SUCCESS
            }
            Err(err) => fail(&format!("failed to encode receipts projection: {err}")),
        },
        Err(message) => fail(&message),
    }
}

enum LaneStateArgs {
    Upsert {
        repo_root: PathBuf,
        lane: Value,
    },
    Remove {
        repo_root: PathBuf,
        issue_id: String,
    },
}

fn parse_lane_state_args(args: &[String]) -> Result<LaneStateArgs, String> {
    let subcommand = args.first().ok_or("USAGE".to_string())?;

    match subcommand.as_str() {
        "upsert" => {
            let mut repo_root: Option<PathBuf> = None;
            let mut lane_json: Option<Value> = None;
            let mut index = 1;

            while index < args.len() {
                match args[index].as_str() {
                    "--repo" => {
                        let value = args.get(index + 1).ok_or("--repo requires a path")?;
                        repo_root = Some(repo_root_arg(value)?);
                        index += 2;
                    }
                    "--lane-json" => {
                        let value = args.get(index + 1).ok_or("--lane-json requires JSON")?;
                        let parsed = serde_json::from_str::<Value>(value)
                            .map_err(|err| format!("invalid --lane-json: {err}"))?;
                        lane_json = Some(parsed);
                        index += 2;
                    }
                    "--help" | "-h" => return Err("USAGE".to_string()),
                    flag => return Err(format!("unknown lane-state upsert argument: {flag}")),
                }
            }

            Ok(LaneStateArgs::Upsert {
                repo_root: repo_root.ok_or("lane-state upsert requires --repo")?,
                lane: lane_json.ok_or("lane-state upsert requires --lane-json")?,
            })
        }
        "remove" => {
            let mut repo_root: Option<PathBuf> = None;
            let mut issue_id: Option<String> = None;
            let mut index = 1;

            while index < args.len() {
                match args[index].as_str() {
                    "--repo" => {
                        let value = args.get(index + 1).ok_or("--repo requires a path")?;
                        repo_root = Some(repo_root_arg(value)?);
                        index += 2;
                    }
                    "--issue-id" => {
                        let value = args.get(index + 1).ok_or("--issue-id requires a value")?;
                        issue_id = Some(value.clone());
                        index += 2;
                    }
                    "--help" | "-h" => return Err("USAGE".to_string()),
                    flag => return Err(format!("unknown lane-state remove argument: {flag}")),
                }
            }

            Ok(LaneStateArgs::Remove {
                repo_root: repo_root.ok_or("lane-state remove requires --repo")?,
                issue_id: issue_id.ok_or("lane-state remove requires --issue-id")?,
            })
        }
        _ => Err("USAGE".to_string()),
    }
}

fn print_lane_state_help() {
    println!(
        "Usage:\n  tuskd-core lane-state upsert --repo PATH --lane-json JSON\n  tuskd-core lane-state remove --repo PATH --issue-id ISSUE_ID"
    );
}

fn run_lane_state(args: &[String]) -> ExitCode {
    let parsed = match parse_lane_state_args(args) {
        Ok(parsed) => parsed,
        Err(message) if message == "USAGE" => {
            print_lane_state_help();
            return ExitCode::SUCCESS;
        }
        Err(message) => return fail(&message),
    };

    let result = match parsed {
        LaneStateArgs::Upsert { repo_root, lane } => lane_state_upsert(&repo_root, lane),
        LaneStateArgs::Remove {
            repo_root,
            issue_id,
        } => lane_state_remove(&repo_root, &issue_id),
    };

    match result {
        Ok(payload) => match serde_json::to_string(&payload) {
            Ok(text) => {
                println!("{text}");
                ExitCode::SUCCESS
            }
            Err(err) => fail(&format!("failed to encode lane-state result: {err}")),
        },
        Err(message) => fail(&message),
    }
}

enum ReceiptArgs {
    Append {
        repo_root: PathBuf,
        kind: String,
        payload: Value,
    },
}

fn parse_receipt_args(args: &[String]) -> Result<ReceiptArgs, String> {
    let subcommand = args.first().ok_or("USAGE".to_string())?;

    match subcommand.as_str() {
        "append" => {
            let mut repo_root: Option<PathBuf> = None;
            let mut kind: Option<String> = None;
            let mut payload: Option<Value> = None;
            let mut index = 1;

            while index < args.len() {
                match args[index].as_str() {
                    "--repo" => {
                        let value = args.get(index + 1).ok_or("--repo requires a path")?;
                        repo_root = Some(repo_root_arg(value)?);
                        index += 2;
                    }
                    "--kind" => {
                        let value = args.get(index + 1).ok_or("--kind requires a value")?;
                        kind = Some(value.clone());
                        index += 2;
                    }
                    "--payload" => {
                        let value = args.get(index + 1).ok_or("--payload requires JSON")?;
                        let parsed = serde_json::from_str::<Value>(value)
                            .map_err(|err| format!("invalid --payload: {err}"))?;
                        payload = Some(parsed);
                        index += 2;
                    }
                    "--help" | "-h" => return Err("USAGE".to_string()),
                    flag => return Err(format!("unknown receipt append argument: {flag}")),
                }
            }

            Ok(ReceiptArgs::Append {
                repo_root: repo_root.ok_or("receipt append requires --repo")?,
                kind: kind.ok_or("receipt append requires --kind")?,
                payload: payload.ok_or("receipt append requires --payload")?,
            })
        }
        _ => Err("USAGE".to_string()),
    }
}

fn print_receipt_help() {
    println!("Usage:\n  tuskd-core receipt append --repo PATH --kind KIND --payload JSON");
}

fn run_receipt(args: &[String]) -> ExitCode {
    let parsed = match parse_receipt_args(args) {
        Ok(parsed) => parsed,
        Err(message) if message == "USAGE" => {
            print_receipt_help();
            return ExitCode::SUCCESS;
        }
        Err(message) => return fail(&message),
    };

    let result = match parsed {
        ReceiptArgs::Append {
            repo_root,
            kind,
            payload,
        } => append_receipt(&repo_root, &kind, payload),
    };

    match result {
        Ok(receipt) => match serde_json::to_string(&receipt) {
            Ok(text) => {
                println!("{text}");
                ExitCode::SUCCESS
            }
            Err(err) => fail(&format!("failed to encode receipt result: {err}")),
        },
        Err(message) => fail(&message),
    }
}

struct QueryArgs {
    repo_root: PathBuf,
    socket_path: PathBuf,
    kind: String,
    request_id: String,
}

fn parse_query_args(args: &[String]) -> Result<QueryArgs, String> {
    let mut repo_root: Option<PathBuf> = None;
    let mut socket_path: Option<PathBuf> = None;
    let mut kind: Option<String> = None;
    let mut request_id: Option<String> = None;
    let mut index = 0;

    while index < args.len() {
        match args[index].as_str() {
            "--repo" => {
                let value = args.get(index + 1).ok_or("--repo requires a path")?;
                repo_root = Some(repo_root_arg(value)?);
                index += 2;
            }
            "--socket" => {
                let value = args.get(index + 1).ok_or("--socket requires a path")?;
                socket_path = Some(PathBuf::from(value));
                index += 2;
            }
            "--kind" => {
                let value = args.get(index + 1).ok_or("--kind requires a value")?;
                kind = Some(value.clone());
                index += 2;
            }
            "--request-id" => {
                let value = args.get(index + 1).ok_or("--request-id requires a value")?;
                request_id = Some(value.clone());
                index += 2;
            }
            "--payload" => {
                let _ = args
                    .get(index + 1)
                    .ok_or("--payload requires a JSON value")?;
                index += 2;
            }
            "--help" | "-h" => return Err("USAGE".to_string()),
            flag => return Err(format!("unknown query argument: {flag}")),
        }
    }

    let repo_root = repo_root.ok_or("query requires --repo")?;
    let socket_path = socket_path.unwrap_or_else(|| default_socket_path(&repo_root));
    let kind = kind.ok_or("query requires --kind")?;
    let request_id = request_id.unwrap_or_else(now_iso8601);

    Ok(QueryArgs {
        repo_root,
        socket_path,
        kind,
        request_id,
    })
}

fn print_query_help() {
    println!(
        "Usage:\n  tuskd-core query --repo PATH [--socket PATH] --kind KIND [--request-id ID] [--payload JSON]"
    );
}

struct ActionPrepareArgs {
    repo_root: PathBuf,
    socket_path: PathBuf,
    kind: String,
    payload: Value,
}

fn parse_action_prepare_args(args: &[String]) -> Result<ActionPrepareArgs, String> {
    let mut repo_root: Option<PathBuf> = None;
    let mut socket_path: Option<PathBuf> = None;
    let mut kind: Option<String> = None;
    let mut payload: Option<Value> = None;
    let mut index = 0;

    while index < args.len() {
        match args[index].as_str() {
            "--repo" => {
                let value = args.get(index + 1).ok_or("--repo requires a path")?;
                repo_root = Some(repo_root_arg(value)?);
                index += 2;
            }
            "--socket" => {
                let value = args.get(index + 1).ok_or("--socket requires a path")?;
                socket_path = Some(PathBuf::from(value));
                index += 2;
            }
            "--kind" => {
                let value = args.get(index + 1).ok_or("--kind requires a value")?;
                kind = Some(value.clone());
                index += 2;
            }
            "--payload" => {
                let value = args
                    .get(index + 1)
                    .ok_or("--payload requires a JSON value")?;
                payload = Some(
                    serde_json::from_str::<Value>(value)
                        .map_err(|err| format!("invalid --payload: {err}"))?,
                );
                index += 2;
            }
            "--help" | "-h" => return Err("USAGE".to_string()),
            flag => return Err(format!("unknown action-prepare argument: {flag}")),
        }
    }

    let repo_root = repo_root.ok_or("action-prepare requires --repo")?;
    let socket_path = socket_path.unwrap_or_else(|| default_socket_path(&repo_root));
    let kind = kind.ok_or("action-prepare requires --kind")?;
    let payload = payload.unwrap_or_else(|| json!({}));

    Ok(ActionPrepareArgs {
        repo_root,
        socket_path,
        kind,
        payload,
    })
}

fn print_action_prepare_help() {
    println!(
        "Usage:\n  tuskd-core action-prepare --repo PATH [--socket PATH] --kind KIND --payload JSON"
    );
}

fn print_action_run_help() {
    println!(
        "Usage:\n  tuskd-core action-run --repo PATH [--socket PATH] --kind KIND --payload JSON"
    );
}

fn run_action_prepare(args: &[String]) -> ExitCode {
    let parsed = match parse_action_prepare_args(args) {
        Ok(parsed) => parsed,
        Err(message) if message == "USAGE" => {
            print_action_prepare_help();
            return ExitCode::SUCCESS;
        }
        Err(message) => return fail(&message),
    };

    match transition_prepare_result(
        &parsed.repo_root,
        &parsed.socket_path,
        &parsed.kind,
        &parsed.payload,
    ) {
        Ok(Some(result)) => match serde_json::to_string(&result) {
            Ok(text) => {
                println!("{text}");
                ExitCode::SUCCESS
            }
            Err(err) => fail(&format!("failed to encode action-prepare result: {err}")),
        },
        Ok(None) => fail(&format!("unsupported action kind: {}", parsed.kind)),
        Err(message) => fail(&message),
    }
}

fn run_action_run(args: &[String]) -> ExitCode {
    let parsed = match parse_action_prepare_args(args) {
        Ok(parsed) => parsed,
        Err(message) if message == "USAGE" => {
            print_action_run_help();
            return ExitCode::SUCCESS;
        }
        Err(message) => return fail(&message),
    };

    match transition_run_result(
        &parsed.repo_root,
        &parsed.socket_path,
        &parsed.kind,
        &parsed.payload,
    ) {
        Ok(Some(result)) => match serde_json::to_string(&result) {
            Ok(text) => {
                println!("{text}");
                ExitCode::SUCCESS
            }
            Err(err) => fail(&format!("failed to encode action-run result: {err}")),
        },
        Ok(None) => fail(&format!("unsupported action kind: {}", parsed.kind)),
        Err(message) => fail(&message),
    }
}

fn run_query(args: &[String]) -> ExitCode {
    let parsed = match parse_query_args(args) {
        Ok(parsed) => parsed,
        Err(message) if message == "USAGE" => {
            print_query_help();
            return ExitCode::SUCCESS;
        }
        Err(message) => return fail(&message),
    };

    match query_response(
        &parsed.repo_root,
        &parsed.socket_path,
        &parsed.request_id,
        &parsed.kind,
    ) {
        Ok(Some(response)) => match serde_json::to_string(&response) {
            Ok(text) => {
                println!("{text}");
                ExitCode::SUCCESS
            }
            Err(err) => fail(&format!("failed to encode query response: {err}")),
        },
        Ok(None) => fail(&format!("unsupported query kind: {}", parsed.kind)),
        Err(message) => fail(&message),
    }
}

fn print_respond_help() {
    println!("Usage:\n  tuskd-core respond --repo PATH [--socket PATH]");
}

fn run_respond(args: &[String]) -> ExitCode {
    let parsed = match parse_projection_args(args, "respond") {
        Ok(parsed) => parsed,
        Err(message) if message == "USAGE" => {
            print_respond_help();
            return ExitCode::SUCCESS;
        }
        Err(message) => return fail(&message),
    };

    let mut request_line = String::new();
    if let Err(err) = std::io::stdin().read_to_string(&mut request_line) {
        return fail(&format!("failed to read request body: {err}"));
    }
    if request_line.trim().is_empty() {
        return fail("missing request body");
    }

    let request = match serde_json::from_str::<Value>(&request_line) {
        Ok(value) => value,
        Err(err) => return fail(&format!("request was not valid JSON: {err}")),
    };

    let request_id = request
        .get("request_id")
        .and_then(Value::as_str)
        .unwrap_or("");
    let kind = request.get("kind").and_then(Value::as_str).unwrap_or("");
    let payload = request.get("payload").cloned().unwrap_or_else(|| json!({}));

    match query_response(&parsed.repo_root, &parsed.socket_path, request_id, kind) {
        Ok(Some(response)) => match serde_json::to_string(&response) {
            Ok(text) => {
                println!("{text}");
                ExitCode::SUCCESS
            }
            Err(err) => fail(&format!("failed to encode respond payload: {err}")),
        },
        Ok(None) => {
            match transition_run_result(&parsed.repo_root, &parsed.socket_path, kind, &payload) {
                Ok(Some(result)) => {
                    match serde_json::to_string(&action_protocol_response(request_id, kind, result))
                    {
                        Ok(text) => {
                            println!("{text}");
                            ExitCode::SUCCESS
                        }
                        Err(err) => {
                            fail(&format!("failed to encode action respond payload: {err}"))
                        }
                    }
                }
                Ok(None) => ExitCode::from(64),
                Err(message) => fail(&message),
            }
        }
        Err(message) => fail(&message),
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();

    match args.first().map(String::as_str) {
        None | Some("-h") | Some("--help") | Some("help") => {
            print_help();
            ExitCode::SUCCESS
        }
        Some("seam") => match args.get(1).map(String::as_str) {
            None => {
                print_seam(false);
                ExitCode::SUCCESS
            }
            Some("--json") => {
                print_seam(true);
                ExitCode::SUCCESS
            }
            Some("-h") | Some("--help") => {
                println!("Usage:\n  tuskd-core seam [--json]");
                ExitCode::SUCCESS
            }
            Some(_) => fail("seam accepts only --json"),
        },
        Some("ensure") => run_ensure(&args[1..]),
        Some("status") => run_status(&args[1..]),
        Some("board-status") => run_board_status(&args[1..]),
        Some("receipts-status") => run_receipts_status(&args[1..]),
        Some("lane-state") => run_lane_state(&args[1..]),
        Some("receipt") => run_receipt(&args[1..]),
        Some("action-prepare") => run_action_prepare(&args[1..]),
        Some("action-run") => run_action_run(&args[1..]),
        Some("query") => run_query(&args[1..]),
        Some("respond") => run_respond(&args[1..]),
        Some(command) => fail(&format!("unknown command: {command}")),
    }
}
