use serde::{Deserialize, Serialize};
use std::error::Error;
use std::fmt;
#[cfg(not(target_arch = "wasm32"))]
use std::process::Command;
#[cfg(target_arch = "wasm32")]
mod nix_plugin;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct ResolveRequest {
    pub rid: String,
    pub seed: String,
    pub branch: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum LockedFetchMetadata {
    Git {
        url: String,
        #[serde(rename = "ref")]
        git_ref: String,
        rev: String,
    },
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ResolveError {
    EmptyField(&'static str),
    MissingField(&'static str),
    BranchNotFound {
        branch: String,
        url: String,
    },
    GitUnavailable(String),
    GitTransportFailed {
        branch: String,
        url: String,
        detail: String,
    },
    UnsupportedRuntime(&'static str),
}

impl fmt::Display for ResolveError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::EmptyField(field) => {
                write!(f, "resolver request field `{field}` must not be empty")
            }
            Self::MissingField(field) => {
                write!(f, "resolver request field `{field}` is required")
            }
            Self::BranchNotFound { branch, url } => {
                write!(f, "branch `{branch}` was not found at `{url}`")
            }
            Self::GitUnavailable(detail) => {
                write!(f, "git is required for live Radicle resolution: {detail}")
            }
            Self::GitTransportFailed {
                branch,
                url,
                detail,
            } => {
                write!(
                    f,
                    "git transport failed for branch `{branch}` at `{url}`: {detail}"
                )
            }
            Self::UnsupportedRuntime(detail) => write!(f, "{detail}"),
        }
    }
}

impl Error for ResolveError {}

pub fn resolve(request: &ResolveRequest) -> Result<LockedFetchMetadata, ResolveError> {
    let url = git_transport_url(request)?;
    let branch = require_non_empty("branch", &request.branch)?.to_owned();
    let rev = resolve_branch_head(&url, &branch)?;

    Ok(LockedFetchMetadata::Git {
        url,
        git_ref: branch,
        rev,
    })
}

pub fn resolve_with_rev(
    request: &ResolveRequest,
    rev: impl Into<String>,
) -> Result<LockedFetchMetadata, ResolveError> {
    let url = git_transport_url(request)?;
    let branch = require_non_empty("branch", &request.branch)?.to_owned();
    let rev = require_non_empty("rev", &rev.into())?.to_owned();

    Ok(LockedFetchMetadata::Git {
        url,
        git_ref: branch,
        rev,
    })
}

pub fn git_transport_url(request: &ResolveRequest) -> Result<String, ResolveError> {
    let seed = require_non_empty("seed", &request.seed)?;
    let rid = require_non_empty("rid", &request.rid)?;

    Ok(format!("https://{}/{}.git", seed, sanitize_rid(rid)))
}

fn require_non_empty<'a>(field: &'static str, value: &'a str) -> Result<&'a str, ResolveError> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        Err(ResolveError::EmptyField(field))
    } else {
        Ok(trimmed)
    }
}

fn sanitize_rid(rid: &str) -> String {
    let raw = rid.trim().strip_prefix("rad:").unwrap_or(rid.trim());
    let mut out = String::new();

    for ch in raw.chars() {
        match ch {
            'a'..='z' | 'A'..='Z' | '0'..='9' => out.push(ch),
            _ if !out.ends_with('-') => out.push('-'),
            _ => {}
        }
    }

    let trimmed = out.trim_matches('-');
    if trimmed.is_empty() {
        "unresolved-rid".to_owned()
    } else {
        trimmed.to_owned()
    }
}

#[cfg(not(target_arch = "wasm32"))]
fn resolve_branch_head(url: &str, branch: &str) -> Result<String, ResolveError> {
    let output = Command::new("git")
        .arg("ls-remote")
        .arg("--refs")
        .arg("--heads")
        .arg(url)
        .arg(format!("refs/heads/{branch}"))
        .output()
        .map_err(|err| ResolveError::GitUnavailable(err.to_string()))?;

    if !output.status.success() {
        let detail = String::from_utf8_lossy(&output.stderr).trim().to_owned();
        return Err(ResolveError::GitTransportFailed {
            branch: branch.to_owned(),
            url: url.to_owned(),
            detail,
        });
    }

    parse_ls_remote_head(&String::from_utf8_lossy(&output.stdout), url, branch)
}

#[cfg(target_arch = "wasm32")]
fn resolve_branch_head(_url: &str, _branch: &str) -> Result<String, ResolveError> {
    Err(ResolveError::UnsupportedRuntime(
        "live Radicle resolution is not available inside the plain wasm32-wasip1 build yet",
    ))
}

