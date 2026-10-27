# Private disposition versus six-parser replay

This scratch campaign compares the prior six-parser-replay routing path with a
candidate that records whether an earlier frontend recognized source during
its original dispatch. It avoids repeated recognition on the rejection edge.
Both paths use the same source bytes, 64-compilation driver, target protocol and
one native Goose `-O2` benchmark binary. The candidate changes four production
modules, so the previous versions are mechanically namespaced inside that
binary and share only the unchanged Result type. Independent read-only review
confirmed the baseline chain calls the old versions. The namespaced baseline
also matched the previous frozen six-replay binary on all eleven cases.
Namespace, code-layout and compiler-optimization effects remain possible.

Preflight and every measured batch matched exact status, argument/result tags
and Wasm bytes for all six accepted and five rejected cases. Every accepted
module independently instantiated in Node and passed a bounded value oracle;
inputs, outputs and Wasm hashes are in `results.json`. Two of the
accepted identity cases were not eligible for the *earlier* previous-versus-new
frontend benchmark, because the older dispatcher rejected them; they are valid
here because six-replay and disposition both accept the exact same artifact.
The 11-case corpus is not a full language proof or ABI qualification.

One idle-host campaign used CPU 0, three warmups, 25 alternating pairs per
case, and 64 compilations per fresh process. The timed wall interval includes
process startup, one source read and repeated per-result equality checks; Node
witnesses are outside timing and the filesystem cache is warm. Raw output
records every wall/user/system CPU and peak-RSS sample plus variant order.
Cgroup `nr_throttled` and `throttled_usec` were unchanged (33 periods elapsed);
external host activity, CPU-frequency and scheduler changes are not excluded.
Ratios are candidate / six-parser replay, and p10/p90 are linearly interpolated.

| Case | Outcome | Replay median | Disposition median | Ratio median | Ratio p10–p90 |
| --- | --- | ---: | ---: | ---: | ---: |
| Bool branch | accepted | 1.990 ms | 1.983 ms | 1.002 | 0.949–1.059 |
| Bool identity | accepted | 5.456 ms | 5.212 ms | 0.960 | 0.896–0.982 |
| U32 identity | accepted | 12.348 ms | 8.682 ms | 0.714 | 0.694–0.768 |
| U32 comparison | accepted | 1.703 ms | 1.677 ms | 0.991 | 0.952–1.155 |
| U32 loop | accepted | 3.476 ms | 3.478 ms | 1.004 | 0.972–1.057 |
| U32 wrapping add | accepted | 2.900 ms | 2.853 ms | 0.995 | 0.935–1.022 |
| Invalid effect | rejected | 1.308 ms | 1.170 ms | 0.902 | 0.839–0.945 |
| Missing return | rejected | 3.145 ms | 2.762 ms | 0.883 | 0.813–0.943 |
| Invalid type | rejected | 2.793 ms | 2.527 ms | 0.917 | 0.868–0.985 |
| Unbound name | rejected | 9.635 ms | 5.901 ms | 0.608 | 0.587–0.661 |
| Unproved addition | rejected | 10.017 ms | 6.139 ms | 0.626 | 0.565–0.659 |

For the strongest effects, previous-first/candidate-first median ratios were
0.715/0.714 for U32 identity, 0.612/0.606 for unbound and 0.618/0.631 for
unproved addition. First-12/last-13 medians were 0.709/0.717, 0.597/0.611 and
0.625/0.626 respectively. Other accepted cases overlap parity. These numbers
show a narrow reduction in redundant private routing work for this corpus; they
are not a full compiler speed claim. The current paths lack complete C09
instrumentation, so this experiment does not establish equal semantic receipts.

`results.json` preserves all 550 raw sample rows, source and
artifact hashes, exact case order and preflight details. CPU quota/stat snapshots,
Goose benchmark driver, both measured dispatch source sets, the corpus, Node
witness and paired harness are included. `source-manifest.json` records hashes
of the copied source/stdlib, Goose/GCC and generated C. The native compiler
binary and full dependency source snapshot are **not included** in this
repository record; hashes alone cannot reconstruct them. The original scratch
snapshot and binary were at `/tmp/k1-disposition-benchmark/` while the temporary
workspace existed. Runtime/linker provenance was not independently
authenticated. Absolute paths and scripts are archival and may not work
elsewhere.

The included Wasm witness artifacts can be rechecked without a compiler or
timing campaign by running `node witness.mjs artifacts CASE` from this directory,
using one of the six accepted case names in `results.json`.
