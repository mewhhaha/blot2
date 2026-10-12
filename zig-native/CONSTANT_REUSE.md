# Approved constant receipts

The owner approved this design and requested implementation on12 October2026.
Task086 is in progress; no constant-slot reuse is implemented or qualified yet.

## Current evidence

The current captured game has 93 units. At qualified implementation `2798ff9`,
an LLVM release profile of a retained scalar edit reports 51–53 ms in constant
work, 19 ms in value evaluation and 545–549 ms in inference. These phase clocks
are separate; they do not attribute all inference to constants.

A separate Fast/no-LLVM attribution build records 872 first constant visits per
real revision, including 662 value constants. One declaration accounts for
57,019 of the unchanged 70,330 total source steps and dominates the inclusive
constant clock. Four edit/revert phases retain exactly those counts. All six
fresh/no-op/edit/revert outputs match the ordinary release's Wasm and source
steps. This slower instrumentation build identifies work; its clocks do not
establish a release speedup. Raw pins and records are under ignored
`build/bench/constant-receipts/`.

## Publication authority

Add a dedicated owned constant receipt. Keep the existing source value-template
transport contract unchanged: transporting a representation alone grants no
constant-slot or callable proof.

A receipt records one successful ordinary constant evaluation: original
producer/declaration identity, exact initializer, published principal interface,
complete value graph, actual value/source/interface/provider reads, evaluation
options and source fuel. It records executed call judgments separately from
unapplied function values. It holds no AST, solver, prior Session pointer or
mutable owner.

An unapplied named closure may link to the current declaration under equal
identity, signature, rows and captures. That link grants no proof of its body:
later specialization and emission validate the current body through their
ordinary gates. A call executed during constant evaluation instead records its
body and transitive observations. A body edit cannot reuse that result.

Before publishing a hit, validate every recorded observation against the new
revision and reconstruct its graph into the current owner. Reuse shared current
constant anchors only after those constants have reached their ordinary ready
state. Remap all identities, captures and type/row evidence; never copy old
callable certificates or raw guest addresses. Serialize static data through the
current allocator and relocation path.

Debit exactly the recorded source fuel at the original evaluation position.
Nested reads need a fuel tape so already completed constants are not charged
twice and newly demanded constants keep ordinary order. A different limit or an
insufficient remaining budget declines the hit and takes ordinary evaluation,
preserving the failure location. Copy/proof work has its own bounded budget.

Reserve all publication capacity first. The final slot transition allocates
nothing. Failed validation, OOM and rejected revisions publish neither a partial
slot nor a new committed receipt owner. Preserve the previous revision.

## Initial admission and required checks

Admit only complete, successful immutable outcomes with complete read and fuel
tapes. Unknown observations, effects, providers, demands, generative state,
cycles, failures and exhausted proofs take ordinary evaluation until a separate
exact reconstruction law supports them. This is an initial scope, not task 086
completion for unsupported constant forms.

Required laws cover unrelated edits, changed actual reads and called bodies,
unapplied function body edits, shadowing/renaming and producer relocation,
provider/generative fallback, evaluation order, tight fuel limits, diagnostics,
failed-edit recovery, complete OOM sweeps and fresh/retained/restart byte
parity. Measure receipt traffic, retained live memory and total release CPU
against an ordinary no-receipt control. Keep a receipt only when validation and
copying pay for themselves. The final compiler/analyzer gate and task 086's full
coverage remain required.
