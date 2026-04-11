# Tusk Adjunct Specs

This directory holds repo-owned adjunct spec families that live near `tusk`
because the repo stages or implements against them, but which do **not** define
Tusk's repo-local workflow kernel.

## Placement Rule

- Use `design/specs/` for Tusk kernel law.
- Use `design/adjuncts/` for imported or collocated domain contracts that Tusk
  may consume, stage, or implement against.
- Use `design/notes/` for Tusk-owned explanatory and adapter notes.
- Use `design/migration-candidates/` for material that is still expected to
  move elsewhere later.

## Current Families

- `bridge-adapter/`
  - External caller -> authoritative provider -> policy-input adapter contract.
  - Repo-owned after import, but not part of the Tusk kernel spec series.

## Working Rule

Adjunct specs may be normative for their own domain surfaces. They do not
override `design/specs/`, and they do not change what Tusk is allowed to own.
