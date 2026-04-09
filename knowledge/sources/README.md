# Knowledge Sources

This directory holds raw source packets and source pointers.

These files are evidence inputs for the compiled knowledge layer.

## Rules

- Prefer one file per source or bounded source batch.
- Treat source packets as immutable observations when possible.
- If a source is mutable, anchor it with enough context to make the observation
  repeatable.

## Minimum Packet Shape

Each source packet should usually capture:

- source id
- title
- origin
- date observed
- revision, URL, or file anchor
- source kind
- short summary
- notable claims
- open questions

## Examples

- upstream repo snapshot
- design note read
- lane receipt summary
- external protocol reference
- downstream repo comparison

## Non-Goal

This directory is not where live operational truth is stored.

For live issue, lane, or backend truth, use the tracker and `tuskd`.
