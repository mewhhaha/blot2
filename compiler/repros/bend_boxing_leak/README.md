# Bend 2 native boxing leak: list identity

Status: fixed upstream in Bend 2.0.28. Bend 2.0.31's generated C also reuses the
list cell correctly. The measurements below describe older releases; the
allocation probe uses an older runtime interface and needs updating before it
can run on 2.0.31. See [BUGS.md](../../../BUGS.md) for current tracking.

The smallest reproducer reduced here is the 12-line [repro.bend](repro.bend). It
defines a two-constructor value and an identity function on lists:

```python
import Base

type Value is Data:
  Scalar{number: U32}
  Pair{left: Nat, right: Nat}

def rebox(values: List<&2, Value>) -> List<&2, Value>:
  match values:
    case Nil{}:
      Nil{}
    case value <> tail:
      value <> tail
```

It needs no compiler pipeline, caches, growing input, recursion, or parallel
calls. This is a small confirmed witness, not a claim that no shorter program
can trigger the bug.

## Reproduce

The directory is self-contained: it imports only Bend's Base and its own files.
Use Bend 2.0.21 or 2.0.24 and a native C toolchain. From this directory:

```sh
bend version
bend PROOF.bend
bend main.bend -o /tmp/bend-boxing-repro
BEND_REPRO_CASE=scalar /tmp/bend-boxing-repro --threads 1
BEND_REPRO_CASE=pair /tmp/bend-boxing-repro --threads 1
```

Scalar output on both versions:

```text
count=1 in_use_bytes=1072
count=1 in_use_bytes=1088
count=1 in_use_bytes=1104
count=1 in_use_bytes=1120
```

Pair control output:

```text
count=1 in_use_bytes=1056
count=1 in_use_bytes=1056
count=1 in_use_bytes=1056
count=1 in_use_bytes=1056
```

The automated check runs both cases with one and eight configured threads:

```sh
deno run --allow-run verify.ts /tmp/bend-boxing-repro
```

It asserts four correct one-element results, then checks **16 bytes lost per
Scalar call** and **zero bytes lost per Pair call**. It intentionally confirms
the bug; a repaired compiler should fail its Scalar leak expectation. No threads
actually fork in the witness, regardless of configured pool size.

## Why this proves a leak, not allocator retention

`main.bend` constructs a fresh singleton, passes it through `rebox`, and
consumes the complete result with `List.length` before calling the observation
effect. Only its scalar length survives. Each round has the same remaining
state. The foreign input prevents Bend from constant-folding the test away.

`probe.c` only supplies the runtime-selected variant and reads allocation
accounting. It never creates a Bend heap node, retains a list, frees a node, or
modifies allocator state. At the effect boundary the CPU pool is joined. It
subtracts all bank and lane hot/cold free-list words from the heap extent;
already-freed allocator storage is therefore excluded. The small runtime/IO
baseline is constant, as the Pair control also demonstrates. These are not RSS
measurements, and waiting for a GC is not involved.

`LAWS.bend` and `PROOF.bend` separately prove that `rebox` is the identity for
every input list in Bend's semantics. That theorem passes on both versions. It
proves value semantics, **not native allocation correctness**: the allocation
bug is demonstrated by the runtime measurements and generated C below.

## The incorrect generated C

Emit and inspect the C:

```sh
bend main.bend -o /tmp/bend-boxing-repro.c
```

On 2.0.24, the `rebox` segment (`spin_1`) consumes the original list cell as
`sp_0`. After opening the head value, its boxing branch is:

```c
Term b_1 = 0;
if (o_1 == 0) {
  b_1 = term_pak(CID_REPRO_SCALAR, o_2);
} else {
  u64 nd_2 = sp_0;
  e.mem[nd_2 + 0] = o_2;
  e.mem[nd_2 + 1] = o_3;
  b_1 = term_ctr(CID_REPRO_PAIR, nd_2);
}
u64 nd_3 = heap_alloc(e, cls_fit(2));
e.mem[nd_3 + 0] = b_1;
e.mem[nd_3 + 1] = f_1;
```

The Pair branch reuses the consumed cell. The Scalar branch does not reuse or
free it. A new output cell is allocated in both cases, so the original two-word
cell is orphaned on Scalar: **2 × 8 = 16 bytes**. Consuming the output frees the
new cell, not the lost one.

The root cause is `val_box`/`ctr_build` sharing the emitter's mutable spare list
across mutually exclusive branches. This is the same defect as the much larger
retained compiler leak documented in [MEMORY.md](../../MEMORY.md).

## Verification

Both official Bend 2.0.21 and the separately extracted 2.0.24 binary pass the
identity proof and reproduce the exact outputs above, with one/eight-thread
configurations. The verifier passes `deno check`. The production toolchain and
compiler implementation are unchanged. Nothing has been posted upstream.
