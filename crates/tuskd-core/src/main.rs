use std::env;
use std::process::ExitCode;

const HELP: &str = "\
Usage:
  tuskd-core seam [--json]
  tuskd-core help

Commands:
  seam   Print the first Rust-owned backend/service seam contract.
  help   Show this help text.
";

const SEAM_TEXT: &str = "\
tuskd core seam scaffold
  package: tuskd-core
  wrapper entrypoint: tuskd core-seam
  transition family: tracker.ensure
  scope:
    - backend ensure
    - live-server adoption
    - healthy service-record publication
  rust next:
    - snapshot normalization
    - witness derivation
    - admission
    - realization planning
    - service-record serialization
  shell remains:
    - CLI argument parsing
    - environment and path adaptation
    - compatibility wrapper over the Rust seam
";

const SEAM_JSON: &str = r#"{
  "kind": "backend-service-carrier",
  "status": "scaffold",
  "package": "tuskd-core",
  "wrapper_entrypoint": "tuskd core-seam",
  "transition_family": "tracker.ensure",
  "scope": [
    "backend ensure",
    "live-server adoption",
    "healthy service-record publication"
  ],
  "rust_next": [
    "snapshot normalization",
    "witness derivation",
    "admission",
    "realization planning",
    "service-record serialization"
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

fn print_seam(json: bool) {
    if json {
        println!("{SEAM_JSON}");
    } else {
        print!("{SEAM_TEXT}");
    }
}

fn fail(message: &str) -> ExitCode {
    eprintln!("tuskd-core: {message}");
    ExitCode::from(1)
}

fn main() -> ExitCode {
    let mut args = env::args().skip(1);

    match args.next().as_deref() {
        None | Some("-h") | Some("--help") | Some("help") => {
            print_help();
            ExitCode::SUCCESS
        }
        Some("seam") => {
            let remaining: Vec<String> = args.collect();
            match remaining.as_slice() {
                [] => {
                    print_seam(false);
                    ExitCode::SUCCESS
                }
                [flag] if flag == "--json" => {
                    print_seam(true);
                    ExitCode::SUCCESS
                }
                [flag] if flag == "-h" || flag == "--help" => {
                    println!("Usage:\n  tuskd-core seam [--json]");
                    ExitCode::SUCCESS
                }
                _ => fail("seam accepts only --json"),
            }
        }
        Some(command) => fail(&format!("unknown command: {command}")),
    }
}
