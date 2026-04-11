# Tusk Design Surface

This directory is organized by authority and placement, not by topic.

## Layout

- `adjuncts/`
  - Repo-owned adjunct spec families that Tusk stages or implements against,
    but which do not define Tusk's repo-local kernel law.
  - These may be normative for their own domain contract. They are not
    authoritative for `design/specs/` or for the Tusk workflow kernel.
- `specs/`
  - Normative kernel specs.
  - This is the only design surface that defines what Tusk is allowed to own
    and what the first governed transition family must do.
  - Once imported here, these repo files are authoritative over any exported
    spec bundle that was used to stage them.
  - New kernel law belongs here first.
- `notes/`
  - Repo-scoped explanatory and adapter notes that help implement or interpret
    the kernel without replacing it.
  - These notes may elaborate the specs, but they do not override them.
- `migration-candidates/`
  - Notes that remain visible in this repo while active work still references
    them, but which are explicitly not kernel-defining and are expected to move
    to a more appropriate context later.

## Placement Rules

- If a surface is an imported or collocated contract that Tusk may implement
  against, but it does not define repo-local workflow law, it belongs in
  `adjuncts/`.
- If a note defines repo-local workflow law, admission law, transition law, or
  projection law, it belongs in `specs/`.
- If a note explains or refines Tusk-owned workflow, control-plane, adapter, or
  operator surfaces, it belongs in `notes/`.
- If a note is mainly about downstream product behavior, upstream method,
  distribution/publication policy, or another context that only temporarily
  lives near Tusk, it belongs in `migration-candidates/` until it moves out.

## Working Rule

Tusk stays scoped by keeping the kernel small, keeping adjunct contracts out of
the kernel, and making migration candidates explicit instead of letting them
sit at peer level with the control-plane law.

See `design/specs/PROVENANCE.md` for the current import and status note for the
kernel series.
See `design/adjuncts/README.md` for imported adjunct contract families that
live in-tree without becoming Tusk kernel law.
