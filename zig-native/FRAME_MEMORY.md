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

## 2. Pointer-identity memoization of pure frame work

Settled bricks have identical inputs every frame, yet their draw records are
rebuilt 60 times a second. For an immutable value, the same pointer means the
same value, so a pure function applied to pointer-identical arguments may
return its previous result.

- **Mechanism:** a compiler-selected memo slot per call site. It holds the
  previous argument pointers (retained) and the previous result (retained). A
  hit returns the result with one retain. The slot is replaced on a miss.
- **Selection:** use effect-free calls whose arguments are reference values from
  long-lived state, and whose result is large relative to a pointer comparison.
  Never key on scalar machine words, which would be pointer guessing.
- **Soundness:** purity comes from the checked effect row, and identity from
  immutability. Retained slots keep their arguments alive; they hold strong
  edges, so a slot is a cycle-capable object (see 1).
- **Gain:** frame cost drops from the number of bricks to the number of changed
  bricks. This is likely the largest win for #16's integration workload.
- **Risk:** slot memory, and the policy for when a slot is worth its retain.
  Measure the hit rate first by instrumenting the draw builders in an isolated
  copy.

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
