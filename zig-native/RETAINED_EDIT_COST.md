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
  decision.
- Constant evaluation is 26 ms above `f7be6e7` (closure specialization in
  retained constants); constant evaluation and serialization together, about 270
  ms, belong to the [retained constant work](CONSTANT_REUSE.md).
- Fragment lookup, assembly and journal freezing add about 27 ms; they were not
  profiled further.
- Certificate images are full structural images, not digests, so retained memory
  grows with program size.

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
