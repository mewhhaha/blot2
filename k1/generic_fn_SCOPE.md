# Private source-bound callable spelling experiment

Accepts one complete noncapturing U32-to-U32 declaration whose callable type is either `U32 -> U32` or `Fn[static, Many, U32, U32]`, followed by the explicit empty effect row and numeric resources. It checks the underlying scalar or finite-loop body using the existing source-bound compiler validator. Header byte positions and exact expected original source are reconstructed before emission; the canonical projection only feeds the existing private body frontend.

Status 0 means accepted by this limited fixture; status 1 means the header is malformed or outside this subset, and body failures retain the existing compiler fixture's private status. These are not a complete K1 diagnostic taxonomy. The producer invokes the same header reconstructor that the verifier later replays; it is not an independently implemented header parser.

Nonempty effects, other argument/result types, Once, non-static callable lifetimes, generics, predicates, captures, multiple declarations and multiline headers are unsupported. The inherited body frontend requires a `do:` block and rejects single-line bodies such as `fn x => return x`. Claimed source resources are recognized but are not independently verified against actual frame/call usage. No public ABI, artifact qualification, full resource or C09 accounting or general K1 admission is established.
