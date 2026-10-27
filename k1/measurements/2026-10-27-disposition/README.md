> Archival copy: commands below refer to the original temporary workspace. The native binary and full dependency source snapshot are not included here; see RESULTS.md before attempting reproduction.

# Private disposition versus six-parser replay

This scratch comparison runs the previously checked six-parser-replay route
against the proposed disposition-recording route. Both modes share one native
Goose binary and receive the same source bytes and result protocol. Because the
candidate changes all four dispatch modules, the driver uses mechanically
namespaced copies of all four *previous* modules and the shared, unchanged
Result struct. The copied baseline matched the previously built six-replay
binary's exact result on all eleven preflight sources. Namespace/code layout
may influence native optimization; equal timing methodology does not establish
identical generated machine instructions or full compiler performance.

The previous and candidate mode report the same status, argument/result tags,
and Wasm bytes for six accepted scalar/Bool/loop cases and five rejected cases;
all 11 are eligible for paired samples. Successful artifacts are independently
instantiated and checked against bounded Node witnesses before timing. Every
64-compile batch also checks exact repeated results, and the controller compares
the batch output to preflight. The checks cover only this sample corpus, not a
complete semantic, fault, ownership, C09 or public ABI equivalence. Runtime
cache/warm-project behavior is not part of this fresh-process test.

`paired.py --verify-only --out PATH` performs no timing; after independent
review and explicit CPU idle clearance, `taskset -c 0 python3 paired.py
--measure --warmup 3 --rounds 25 --out PATH` captures paired raw wall/user/system
CPU and peak RSS samples. Case and variant orders alternate, each sample reads
one source once and compiles 64 times; process startup and byte comparisons are
included, filesystem cache is warm. Snapshot cgroup CPU quota/throttling before
and after the complete run. Record source/Wasm/compiler/dependency hashes and
Goose/C toolchain metadata as in the raw JSON, and disclose that host runtime,
linker and binary provenance are not fully attested. Report accepted and
rejected cases individually, and avoid a full-compiler or equal-C09-work claim.
