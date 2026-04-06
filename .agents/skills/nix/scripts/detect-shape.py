#!/usr/bin/env python3
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

IGNORE_DIRS = {
    ".git", ".hg", ".svn", ".direnv", "node_modules", "result",
    "dist", "build", ".venv", "venv", "__pycache__", ".devenv"
}
ROOT_MARKERS = [
    "flake.nix",
    "flake.lock",
    "default.nix",
    "shell.nix",
    "configuration.nix",
    "home.nix",
    "darwin-configuration.nix",
]

PATTERNS = {
    "flake_outputs": re.compile(r"\b(nixosConfigurations|darwinConfigurations|homeConfigurations|packages|checks|devShells)\b"),
    "nixos": re.compile(r"\bnixosConfigurations\b|\blib\.nixosSystem\b"),
    "darwin": re.compile(r"\bdarwinConfigurations\b|\bdarwinSystem\b|\bnix-darwin\b"),
    "home": re.compile(r"\bhomeConfigurations\b|\bhome-manager\b|\bhomeManager\b"),
    "den": re.compile(r"\bden\."),
    "den_ctx": re.compile(r"\bden\.ctx\b"),
    "den_aspects": re.compile(r"\bden\.aspects\b"),
    "den_hosts": re.compile(r"\bden\.hosts\b"),
    "den_provides": re.compile(r"\bden\.(?:provides|_)\b"),
    "flake_parts": re.compile(r"\bflake-parts\b"),
}

def find_root(start: Path) -> Path:
    start = start.resolve()
    if start.is_file():
        start = start.parent
    current = start
    last_with_marker = None
    for candidate in [current, *current.parents]:
        if any((candidate / marker).exists() for marker in ROOT_MARKERS):
            last_with_marker = candidate
    return last_with_marker or start

def list_nix_files(root: Path, max_files: int):
    files = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in IGNORE_DIRS]
        for name in filenames:
            if name.endswith(".nix"):
                files.append(Path(dirpath) / name)
                if len(files) >= max_files:
                    return files
    return files

def safe_read(path: Path, max_bytes: int = 512_000) -> str:
    try:
        data = path.read_bytes()
    except Exception:
        return ""
    if len(data) > max_bytes:
        data = data[:max_bytes]
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("utf-8", errors="replace")

def detect_nix_version():
    try:
        out = subprocess.check_output(["nix", "--version"], stderr=subprocess.STDOUT, text=True).strip()
        return {"available": True, "version": out}
    except Exception:
        return {"available": False}

def main():
    parser = argparse.ArgumentParser(
        description="Detect the shape of a Nix repository or working directory and emit JSON."
    )
    parser.add_argument("path", nargs="?", default=".", help="Path inside the repo to inspect.")
    parser.add_argument("--max-files", type=int, default=300, help="Maximum number of .nix files to scan.")
    args = parser.parse_args()

    root = find_root(Path(args.path))
    files = list_nix_files(root, args.max_files)

    hits = {key: [] for key in PATTERNS}
    total_scanned = 0

    for path in files:
        text = safe_read(path)
        if not text:
            continue
        total_scanned += 1
        rel = str(path.relative_to(root))
        for key, pattern in PATTERNS.items():
            if pattern.search(text):
                if len(hits[key]) < 12:
                    hits[key].append(rel)

    domains = []
    if hits["nixos"]:
        domains.append("nixos")
    if hits["darwin"]:
        domains.append("darwin")
    if hits["home"]:
        domains.append("home-manager")
    if hits["den"]:
        domains.append("den")
    if hits["flake_outputs"] or (root / "flake.nix").exists():
        domains.append("flake")

    if not domains and files:
        domains.append("nix")

    recommendation = []
    if "den" in domains:
        recommendation.append("Topology first, then Den lens if the question is conceptual.")
    elif "flake" in domains:
        recommendation.append("Run probe-flake.sh next.")
    elif domains:
        recommendation.append("Start with direct file inspection and narrow nix eval probes.")
    else:
        recommendation.append("No obvious Nix shape detected; inspect the path manually.")

    result = {
        "root": str(root),
        "path_exists": Path(args.path).exists(),
        "nix": detect_nix_version(),
        "files_scanned": total_scanned,
        "domains": domains,
        "markers": {
            key: value for key, value in hits.items() if value
        },
        "recommended_next_steps": recommendation,
    }

    print(json.dumps(result, indent=2, sort_keys=True))

if __name__ == "__main__":
    main()
