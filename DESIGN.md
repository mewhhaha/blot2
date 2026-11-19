# Blot design direction

The [language guide](docs/language/guide.md), the compiler's recorded
references and guest tests, and `std/` describe the executable language. This document records the intent behind the
current work; [CONTINUE.md](CONTINUE.md) records what has actually been
qualified.

Blot compiles to WebAssembly through one handwritten compiler, written in
Goose. Semantic
checking, compile-time evaluation and Wasm emission belong there. The Deno and
Tree-sitter parsers serve source tools and editor highlighting.

The language combines inferred types and effect rows, ordinary generic
functions, pattern matching, nominal types, statically selected associated
operations and compile-time evaluation. Runtime values retain their snapshot
meaning across rebinding. Mutation is explicit in named storage; borrowing and
copying expose its lifetime and cost.

Primitive `and`/`or` short-circuit; ordinary Unit callbacks express other
deferred work. Memoized `~` parameters/types are retired. Immutable `List T`
remains a build/concat/traverse collection;
[packed sequences](docs/compiler/PACKED_SEQUENCES.md) are the next
representation pilot. Arrays retain indexed mutation.

The target memory model uses named owners, invocation-local borrows, inline
scalar/record layouts and explicit copies. Host and worker boundaries exchange
copied packets. Keep small values simple and remove representation work before
adding optimizer machinery. The older counted backend remains live until
[task 120](tasks/120-retire-counted-storage-and-language-tasks.md) completes.

Compilation and edit-to-running-game latency are primary product requirements.
Prefer shared semantic shapes and bounded analysis over repeatedly expanding
physical values. Any optimization must preserve checked authority, effect order,
trap behavior, numerical bits and real application budgets.

Ordinary `#run` functions can read declared build inputs, build lookup tables
and return a function that closes over the resulting data. The public
declaration supplies the name. Reflection and quotation-based code generation
remain open. Binary operators select an implementation on the left operand.
The export-signature experiment checks written public contracts while letting
private helpers infer.
Language tasks are retired from the target model; isolated host workers remain.

The earlier proposal catalogue is available in the
[pinned design history](https://github.com/mewhhaha/blot2/blob/541ff890f1df53b5fe8572bd7f2bc41230f2fddb/DESIGN.md).
Its alternative spellings and unsettled choices do not override the current
language guide or ownership contract. Active requirements remain in
[PLAN.md](PLAN.md) and [the rewrite tasks](tasks/STORAGE_REWRITE.md).
