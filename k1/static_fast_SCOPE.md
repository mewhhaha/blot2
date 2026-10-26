# Optional private static-evaluation cache

`static_fast_entry` offers an optional source-bound path through the existing
private static-product parser and evaluator. The baseline remains available.
For every invocation, the verifier replays the exact source and may reuse a
previous independently verified scalar syntax result only when the component's
complete source bytes and type match. The evaluator retains the first two
independently verified scalar trees for exact-byte/type matches; every component
is still evaluated in source order and charged against the existing fixture
step and output-byte budget. Cache state is local to one invocation. Failures
return no partial value.

The optional `build_image` passes its result through the existing independent
`static_publish_verify` source/value checker before returning an image. This
recheck executes the baseline evaluation again. The isolated evaluation-phase
measurement below does not include that recheck, source parsing, target
emission, host linking, or native compilation. No speedup for complete
`build_image` or public compilation is implied.

Run `GOOSE=/path/to/goose GOOSE_HOME=/path/to/goose-home python3
k1/static_fast_bench.py` to reproduce the paired private-phase experiment. It
builds one O2 native binary containing both implementations, checks complete
output-byte and step equality, performs four warmup pairs, and records 31
alternating pairs for both repeated and unique 8,193-row arrays. It records
raw samples, source/binary hashes, machine load and available CPU-throttling
counters. One run's complete record is in
`measurements/2026-10-26-static-cache/raw.txt`.

On that run, repeated fields had baseline p10/median/p90 of
24.497/24.694/24.928 ms and candidate 1.107/1.112/1.135 ms; paired speedup
p10/median/p90 was 21.687/22.106/22.431×. For all-unique fields, baseline was
25.003/25.194/25.471 ms and candidate 25.080/25.275/25.547 ms; paired speedup
was 0.979/0.994/1.014×, a median regression of about 0.6%. The cgroup reported
no throttling during the run. These are isolated fixture measurements, not a
comparison against the previous compiler or a guarantee for other workloads.

The baseline and cache do not implement the full C09 semantic-visit receipt.
A qualified pipeline must charge required logical work consistently even when
physical checks are reused. Static Domain authentication, public compilation,
and the remaining K1 static-evaluation features are outside this experiment.
