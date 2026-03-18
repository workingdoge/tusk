# Issue Shaping

Use this reference when deciding whether an issue is ready for a lane, how to split broad work into linked issues, or how to order multiple issues for execution.

## Ready Issue Checklist

A ready issue usually includes:

- one clear goal,
- explicit non-goals,
- concrete verification,
- a declared landing boundary,
- enough context to know the primary files or subsystems involved.

If those are missing, tighten the issue before launching a worker.

## Sizing Rules

- Prefer one issue to one workspace to one primary visible commit.
- Split on dependency edges: if one part must land before another can start safely, separate them.
- Split on verification boundaries: if different parts need materially different validation, separate them.
- Split on landing ownership: if one part is worker-owned and another is coordinator-owned, separate them.
- Split on risk: isolate risky runtime, tracker, or migration work from ordinary feature work.
- Do not split purely by file path if the user-visible outcome is still one coherent change.

## Ordering Rules

Default execution order:

1. runtime or tracker unblockers
2. dependency roots
3. independent leaves that can run in parallel
4. integration, cleanup, or follow-through

This usually produces better parallelism and fewer rebases than picking issues by recency or file adjacency.

## When To Create A Follow-Up

Create a linked follow-up issue when:

- new independent work is discovered,
- the current issue would need a second landing boundary,
- the verification surface grows materially,
- the issue turns into "cleanup and miscellany" rather than one reviewable change.

Do not quietly widen the current lane and hope the history still makes sense later.

## Hierarchy Versus Lineage

Use tracker hierarchy deliberately:

- `parent-child` is for true completion hierarchy. Use it when the parent issue is meaningfully incomplete until the child issues are complete, and you want the tracker to enforce that relationship.
- `discovered-from` is for provenance and umbrella planning. Use it when you want to show where work came from without making the child issue depend on parent completion.
- `blocks` is for real execution order. Add it only when one issue genuinely cannot proceed until another lands or reaches a defined handoff point.

For roadmap-shaped programs, the safer default is:

1. create an umbrella epic for navigation,
2. link child issues back to it with `discovered-from` or another non-blocking relation,
3. add `blocks` edges only for the actual dependency chain.

That keeps child issues visible in `bd ready` while still preserving lineage and order.

## Anti-Patterns

- omnibus "fix several unrelated things" issues
- issues with no verification plan
- issues that mix runtime repair, tracker repair, and product changes without boundaries
- issues that require multiple teams or landing owners but are still written as one lane
- using `parent-child` as a cosmetic grouping mechanism when the children still need to show up as individually actionable work
