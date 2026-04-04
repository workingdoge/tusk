# Remote REPL policy

Remote evaluation is a backend choice, not the first architectural move.

## Use remote only when
- the target configuration really lives on another machine or store
- the local repo cannot reproduce the relevant state
- the local interrogation workflow is already working

## Do not use remote first because
- it hides whether the problem is conceptual or environmental
- it makes probing slower and noisier
- it encourages wandering instead of narrowing

## Default order
1. local shape detection
2. local flake topology
3. local focused evaluation
4. local REPL if needed
5. remote backend only after the question is already narrow
