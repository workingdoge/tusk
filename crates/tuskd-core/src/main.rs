use chrono::Utc;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::env;
use std::ffi::OsStr;
use std::fs::{self, File, OpenOptions};
use std::io::Write;
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
  tuskd-core help

Commands:
  seam    Print the first Rust-owned backend/service seam contract.
  ensure  Run the Rust-owned backend ensure and service publication path.
  status  Publish the current backend/service projection without repair.
  help    Show this help text.
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

fn configure_backend_endpoint(repo_root: &Path, port: u16) -> Result<(), String> {
    let port_string = port.to_string();
    let data_dir = backend_data_dir(repo_root).to_string_lossy().into_owned();
    let (exit_code, output) = run_tracker_capture_in_repo(
        repo_root,
        [
            "backend",
            "configure",
            "--host",
            backend_host(),
            "--port",
            port_string.as_str(),
            "--data-dir",
            data_dir.as_str(),
        ],
    )?;

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

fn append_receipt(repo_root: &Path, kind: &str, payload: Value) -> Result<(), String> {
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
    Ok(())
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

fn ensure_projection(repo_root: &Path, socket_path: &Path) -> Result<Value, String> {
    ensure_state_files(repo_root)?;
    let health = health_snapshot(repo_root, socket_path, true)?;
    let leases = current_leases(repo_root);
    let server_pid = live_server_pid(repo_root);
    let (mode, pid) = if let Some(pid) = server_pid {
        ("serving", Some(pid))
    } else {
        ("idle", None)
    };

    let record = write_service_record(repo_root, socket_path, mode, pid, &health, &leases)?;
    append_receipt(repo_root, "tracker.ensure", json!({ "service": record }))?;
    Ok(record)
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

    match ensure_projection(&parsed.repo_root, &parsed.socket_path) {
        Ok(record) => {
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
        Some(command) => fail(&format!("unknown command: {command}")),
    }
}
