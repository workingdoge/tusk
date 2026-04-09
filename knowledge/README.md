# Tusk Knowledge

This directory is the repo-local knowledge layer for `tusk`.

It sits between raw sources and live control-plane authority.

The rule is:

- sources are observed
- knowledge is compiled
- authority decides truth

## Layout

```text
knowledge/
  README.md
  index.md
  log.md
  sources/
  wiki/
```

## Meanings

- `sources/` contains raw source packets and source pointers.
- `wiki/` contains maintained synthesis pages.
- `index.md` is the content-oriented catalog.
- `log.md` is the append-only chronology.

## Boundaries

This directory is not the live control plane.

Live truth still belongs to:

- tracker state
- `tuskd`
- lane state
- receipts

This directory exists to preserve learning, synthesis, comparison, and design
memory in a reviewable repo-local form.

## First Workflow

1. Add or update one source packet in `sources/`.
2. Update one or more pages in `wiki/`.
3. Refresh `index.md`.
4. Append one entry to `log.md`.

## Naming

Use stable, readable file names.

Examples:

- `sources/2026-04-08-tuskd-autonomous-lane-dogfood.md`
- `wiki/tusk-control-plane.md`
- `wiki/upstream-boundary-map.md`
- `wiki/premath-nerve-wcat-map.md`

## Page Rule

Compiled pages should point back to the sources they synthesize.

Do not let a compiled page present uncited synthesis as if it were live
authority.
