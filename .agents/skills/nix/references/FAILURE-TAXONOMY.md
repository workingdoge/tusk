# Failure taxonomy

Use this after you already have a concrete failing installable or a raw trace.

## 1. Missing attribute
Typical shape:
- `attribute 'x' missing`

Likely causes:
- wrong output path
- misspelled attribute
- wrong flake domain or class
- expecting a Den aspect/class to resolve into an output it does not provide

First moves:
1. inspect flake topology with `scripts/probe-flake.sh`
2. confirm the exact installable path
3. inspect the attrset immediately around the missing attribute

## 2. Option does not exist
Typical shape:
- `The option '...' does not exist`

Likely causes:
- wrong module system (NixOS vs Home Manager vs Darwin)
- module not imported
- outdated option path
- Den class mismatch causing the configuration to land in the wrong domain

First moves:
1. confirm the domain (`nixos`, `darwin`, `home`)
2. inspect the module import or aspect route
3. probe the realized config path only after the output path is known to exist

## 3. Type mismatch
Typical shape:
- expected set/list/string/bool/int but got another kind of value

Likely causes:
- wrong merge shape
- passing a function where a realized value is expected
- returning the wrong payload shape from an aspect
- mixing list and attrset style APIs

First moves:
1. reduce to the smallest expression producing the value
2. inspect the immediate producer, not every downstream merge
3. if the result is not JSON-representable, narrow further and use `nix repl`

## 4. Infinite recursion
Typical shape:
- `infinite recursion encountered`

Likely causes:
- circular dependence through `config`
- imports depending on values that themselves depend on imports
- self-reference through flake outputs
- context transitions depending on data that only exists downstream

First moves:
1. identify the cycle boundary
2. remove one layer and re-evaluate
3. look for `_module.args`, `config`, or self references in the smallest scope

## 5. Path / import failure
Typical shape:
- file not found
- cannot import
- no such file or directory

Likely causes:
- wrong relative path
- wrong root assumption
- stale lockfile or input mismatch
- path computed from unavailable inputs

First moves:
1. inspect the literal path
2. confirm the working root
3. only then reason about architecture

## 6. Non-JSON evaluation result
Typical shape:
- `cannot convert function to JSON` or equivalent

Likely causes:
- probing too high in the value graph
- asking `nix eval --json` for a function
- querying a module/function instead of a realized value

First moves:
1. target a deeper concrete attribute
2. switch to `nix repl` once the surface is already narrow
