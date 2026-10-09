# Variable-indexed inference work

Production schedules inference regions with more than eight constraints or eight
data aliases through variable-indexed worklists. Smaller regions keep bounded
scans. This record states the contract and its qualification; it does not claim
the compiler-wide CPU or allocation targets.

## Order and ownership

Each inference region owns separate constraint and data-alias queues, allocated
together behind one pointer the first time a solver step sees more than eight
constraints or eight data aliases. A region that grows past either bound while
scanning switches before its next whole pass. New work runs in append order. A
write can wake later work in the current pass; earlier work waits for the next
pass. Aliases reach their fixed point before the next constraint pass. The
transfer rules and source diagnostic order remain shared with the scan
implementation, retained as a differential oracle.

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
watches an external completion event. Every solver step wakes that event on
entry, which covers both the ordinary caller resuming after a queue drain and
the summary stack resuming a parent job directly after a child completes.

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
`build/bench/indexed-solver/`. The candidate passes 35 focused inference checks
and the additional chain/ownership filter. A 64-link reverse constraint chain
takes 127 visits, compared with 2,080 in the scan oracle. Reverse data aliases
reach the same result; queue refresh, rollback, effect writes and
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
Seven pairs measure 947/934 ms fresh CPU, 1,110/1,090 ms population, 250/260 ms
first edits and 230/230 ms subsequent edits. The restart batch measures
1,042/1,037 ms cold population, 653/659 ms restart, 1,100/1,090 ms retained
population, 250/250 ms first edits and 220/220 ms subsequent edits. All byte
comparisons pass. These loaded-host results are mixed across phases.

The initial queue filter did not discover the standalone queue module's tests.
Production integration adds its explicit comptime import. The corrected filter
passes 18 checks, including discovery, and actually exercises all queue laws:
future clocks, physical edits, saturation, frontier bounds, recycled watch slots
and work appended after a pass. The earlier filter result is not evidence for
those standalone laws.

The broader cost check prevents accepting this version. The annotated 128-link
chain grows from 6,348,654 to 7,442,090 requested bytes, despite almost
unchanged constraint visits. Allocating queue state in many small regions
outweighs its benefit there. The full native runs and production integration
decision remain pending; the initial timing result does not complete the task.

A follow-on candidate allocates both worklists behind one region-owned pointer
only after the region exceeds eight constraints or eight data aliases. Smaller
regions use bounded scans. A region that grows during solving switches before
another whole pass. This keeps the same transfer rules, source order and
complete dependency watches in larger regions. Thirty-nine focused native checks
pass, including the small-region transition and allocation failures.

Its first allocation screen compared a debug candidate with the release
baseline. The apparent 6–11% reductions came from the build mode, not the
scheduler, and are withdrawn. The release comparison follows.

## Production qualification, 9 October 2026

The lazy representation is accepted on top of `34c881b`. The production release
`d04f4246c48a49fbaf14978cd54485171bc3df76eb9446bea9b8c4b106a92689` and debug
build `c56bb08fec1f27417f1f538d672d74c768005ac0a93b5d0e26e8992f2cfd94ee` are
pinned in `build/bench/indexed-solver-lazy-release/`. Its `manifest.json`
records source hashes, the source patch and every evidence file. The comparison
baseline is the composite-cache release
`0e78ed2c1e6343c41fb92cc1565fc0f11ffa007a74ca869826cf67307ddcb78d`.

Zig 0.17.0, the full native suite and all 598 guest/client tests pass. The
analyzer reports zero findings across 290 Zig files. The 305-case corpus (610
invocations, 244 successful cases) matches the baseline for both the debug and
release candidates: diagnostics, constant steps, code instances and Wasm are
identical, and no case leaves live compiler memory. Both compilers report the
same `TypeLimit` for the 2,048-link logical alias fixture.

Release-to-release requested allocation is essentially unchanged on the budget
workloads. The annotated chain moves from 6,348,834 to 6,350,930 bytes, the
generic chain from 6,675,554 to 6,677,666, the diamond from 3,455,418 to
3,455,738 and fanout from 11,210,131 to 11,170,567. The lazy representation
removes the first candidate's 17% chain regression without reducing allocation.
Fanout falls from 3,095 to 2,582 constraint visits and from 1,312 to 1,311
passes; its budget is tightened accordingly.

On gdev, constraint visits fall from 35,215 to 29,679 and passes from 3,889 to
3,883. Requested allocation falls from 321,082,488 to 319,651,956 bytes,
allocations from 960,941 to 956,838 and peak requested memory from 78.9 to 78.0
MB. Wasm is identical, at 622,957 bytes.

An instrumented build, not production, attributes the remaining gdev visits. In
496 indexed regions holding 22,407 constraints, the solver makes 27,023 visits,
or 1.21 per constraint, since every constraint is attempted at least once. The
other 954 regions hold 1,644 constraints and take 2,656 bounded-scan visits.
Body collection woke all unresolved work 2,101 times; rollback or physical edits
1,100 times; and the fallback phase 37 times. Only 57 of 7,144 refreshed watches
were broad, and no frontier exceeded its discovery bounds. The probe patch and
counts are `visit-probe.patch` and `gdev-visit-probe.log`.

Seven alternating no-cache pairs measure baseline/candidate medians of 633/623
ms fresh CPU, 730/720 ms population, 150/150 ms first edit and 130/140 ms
subsequent edit. Five of seven candidate fresh samples are below the baseline
minimum. Twenty-one pairs under heavier, varying load measure 660/659 ms fresh,
770/760 ms population, 160/160 ms first edit and 140/150 ms subsequent edit;
subsequent-edit means are 153.3/150.5 ms, so the one-tick median difference is
within the 10-ms accounting resolution. The restart batch measures 691/682 ms
cache population and 390/397 ms restart. No-op samples are at the accounting
limit. Every fresh/retained/restart and cross-compiler byte comparison passes.

These measurements show fewer solver visits and slightly less allocation with no
CPU regression outside accounting noise. They are not a compiler-speed claim.
Remaining limits: regions with at most eight constraints and aliases scan them
on every pass; body collection, rollback, physical edits, saturated clocks and
the fallback phase wake all unresolved work; and effect-argument recovery,
source-witness comparisons and oversized frontiers keep broad write watches.
