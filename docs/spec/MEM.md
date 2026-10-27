# K1 implementation specification — memory, runtime, and ABI

**Specification ID: K1-MEM. Edition: K1 revision 1, 26 October 2026.**
**Parent and full handoff:** [Language design program — issue #37](https://github.com/mewhhaha/blot2/issues/37). Read K1-LANG, K1-MEM, K1-CORE, and K1-EXEC together; the parent links every part.

**Status:** normative proposed K1 v1, not a description of an implemented compiler. This chapter is part of the issue #37 handoff. Its baseline is `mewhhaha/blot2` commit `1e39b5d8a4268b9edf769c2813d5231abe1c963b`. The language and compiler chapters supply source grammar, proof rules, and artifact admission. Here, capitalized **MUST**, **MUST NOT**, and **MAY** are requirements. Operation spellings describe the closed builtin registry; surface elaboration may wrap them but must preserve their contracts.

## M01. Scope and the memory guarantee

K1 v1 targets single-threaded Wasm32 with fixed linear memory. It supports reference-free array elements, immutable views, exclusive fixed-capacity builders, lexical loans, caller destinations, bounded closure environments, and independently transferable whole-region packages. There is **no tracing collection, cycle collection, reference counting, hidden shared ownership, or per-element destructor traversal**. A control record for each independently allocated backing region is allowed; it contains no reference count.

Successful checking establishes that ordinary language execution cannot read outside an initialized extent, forge storage authority, use a closed/reset region, publish partially initialized data, or duplicate an owning capability. It does not establish an arbitrary application's intended answer. Resource exhaustion is an explicit result where reservation or placement can fail. Host corruption, compiler defects, and engine failures remain outside this theorem; they are not disguised as ordinary language errors.

General backing growth, compaction, arbitrary external resources, destructor graphs, owning closure captures, shared independently freed objects, concurrency, asynchronous suspension, callbacks from the host, and native virtual-memory reservation are outside v1. A use requiring one of them MUST receive an explicit unsupported-feature diagnostic. It MUST NOT fall back to the legacy counted heap.

## M02. Layout classes and hard representation limits

A word is four bytes. Stored integers and tags use little-endian encoding. Nonempty K1 layouts have alignment four; `Unit` has size zero and alignment one. Array stride equals element size. There are no interior object headers.

| Class or value | Physical representation and limit |
|---|---|
| `U32`, `Bool`, `Index[d,n]` | One word; Bool is exactly 0 or 1 |
| `F32` | One IEEE-754 binary32 word; numerical semantics are defined by the language chapter |
| `Unit` | Zero words; produces no load or store |
| Fixed product/record | Fields concatenated in declaration order |
| Closed sum | One declaration-order U32 tag followed by the largest arm's payload area |
| `Plain` element | At most 16 words / 64 bytes |
| Ordinary argument/result aggregate | At most 64 words / 256 bytes |
| Closure environment | At most 64 words / 256 bytes |
| `View[r,T,n,d]` | `{data:u32, length:u32}` |
| `Dest[r,T,c]`, `EnvDest[r,c]` | `{data:u32, capacity:u32}`; capacity counts elements or bytes respectively |
| `Builder[r,T,n,c,Mode]` | `{data:u32, length:u32, capacity:u32}` |
| `RegionOwner[r]`, `Space[r]`, `Owned[P]` | `{slot:u32, generation:u32}`; different checked authority despite identical shape |
| Internal `OwnedConstruction[r]` | Same two-word handle; available only to the owning-scope elaboration |
| `Fn[r,Mode,A,B]` | `{table_code:u32, environment:u32}` |

`Plain` contains scalar values, refined scalar values including `Index`, fixed products, and bounded closed sums of Plain. It excludes every view, function, pointer, owner, destination, builder, and `Owned`. A sum has at most four constructors. Its inactive payload words MUST be zero at publication; its live payload MUST have the constructor's canonical representation. The layout checker admits at most 32 stored structural nodes, 64 scalar leaves, and 32 refinement/validity guards per Plain schema. It rejects excess work deterministically. These are versioned K1 limits, not optimizer heuristics.

`Share` contains Plain, immutable View, FnMany, and fixed products/sums of these. It does not mean shared ownership. Copying Share duplicates scalar data or a checked immutable loan. It never extends a region's lifetime. `FnOnce`, `Owned`, and affine storage capabilities are not Share. The builtin `Result` is affine and must-handle, so it is neither Plain nor Share even when its fields have a numerical representation; an ordinary user sum follows its field classes. Ordinary aggregates may contain affine fields, but must satisfy the language's complete-destructuring and move rules; they receive no runtime partial-move bitmap.

A user existential binds only Nat and Domain, so its layout remains fixed independently of witness values. Such a package is Plain exactly when its payload is Plain and its Nat-prefix-plus-payload layout satisfies the 64-byte Plain limit and other Plain layout budgets. It is Share exactly when its payload is Share and its complete descriptor satisfies the 256-byte aggregate limit. Prefix witnesses add ordinary scalar words; hidden Domain binders add none. Neither classification erases a payload's Result obligation, borrow footprint, or domain identity. Dynamic Type/Region existential boxing is not provided.

All type-dependent layout computations MUST finish before function admission. Recursive or unbounded storage layouts are rejected. Generic bodies receive admitted immutable layout dictionaries; they do not inspect source types or request new type inference at runtime.

Empty nonzero-sized views use canonical `{0,0}`. Zero-sized element views use `{0,n}`, including `n>0`. Their logical bounds remain real: a Unit read needs an in-range index but performs no load. Unit append consumes logical capacity. Zero-byte destinations still carry affine authority and cannot be duplicated. Neither a zero address nor equal bits establishes domain or storage identity.

## M03. Fixed backing pool and numerical resource plan

A K1 module declares one memory with equal initial and maximum page counts. `memory.grow` MUST NOT occur in its code. The manifest fixes all following values before instantiation:

| Resource | Default | Hard K1 v1 restriction |
|---|---:|---:|
| Wasm page | 65,536 bytes | Fixed |
| Region allocation granule | 4,096 bytes | Fixed |
| Region backing pool | 16 MiB | Whole granules; fits total memory limit |
| Usable owner slots | 256 | At most 4,096 |
| Owner entry | 32 bytes | Fixed |
| Language frame arena | 1 MiB | At most 16 MiB |
| Host ingress window | 64 KiB | Manifest-sized, four-byte aligned |
| Host egress window | 64 KiB | Manifest-sized, four-byte aligned |
| Owned root capsule | 256 bytes | Fixed, in addition to working bytes |
| Entire linear memory | Computed | At most 1 GiB, exclusive end `0x40000000` |

The complete memory map contains static data and dictionaries, control words, owner entries, the pool allocation bitmap, frame arena, host windows, alignment padding, and backing pool. Every component MUST appear in the manifest and fit the total limit. The backing pool begins at a granule boundary. The frame arena and host windows are disjoint from it and from each other. All static descriptors are immutable by language authority.

At defaults, 256 owner entries cost 8,192 bytes. The 16 MiB pool has 4,096 granules and therefore a 512-byte allocation bitmap. Bitmap bytes are `ceil(granules/8)`, rounded to four-byte alignment for placement. Even a maximally configured module MUST include metadata in its one-GiB calculation; the pool does not itself receive the entire cap. Initial pages are the checked ceiling of the final memory-map end divided by 65,536.

The allocator is deterministic first-fit over contiguous free granules in ascending address order, using the first reusable owner slot. Fragmentation may cause `NoContiguousSpace` despite enough total free bytes. There is no collection or automatic compaction to repair this. Reservation scans are bounded by declared bitmap and slot counts; their worst case is not constant time. Closing a region clears its reserved bitmap run and costs time proportional to touched bitmap words, with no dependence on the number or shape of logical elements. Reset is constant time.

### Owner control record

Slots are numbered `1..owner_slots`; zero is invalid. Entry `slot-1` has eight U32 fields in this order:

```text
base, requested_bytes, rounded_bytes, top,
generation, state, root_schema, root_words
```

State encodings are `Free=0`, `Open=1`, `SealedOwned=2`, `Retired=3`, `BuildingOwned=4`. Initially all slots are Free with generation zero. On reservation the selected slot's generation increments, starting at one. Closing a slot whose generation is `0xffffffff` retires it instead of making it Free. Generation MUST never wrap, and a failed reservation does not change retirement state. Invalid/stale handles are implementation-boundary faults, not convertible storage authority. Runtime operations receiving owner handles MUST verify slot range, generation, and permitted state before accessing their entry.

The free-slot search and bitmap search happen before commitment. A failed reservation changes neither. A successful reservation sets the bitmap run and initializes the full entry before returning authority. The backing bytes need not be zeroed; they are uninitialized and inaccessible until written through valid capabilities.

## M04. Reservation, arithmetic, and error outcomes

`region.reserve(bytes)` returns `Result[(RegionOwner[r], Space[r]), ReserveError]`, introducing fresh `r`. `ReserveError` has declaration-order variants `SizeOverflow`, `NoOwnerSlots`, and `NoContiguousSpace`. Error priority follows that order when several conditions fail. On error it publishes no owner or storage capability.

This is a Core operation; source introduces its fresh region through the language chapter's lexical `region@[T](bytes) as r (owner,space) in do:` form. It is not an unrestricted user function returning an existential Region owner.

For ordinary regions, `requested_bytes=bytes`, `top=0`, and physical reservation is `round_up(bytes,4096)`. Authority covers exactly `bytes`, never rounding slack. A zero-byte reservation consumes an owner slot but no granules; its base, requested size, rounded size, and top are zero. It can support zero-sized values, not a nonempty nonzero-sized allocation.

All byte-size, alignment, frame, window, and address arithmetic MUST be checked before it changes state. For nonzero stride s, check `count <= U32.max/s` to detect multiplication overflow before checking capacity with `count <= available/s`; separately account for alignment padding. Addition uses a subtraction-based bound or an equivalently verified check. Rounding MUST check its addition before masking/dividing. A mathematical fact about unbounded integers does not authorize wrapping machine arithmetic. No i64 support is required.

`region.try_alloc<T>(space,c)` consumes the incoming frontier capability and returns:

```text
Ok(space_next, Dest[r,T,c])
Err(space_unchanged, AllocError)
```

`AllocError` has variants `SizeOverflow`, `NoSpace`, in that priority order. Placement accepts a Space from Open or BuildingOwned; the latter's initial frontier excludes the root capsule. On success, the implementation aligns `top` for T, reserves `c * sizeof(T)` within requested bytes, and advances top to the allocation end. On failure, top and all permissions are unchanged. A zero-sized allocation leaves top unchanged and returns a logical destination with data zero. `env.try_alloc(space,bytes)` has the same transition and errors, with alignment four and result `EnvDest[r,bytes]`.

A proved `region.alloc` may omit the failure branch only when the checked contract proves the same size/alignment/capacity conditions. Placement inside already reserved storage is distinct from backing reservation: a no-backing-allocation kernel may use explicit destinations and fallible placement. Its contract still includes that failure and any observable effect.

## M05. Provenance, splitting, reset, and separate scratch

`RegionOwner` is the single whole-region release/reset authority. `Space` is the single current frontier authority. They are affine, are not interchangeable, and are not constructible from their physical words. Allocation advances Space but does not consume RegionOwner. The owner cannot reset or close while Space or any descendant destination, builder, view loan, or closure loan survives.

`space.end` consumes Space without rewinding top. `dest.discard` and `builder.discard` consume their authority without reclaiming their individual byte ranges. Such consumed ranges become reusable at the next valid whole-region reset or close. K1 does not maintain free lists of logical arrays.

`dest.split(dst,k)` requires `k <= c`, consumes `Dest[r,T,c]`, and returns destinations of capacities `k` and `c-k` covering its prefix and suffix. Nonzero-size suffix data is `data + k*sizeof(T)` after the parent bounds justify the arithmetic. Zero-sized children have data zero but distinct linear derivations. Nested splits retain the parent range provenance. The compiler MUST establish byte disjointness from a common exclusive range or separate backing reservations; merely assigning two compiler identities is not a disjointness proof.

A writable destination may not overlap any live input read loan or other writable permission. Mutable accesses additionally require the correct builder state/version. Read-only slices may overlap. `view.slice(v,start,count)` requires `start <= n` and `count <= n-start`, and returns `exists[d:Domain] => View[r,T,count,d]` with fresh d; it does not implicitly reinterpret existing Index values. Empty slices use the canonical empty representation.

`region.reset(owner)` consumes an Open owner after every old descendant and frontier capability has ended. It sets top to zero and returns the owner with a fresh Space and fresh static region epoch. Old views and borrowed closure environments cannot cross this transition. An independently stored Plain Index contains no address and need not keep its original backing bytes alive; retaining it does not make its old domain compatible with any newly frozen/sliced view. The runtime generation need not change, because no legitimate old handle-derived loan survives. Reset does not inspect or zero old objects. `region.close(owner)` has the same no-descendants precondition, clears the bitmap run, and makes the slot Free or Retired. It returns Unit and cannot fail for a valid owner.

Splitting a destination never grants an independent reset right. **K1 v1 has no child-region reset primitive.** A computation retaining results while reusing scratch MUST use two separately reserved regions or caller-supplied distinct owners. A result loan cannot refer to scratch after scratch resets. Compiler output, closure captures, and helper return signatures must preserve this separation; a “scratch” name alone proves nothing.

## M06. Initialized-prefix builder state machine

The abstract builder state is `(r, range, T, n, c, mode, version)` with `0 <= n <= c`. Exactly elements `[0,n)` are initialized. `[n,c)` is unreadable, even if previous physical contents happen to look valid. The runtime stores only data, n, and c; typestate, version, loans, and provenance belong to checked IR.

| Primitive | Required state | Successful transition | Failure obligation |
|---|---|---|---|
| `begin_append(dst)` / `begin_resize(dst)` | Exclusive Dest | Builder with `n=0` and selected mode | Infallible |
| `read(builder,i)` | `i<n`, temporary read loan | Copy of Plain element | No unchecked form |
| `append(builder,x)` | No live loans, `n<c` | Write complete element n; publish `n+1` | Infallible after proof |
| `try_append(builder,x)` | No live loans | Same as append | Returns unchanged builder and unused x on full capacity |
| `set(builder,i,x)` | No live loans, `i<n` | Replace initialized slot; n unchanged | Infallible after proof |
| `truncate(builder,m)` | Resize mode, no live loans, `m<=n` | New initialized prefix m | Infallible after proof |
| `freeze(builder)` | No live loans | `exists[d:Domain] => View[r,T,n,d]` with fresh stable d | Infallible; no data copy |
| `discard(builder)` | No live loans | No surviving access authority | Infallible; no per-element cleanup |

Append mode permits append and replacement; Resize additionally permits truncation. Neither reallocates backing. Growing logical length requires initializing every newly exposed element through append or a checked equivalent loop. There is no primitive that just increases length. Truncation makes the removed suffix unreadable; its subsequent extension must write it again.

Expression evaluation follows the language's fixed left-to-right order. Moving the builder into an internal argument temporary may happen before evaluation of the element argument; the moved source binding is then unavailable. No append mutation or initialized-length transition occurs until all arguments have been evaluated. An early transfer or failure during argument construction must explicitly discharge or pass on the held builder obligation. Computing a fallible element first and then calling append is the straightforward source pattern; no special delayed move or two-phase borrowing is implied. A helper that can fail during several writes must return its still-owned partial builder/capabilities or discharge them locally. It MUST NOT publish a partial immutable result as success or silently lose Space/owner obligations.

Every element is completely written, including required inactive sum words, before its contribution to n is published. Freeze consumes the builder and transfers its initialized extent to a view. There is no thaw in v1. Editing an immutable view requires an explicit separate destination and copy/transform operation. Builder-derived loans block every mutation or consuming operation until their lexical scope ends; v1 does not attempt fine-grained mutable subloans.

`index.try_make(view,i)` returns `Option[Index[d,n]]`, with Some only after checking `i<n`. `view.try_read(view,i)` returns `Option[T]`; `view.read` requires an existing matching Index or proved numerical bounds. Builder reads use numerical proofs against the exact current builder version. A resizable builder does not mint a persistent branded Index in v1. A matching immutable Index proves position validity, not a property of the element stored there. Equal lengths do not establish equal domains. An Index payload alone does not reify its erased n; the associated view or package supplies the Nat witness.

## M07. Publication, failures, and faults

A caller result slot and an output destination are initially exclusive uninitialized storage. The callee MUST initialize the complete declared result before normal return, including an error variant's active payload and canonical inactive words. The caller gains read permission only at that return. A helper using an additional data destination publishes its view only through a completed success result; an error must explicitly return the destination/builder authority if the caller is expected to reuse it.

There is no ordinary exception unwinding in this protocol. Recoverable failures are typed Results, and all branches account for affine values. A runtime implementation invariant violation, unreachable checked operation, Wasm trap, or engine exhaustion poisons the invocation/instance through the generated host wrapper. A poisoned instance MUST NOT resume execution. The host may destroy the entire instance. This is not a recoverable allocation failure and is never retried by switching runtimes.

“Poison” for uninitialized storage is primarily a static inaccessible state. Debug runtimes MAY fill abandoned/uninitialized bytes with a pattern, but correctness MUST NOT rely on the pattern or a runtime initialization bitmap. Publication checks belong to the validator. The runtime MUST never copy uninitialized padding to a host output. Bulk zeroing an entire region is neither required nor sufficient to establish an element's typed validity.

## M08. Closures without hidden ownership

A nonescaping closure may keep its bounded environment in the current fixed frame. Its loan lifetime is its defining lexical activation, including the current loop iteration, rather than automatically the entire function. The body-only Region token `local` names that activation for explicit callback instantiation; it grants no Owner/Space and cannot appear free in a public interface. A closure cannot survive into another iteration through loop carry/result while its slot is reused. Crossing that activation requires explicit placement: the source form `fn in env_dest x => ...` consumes `EnvDest[r,c]`. The compiler computes its concrete environment layout and proves that its bytes fit c. Failure to prove fit is a diagnostic stating the required size; v1 does not implicitly allocate a larger environment. `EnvDest` is a separate internal layout capability, not a cast from an arbitrary array destination.

The environment contains only Share captures. Plain captures are copied; View and FnMany captures retain their checked loans. Every captured loan must outlive the closure's promised lifetime. Function descriptors are cheap to copy, but their environments are not thereby copied. There is no generic runtime closure-cloning operation, arbitrary environment inspection, or hidden box. Environment allocation/padding is charged to the chosen explicit region or frame.

Many permits repeated calls. Once grants at most one invocation and is affine; discarding an unused Once is allowed because it owns no captured resource. Many may be weakened to Once. Neither permits capturing Owner, Space, Dest, Builder, Owned, or another Once. Stateful functional APIs pass affine state explicitly through input and result. Closed `Owned<FnMany>` is supported under M09; `Owned<FnOnce>` is rejected.

Every callable has a complete checked argument/result, environment schema, effect, multiplicity, frame, and depth contract. Unknown calls use that contract and a table entry with the same machine ABI and a checked compatible semantic contract; actual resource requirements may be smaller than a widened advertised allowance. Widening resource bounds alone needs no adapter. Table contents are immutable under language authority. Calls cannot discover a type by evaluating the function. Local known identity may become a direct call. No runtime refcount or callable-liveness heap is introduced.

## M09. Independently transferable whole-region packages

`Owned[P]` is one affine owner of **one entire backing region**. P must be Share, fit the 256-byte root capsule, and be transitively closed over only that region or static storage. No nested Owned, external region loan, external environment pointer, FnOnce, or affine storage capability is permitted in P. Refinement/domain witnesses exported in P must be closed by its declared package schema. The checker verifies this from typed capture/provenance evidence, without traversing a runtime graph.

The internal `owned.begin(work_bytes)` returns `Result[(OwnedConstruction[r],Space[r]),ReserveError]`. It reserves `256 + work_bytes`, after checked addition and granule rounding, and enters BuildingOwned with top 256. Its first 256 bytes are reserved exclusively for the root capsule. Working Space grants exactly `work_bytes`, excluding rounding slack. Even a zero-work package reserves one granule. This differs deliberately from `region.reserve(0)`, which reserves no granule. The owning surface scope exposes Space and a fresh region binder, but retains the construction token internally; it never exposes an ordinary RegionOwner. The owning construction must finish in exactly one of these outcomes:

1. **`owned.seal`:** require BuildingOwned and its exact construction token, initialize P's root descriptor and zero unused capsule bytes, end all construction capabilities except the payload loans being internalized, consume the token and Space, and set the entry to SealedOwned with root schema ID and root word count. Return one Owned handle.
2. **`owned.abort`:** require BuildingOwned and its exact token, end local descendants, consume the frontier and token, free/retire the region, and return the typed failure. No package is published. The source owned body must terminate through seal or abort; an outer return/break cannot bypass these terminals.

Seal is a scope-closing operation. It cannot accept an ordinary Open region, and regular region reset/close cannot accept BuildingOwned. It is not an unrestricted function that can move an owner while some external view still aliases it. Previously created external data must be explicitly copied into this new region before capture. Copying a foreign View or Fn descriptor does not satisfy closedness. In particular, placing an environment in the package region does not relocate another captured closure's environment.

Moving Owned transfers only `{slot,generation}` and the static release obligation. Backing bytes and addresses stay fixed. There is no increment, decrement, duplicate owner, or deep copy. `owned.open` lends P in a lexical opening with a fresh hidden region identity; it exposes no reset/release authority. Moving or closing the owner while an opening survives is rejected. The result of the opening cannot retain that loan or its hidden storage identity. Multiple read-only openings are allowed; separate existential openings are not automatically treated as equal domains. To keep a view and its Index related, carry/use them inside the same declared existential package/opening.

`owned.close` consumes the handle after all openings have ended, verifies SealedOwned, clears the reserved bitmap run, and retires/frees the slot. It never invokes payload callbacks or follows captures. Sealed packages cannot reset or append. To change one, build another explicitly. Every normal and typed-error path must transfer or explicitly close a detached Owned; generic discard is rejected. Any lexical region cleanup inserted by surface syntax is a statically enumerated close action, not discovered runtime Drop behavior.

## M10. Physical function ABI: K1-WASM32-ABI1

The canonical callable convention orders machine parameters as follows: environment pointer; result-slot pointer if the result is indirect; declared generic layout dictionaries in binder order; explicitly reified Nat witnesses not already supplied by a designated descriptor field; then source argument representation. Domains and proof evidence have no machine parameter. A Unit argument contributes none.

A statically known scalar argument/result uses i32 or f32. Unit returns no machine value. Products, sums, Views, builders, owners, and other nonscalar values use pointers to caller-provided aggregate slots; their descriptors are not flattened opportunistically. Generic type parameters use indirect slots even when a concrete instance is scalar. Inputs are borrowed immutable or moved according to the checked contract; an indirect affine move invalidates the old source authority. An aggregate result uses an exclusive out pointer and returns no machine scalar. Ordinary Result therefore uses a result slot. No Wasm multivalue extension is required.

A noncapturing callable uses environment zero. A direct function may additionally have one declaration-fixed thin entry without that parameter, identified in its completed ABI summary, with a single checked canonical adapter when used as a value. Call sites cannot invent conventions or trigger body re-inference. A simpler implementation MAY use canonical entries everywhere.

Each immutable layout dictionary is four U32 words: `size_bytes, alignment_bytes, flags, schema_id`. Flags are `Plain=1`, `Share=2`, `ZeroSized=4`, combined as applicable; unassigned bits are zero. Schema IDs name canonical versioned type/layout records in the artifact. Dictionaries are manufactured by the compiler and cannot be supplied from arbitrary source integers. A dictionary proves representation and admitted operations only with its checked generic binder; the flag word alone is not a dynamic authorization mechanism. Generic affine values can be moved indirectly but not copied or discarded through an invented generic destructor.

Input/output slot alignment, complete initialized extent, call-duration loans, and disjoint writable result storage MUST be validated before lowering. Zero-sized slots may use address zero and perform no memory access. Nested sum slots use the same canonical tag/padding rules. A View carries no runtime stride; its exact element layout is supplied by its static or generic contract. An existential package stores one U32 witness for each hidden Nat binder, in binder order, followed by its payload layout. Hidden Domain binders add no words. These witness words count toward every applicable aggregate/root limit. K1 v1 does not omit a package Nat prefix merely because a payload view happens to repeat that length.

The artifact ABI hash covers this chapter's versioned primitive schemas, layout rules, owner fields/state encodings, dictionary schema, call convention, limits, and host wire schema. Each interface, implementation artifact, manifest, and structural certificate MUST contain the same hash. A mismatch fails linking before execution. Per-module geometry has its own manifest hash bound into the certificate. Type/schema IDs are resolved from canonical schema bytes, never accepted merely because numeric IDs coincide across unrelated modules.

## M11. Frames and resource contracts

The compiler reserves a bounded portion of the fixed frame arena for each active call. All aggregate temporaries, indirect results, spilled descriptors, and local closure environments count toward its conservative frame size. Every exit restores the incoming frame frontier. Frame bytes are never mistaken for backing-region storage and cannot escape their defining lexical activation. The same activation rule applies to any borrowed block temporary; a loop cannot retain it across slot reuse.

Every callable carries `resources {depth: D, frame: S}`. Public and parameter interfaces supply closed integer upper bounds; private acyclic declarations may infer them. A leaf has depth at least one and the K1 v1 depth hard cap is 128. There is no symbolic resource polymorphism. A caller must account for its local frame plus the largest reachable callee frame requirement, and a depth strictly greater than every callee's. Canonical/thin adapters count toward these bounds. Source recursive declaration cycles are rejected in v1; the finite decreasing call allowance also prevents closure-hidden cycles from bypassing that rule. Loops reuse their frame slots. Optional optimization cannot rescue a function that failed the baseline frame contract.

The export wrapper preflights the complete invocation frame bound before source effects. A conforming implementation must establish frame-arena bounds without relying on accidental Wasm out-of-bounds traps. The host runtime separately promises sufficient engine resources for the bounded emitted call/local envelope; a linear-memory frame bound is not a universal statement about engine/JIT/native stack bytes or whole-host memory. No claim of bounded execution time follows merely from bounded memory: an admitted loop may still run for a data-dependent number of iterations.

## M12. Mandatory copy-only host array bridge

Scalar-only exports are the first milestone. The mandatory array bridge has one precise shape: a noncapturing Many function accepts one fixed record containing zero or more Plain fields, zero or more input View fields, and exactly one output Dest field. Its result is `Result[exists[m:Nat,d:Domain] => View[r,U,m,d], E]`, with one result array. U and all input element/scalar layouts are concretely selected in the manifest. E is Unit or a closed nullary sum, mapped to detail zero or its constructor tag. Other shapes, nested array descriptors, data-bearing errors, and returned ownership are outside this v1 bridge; an explicit checked source adapter may normalize a program to this shape.

The manifest gives export ID, completed callable identity, explicit type substitutions, source field order, wire schemas, each input View's `max_count`, output Dest element capacity C, fixed `work_bytes`, frame/depth bounds, and ABI/manifest hashes. The record's wire fields follow source order with the output Dest omitted; the wrapper supplies that capability. Input View i maps to wire `{count,byte_offset}` and fresh `n_i,d_i`; its region, and the output destination's region, instantiate to the invocation region r. It obtains fresh domains by freezing copied input builders. Nat arguments come from validated lengths or manifest C according to the completed ABI. Repeated Nat binders require equal supplied values; input Domain binders must be pairwise distinct. Any unmapped binder makes the export ineligible. No caller supplies region/domain authority.

The manifest's work_bytes must cover the checked worst-case aligned sum of every input `max_count * element_size` and `C * sizeof(U)`. There is no inferred arbitrary workspace formula. The compiler also establishes the wrapper's frame allowance. Source effects are limited to immutable reads and writes through its passed destination; additional backing reservation, region reset/release, host effects, and persistent mutation are ineligible. The returned view may alias a matching input after the output Dest has been properly discharged; all input bytes remain live through output copying. Its actual result size determines output-capacity success.

Only the bridge's designated outer collection View/domain and output Dest are translated into wire arrays. Their raw descriptors never cross the boundary. Inside Plain payload schemas, reject Index and Domain-branded types transitively through aliases, records, sums, arrays, and existential packages, on input and output. Plain alone does not establish wire eligibility. Host graph endpoints must use ordinary U32 fields, then checked source validation against the newly frozen collection creates Index authority; output endpoints explicitly project back to U32. Erasing a tag's bytes does not erase this requirement.

The generated host API keeps raw memory private and exposes copied host values. There are no host callbacks/imports during execution. The host must not mutate private memory or windows while Busy. These are explicit trust-boundary conditions, not guarantees against a malicious holder of raw Wasm memory.

The wire header is eight U32 words: `abi_tag, export_id, status, payload_bytes, required_bytes, item_count, detail, reserved`. `abi_tag=0x4b310001`; reserved is zero. Scalars/fixed fields follow their Plain layout. Each array descriptor is `{count,byte_offset}` with an aligned range wholly within the payload area; offsets are relative to its beginning, never guest addresses. Array data must start after the fixed field/descriptor area. Input array ranges may overlap as immutable bytes; independent copies grant disjoint destination authority. Output payload starts with the sole result-array descriptor, followed by its canonical contiguous data. Padding is zero. A Unit array has zero data bytes, but count still must satisfy its input max_count or output logical bounds; its host value uses a compact `{length}` representation rather than allocating one host object per Unit.

The public Wasm entry takes `(export_id:i32, input_bytes:i32, output_capacity:i32)` and returns a status i32. It reads the fixed ingress window and writes a fixed 32-byte control header plus payload in the disjoint egress window. Window sizes include those headers and are at least 32 bytes. Require `32 <= input_bytes <= ingress_window_bytes`, ingress header payload_bytes equal to `input_bytes-32`, matching ABI/export identifiers, and ingress status/required_bytes/detail/reserved all zero. The schema supplies the required item_count value or requires zero. Require `output_capacity <= egress_window_bytes-32`; output_capacity counts only available payload bytes. Every check precedes a dependent memory access.

Status codes are `Ok=0`, `InvalidInput=1`, `OutputTooSmall=2`, `ReservationFailed=3`, `Busy=4`, `FrameLimit=5`, `LanguageError=6`. Detail uses the selected schema's stable error code or the reservation error tag. The generated host wrapper reports `Poisoned` separately after an engine trap; it does not attempt another invocation. A Busy rejection performs no state/window writes, because the active invocation owns them.

The required lifecycle is:

1. Check Busy before mutation; otherwise acquire the invocation guard. Validate export/schema identity, header values, bounds, every count/offset calculation, alignment, and Bool/tag validity. A count above its declared max_count is InvalidInput. Evaluate the completed function's numeric preconditions over validated scalar fields, lengths, and C using the specified checked predicates; a false precondition is InvalidInput. Unsupported preconditions make the export ineligible at compilation, not trusted at runtime.
2. Preflight frames and reserve one private invocation region using work_bytes. Copy and freeze each input in field order, then allocate the disjoint output Dest with capacity C. Source receives the record and validated hidden witnesses. Temporary descriptors and all allocations are covered by the resource plan; the remaining Space stays with the wrapper. Setup cannot exceed its admitted worst-case placement bound.
3. Execute once. Output is built into exclusive destinations in the same still-live invocation region. No host output is published during execution. A typed language error is encoded in the control header with the export's error code; no data payload is published.
4. Compute the complete checked output wire size. If it exceeds output_capacity, return OutputTooSmall with required_bytes and no payload publication. The function is not rerun internally. A later caller retry is a new observable invocation and requires no hidden replay semantics.
5. On success, copy the entire canonical result into egress payload and publish its Ok header last. Zero padding/inactive words prevents disclosure of uninitialized storage. The wrapper copies those bytes into host-owned values before another call may reuse the window.
6. On every normal/status path, discharge invocation loans/capabilities, close the private region if acquired, restore the frame frontier, and release Busy. Previous egress payload may remain physically present after errors, but is inaccessible through the API because status and payload_bytes publish no value.

`required_bytes` is exact only for Ok/OutputTooSmall and is zero for other statuses. `payload_bytes` is the published successful byte count, otherwise zero. `item_count` is the schema-designated primary array count, or zero when none; it is informational, never proof. OutputTooSmall is discovered after execution when output size is data-dependent, so this bridge permits only exports whose externally observable effects are their returned value and specified resource failure. Host effects, callbacks, persistent mutable state, and returned region ownership require a future protocol.

## M13. Legacy fence, certificate, and acceptance tests

The baseline compiler already has two-word closures, ownership contracts, and checked builder cleanup. Those are useful implementation starting points, not proof that its existing runtime has K1's ownership model. Its closure environment is currently classified as a reference; public owner leases form reference-bearing structures; and `region_runtime.complete` explicitly requires RC and root machinery. K1 MUST therefore have distinct semantic runtime roles or a separate checked lowering path. Relabeling an unvalidated pointer as an ordinary scalar does not implement this fence. Existing RC insertion, retaining, and heap finalization passes MUST NOT run on K1 values. [M-REF1–M-REF4]

Each admitted artifact supplies a structural certificate listing primitive IDs, memory map and imports, callable schemas/resource bounds, proof-erasure boundary, and all backing/placement/reset/close operations. A final validator checks: no `memory.grow`, legacy allocation/retain/release/collector helper, externref-owned object, unexpected host import, forged dictionary, or unregistered indirect target; all accesses are justified by admitted layout/bounds/initialization/provenance evidence; affine transitions and all exits balance; exported bridge resources and hashes agree. Runtime helper bodies are versioned trusted components with separately tested contracts. Certificate checks cannot merely trust a source-level `kernel` annotation.

Required acceptance families are:

- Bounds at zero, `n-1`, n, U32 maximum, exact capacity, empty and Unit arrays; failed size/alignment/rounding arithmetic changes no frontier.
- Disjoint split success, forged overlap rejection, mutable-input/output alias rejection, reset/close with live loan rejection, result/scratch confusion rejection.
- Partial initialization, truncate/re-extend, failure before and after element evaluation, sum padding, freeze/discard, and capability preservation on every allocation failure.
- Pool fragmentation, zero-byte regions, exhausted slots, rounded slack rejection, generation retirement, stale handles, repeated reserve/reset/close, and exact metadata accounting.
- Local/placed closures, escaping-frame rejection, foreign captured environment rejection, FnMany package movement, FnOnce/Owned capture rejection, and bounded indirect-call resources.
- Owned seal/error/open/move/close, no leaked external loans, no duplicate close, no nested ownership, and no payload traversal on close.
- ABI and schema-hash mismatches, generic zero-sized slots, aggregate error results, forged wire offsets/tags/counts, Busy rejection, all bridge cleanup paths, output-too-small publication, and poisoned-instance refusal.
- A structural assertion that representative K1 arrays, closures, and Owned results emit zero retain/release calls, zero collector calls, and no backing allocation inside a declared no-backing-allocation kernel. Placement into reserved destinations remains visible and counted.

### Pinned baseline references

- **M-REF1:** [Current runtime layouts](https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/zig-native/src/runtime/runtime_layout.zig): closure, owner lease, and counted arena representations.
- **M-REF2:** [Current region runtime](https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/zig-native/src/runtime/region_runtime.zig): region implementation depends on RC/root runtime.
- **M-REF3:** [Current runtime IR](https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/zig-native/src/backend/runtime_ir.zig): machine types, runtime roles, and single-result signatures.
- **M-REF4:** [Usage contracts](https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/zig-native/USAGE_CONTRACTS.md): existing lexical usage and callable multiplicity, including counted shared ownership that K1 does not inherit.
- **M-REF5:** [Builder contracts](https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/zig-native/RAGGED_BUILDERS.md): useful begin/fill/finish/discard, evaluation-order, and failure obligations.
