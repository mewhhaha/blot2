# Same-owner particle runtime fixture

This private fixture places one frozen particle input and one output builder in
separate ranges of a single pool owner. Before entering the worker, its wrapper
checks their concrete extents against the owner's requested allocation and
current frontier. For nonempty input and output ranges, it rejects an output
range beginning inside the input. Checks happen before output writes or
initialized-length publication. The checked worker evaluates both F32 row
arguments before either output store, and advances the initialized length only
after both fields have been stored.

The source experiment recognizes the bounded `particle_lower` declaration and
expression subset. The final target checker independently reconstructs the
worker from that checked source, and compares the setup, preflight, and
lifetime helper bodies to the reviewed fixture snapshot. It is not a general
Wasm validator or a source-level compiler qualification.

The fixture exposes descriptor lifecycle operations: `input_end` ends the
frozen input descriptor, `output_end` ends a live builder or frozen output
descriptor, and `input_discard` aborts a mutable input without freezing it.
`close` rejects while either descriptor is live. These are fixture-state
transitions with host-visible memory; they do not authenticate K1 capabilities,
enforce all lexical loans, or prevent a host from forging descriptor state.
Input initialization, actual source-level ownership and lifetime, global pool
metadata integrity, and caller discipline remain assumed. A temporary input
read ending inside the worker does not end the underlying frozen View loan.

The exported interface is a raw test ABI, not the public K1 ABI or a complete
M12 invocation. It has no canonical host windows, invocation-region resource
certificate, full cleanup/poison model, or general source-callable admission.
Arithmetic NaN tests cover classification, not the complete allowed payload
and sign set. No complete I08, M12, M13, or compiler qualification is claimed.
