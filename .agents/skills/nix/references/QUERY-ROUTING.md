# Query routing

This file exists for ambiguous cases where the user's phrasing could fit more
than one bucket.

## Bucket matrix

| Bucket | User signals | First probe | Primary goal |
|---|---|---|---|
| Topology | "what exists?", "what does this flake export?", "is this Den?" | `python3 scripts/detect-shape.py .` then `scripts/probe-flake.sh .` | map outputs and configuration domains |
| Realized value / provenance | "where does this come from?", "what is the actual value?" | `scripts/probe-config-path.sh <flake-ref> <domain> <name> <config-path>` | separate realized value from definitions |
| Evaluation failure | "attribute missing", "option does not exist", trace output | `python3 scripts/classify-trace.py`, then `scripts/probe-eval.sh` | find the first user-owned cause |
| Den lens | "is this fibrational?", "how should we name this?" | `python3 scripts/detect-shape.py .`, then inspect `den.*` usage | translate Den without overclaiming |
| Authoring / design | "how should we write this?", "how should we structure Den?", "what goes in schema vs aspects?" | `python3 scripts/detect-shape.py .`, then inspect `flake.nix` and narrow `den.*` files | produce the next small working structural slice |

## Short routing heuristics
- If the question mentions **exports**, **hosts**, **homes**, **systems**, or
  **flake shape**, choose **Topology**.
- If the question mentions a **config path** or **realized setting**, choose
  **Realized value / provenance**.
- If the question contains a literal error message or trace, choose
  **Evaluation failure**.
- If the question is about **Premath**, **fibration**, **bundle**, **context**,
  or **admissibility**, choose **Den lens**.
- If the question is about **how to write**, **how to structure**, **schema vs
  aspects**, or **which Den battery to use**, choose **Authoring / design**.

## Tie-breakers
If it could be either topology or Den lens:
- start with topology;
- only escalate into Den language after confirming the repo uses Den.

If it could be either Den lens or authoring / design:
- choose authoring if the user wants the next implementation move;
- choose Den lens if the user wants naming, mapping, or conceptual translation.

If it could be either provenance or evaluation failure:
- if you already have an error, choose evaluation failure;
- if evaluation succeeds and the question is "why this value?", choose provenance.
