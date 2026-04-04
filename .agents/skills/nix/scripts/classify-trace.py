#!/usr/bin/env python3
import argparse
import json
import re
import sys
from pathlib import Path

CATEGORY_PATTERNS = [
    ("infinite-recursion", re.compile(r"infinite recursion encountered", re.IGNORECASE)),
    ("option-missing", re.compile(r"The option [`'\"]([^`'\"]+)[`'\"] does not exist", re.IGNORECASE)),
    ("attribute-missing", re.compile(r"attribute [`'\"]([^`'\"]+)[`'\"] missing", re.IGNORECASE)),
    ("path-or-import-failure", re.compile(r"(No such file or directory|cannot import|getting status of|path .* does not exist)", re.IGNORECASE)),
    ("type-mismatch", re.compile(r"(expected .* but got|value is .* while a .* was expected|cannot coerce)", re.IGNORECASE)),
    ("json-nonrepresentable", re.compile(r"(cannot convert .* to JSON|not representable as JSON)", re.IGNORECASE)),
]

NIX_PATH_RE = re.compile(r"((?:/[^:\s]+|\./[^:\s]+|\.\./[^:\s]+)[^:\s]*\.nix)(?::\d+(?::\d+)?)?")

RECOMMENDATIONS = {
    "infinite-recursion": [
        "Identify the smallest self-reference boundary involving config, imports, or outputs.",
        "Remove one dependency edge and re-evaluate.",
    ],
    "option-missing": [
        "Confirm the target domain: nixos, darwin, or home.",
        "Inspect imports or aspect routing before reading docs.",
    ],
    "attribute-missing": [
        "Verify the attr path against flake topology.",
        "Check spelling and class/output assumptions.",
    ],
    "path-or-import-failure": [
        "Inspect the literal path first.",
        "Confirm the repo root and relative import assumptions.",
    ],
    "type-mismatch": [
        "Reduce to the smallest expression producing the wrong value shape.",
        "Inspect the immediate producer rather than downstream merges.",
    ],
    "json-nonrepresentable": [
        "Target a deeper concrete attribute.",
        "Switch to nix repl once the scope is already narrow.",
    ],
    "unknown": [
        "Read the first user-owned file in the trace.",
        "Shrink to the smallest failing installable and re-run with --show-trace.",
    ],
}

def first_user_file(text: str):
    for match in NIX_PATH_RE.finditer(text):
        candidate = match.group(1)
        if "/nix/store/" not in candidate:
            return candidate
    return None

def classify(text: str):
    clues = []
    category = "unknown"
    for name, pattern in CATEGORY_PATTERNS:
        match = pattern.search(text)
        if match:
            category = name
            if match.groups():
                clues.extend([g for g in match.groups() if g])
            break

    file_hint = first_user_file(text)

    return {
        "category": category,
        "first_user_file": file_hint,
        "clues": clues,
        "recommendations": RECOMMENDATIONS[category],
    }

def main():
    parser = argparse.ArgumentParser(description="Classify a Nix error trace and emit JSON.")
    parser.add_argument("file", nargs="?", help="Optional trace file. Reads stdin if omitted.")
    args = parser.parse_args()

    if args.file:
        text = Path(args.file).read_text(encoding="utf-8", errors="replace")
    else:
        text = sys.stdin.read()

    result = classify(text)
    result["bytes"] = len(text.encode("utf-8", errors="replace"))
    print(json.dumps(result, indent=2, sort_keys=True))

if __name__ == "__main__":
    main()
