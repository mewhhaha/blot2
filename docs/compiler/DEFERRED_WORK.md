# Explicit deferred work

Memoized demand parameters, demand types and `@demand` have been removed. `and`
and `or` are primitive short-circuit operators. Other deferred work uses
ordinary Unit callbacks, and explicit local bindings share a computed value.

`Maybe.unwrap_or_else` and `Result.unwrap_or_else` now take a Unit callback;
calling a callback again evaluates its body again. There are no implicit memo
cells, force runtime operations, demand lowering reports or `explainDemands`
project options. Typed Code carries its latent effects on an ordinary
Unit-to-Unit function type.

The previous
[demand design](https://github.com/mewhhaha/blot2/blob/742f1cae8c76c8380716e17d78ff6ec5f11da681/docs/compiler/DEMANDS.md)
and
[callback memo experiments](https://github.com/mewhhaha/blot2/blob/742f1cae8c76c8380716e17d78ff6ec5f11da681/docs/compiler/KNOWN_CALLBACK_MEMOS.md)
remain pinned historical evidence. They do not describe the current compiler.
