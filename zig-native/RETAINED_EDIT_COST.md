# Retained edit cost on a large program

Task 093 closes part of the gap between retained literal edits on the frozen
gdev copy and the compiler at `f7be6e7`, before call-summary jobs. Task 088 left
edits at about 570 ms of CPU against 400 ms there. The compiler milestone is
`aef65e79230e0dd9b6eddb76d93f5d53b0531a7b`.

## Attribution

Sampled profiles of 30 edits each (compile thread only), in milliseconds per
edit; before is the task-088 compiler:

| Phase                                                  | `f7be6e7` | Before | Candidate |
| ------------------------------------------------------ | --------: | -----: | --------: |
| Fragment lookup and admission (`State.find`)           |     14 ms |  72 ms |     26 ms |
| Fragment setup, including gate setup and module stamps |     22 ms |  59 ms |     45 ms |
| Certificate capture (`freezeValidation`)               |      0 ms |  31 ms |      3 ms |
| Constant evaluation (`Session.prepare`)                |    126 ms | 152 ms |    152 ms |
| Constant serialization                                 |    132 ms | 240 ms |    120 ms |

Three defects explained most of the growth:

- **Signature lookup.** [Fragment admission](src/reuse/artifact_fragment.zig)
  resolved each old function signature by scanning every old emission record. A
  one-time index from signature ID to its first record keeps interning lazy and
  in the same order, so emitted types are unchanged.
- **Value matching.** Each static read and aggregate constant matched its value
  graph with fresh arrays sized to every old and current value, then scanned the
  correspondence twice. Admission now reuses one bound `QueryScratch` through
  `matchIntoWithScratch`, and `Importer.recordValueAnchorIds` records only
  matched entries, sorted so they are inserted in the same order as the full
  scan.
- **Certificate budget.**
  [Dependency certificates](src/reuse/dependency_certificate.zig) shared a query
  table's 16 MiB budget. gdev's 82 module images take about 19.7 MB, so the last
  capture declined and the certificate was dropped. Every edit then
  re-serialized all images and revalidated every module's dependency graph,
  including its cycle check. Certificates now have their own 64 MiB budget;
  after the first edit 81 of 82 images are reused.

## Qualification on 11 October 2026

- Zig 0.17.0 before every build batch. `deno task test:compiler` passes the full
  LLVM native suite and 638 guest/client tests; `deno task lint:zig` reports
  zero findings across 310 files. All three changes preserve output: the
  existing retained/fresh laws compare bytes, and gdev regenerates the same 102
  functions per edit.
- Measurements, pinned in
  [the pins](qualification/retained-edit-cost-pins.json): three alternating
  triples on the frozen gdev copy at load 0.6–1.1
  ([CSV](qualification/retained-edit-cost-gdev.csv)).

| gdev, medians of edits 2–4 | `f7be6e7` | Before (`915b7e1`) | Candidate |
| -------------------------- | --------: | -----------------: | --------: |
| Retained edit CPU          |    400 ms |             570 ms |    440 ms |
| Inference per edit         |    196 ms |             238 ms |    234 ms |
| Fresh named functions      |       264 |                102 |       102 |
| Cold build CPU             |  1,470 ms |           1,150 ms |  1,140 ms |

Each change was paired separately: the signature index saved about 30 ms per
edit, value matching about 30 ms and the certificate budget about 40 ms.
Retaining the certificate raises the server's resident memory from about 154 to
173 MB and its peak from 224 to 232 MB, while each edit stops allocating and
discarding about 16 MB of images.

## Remaining scope

- Edits still cost 1.10× `f7be6e7`. Module stamping takes about 39 ms per edit:
  the importer and the gate re-hash every retained module to prove its pointer
  still names the pinned Core before comparing current structure. That is a
  deliberate integrity check; replacing it with owned lifetimes is a design
  decision. (On 18 October 2026 the owner approved generation tokens, CT18 in
  [the compile-time hills](../COMPILE_HILLS.md); the digest check is now the
  opt-in `validate_pins`.)
- Constant evaluation is 26 ms above `f7be6e7` (closure specialization in
  retained constants); constant evaluation and serialization together, about 270
  ms, belong to the [retained constant work](CONSTANT_REUSE.md).
- Fragment lookup, assembly and journal freezing add about 27 ms; they were not
  profiled further.
- Certificate images are full structural images, not digests, so retained memory
  grows with program size.

## Recreated-workload work audit — 20 October 2026

Reanalysis of the qualified task-053 release `1b05518e…` covers 108 game
observations across three strict parity rounds and 36 compiler/phase rows. It
reproduces all 18 earlier candidate CPU medians and 126 counter distributions.
The workload is the owner-approved recreated freeze, manifest
`4689301ed5ef13f9cce244a474fbe353ebfeceeb072101c85f6663995e0b0728`; its absolute
timings do not establish the lost original `f7be6e7` comparison.

