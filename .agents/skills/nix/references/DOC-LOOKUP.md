# Doc lookup after local probing

Do **not** start here.
Use this file only after a local probe has narrowed the question.
Read `references/NIX-TOOLING.md` when the missing piece is command choice rather
than documentation choice.

## Rule of thumb
First ask:
- what fact am I missing?
- which local command could reveal that fact?
- only then ask which doc explains the fact.

## Routing table

| Question shape | Local probe first | Then read docs about |
|---|---|---|
| What does this flake export? | `scripts/probe-flake.sh .` | `nix flake show` semantics and standard flake outputs |
| What is the value of this config path? | `scripts/probe-config-path.sh ...` | the exact option or config path semantics |
| Why does this installable fail to evaluate? | `scripts/probe-eval.sh '<installable>' --show-trace` and `python3 scripts/classify-trace.py` | the failing language/module construct, not the whole manual |
| What does this Nix function / attrset / expression mean? | narrow scope, then use `nix repl` | the language or lib function docs |
| What is Den doing here? | inspect `den.ctx`, `den.aspects`, `den.hosts`, `den.provides` in the repo | Den core principles, context pipeline, and `den.ctx` docs |
| How should I write or restructure this in Den? | inspect the concrete flake outputs and local `den.*` declarations first | `references/DEN-AUTHORING.md`, then the exact official Den page |
| Is this about the running host, not the repo? | local host commands such as `nixos-option` on NixOS | the corresponding NixOS option / manual page |

## Preferred order for ordinary Nix questions
1. repo shape
2. flake output graph
3. focused evaluation
4. interactive REPL only if needed
5. docs for the exact semantic gap

## Preferred order for Den questions
1. detect Den markers in the repo
2. inspect the concrete `den.*` declarations involved
3. read `references/DEN-AUTHORING.md` if the task is about writing or reshaping
4. read the official Den docs at `https://den.oeiuwq.com/` for the exact layer:
   - core principles
   - context pipeline
   - `den.ctx`
5. only then translate into Premath language

## Anti-patterns
Avoid:
- grepping the whole docs tree before inspecting the repo
- reading many pages when one command would settle the fact
- using remote evaluation before local questioning is disciplined
