# OxCaml compiler rebuild

This directory is an independent, opt-in rebuild of Blot's compiler. The Bend
compiler remains the default and the compatibility oracle until the replacement
passes the existing language, Wasm ABI, and incremental-session tests. Nothing in
this branch should silently fall back to Bend or claim parity from smoke tests.

The initial commit establishes native build/test plumbing. Subsequent commits on
the same PR implement and test the compiler. The authoritative starting point is
`832e92be7ef227be202771d582d4cdd16967561f`; `../guide.md`, the source prelude,
and the existing compiler tests define the executable language, not the wider
editor grammar.

## Build and test

Install OxCaml using the official instructions at <https://oxcaml.org/get-oxcaml/>:

```sh
opam switch create 5.2.0+ox --repos ox=git+https://github.com/oxcaml/opam-repository.git,default
eval $(opam env --switch 5.2.0+ox)
make -C compiler/oxcaml test
```

Only the standard library is used. CI builds with the actual OxCaml toolchain;
ordinary OCaml is a supplementary portability check, not an OxCaml substitute.

## Compatibility gates

- Source syntax, imports, source prelude, tags, and source-defined operators.
- Rank-1 inference, nominal data, patterns, closures, and source effect providers.
- Bounded constant evaluation and deterministic diagnostics.
- Wasm exports, the `blot:abi` contract, arrays and explicit host callbacks.
- Incremental edits, cache invalidation, and success-only cache publication.

The default compiler will not be switched before these gates have executable
coverage. Build and compile timings must be reported separately, with the same
input programs and observable results.
