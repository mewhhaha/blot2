# Source-local particle capability experiment

This private, fixed-source experiment models one particle function body. The
compiler builds a source-owned trace over the independently recognized
`i08_job` expression and loop Core. The verifier checks the exact retained
source and trace, reconstructs the event associations, and interprets a held
builder, expression value uses, complete-row construction, append, loop carry,
freeze, and return. Every field read has an explicit begin/read/end sequence
bound to the checked input version, domain, index, and bounds proof. Append and
freeze require no such body-local transient read to remain outstanding. The
append and carry events require their checked loop evidence; this is a fixed
loop witness, not general invariant inference or general ownership checking.

The begin/read/end steps model **temporary reborrows and reads through the input
View**. Ending a temporary read does not end or consume the caller-owned View's
underlying immutable loan. That loan must remain live for the call; this
experiment has no authority to revoke or authenticate it.

Local numbers and source-local records are bookkeeping, not authenticated
capabilities. In particular, separate region, domain, and owner IDs do not
establish that runtime backing ranges are disjoint. The caller or checked
wrapper must establish actual immutable input, exclusive builder ownership,
disjoint backing, initialized extent, valid lifetime, and the precondition
`Le(n,c)` before a call. This experiment does not implement that call-site
provenance or obligation discharge. The separately emitted private wrapper
checks some raw descriptor geometry, but has caller-controlled memory and is
not an authority proof or public K1 ABI.

After this checker succeeds, emission uses `i08_job_wasm` and its independently
checked generated target. The finite F32 expressions and worker are a narrow
subset of I08; F32 NaN payload/sign qualification, actual loans and affine
arguments at callers, public host ABI, frame/resource certification, and M13
are not implemented here. No complete I08 or general compiler qualification is
claimed.