#[cfg(not(target_arch = "wasm32"))]
fn parse_ls_remote_head(output: &str, url: &str, branch: &str) -> Result<String, ResolveError> {
    let expected_ref = format!("refs/heads/{branch}");

    for line in output.lines() {
        let mut parts = line.split_whitespace();
        let rev = parts.next();
        let ref_name = parts.next();

        if let (Some(rev), Some(ref_name)) = (rev, ref_name) {
            if ref_name == expected_ref && is_hex_object_id(rev) {
                return Ok(rev.to_owned());
            }
        }
    }

    Err(ResolveError::BranchNotFound {
        branch: branch.to_owned(),
        url: url.to_owned(),
    })
}

#[cfg(not(target_arch = "wasm32"))]
fn is_hex_object_id(value: &str) -> bool {
    value.len() == 40 && value.chars().all(|ch| ch.is_ascii_hexdigit())
}

#[cfg(test)]
mod tests {
    use super::{
        git_transport_url, parse_ls_remote_head, resolve_with_rev, LockedFetchMetadata,
        ResolveRequest,
    };

    #[test]
    fn resolves_git_metadata_from_request() {
        let request = ResolveRequest {
            rid: "rad:z3example".to_owned(),
            seed: "iris.radicle.xyz".to_owned(),
            branch: "main".to_owned(),
        };

        let resolved = resolve_with_rev(&request, "22b2871f64ecf34a22d32add0dd59a0c7c96ad10")
            .expect("resolver should succeed");

        match resolved {
            LockedFetchMetadata::Git { url, git_ref, rev } => {
                assert_eq!(url, "https://iris.radicle.xyz/z3example.git");
                assert_eq!(git_ref, "main");
                assert_eq!(rev, "22b2871f64ecf34a22d32add0dd59a0c7c96ad10");
            }
        }
    }

    #[test]
    fn rejects_empty_fields() {
        let request = ResolveRequest {
            rid: "rad:z3example".to_owned(),
            seed: "".to_owned(),
            branch: "main".to_owned(),
        };

        let err = resolve_with_rev(&request, "22b2871f64ecf34a22d32add0dd59a0c7c96ad10")
            .expect_err("empty seed must fail");
        assert_eq!(
            err.to_string(),
            "resolver request field `seed` must not be empty"
        );
    }

    #[test]
    fn serializes_ref_field_as_ref() {
        let request = ResolveRequest {
            rid: "rad:z3example".to_owned(),
            seed: "iris.radicle.xyz".to_owned(),
            branch: "main".to_owned(),
        };

        let resolved = resolve_with_rev(&request, "22b2871f64ecf34a22d32add0dd59a0c7c96ad10")
            .expect("resolver should succeed");
        let json = serde_json::to_value(resolved).expect("serialization should work");

        assert_eq!(json["kind"], "git");
        assert_eq!(json["ref"], "main");
        assert!(json.get("git_ref").is_none());
    }

    #[test]
    fn builds_transport_url_from_seed_and_rid() {
        let request = ResolveRequest {
            rid: "rad:z3gqcJUoA1n9HaHKufZs5FCSGazv5".to_owned(),
            seed: "seed.radicle.xyz".to_owned(),
            branch: "master".to_owned(),
        };

        let url = git_transport_url(&request).expect("url should build");
        assert_eq!(
            url,
            "https://seed.radicle.xyz/z3gqcJUoA1n9HaHKufZs5FCSGazv5.git"
        );
    }

    #[test]
    fn parses_ls_remote_output_for_matching_branch() {
        let output = "22b2871f64ecf34a22d32add0dd59a0c7c96ad10\trefs/heads/master\n";

        let rev = parse_ls_remote_head(
            output,
            "https://seed.radicle.xyz/z3gqcJUoA1n9HaHKufZs5FCSGazv5.git",
            "master",
        )
        .expect("branch head should parse");

        assert_eq!(rev, "22b2871f64ecf34a22d32add0dd59a0c7c96ad10");
    }

    #[test]
    fn reports_missing_branch_from_ls_remote_output() {
        let output = "22b2871f64ecf34a22d32add0dd59a0c7c96ad10\trefs/heads/master\n";

        let err = parse_ls_remote_head(
            output,
            "https://seed.radicle.xyz/z3gqcJUoA1n9HaHKufZs5FCSGazv5.git",
            "main",
        )
        .expect_err("unexpected branch should fail");

        assert_eq!(
            err.to_string(),
            "branch `main` was not found at `https://seed.radicle.xyz/z3gqcJUoA1n9HaHKufZs5FCSGazv5.git`"
        );
    }
}
