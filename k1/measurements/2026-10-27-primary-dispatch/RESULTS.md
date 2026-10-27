# Private dispatcher routing experiments

Three exploratory campaigns compare the previous private dispatcher with three
proposed routes. The first tries the new source-owned frontend first; the
second tries the previous dispatcher first and falls back to the new checked
frontend on rejection. The final route additionally replays six parsers on
rejection to prevent fallback when an earlier frontend accepted but emission
failed. Each campaign places both its previous and proposed
function in the same native Goose `-O2` binary, feeds identical source bytes and
uses the same result protocol. The campaigns have different binary hashes;
ratios are paired **within** each binary, not comparisons of absolute times
across campaigns.

These records cover the exact routing sources included here. The previous-first
rejected-input measurements do not apply to the final six-parser-replay route.

This is not a full compiler benchmark or public K1/C09 qualification. The
paths can perform different source and target validation; byte-identical
results do not establish equal semantic work, ABI authority or safety
obligations. Source-byte and other required C09 telemetry remain incomplete.
The latter routes protect the previously accepted path but add fallback work
for previously rejected sources.

All preflights exercised the same 11 sources. Four U32/Bool/loop fixtures
were accepted by both paths with identical status, argument/result tags and
Wasm bytes. Five invalid or unsupported fixtures were rejected by both with
identical status and no Wasm. Node independently instantiated every successful
module and checked bounded witnesses. Two identity fixtures rejected by the
previous path but accepted by the candidate were recorded separately and
excluded from timing comparisons. This is a small test corpus, not a proof of
all input or failure cases.

Each campaign ran 25 paired samples after three warmups, pinned to CPU 0, with
alternating dispatch and case order. Each fresh process read the source once,
compiled it 64 times and compared every output to the first; the controller
compared each batch to preflight. Wall time includes process startup and those
checks. The filesystem cache was warm; Node witnesses were outside the timing.
Cgroup throttled periods and throttled time did not increase in any campaign.
Other-host contention, CPU frequency and scheduler effects were not eliminated.

Numbers are median paired wall-time ratios (candidate / previous), with
linearly interpolated p10–p90 in parentheses:

| Case | Outcome | New frontend first | Previous path first | Final replay |
| --- | --- | ---: | ---: | ---: |
| Bool branch | accepted | 5.632 (5.229–5.851) | 0.988 (0.933–1.029) | 1.009 (0.947–1.087) |
| U32 comparison | accepted | 2.721 (2.515–2.882) | 0.989 (0.950–1.187) | 0.997 (0.914–1.101) |
| U32 loop | accepted | 2.729 (2.641–2.830) | 0.984 (0.932–1.034) | 1.000 (0.895–1.081) |
| U32 wrapping add | accepted | 2.151 (2.066–2.238) | 0.987 (0.917–1.028) | 1.016 (0.917–1.085) |
| Invalid effect | rejected | 1.015 (0.958–1.097) | 1.037 (0.922–1.145) | 1.215 (1.104–1.270) |
| Missing return | rejected | 1.998 (1.917–2.155) | 2.007 (1.882–2.081) | 2.334 (2.185–2.601) |
| Invalid type | rejected | 2.014 (1.877–2.200) | 2.108 (1.822–2.203) | 2.243 (2.000–2.353) |
| Unbound name | rejected | 1.229 (1.167–1.255) | 1.211 (1.148–1.265) | 1.975 (1.880–2.065) |
| Unproved addition | rejected | 1.296 (1.261–1.370) | 1.311 (1.275–1.359) | 2.124 (2.007–2.284) |

The previous-first route removes the large primary-first regression for these
already accepted cases, within the observed sample noise; it does not prove a
speedup. In the final replay route, rejected cases are 1.22–2.33 times slower.
The previous-first (without replay) accepted-case
previous-first / candidate-first median ratios were 0.973/0.994 for Bool,
0.985/0.989 for comparison, 0.968/0.986 for loop and 0.981/1.001 for wrapping
add. These small order slices and the individual raw samples show variability.

The three subdirectory `results.json` files preserve all raw
samples, order labels, preflight statuses, source and output hashes, and witness
inputs. Each subdirectory also contains the source corpus, observed dependency
hashes, scripts, Wasm witness artifacts and cgroup snapshots. The common driver
and the three routing sources are recorded as `.goose.txt` files. The exact full
Goose source snapshots, native binaries and complete host toolchains are **not**
included here; manifests and hashes alone cannot reconstruct or authenticate
them. The scripts and absolute paths are archival copies from the original
scratch runs, so they require those missing snapshots and rebuilt binaries to
run again. Goose stdlib hashes were observed, but the complete runtime/linker
and operating-system provenance was not attested.