| Candidate operation | CPU median (min–max), ms | Functions optimized | Functions reused | Largest region, scopes |
| ------------------- | -----------------------: | ------------------: | ---------------: | ---------------------: |
| Literal edit        |      3,908 (3,399–7,733) |               3,047 |            1,008 |                  1,078 |
| Literal revert      |      2,297 (2,141–4,216) |                   3 |            4,052 |                  1,078 |
| Body edit           |      3,982 (3,704–4,405) |                 763 |            3,292 |                  6,276 |
| Body revert         |      3,995 (3,083–4,837) |                  18 |            4,037 |                  6,276 |

Each row has three samples. Frontend body elaboration and lowering are zero in
all four rows. Literal edit and revert both emit 315 fresh named functions and
reuse 1,767; body edit and revert both emit 388 and reuse 1,694. Reducing
runtime reoptimization alone therefore does not account for the remaining edit
CPU. The three-round timings are descriptive and separate from the passing
preselected 15-pair CPU guard.

Runtime matching records about 1.62–2.25 million work units for these
operations, with one bounded matcher exhaustion on edits and none on reverts.
This counter includes a bounded relocation attempt and a separate linear
positional pass; exceeding one million is not evidence that the bounded attempt
ignored its limit. Transitive callee checks protect inlining, lifetime and
ownership facts. Their cost needs profiling before changing admission or its
budget.

Raw parity inputs remain in `build/bench/task053-catalog-package-parity/`; the
audited report is `build/bench/task093-task053-retained-work-audit.json`,
SHA-256 `06110a8a4c8c5d61d850c7f2bbaf4ab64f426d785247bccbb4811c7a53ae2647`.
These counters measure work, not phase CPU. Solver and scratch requested bytes
cover those owners only, not whole-compiler allocation or RSS. Task 093 still
requires current attribution and explicit justification of remaining costs; task
047's pending release measurements must be audited separately.

## Exact shared foreign owners — 15 October 2026

Private retained validation now follows physically shared transitive Core
owners, with exact current nominal/bound facts. A changed owner invalidates
every reverse observer, including dependency cycles. Scoped callers additionally
observe global invocation-catalog activation. Public ContextImage admission
remains unchanged. Scratch is invocation-local and bounded; exhaustion falls
back to fresh checking. Root direct/transitive/global full-OOM laws and
Source/archive execution pass, alongside six unchanged public-context negative
controls and zero analyzer findings. Evidence is in
`build/bench/finish-rest-20261015/dependency-owner-memo-integration/`. Release
captured-project timing and the total edit/allocation targets remain open;
structural reuse counters do not establish a speedup.

## Long-session and checkpoint recovery, 23 October 2026

The LLVM compiler from `4091cb2` (unchanged compiler source in `8d73aa8`) passes
64 distinct scalar edits on the 583-file frozen workload, with one
codegen/semantic worker and profiling enabled. All 64 outputs have distinct
hashes. Edits 1, 16, 32 and 64 match independent fresh builds; an invalid edit
after 32 is rejected and recovery restores the prior valid bytes. Final revert
and an actual checkpoint-loaded restart both preserve the original bytes.

| Edit | Child CPU, ms | Current child RSS, MiB | Child high-water RSS, MiB |
| ---- | ------------: | ---------------------: | ------------------------: |
| 1    |        1494.8 |                  323.7 |                     447.1 |
| 8    |        1275.5 |                  325.1 |                     447.1 |
| 16   |        1312.3 |                  325.8 |                     447.7 |
| 24   |        1192.4 |                  326.5 |                     449.1 |
| 32   |        1208.8 |                  327.1 |                     450.4 |
| 40   |        1734.1 |                  327.8 |                     488.4 |
| 48   |        1309.1 |                  328.3 |                     488.4 |
| 56   |        1190.1 |                  329.0 |                     488.4 |
| 64   |        1128.1 |                  329.6 |                     488.4 |

The last sixteen edits have 1,167.6 ms median CPU. Current RSS rises by about 6
MiB over the session; this does **not** demonstrate an RSS plateau or identify a
leak. Optimizer-retained bytes stay at 15,778,924. Region-retained bytes are
normally 6,680,792, with a transient rise to 57,225,552 at edit 40 that clears
afterward. Cumulative requested allocation, live owned state, allocator capacity
and RSS remain distinct measurements. The memory target is still open.

The checkpoint directory contains a 26.9-MB seed, a 24.9-MB checkpoint and
4.0-MB saved output. Independent copies with a flipped byte in each of
`.blotcache`, `.blotseed` and `.blotout` all fall back to valid work: restart,
changed-source build and revert match the known hashes. An unchanged copied
checkpoint also loads successfully. Raw cache payloads are not published.

The
[report and exact measured scripts](measurements/long-edit-recovery-2026-10-23.tar.gz)
pin compiler, source and library identities and retain all per-edit statistics
and corruption checks. This completes a longer correctness/recovery screen, not
all of issue 27's memory or latency requirements.
