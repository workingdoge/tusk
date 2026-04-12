use std::env;
use std::ffi::OsString;
use std::path::PathBuf;
use std::process::ExitCode;

use tusk_bridge_adapter::{
    AuthorizeRequest, ProviderResults, assemble, audit_stub, load_json_file, write_json_file,
};

const HELP: &str = "\
Usage:
  tusk-bridge-adapter assemble --authorize-request PATH --provider-results PATH --out PATH [--audit-out PATH] [--authoritative-time-source URI]
  tusk-bridge-adapter help

Commands:
  assemble  Assemble bridge policy input and optionally emit the audit stub.
  help      Show this help text.
";

enum Command {
    Assemble {
        authorize_request: PathBuf,
        provider_results: PathBuf,
        out: PathBuf,
        audit_out: Option<PathBuf>,
        authoritative_time_source: String,
    },
    Help,
}

fn main() -> ExitCode {
    match run(env::args_os()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("tusk-bridge-adapter: {message}");
            ExitCode::from(1)
        }
    }
}

fn run(args: impl IntoIterator<Item = OsString>) -> Result<(), String> {
    match parse_args(args)? {
        Command::Assemble {
            authorize_request,
            provider_results,
            out,
            audit_out,
            authoritative_time_source,
        } => {
            let authorize_request: AuthorizeRequest = load_json_file(&authorize_request)?;
            let provider_results: ProviderResults = load_json_file(&provider_results)?;
            let assembled = assemble(authorize_request, provider_results)?;
            write_json_file(&out, &assembled)?;

            if let Some(audit_out) = audit_out {
                let audit = audit_stub(&assembled, &authoritative_time_source)?;
                write_json_file(&audit_out, &audit)?;
            }

            Ok(())
        }
        Command::Help => {
            print!("{HELP}");
            Ok(())
        }
    }
}

fn parse_args(args: impl IntoIterator<Item = OsString>) -> Result<Command, String> {
    let args = args.into_iter().collect::<Vec<_>>();
    let Some(command) = args.get(1).and_then(|value| value.to_str()) else {
        return Ok(Command::Help);
    };

    match command {
        "help" | "--help" | "-h" => Ok(Command::Help),
        "assemble" => parse_assemble(&args[2..]),
        other => Err(format!("unknown command: {other}")),
    }
}

fn parse_assemble(args: &[OsString]) -> Result<Command, String> {
    let mut authorize_request = None;
    let mut provider_results = None;
    let mut out = None;
    let mut audit_out = None;
    let mut authoritative_time_source = "time-authority://core/ntp-primary".to_string();

    let mut index = 0;
    while index < args.len() {
        let flag = args[index]
            .to_str()
            .ok_or_else(|| "arguments must be valid UTF-8".to_string())?;
        let value = args
            .get(index + 1)
            .ok_or_else(|| format!("missing value for {flag}"))?;

        match flag {
            "--authorize-request" => authorize_request = Some(PathBuf::from(value)),
            "--provider-results" => provider_results = Some(PathBuf::from(value)),
            "--out" => out = Some(PathBuf::from(value)),
            "--audit-out" => audit_out = Some(PathBuf::from(value)),
            "--authoritative-time-source" => {
                authoritative_time_source = value
                    .to_str()
                    .ok_or_else(|| "authoritative time source must be valid UTF-8".to_string())?
                    .to_string();
            }
            other => return Err(format!("unknown flag for assemble: {other}")),
        }

        index += 2;
    }

    Ok(Command::Assemble {
        authorize_request: authorize_request
            .ok_or_else(|| "--authorize-request is required".to_string())?,
        provider_results: provider_results
            .ok_or_else(|| "--provider-results is required".to_string())?,
        out: out.ok_or_else(|| "--out is required".to_string())?,
        audit_out,
        authoritative_time_source,
    })
}
