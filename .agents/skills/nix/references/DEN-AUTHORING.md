# Den authoring after local probing

Do **not** start here.
Use this note after detecting shape and inspecting the local flake.

## Scope
Use this file when the task is:
- writing Den top-down
- reshaping a flake around Den contexts and aspects
- deciding what belongs in schema, defaults, or aspects
- figuring out which Den docs to read

This is not only for host configuration.
Use the same discipline for any flake outputs or context families you are
organizing with Den.

## Official sources
- Docs site: `https://den.oeiuwq.com/`
- Source: `https://github.com/vic/den`

Prefer the docs site for explanation and guides.
Prefer the source repo when you need the exact module or battery definition.

## Docs map
Read only the smallest page that matches the question:

1. Overview
   - `https://den.oeiuwq.com/overview/`
   - Use first when deciding entrypoint, template choice, or overall shape.

2. Core principles
   - `https://den.oeiuwq.com/explanation/core-principles/`
   - Use when deciding feature-first vs host-first vs context-first.

3. Library vs framework
   - `https://den.oeiuwq.com/explanation/library-vs-framework/`
   - Use when deciding whether to adopt Den directly or only borrow ideas.

4. Context system
   - `https://den.oeiuwq.com/explanation/context-system/`
   - Use when reasoning about `den.ctx.*`, admissibility, and context stages.

5. Context pipeline
   - `https://den.oeiuwq.com/explanation/context-pipeline/`
   - Use when reasoning about host -> user -> hm-user flow and realization.

6. Home Manager guide
   - `https://den.oeiuwq.com/guides/home-manager/`
   - Use when host users and standalone homes must both work.

7. Custom classes guide
   - `https://den.oeiuwq.com/guides/custom-classes/`
   - Use only after the base host/home path is stable.

## Pi-first authoring stance
Use this reading when writing Den top-down:

- Sigma side:
  concrete witnesses and schema such as `den.hosts`, `den.homes`, and other
  declared entities.
- Pi side:
  aspects, batteries, and defaults that state what should hold uniformly
  whenever the relevant context witness exists.

This means:
- declare what exists first
- write what should hold uniformly second
- keep machine- or repo-specific facts in the narrowest concrete aspect that
  needs them

## Practical order
For a Den rewrite or refactor:

1. Identify the target output or realization class.
   Examples: `darwinConfigurations`, `homeConfigurations`, custom forwarded
   classes.

2. Identify the concrete witnesses.
   Examples: hosts, users, homes, profiles.

3. Identify the built-in context path already supplied by Den.
   Examples: `host`, `user`, `hm-host`, `hm-user`.

4. Move uniform constraints into defaults or reusable aspects.
   Good candidates:
   - `hostname`
   - `define-user`
   - `primary-user`
   - `user-shell`

5. Keep concrete facts in narrow aspects.
   Good candidates:
   - machine-specific secrets
   - per-user git identities
   - repo-local shell aliases

6. Validate the smallest slice.
   Prefer `nix eval` on a narrow config path or a dry-run build for the default
   output.

## Heuristics
- Prefer Den Minimal-style entry over a larger framework setup unless the flake
  already uses the richer framework.
- Keep aliases thin. An alias can improve ergonomics, but it should not hide a
  meaningful context transition.
- Avoid inventing a local pseudo-Den layer when upstream Den already supplies
  the needed context or battery.
- Avoid giant monolithic aspects once two or three coherent Pi-side slices are
  visible.
- Do not force every value into the schema. Schema is for witnesses, not every
  option leaf.

## Good questions to ask during authoring
- What concrete witnesses exist in this flake?
- Which context shape makes this fragment admissible?
- Is this uniform enough to live in a default or reusable aspect?
- Is there already a Den battery for this?
- What is the smallest validation that would prove this slice works?
