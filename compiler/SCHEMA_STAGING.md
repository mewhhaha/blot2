# Evaluate checked schema queries before cloning

2026-09-24. Follow-up to
[the String/catalog integration](HIGH_COST_IMPLEMENTATION.md).

## Implemented

`schema_stage.bend` recognizes a narrow linked-schema membership function from
independently checked source. It captures the node method, terminal method,
equality forwarder, type-equality method, and their nominal declarations. Names
and module identities come from the program; no gdev paths or saved ASTs are
embedded in the compiler.

When the receiver chain and witness type are concrete, specialization computes
the answer and infers a small curried Bool helper. This removes an entire chain
of helper specialization, checking, and constant evaluation. For gdev:

- 28 membership clones, 28 type-equality clones, and 28 generated
  type-comparison helpers are removed; eight schema helpers are added.
- Checked functions decrease **821 → 745**.
- Constant evaluation uses **1,872 fewer steps**: 15,919 → 14,047.
- Wasm remains byte-identical: 192,168 bytes, SHA-256
  `3acd6c59325af25370b39d7a5b6259ce7fd6314d944f2f3831f0ca1793c4cf9a`.

Generated names can change with clone counters, so complete analysis JSON is not
byte-identical. The gdev comparison also preserves all 18 ordered world cells,
22 scope closures, nine checkpoints, ten scheduled systems, closure
identities/captures, and create/clean/frame behavior.

## Correctness boundaries

The pass validates exact checked source, nominal identities, the selected
method, and a pure resolved result. It checks the entire chain even after a
match; an invalid later head or tail must retain its ordinary diagnostic.
Field/method ambiguity, shadowing, open types, changed helpers, exhausted
structural fuel, fresh-ID limits, and name collisions all cause fallback.

The generated call preserves receiver and witness evaluation. Failed optional
inference returns to the original specialization state. Unused source still
undergoes the initial check. Four executable laws cover bounded failure,
rejected evidence, continued tail validation after a hit, and ordinary-selection
fallback.

Sessions capture the same checked evidence. Their specialization context key
includes evidence count and all four exact source functions, as well as the
existing full nominal and operation catalogs. This retains cache dependencies
even when the pass removes the calls that originally established them.

This is a bounded optimization for one source grammar. Unsupported abstractions
continue through ordinary specialization. The tested imported-library fixture
uses the optimization; the tested entry-owned generic helper falls back under
the conservative exact-source guard. Both retain the existing type-system rules.

The const-step budget counts residual evaluator work. At 15,000 steps, gdev now
succeeds with 953 remaining where the previous compiler exhausted its budget. At
14,000 both fail with the same budget diagnostic. This is an intentional
consequence of reducing evaluated work.

## Native measurements

Five alternating fresh-process pairs per worker count, comparing the integrated
`a884b7e` compiler against this pass. Every request validates exact gdev Wasm.
Our builds and tests were stopped during timing; unrelated CPU-heavy work
continued. These windows had substantially higher host load than the earlier
String/catalog measurements. Compare paired controls, not absolute times across
windows or worker rows.

| Median                      | 1 worker: baseline → staged | 4 workers: baseline → staged |
| --------------------------- | --------------------------: | ---------------------------: |
| Compile call                |            1,468 → 1,450 ms |         **1,861 → 1,682 ms** |
| Native CPU                  |            1,350 → 1,260 ms |             1,630 → 1,480 ms |
| Peak RSS                    |         43,776 → 45,032 KiB |          62,824 → 64,224 KiB |
| Startup + loading + compile |            1,732 → 1,650 ms |             2,157 → 1,979 ms |

Four-worker compile and CPU medians decrease **9.6% and 9.2%**; all five pairs
improve both. One-worker CPU decreases **6.7%**, improving in every pair, while
compile wall time decreases 1.2% at the median and improves in four of five
pairs. The memory increase is about 1.2–1.4 MiB. Stage medians do not
necessarily sum to median total time.

Baseline executable SHA-256:
`0ff3102bea067b66a8cfd3f267a3a7557966de0f4eeb57ce8d45091a924f1376`. Staged
executable SHA-256:
`6f13da2259b954a2752bd3d9b14abd678a63534329ed2710ffdc673e670f12b0`. Raw pairs
and summaries are `build/high-cost-integration/root/pairs-schema-{1,4}.*`.

## Validation and reproduction

The full Bend build, five native kernel guards, ownership regression at one/four
workers, and private full proof passed before installation. Native differential
testing matched 176 API operations. Self-contained source, exact cache-key, and
native project tests cover actual optimization hits, true/false answers,
malformed/open chains, changed helpers/catalogs, and failed-edit rollback.

Full-gdev diagnostic comparisons match for duplicate registration, a changed
terminal helper, unused invalid source, and panicking receiver/witness operands.
Native cold and project-session compilation each emit the same eight schema
helpers and identical Wasm. An unchanged session recomputes no groups,
constants, or Wasm entries; this is distinct from the fresh-process measurements
above.

The staged build and source fingerprints are under
`build/high-cost-integration/schema-candidate/`. Gdev semantic, fallback, and
fuel evidence is under `build/high-cost-integration/staging/`; native API,
project-session, repository-test, and proof logs are under
`build/high-cost-integration/root/`.

The installed compiler passes **735 compiler/transformer tests**, the additional
focused operand-evaluation regression, and **24 gdev tests**, including 1,200
frames and recompilation. Each panic fixture proves that schema selection ran
before checking its native diagnostic. The final repository
`BEND_NO_TELEMETRY=1 bend PROOF.bend` also passes: all terms check.

## Next measured opportunity

An independent census of the preceding integrated compiler found **451,516
rebuilt function-name list cells** and **264,462 linear function-kind
comparisons** in a gdev compile. A persistent function-kind index, extended only
when functions are emitted, could avoid this work. The binding index,
pending-constraint cache, and session task cache do not cover it.

This is a concrete next experiment, with no native speedup claimed. Those
membership comparisons account for only about 5% of the earlier name-comparison
census, so an index alone is unlikely to deliver the requested 100–200 ms.
Broader reuse of checked template inference and a more compact inference
representation remain larger architectural candidates.

The **100–200 ms cold compilation target remains unmet**.
