# Tusk Kernel Spec Provenance

This directory is the repo-owned source of truth for the current Tusk kernel
spec series.

## Imported Series

The current `TUSK-0000` through `TUSK-0005` series was imported from the
exported bundle named `tusk-spec-kernel-sharpened-overlay.zip` while shaping
`tusk-asy.2.40`.

After import, the repo copies under `design/specs/` are authoritative for this
checkout. The exported zip is an import/export artifact and audit trail, not
the live source of truth for ongoing edits.

## Repo Status

- `TUSK-0000` through `TUSK-0005` are repo-owned drafts.
- `TUSK-0004` is the binding engineering surface for runtime and test
  conformance work.
- `TUSK-0005` is only partially realized today. The projection family exists,
  but the spec-shaped fields still need hardening work in the runtime and UI.
- The broader `design/notes/` tree remains informative. It may elaborate the
  kernel, but it does not override `design/specs/`.

## Update Rule

- Edit `design/specs/*` first when changing kernel law.
- Treat future exported bundles as staging or distribution artifacts, not as a
  second authority surface.
- Record later spec refreshes or imports in tracker history and commit
  messages so the provenance stays readable.
