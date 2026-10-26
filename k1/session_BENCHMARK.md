# Private scalar-session benchmark

`session_bench.goose` and `session_bench.py` compare only this repository's
private scheduled scalar fixture in two situations: a newly initialized
session performing fresh compilation on each request, and an already primed
same-process session reusing an exact source/observation match. This does not
compare K1 against the legacy compiler, exercise a public project protocol, or
measure generated-kernel runtime. The source is the exact scalar identity in
`session_bench.goose`; each run writes and verifies its source and Wasm bytes.

With the pinned Goose and Node available, run a non-timing correctness preflight:

```sh
GOOSE=/path/to/pinned/goose GOOSE_HOME=/path/to/goose-home \
  python3 k1/session_bench.py /tmp/unused.json --preflight-only
```

When the host is otherwise idle, run the measured benchmark:

```sh
GOOSE=/path/to/pinned/goose GOOSE_HOME=/path/to/goose-home \
  python3 k1/session_bench.py /tmp/private-session-samples.json
```

The harness builds one `-O2` executable, checks source and output hashes,
executes an independent Node identity witness, and checks one untimed warm and
fresh request. It then runs four warmup pairs and 31 measured pairs, alternating
the order. Each process reports a monotonic-clock interval for 200 operations.
Every iteration checks its output against the same baseline and checks
fresh/hit counters and partial work counters. Every sample's source and Wasm
hash is checked against the preflight. Ordered raw elapsed samples, paired
ratios, toolchain/binary/source hashes, CPU metadata and before/after cgroup
CPU counters are written to the requested JSON file. The p10–p90 interval is
sample spread, not a confidence interval.

Fresh timings include construction and initialization of a new session on
every iteration, plus the private compiler's fresh checking, plan derivation,
target emission and target revalidation. Warm timings reuse one session but
still revalidate source-to-plan association, executable bytes and canonical
fixture metadata. Both modes include per-iteration output/counter assertions.
Consequently this is an instrumented microbenchmark of those exact paths,
including different session setup costs; its ratio is not a production compiler
speedup. It does not itself monitor other processes or guarantee an idle host.
The work receipts are partial and do not establish complete K1 policy parity.
No benchmark result is claimed until the measured command is run and reviewed.
