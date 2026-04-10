# Tusk Spec Kernel Overview

This series is intentionally small. The goal is not to produce a cathedral of
RFCs. The goal is to freeze the minimum law that the repo already depends on.

## Landing order

1. **`TUSK-0000` — Identity and Boundary**
   - freezes what Tusk is allowed to own
   - prevents silent scope expansion

2. **`TUSK-0001` + `TUSK-0002` — Structure and Admission**
   - makes the base/fiber split explicit
   - turns hidden preconditions into named witnesses

3. **`TUSK-0004` — Transition Contracts**
   - binds the runtime and tests to one concrete engineering surface
   - gives each transition an `admitted iff` condition and success postconditions

4. **`TUSK-0003` + `TUSK-0005` — Closure and Projection**
   - defines what it means for local work to be discharged
   - defines what the operator surface must expose without becoming authority

## Hardening path

The practical hardening path is:

1. make `transition_prepare` and `transition_run` read naturally against
   `TUSK-0002` and `TUSK-0004`
2. make the transition tests exercise:
   - admitted success
   - rejected admission
   - apply-time failure with restoration when relevant
3. make board/operator projections expose:
   - base locus
   - live lane
   - missing witness for the next move
   - closure eligibility

## Success condition

The series is doing its job when:

- fewer facts need to live in the operator’s head,
- rejection messages correspond to named witnesses,
- local terminality is no longer confused with canonical closure,
- and a new transition can only enter Tusk by taking the existing shape.
