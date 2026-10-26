# Private static-array publication witness

A single source-owned, nonempty homogeneous tuple array accepted by the
private `static_product` evaluator is re-recognized and evaluated before a
private image can be emitted. The independent image checker verifies exact
source, shape, evaluation result, fixture step count and every immutable data
byte. The final target checker separately reconstructs the complete expected
Wasm bytes. Evaluation, limit, geometry or verification failure yields no
module. This private accounting is not the shared C09 semantic-work receipt.

The emitted module initializes a fixed, unexported memory with the checked
static bytes. It exports bounded read, length and width test functions, imports
nothing and contains no store. The memory and its bytes belong to each Wasm
instance, and cannot be mutated through this interface. Equivalent source
arrays may produce identical module bytes; separate instances still have
separate memory. This is a small executable publication witness, not the
complete static memory map, canonical K1 public ABI, export bridge, or M13
certificate.

The separate JavaScript test adapter creates per-instance opaque index objects
and tracks their positions in a private WeakMap. It rejects a token issued by
another instance, even when their source and bytes are equal. This is an
executable isolation model only: it is not K1's erased, statically checked
`Index[d,n]` or a compiler-owned module-instance Domain authority. The adapter
assumes it is passed the compiler-verified fixture bytes; it does not
independently authenticate an arbitrary module. Proper K1 Domain identity must
be derived from a trusted module instance and declaration and checked during
typing/proof admission, without exposing an integer witness as authority.

Only the existing nonempty static tuple-array subset is admitted; calls inside
array fields, empty arrays, generic static storage, multiple declarations,
portable artifacts and general source evaluation are unsupported. The 4 MiB
and 100,000-step helpers apply under the existing fixture's local charging
rules; there is no complete shared 1,048,576-visit receipt or full C09 meter.
