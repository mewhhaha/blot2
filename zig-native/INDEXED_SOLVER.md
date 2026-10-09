# Variable-indexed inference work

The implementation is being qualified in an isolated checkout. Production still
uses the existing scan scheduler. This record describes the candidate contract;
it does not claim completion of the scheduling or compiler performance targets.

## Order and ownership

Each inference region owns separate constraint and data-alias queues. New work
runs in append order. A write can wake later work in the current pass; earlier
work waits for the next pass. Aliases reach their fixed point before the next
constraint pass. The transfer rules and source diagnostic order remain shared
with the scan implementation, retained as a differential oracle.

The queue owns numeric work IDs, ready bits, and reverse dependency links. It
does not retain pointers into growing solver or constraint arrays. Removing or
refreshing a work item unlinks its old watches and recycles their slots. Region
teardown releases every buffer, including partial allocation-failure state.
Publication and persistent evidence never contain this scheduling metadata.

## Waking work

An unresolved item watches the normalized type variables and effect tails of its
actual solver inputs. Type and effect version records wake the corresponding
reverse indexes. Multiple writes coalesce into one ready bit. Rechecking an item
replaces its frontier so aliases and newly exposed tails remain observed.

Input roles matter. A call summary's `right` field contains a source type ID; an
invocation's `right` is a flag. Neither is a solver type. A call summary also
watches an external completion event. That event is checked both when the
ordinary caller resumes and when the summary stack resumes a parent job directly
after a child completes.

Rollback and physical type/effect mutations wake all unresolved work before any
recycled ID can be consulted. Saturated generations retain this conservative
behavior. Future type views watch the shared history clock. Collecting more
source bodies also wakes unresolved work because source witnesses can change
without a new substitution. Effect argument recovery and source-witness
comparisons retain broad write watches for dependencies outside their explicit
type roots.

Frontier discovery bounds work at 1,024 visited nodes, 256 pending roots and 64
distinct dependencies. A larger frontier or a non-allocation discovery failure
uses a broad write watch. Discovery cannot report an earlier semantic error than
the authoritative constraint attempt. The fallback phase still revisits all
unresolved constraints before one-sided dispatch inference and the final error.

## Initial qualification, 9 October 2026

The development pin is
`11d9c64417b14edfee2710fd05de97c2df719d4c8bf8947bb096aacd24fab81c`, in
`build/bench/indexed-solver/`. The candidate passes 35 focused inference/queue
checks and the additional chain/ownership filter. A 64-link reverse constraint
chain takes 127 visits, compared with 2,080 in the scan oracle. Reverse data
aliases reach the same result; queue refresh, rollback, effect writes and
allocation-failure cleanup are exercised separately.

The analyzer reports zero findings across 290 Zig files. The corpus comparison
passes 305 cases, comprising 610 compiler invocations and 244 successful cases,
with identical diagnostics, semantic results and Wasm. Thirty-nine execution
laws pass across call summaries, callback/qualified rows, captured callables and
demand forwarding, including synchronous and JSPI cases, dependencies,
checkpoints, failed edits and recovery.

Release `fdecd300af46f8b03ee7c9593b5b610db529a435b10ed43695dc973c057b524f` is
pinned in `build/bench/indexed-solver-release/`. All 598 guest/client tests
pass. Three initial gdev pairs measure 976/932 ms fresh CPU, 1,110/1,100 ms
population, 260/260 ms first edits and 230/230 ms subsequent edits,
baseline/candidate. Constraint visits fall from 35,215 to 29,641 and requested
allocation from 321,088,050 to 319,804,618 bytes. Every byte comparison passes.
These are loaded-host screening results; seven-pair and restart qualification is
still running.

The full native runs and production integration decision remain pending. No task
completion claim follows from the reverse-chain or initial timing results.
