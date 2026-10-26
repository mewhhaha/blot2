# Private same-region particle bridge witness

This fixture snapshots and validates one fixed particle wire record, reserves a
single private fixture owner, copies and freezes the input, places a disjoint
builder, calls the checked particle worker once, copies the result into new host
memory, ends both descriptor states and closes the owner. Test-only injected
failures exercise mutable input discard and cleanup; they are not source-level
language errors. The generated target is pinned byte for byte and its worker is
independently checked against the restricted particle source.

This does not implement the M12 host ABI or validate a general manifest. Its
numeric descriptors and source region symbols do not establish authentic source
capabilities or immutable loans. The restricted particle source checker
assumes distinct input and output backing regions; the disjoint ranges in this
one-owner witness have not been justified as a valid substitution for those
formal regions. This bridge therefore cannot admit that source-level call.
Host frame preflight, source-level error
recovery, shared-memory concurrency, complete arithmetic-NaN qualification and
an input-alias result are absent. The particle callable returns only its output
builder view. Mutable Wasm memory and trusted runtime invariants remain private
fixture assumptions; a Wasm trap poisons the fixture and requires disposal.
