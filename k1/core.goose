// Experimental, in-memory representations for the private scalar fixture.
// They own only fixed-width values and retain no frontend or source pointers.
// These are not portable, canonical C05 artifacts: stable producer identity,
// semantic digests, ABI hash, dependencies, origins and certificates remain
// unimplemented. Do not decode untrusted cache bytes as these structures.
namespace core;

// Transient tags, not wire-format schema IDs. Every value is checked.
// edition/semantic/optimizer/ABI version 1 are respectively K1,
// K1-SEM-POLICY-1, K1-OPT-POLICY-1 and K1-WASM32-ABI1.
struct Header {
    edition: i64 = 1,
    semantic_policy: i64 = 1,
    optimizer_policy: i64 = 1,
    abi: i64 = 1,
    schema: i64 = 1
}

// Closed, monomorphic U32 -> U32, one parameter, noncapturing Many, no
// effects/contracts/binders/calls/captures, and a leaf depth of one.
struct CheckedInterface {
    header: Header = Header {},
    parameter_type: i64 = 1, // U32
    result_type: i64 = 1,    // U32
    parameter_count: i64 = 1,
    call_mode: i64 = 1,      // Many
    effects: i64 = 0,
    binders: i64 = 0,
    captures: i64 = 0,
    requires_count: i64 = 0,
    ensures_count: i64 = 0,
    depth: i64 = 1,
    frame_bytes: i64 = 0
}

// One entry block. Value 1 is the U32 parameter. For kind 2 the constant
// defines value 2 and the return consumes it; kind 1 returns value 1 directly.
// No effect, evidence, ownership or call operation exists in this subset.
struct CheckedFunction {
    interface: CheckedInterface = CheckedInterface {},
    block_count: i64 = 1,
    entry_block: i64 = 1,
    parameter_value: i64 = 1,
    operation_kind: i64 = 1, // 1 parameter, 2 U32 constant
    operation_result: i64 = 1,
    literal: u32 = 0,
    terminator: i64 = 1,     // return
    return_value: i64 = 1,
    call_count: i64 = 0,
    evidence_count: i64 = 0,
    ownership_count: i64 = 0,
    static_count: i64 = 0
}

// The full function is copied into the plan, so no compiler-session object is
// borrowed. One canonical (env i32, arg i32) -> i32 entry; no adapters,
// helper imports, backing allocation or memory.grow are admitted here.
struct LoweringPlan {
    function: CheckedFunction = CheckedFunction {},
    abi: i64 = 1,
    optimization_policy: i64 = 1,
    parameter_representation: i64 = 1, // i32
    result_representation: i64 = 1,    // i32
    environment_parameter: i64 = 1,
    result_slot: i64 = 0,
    adapter_count: i64 = 0,
    helper_count: i64 = 0,
    backing_allocation: i64 = 0,
    memory_grow: i64 = 0,
    memory_initial_pages: i64 = 275,
    memory_maximum_pages: i64 = 275,
    depth: i64 = 1,
    frame_bytes: i64 = 0
}

fn make_function(kind: i64, literal: u32) -> CheckedFunction {
    var function = CheckedFunction {};
    function.operation_kind = kind;
    function.literal = literal;
    if kind == 2 {
        function.operation_result = 2;
        function.return_value = 2;
    }
    return function;
}

fn make_plan(function: CheckedFunction) -> LoweringPlan {
    return LoweringPlan { function: function };
}

fn validate_header(h: Header) -> bool {
    return h.edition == 1 && h.semantic_policy == 1 &&
        h.optimizer_policy == 1 && h.abi == 1 && h.schema == 1;
}

fn validate_interface(i: CheckedInterface) -> i64 {
    if !validate_header(i.header) { return 1; }
    if i.parameter_type != 1 || i.result_type != 1 || i.parameter_count != 1 ||
       i.call_mode != 1 || i.effects != 0 || i.binders != 0 || i.captures != 0 ||
       i.requires_count != 0 || i.ensures_count != 0 || i.depth != 1 ||
       i.frame_bytes != 0 { return 1; }
    return 0;
}

fn validate_function(f: CheckedFunction) -> i64 {
    if validate_interface(f.interface) != 0 { return 1; }
    if f.block_count != 1 || f.entry_block != 1 || f.parameter_value != 1 ||
       f.terminator != 1 || f.call_count != 0 || f.evidence_count != 0 ||
       f.ownership_count != 0 || f.static_count != 0 { return 1; }
    if f.operation_kind == 1 {
        if f.operation_result != 1 || f.return_value != 1 || f.literal != 0 { return 1; }
    } else if f.operation_kind == 2 {
        if f.operation_result != 2 || f.return_value != 2 { return 1; }
    } else { return 1; }
    return 0;
}

fn validate_plan(p: LoweringPlan) -> i64 {
    if validate_function(p.function) != 0 { return 1; }
    if p.abi != 1 || p.optimization_policy != 1 ||
       p.abi != p.function.interface.header.abi ||
       p.optimization_policy != p.function.interface.header.optimizer_policy ||
       p.parameter_representation != 1 || p.result_representation != 1 ||
       p.environment_parameter != 1 || p.result_slot != 0 || p.adapter_count != 0 ||
       p.helper_count != 0 || p.backing_allocation != 0 || p.memory_grow != 0 ||
       p.memory_initial_pages != 275 || p.memory_maximum_pages != 275 ||
       p.depth != p.function.interface.depth ||
       p.frame_bytes != p.function.interface.frame_bytes { return 1; }
    return 0;
}
