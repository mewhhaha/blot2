# Retained replay state writing record

Full production first writing passes are present for reuse/artifact_fragment and
reuse/constant_receipt_reuse. These files have not been compiled, checked, run,
or qualified. No builds, tests, formatter checks, or compiler invocations ran.

Both provide initPooledRef/releasePooled and the backend's canonical initInto
surface. Their canonical State objects own copied Module header runs; the
constant state also copies the Pools header, and the fragment state copies the
Capture header. Nested graph storage is borrowed from the pinned typed owners.
State cleanup releases real typed pools, importers, retained gates and scratch.

Fragment admission preserves positive request memoization only for the exact
nonzero generator owner; full static value graphs remain live. The chronological
replay preserves child job skipping, source/body authority, signature/import and
runtime resource relocation, exact aggregate root bindings, symbolic operands,
semantic instruction sites, static bytes, solved mappings and scope receipts.
Serialized entries retain an O(n log n) address sort and binary searches.

Constant receipts retain source identity and generativity checks, exact input
and output evidence, scalar and aggregate replay, ordered reads, live queries and
judgments, alias topology and buffer frontiers, source fuel, debt and collection
mutation charges. Ordinary semantic failures decline; allocation failure remains
an error. Demand failure marks the ordinary retry path at the original event.

Source construction integration remains part of the writing phase. In
particular exact copied Module catalogs must be recognized by equal header
storage boundaries and nonzero owner IDs, since copying header arrays changes
the enclosing slice address. This grants no new source, effect or graph authority.
