use radicle_flake_wasm_resolver::{resolve, ResolveRequest};
use std::env;
use std::io::{self, Read};
use std::process;

fn main() {
    if let Err(err) = run() {
        eprintln!("radicle-flake-wasm-resolver: {err}");
        process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let request_json = request_payload()?;
    let request: ResolveRequest = serde_json::from_str(&request_json)
        .map_err(|err| format!("invalid request JSON: {err}"))?;
    let resolved = resolve(&request).map_err(|err| err.to_string())?;

    serde_json::to_writer_pretty(io::stdout(), &resolved)
        .map_err(|err| format!("failed to serialize resolver output: {err}"))?;
    println!();
    Ok(())
}

fn request_payload() -> Result<String, String> {
    if let Some(arg) = env::args().nth(1) {
        return Ok(arg);
    }

    let mut stdin = String::new();
    io::stdin()
        .read_to_string(&mut stdin)
        .map_err(|err| format!("failed to read stdin: {err}"))?;

    if stdin.trim().is_empty() {
        Err("expected request JSON as the first argument or on stdin".to_owned())
    } else {
        Ok(stdin)
    }
}
