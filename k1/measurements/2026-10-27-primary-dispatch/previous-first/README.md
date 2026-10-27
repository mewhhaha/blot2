> Archival copy: commands below refer to the original temporary workspace. The exact compiler binary and full source snapshot are not included here; see the top-level RESULTS.md before attempting reproduction.

# Private primary dispatcher before/after experiment

This is a **private fixture** comparison, not a public K1 compiler benchmark or
complete C09 validation. The same native Goose binary contains both existing
`typed_dispatch::compile` and the proposed `primary_dispatch::compile`; a
command-line mode selects the implementation. Both receive the exact same
immutable source bytes and output protocol. The binary was built once from the
copied scratch sources with Goose `ga108677d`, default `-O2`, without `--debug`.
The generated C, Goose binary, all copied `.goose` files, Goose stdlib files and
C compiler executable are hashed in `preflight.json`. Host dynamic libraries,
linker and full build provenance are not authenticated. A changed candidate or
new revision requires a new frozen snapshot, native build and preflight.

`preflight.py` runs each side once without timing. It requires identical status,
argument/result tags and complete Wasm bytes for every previously successful
case; it also checks that cases rejected by both have identical statuses and
empty bytes. An old-success/new-failure, changed previously accepted output,
or changed rejection status makes the preflight fail. Positive cases must be
accepted by primary; named invalid cases must be rejected by both. Every
successful Wasm module must instantiate without imports and match a separate
bounded input oracle. The exact source bytes and result hashes are recorded.

Current preflight corpus: four exact `both_accepted` U32/Bool/loop programs,
five exact `both_rejected` cases and two `primary_only` successes. A speed
comparison is meaningful only between the nine exact-parity cases. The two new
successes are reported separately and excluded from paired ratios; comparing
an old rejection with a new compilation would be misleading. The 64-bit semantic
work receipts are incomplete for these paths and are not made equal by this
harness: the implementations perform different checks, and successful results
and byte parity do not establish equal work, effects, loans, C09 or full
qualification. Rejected-source correctness is tested only for this small corpus.

Run without any timing:

```sh
python3 /tmp/k1-primary-benchmark/paired.py \
  --out /tmp/k1-primary-benchmark/new-preflight --verify-only
```

After all suites have finished and an idle CPU is explicitly assigned, run:

```sh
taskset -c 0 python3 /tmp/k1-primary-benchmark/paired.py \
  --out /tmp/k1-primary-benchmark/new-measurement --measure --warmup 3 --rounds 25
```

Capture `/sys/fs/cgroup/cpu.max` and `cpu.stat` immediately before/after the
whole campaign. Run only if CPU 0 is in the allowed affinity; choose another
allowed CPU otherwise. Reports store complete paired samples, per-child wall,
user/system CPU and peak RSS, case order and binary/source/dependency identities.
Each timed sample launches a fresh process, reads one source file, compiles it
64 times, checks every result against its first status/bytes, and prints the
result once. The controller then compares the sample bytes to the preflight
artifact. Source/target validation inside each call and equality checks are
included in the timing. Filesystem cache is warm; no cold-disk or sustained
project-build claim is warranted. Alternate variant and corpus order; report
per-case sample distributions and paired ratios, separately for accepted and
rejected inputs. Do not average them into an unrepresentative single score.
Changing the number of checks, the cache, process startup or output transport
can affect results; labels and confidence must reflect those boundaries.
