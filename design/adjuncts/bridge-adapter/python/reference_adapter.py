#!/usr/bin/env python3
"""Reference bridge adapter that assembles policy input from an external authorize
request plus authoritative provider results.

This script does not perform cryptographic verification itself. It validates the
shapes of the request and provider results, assembles the internal policy input
contract used by the bridge policy layer, validates the assembled input, and
emits an audit-record stub.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any, Dict

import jsonschema


HERE = Path(__file__).resolve().parent
SCHEMAS = HERE.parent / "schemas"


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def canonical_json_bytes(obj: Any) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256_hex(obj: Any) -> str:
    return hashlib.sha256(canonical_json_bytes(obj)).hexdigest()


class SchemaStore:
    def __init__(self) -> None:
        self._cache: Dict[str, Any] = {}
        self._store: Dict[str, Any] = {}
        for path in SCHEMAS.glob("*.json"):
            schema = load_json(path)
            self._cache[path.name] = schema
            if "$id" in schema:
                self._store[schema["$id"]] = schema

    def load(self, name: str) -> Any:
        return self._cache[name]

    def resolver_store(self) -> Dict[str, Any]:
        return dict(self._store)


def validate(instance: Any, schema_name: str, store: SchemaStore) -> None:
    schema = store.load(schema_name)
    resolver = jsonschema.RefResolver.from_schema(schema, store=store.resolver_store())
    jsonschema.Draft202012Validator(schema, resolver=resolver).validate(instance)


def compute_cross_domain(call: Dict[str, Any]) -> bool:
    if "cross_domain" in call:
        return bool(call["cross_domain"])
    return call.get("destination_domain", call["source_domain"]) != call["source_domain"]


def assemble(authorize_request: Dict[str, Any], provider_results: Dict[str, Any]) -> Dict[str, Any]:
    call = authorize_request["call"]
    runtime = provider_results["runtime"]
    destination_domain = call.get("destination_domain", call["source_domain"])
    return {
        "witness": authorize_request["witness"],
        "preflight": provider_results["preflight"],
        "events": provider_results["events"],
        "runtime_request": {
            "attestation_snapshot": runtime["attestation_snapshot"],
            "cross_domain": compute_cross_domain(call),
            "current_mode": runtime["current_mode"],
            "destination_domain": destination_domain,
            "now": runtime["authoritative_now"],
            "payload_hash": call.get("payload_hash", ""),
            "pop_proof": call["pop_proof"],
            "requested_resource": call["requested_resource"],
            "requested_tool": call["requested_tool"],
            "resource_policy": runtime["resource_policy"],
            "revocation_snapshot": runtime["revocation_snapshot"],
            "rp_initiated": call["rp_initiated"],
            "session_nonce": call["session_nonce"],
            "source_domain": call["source_domain"],
            "time_source_ok": runtime["time_source_ok"],
            "verifier_id": runtime["verifier_id"],
        },
    }


def audit_stub(policy_input: Dict[str, Any], authoritative_time_source: str) -> Dict[str, Any]:
    witness = policy_input["witness"]
    return {
        "version": "0.2",
        "record_type": "authorize",
        "event_time": policy_input["runtime_request"]["now"],
        "authoritative_time_source": authoritative_time_source,
        "trace": witness["trace"],
        "jti": witness["jti"],
        "effect": "error",
        "subject": witness["sub"],
        "act_for": witness.get("act_for", ""),
        "domain": witness["domain"],
        "source_domain": policy_input["runtime_request"]["source_domain"],
        "destination_domain": policy_input["runtime_request"]["destination_domain"],
        "tool": witness["tool"],
        "resource": witness["resource"],
        "current_mode": policy_input["runtime_request"]["current_mode"],
        "witness_sha256": sha256_hex(witness),
        "policy_input_sha256": sha256_hex(policy_input),
        "deny_reasons": [],
        "burn_reasons": [],
        "labels": {
            "conf_label": witness["conf_label"],
            "integ_label": witness["integ_label"],
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Assemble bridge policy input.")
    parser.add_argument("--authorize-request", required=True, type=Path)
    parser.add_argument("--provider-results", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--audit-out", type=Path)
    parser.add_argument(
        "--authoritative-time-source",
        default="time-authority://core/ntp-primary",
        help="Recorded in the emitted audit stub.",
    )
    args = parser.parse_args()

    store = SchemaStore()
    authorize_request = load_json(args.authorize_request)
    provider_results = load_json(args.provider_results)

    validate(authorize_request, "authorize.request.schema.json", store)
    validate(provider_results, "provider-results.schema.json", store)

    assembled = assemble(authorize_request, provider_results)
    validate(assembled, "policy-input.schema.json", store)

    args.out.write_text(json.dumps(assembled, indent=2) + "\n", encoding="utf-8")

    if args.audit_out:
        audit = audit_stub(assembled, args.authoritative_time_source)
        validate(audit, "audit-record.schema.json", store)
        args.audit_out.write_text(json.dumps(audit, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
