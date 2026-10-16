# Language qualification

The 15 October source freeze `3548546c…` passes 2,223 native laws, 1,404
guest/client tests and 1,366 complete allocation-failure sweeps, with zero
analyzer findings across 455 Zig files. Release SHA-256 is
`6a83bad5560ec1a82220dc834dd366646fb8ab10370f82b26a2bcb775111ae6b`. Exact
source, toolchain, executable, bundle, handshake and test pins are in
`build/bench/complete-program-20261015/final-proof-repaired-gate/qualified-pins.json`.
Later compiler changes require their own combined qualification.

The executable acceptance index is
`build/bench/finish-rest-20261015/language-acceptance/qualified-baseline.json`
(SHA-256 `8a7191ec053504d927b3b7df5cd2f840a8aacedb520b8c0da6ace08babeee009`). It
checks all 2,223 distinct native test names and the successful guest JUnit
report, then records the exact passing laws and guest source hashes for each row
below. Counts overlap between rows; they are not additional tests.

| Contract             | Qualified requirements                                            | Native laws | Guest tests |
| -------------------- | ----------------------------------------------------------------- | ----------: | ----------: |
| Scoped identities    | Fresh owners, routing, shadowing, forwarding, symbolic rows       |          96 |          14 |
| Scoped identities    | Aliases, dependent/generative contracts, multi-input callbacks    |          48 |          12 |
| Scoped identities    | Requests, cancellation, revocation, imported recovery             |          28 |           7 |
| Capability lifetimes | Closures, demands, aggregates, projections                        |          27 |          13 |
| Capability lifetimes | Sinks, opaque contracts, bounded diagnostics                      |          28 |           9 |
| Usage                | Moves, aliases, branches, loops, once/many                        |          39 |           9 |
| Usage                | Loans, sharing, qualified polymorphic calls                       |          28 |           5 |
| Resources            | Return/break/trap, host failure, suspended cancellation           |          36 |          10 |
| Resources            | Transfer, retirement, persistent journal, structural host roles   |          37 |          12 |
| Higher rank          | Structural rank, annotated recursion, skolems, bounded rejection  |          30 |          10 |
| Higher rank          | Row/region binders, predicates, associated evidence, dictionaries |          67 |          13 |
| Packages             | Sealing, heterogeneous carriers, openings, stored evidence        |          38 |          27 |
| Packages             | Resealing, associated payloads, captures, affine ownership        |          38 |          12 |

Source/archive/checkpoint/restart, failed edits, recovery, both compiler tiers
and sync/JSPI are exercised by the recorded guest groups. The index includes the
explicit affine universal identity, region-quantified loan reader, dynamic
universal dictionaries, qualified package destruction and ABI 7 structural
host-cleanup controls. Earlier subset notes in individual implementation records
describe their historical checkpoints.

Unannotated higher-rank inference, affine values hidden in unrestricted type
binders, unknown cleanup termination and unproved storage lifetimes remain
intentional rejections under the normative designs. A type spelling or physical
layout supplies no missing evidence. The separate typed-staging continuation
still needs closed pure scope evaluation and its final combined gate.

## Measured scope cost

Both controls return `[11,102,10,100]`: two closed static families versus two
fresh scoped State owners. Seven alternating compiler pairs use five fresh
processes per variant, disabled persistence and child user plus system CPU.
Median fresh CPU is 1.6322 ms static and 1.7874 ms scoped (ratio 1.0951).

Thirty-one warmed guest pairs per execution mode use 2,048 calls per sample,
including identical result copying. Median sync call cost is 1,181.7 ns static
and 1,489.6 ns scoped (ratio 1.2605); JSPI is 2,532.6/2,737.1 ns (1.0807). All
result checks pass and warmed memory stays flat.

Seven repetitions also separate retained-project phases. These wall times
include IPC and do not qualify the captured-project CPU targets:

| Workload       | Population ms | First edit ms | Revert ms | No-op ms | Restart ms |
| -------------- | ------------: | ------------: | --------: | -------: | ---------: |
| Static State   |        2.5374 |        2.1689 |    1.9133 |   0.8259 |     2.3010 |
| Scoped State   |        2.5223 |        2.5023 |    2.1602 |   0.8633 |     2.6269 |
| Resource scope |        1.8337 |        1.6419 |    1.4306 |   0.7313 |     1.8615 |

All phases preserve fresh/revert bytes. Exact inputs, executable identity and
every raw sample are in
`build/bench/finish-rest-20261015/language-contracts-v2/`.
