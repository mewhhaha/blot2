# Frame memory directions (issue #16 follow-ups)

Issue #16 measured a game frame spending 78% of guest samples in the cycle
collector, reclaiming nothing. The near-term fixes landed separately:
- Trial discovery stops at `no_cycle` objects.
- Removal traffic is charged once per queued candidate.
- Passes trigger in proportion to the vertices the previous pass kept.
- The acyclic proof covers nominals of every unit and Array/List edges, so plain
  data, including its temporary containers, never becomes a candidate.

This note records larger directions, ordered by expected payoff per unit of
risk. None is scheduled; each needs its own measured task.

## Facts the directions rely on

- Values are immutable. `:=` rebinds or performs a copy-on-write update.
  Runtime reference cycles need State cells, memoized demands or closures
  (CONTRACT.md, "State plus memoized demands can construct real cycles").
- Old objects therefore never point to younger ones, except through those
  cycle-capable cells.
- A frame's temporaries reach the host as serialized bytes. They survive the
  frame only through a State write, a memo result or a host-retained handle.

## 1. A separate heap for cycle-capable objects

Allocate State cells, demands, closures and any layout the acyclic proof
declines in their own size classes, and run trial deletion only over that heap.

- **Soundness:** a cycle consists only of objects whose layouts admit a back
  edge, so every member of every cycle lives in the cycle heap. Objects outside
  it become exactly today's `no_cycle` objects. Discovery already stops at them,
  and they still release their children by ordinary RC.
- **Gain:** pass cost scales with the cycle-capable population, not with live
  data. Once the proof is wide, this is mostly a layout of existing behavior; it
  pays when declined layouts stay common, such as erased fields or providers.
- **Prerequisite:** allocation sites must know the layout's proof result. The
  emitter already computes it for `mark_acyclic`.

## 2. Measure stable inputs before memoizing pure frame work

Settled stacks are immutable, but the current gdev draw call is
`stack_draws (rise stack.x stack.z) stack ahead`. `ground` is computed from
terrain and `ahead` depends on the frame's presentation alpha. A stack pointer
alone is therefore not a sound cache key, and changing `ahead` may prevent
hits even when the stack is unchanged.

- **Measurement first:** record how often all arguments repeat for each stack
  across real frames, including the bit patterns of `ground` and `ahead`.
  Do not assume the reduced static workload has the same hit rate.
- **Mechanism if hits justify it:** an effect-free call may reuse its previous
  result when immutable reference arguments have the same identity and scalar
  arguments have the same bits. Keep a bounded entry per stack or collection
  element: one slot for the whole call site would be replaced by every stack
  in the loop. Retain reference keys and results while the entry is live.
- **Soundness:** exact scalar-bit comparison is conservative for numerically
  equivalent values and avoids treating scalar words as pointers. The checked
  effect row establishes purity. Retained entries hold strong edges and must
  remain visible to cycle collection (see 1).
- **Decision:** if frame-dependent `ahead` makes hits rare, prioritize writing
  frame output at its destination (3) instead of adding a cache.

## 3. Build frame output at its destination

Today the frame builds per-brick records, gathers them in nested arrays,
flattens them, then serializes the result for the host. Fuse that chain so the
producers write into the host frame buffer directly, as destination-passing
style does.

- **Soundness:** this applies only when the intermediate arrays have no other
  consumer. Row fusion and collection iteration already prove single-consumer
  chains.
- **Gain:** draw data makes no heap allocation, does no RC and creates no
  candidates.

## 4. Flat layouts for reference-free data

A record of scalars, nested scalar records and scalar arrays can be stored
inline as one block with no internal references.

- A reference-free block needs no counts beyond its own, can never be in a
  cycle, and is already in wire format for the host.
- This generalizes today's scalar List trees and packed layouts to nested
  records with variable-length scalar arrays.
- **Cost:** variable-length members are iterable but not indexable without an
  offset table.

## 5. A frame nursery

Bump-allocate a frame's temporaries and reset the nursery at the frame
boundary. Values that escape through a State write, a memo result or a host
handle are copied to the RC heap at that point.

- **Soundness:** immutability means no old-to-new pointers except through those
  escape points, so they are the only barrier. This is ulterior reference
  counting (Blackburn and McKinley) specialized to a fixed-tick language.
- **Cost:** it is the largest change, touching root management, snapshots and
  rewind history, and in-flight host frames, which may need a ring of
  nurseries. Consider it only if 1–4 leave frames over budget.

## Measurement

Use the #16 repro shape: persistent records, per-frame draw records with a
foreign matrix, an optional field and an array field, nested comprehension and
flatten. Report `blot:cycle_*` and `blot:rc_*` per frame, committed memory over
many frames, and ms per frame at N = 128, 512 and 2048. The existing
cyclic-reclamation laws must keep passing.
