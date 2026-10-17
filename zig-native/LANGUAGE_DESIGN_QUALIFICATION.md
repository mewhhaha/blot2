# Language design qualification

Documentation checkpoint based on qualified main `ef57ec5`, isolated in
`/var/tmp/blot2-language-design-20261013`. Specifications 060/063/066/072 settle
source syntax, checking/lifecycle laws, owned portable evidence, compatibility,
diagnostics and accepted/rejected traces. They intentionally proceed ahead of
unfinished implementation dependencies. No implementation task is marked
complete.

Reviewed against [the current guide](../compiler/guide.md),
[ownership/semantic contract](CONTRACT.md), [scoped effects](SCOPED_EFFECTS.md),
[shared ownership](SHARED_OWNERSHIP.md),
[suspended ownership](SUSPENDED_OWNERSHIP.md) and
[demand completion](DEMANDS.md#completion-and-cancellation). Once is at-most-
once; demand retries cannot silently consume affine captures; raw Wasm traps use
host journals, not promised source unwinding. Packages/quoted code/tasks retain
borrow and capability footprints. Dynamic dictionaries and host task scheduling
have explicit ABI requirements. Ordinary syntax, arrows and opaque boundaries
keep their existing behavior until implementation qualification.

Validation: Deno 2.9.7 Markdown formatting plus local file/heading checks only.
The generated check log/pins are preserved in ignored
`build/bench/language-design-20261013/`. No compiler build, gate, benchmark or
runtime validation belongs to this documentation checkpoint. Each downstream
task still requires executable source/import/artifact/restart, failed-edit/OOM,
behavior and relevant CPU/memory qualification.
