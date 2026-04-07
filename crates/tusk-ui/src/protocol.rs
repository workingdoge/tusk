use std::env;
use std::io::{self, Read, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, anyhow, bail};
use serde::de::DeserializeOwned;
use serde_json::{Value, json};

use crate::types::{
    BoardStatus, ClaimIssuePayload, FinishLanePayload, LaunchLanePayload, OperatorSnapshot,
    PingStatus, ReceiptsStatus, Response, TrackerStatus,
};

#[derive(Debug, Clone)]
pub(crate) struct ProtocolClient {
    pub(crate) repo_root: PathBuf,
    pub(crate) socket_path: PathBuf,
}

impl ProtocolClient {
    pub(crate) fn new(repo_root: PathBuf, socket_path: PathBuf) -> Self {
        Self {
            repo_root,
            socket_path,
        }
    }

    pub(crate) fn tracker_status(&self) -> Result<TrackerStatus> {
        self.query("tracker_status")
    }

    pub(crate) fn operator_snapshot(&self) -> Result<OperatorSnapshot> {
        self.query("operator_snapshot")
    }

    pub(crate) fn board_status(&self) -> Result<BoardStatus> {
        self.query("board_status")
    }

    pub(crate) fn receipts_status(&self) -> Result<ReceiptsStatus> {
        self.query("receipts_status")
    }

    pub(crate) fn ping(&self) -> Result<PingStatus> {
        self.query("ping")
    }

    pub(crate) fn claim_issue(&self, issue_id: &str) -> Result<ClaimIssuePayload> {
        self.query_with_payload("claim_issue", json!({ "issue_id": issue_id }))
    }

    pub(crate) fn launch_lane(&self, issue_id: &str, base_rev: &str) -> Result<LaunchLanePayload> {
        self.query_with_payload(
            "launch_lane",
            json!({ "issue_id": issue_id, "base_rev": base_rev }),
        )
    }

    pub(crate) fn finish_lane(
        &self,
        issue_id: &str,
        outcome: &str,
    ) -> Result<FinishLanePayload> {
        self.query_with_payload(
            "finish_lane",
            json!({ "issue_id": issue_id, "outcome": outcome }),
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
        let request = json!({
            "request_id": request_id(),
            "kind": kind,
            "payload": payload,
        });

        match self.query_via_socket::<T>(&request) {
            Ok(value) => Ok(value),
            Err(error) if should_fallback_to_command(&error) => self.query_via_command(&request),
            Err(error) => Err(error),
        }
    }

    fn query_via_socket<T>(&self, request: &Value) -> Result<T>
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

        let mut body = serde_json::to_vec(request).context("serialize request")?;
        body.push(b'\n');
        stream.write_all(&body).context("write request")?;

        let mut response = String::new();
        stream
            .read_to_string(&mut response)
            .context("read response from socket")?;

        decode_response::<T>(&response)
    }

    fn query_via_command<T>(&self, request: &Value) -> Result<T>
    where
        T: DeserializeOwned,
    {
        let mut child = Command::new(tuskd_bin())
            .arg("respond")
            .arg("--repo")
            .arg(&self.repo_root)
            .arg("--socket")
            .arg(&self.socket_path)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .context("spawn tuskd respond")?;

        {
            let stdin = child
                .stdin
                .as_mut()
                .context("tuskd respond missing stdin pipe")?;
            let mut body = serde_json::to_vec(request).context("serialize command request")?;
            body.push(b'\n');
            stdin
                .write_all(&body)
                .context("write request to tuskd respond")?;
        }

        let output = child
            .wait_with_output()
            .context("wait for tuskd respond output")?;
        if !output.status.success() {
            let stderr =
                String::from_utf8(output.stderr).unwrap_or_else(|_| "<non-utf8 stderr>".to_owned());
            bail!("tuskd respond failed: {}", stderr.trim());
        }

        let stdout =
            String::from_utf8(output.stdout).context("decode tuskd respond stdout as utf-8")?;
        decode_response::<T>(&stdout)
    }
}

pub(crate) fn should_fallback_to_command(error: &anyhow::Error) -> bool {
    error.chain().any(|cause| {
        cause
            .downcast_ref::<io::Error>()
            .map(|io_error| {
                matches!(
                    io_error.kind(),
                    io::ErrorKind::NotFound
                        | io::ErrorKind::ConnectionRefused
                        | io::ErrorKind::ConnectionReset
                        | io::ErrorKind::BrokenPipe
                )
            })
            .unwrap_or(false)
    })
}

pub(crate) fn decode_response<T>(response: &str) -> Result<T>
where
    T: DeserializeOwned,
{
    let decoded: Response<T> =
        serde_json::from_str(response).context("decode protocol response")?;
    if decoded.ok {
        decoded.payload.context("missing response payload")
    } else {
        let message = decoded
            .error
            .map(|error| error.message)
            .unwrap_or_else(|| "unknown protocol error".to_owned());
        Err(anyhow!("request failed: {message}"))
    }
}

pub(crate) fn tuskd_bin() -> String {
    env::var("TUSKD_BIN").unwrap_or_else(|_| "tuskd".to_owned())
}

pub(crate) fn request_id() -> String {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    format!("req-{millis}")
}
