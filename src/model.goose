// Shared K1 flat-table schema. Root-owned; coordinate schema changes.
// ID 0 is absent; row tables have a zero sentinel. refs and bytes are raw arenas.
import std;

let SEM_POLICY: u32 = 1;
let OPT_POLICY: u32 = 1;
let ABI_HASH: u8[32] = [0xc2, 0x8c, 0xdf, 0xcb, 0xe3, 0x7b, 0xe7, 0xdb, 0xe9, 0x0a, 0xcf, 0x94, 0x4c, 0x4d, 0xad, 0x91, 0x19, 0x81, 0xe8, 0x84, 0x27, 0xe0, 0xd2, 0x9a, 0x3a, 0x24, 0x04, 0xb3, 0x54, 0xf0, 0xf4, 0x2f];
let ABI_HASH_HEX = "c28cdfcbe37be7dbe90acf944c4dad911981e88427e0d29a3a2404b354f0f42f";
let ABI_VERSION: u32 = 0x4b310001;
let MAX_U32: u64 = 4294967295;
let LIMIT_SOURCE: u32 = 16777216;
let LIMIT_VISITS: u32 = 1048576;
let LIMIT_OPS: u32 = 65536;
let LIMIT_BLOCKS: u32 = 4096;
let LIMIT_TYPES: u32 = 8192;
let LIMIT_TERMS: u32 = 4096;
let LIMIT_FACT_EDGES: u32 = 16384;
let LIMIT_PROOF_VISITS: u32 = 65536;
let LIMIT_NEST: u32 = 64;
let LIMIT_BINDERS: u32 = 32;
let LIMIT_ARTIFACT: u32 = 16777216;

let TY_INVALID: u32 = 0;
let TY_UNIT: u32 = 1;
let TY_BOOL: u32 = 2;
let TY_U32: u32 = 3;
let TY_F32: u32 = 4;
let TY_TUPLE: u32 = 5;
let TY_RECORD: u32 = 6;
let TY_SUM: u32 = 7;
let TY_RESULT: u32 = 8;
let TY_VIEW: u32 = 9;
let TY_INDEX: u32 = 10;
let TY_REGION_OWNER: u32 = 11;
let TY_SPACE: u32 = 12;
let TY_DEST: u32 = 13;
let TY_ENV_DEST: u32 = 14;
let TY_BUILDER: u32 = 15;
let TY_FN: u32 = 16;
let TY_OWNED: u32 = 17;
let TY_FORALL: u32 = 18;
let TY_EXISTS: u32 = 19;
let TY_PARAM: u32 = 20;
let TY_ALIAS: u32 = 21;

let TY_OWNED_CONSTRUCTION: u32 = 22;

let KIND_INVALID: u32 = 0;
let KIND_TYPE: u32 = 1;
let KIND_REGION: u32 = 2;
let KIND_NAT: u32 = 3;
let KIND_DOMAIN: u32 = 4;

let CONSTRAINT_PLAIN: u32 = 1;
let CONSTRAINT_SHARE: u32 = 2;

let MODE_INVALID: u32 = 0;
let MODE_MANY: u32 = 1;
let MODE_ONCE: u32 = 2;
let MODE_APPEND: u32 = 3;
let MODE_RESIZE: u32 = 4;

let OP_INVALID: u32 = 0;
let OP_UNIT: u32 = 1;
let OP_BOOL: u32 = 2;
let OP_U32: u32 = 3;
let OP_F32: u32 = 4;
let OP_COPY: u32 = 5;
let OP_TUPLE: u32 = 6;
let OP_RECORD: u32 = 7;
let OP_PROJECT: u32 = 8;
let OP_SUM: u32 = 9;
let OP_TAG: u32 = 10;
let OP_PAYLOAD: u32 = 11;
let OP_CALL: u32 = 12;
let OP_CALL_INDIRECT: u32 = 13;
let OP_CLOSURE: u32 = 14;
let OP_PACK: u32 = 15;
let OP_OPEN: u32 = 16;
let OP_U32_ADD: u32 = 17;
let OP_U32_SUB: u32 = 18;
let OP_U32_MUL: u32 = 19;
let OP_U32_DIV: u32 = 20;
let OP_U32_REM: u32 = 21;
let OP_U32_ADD_WRAP: u32 = 22;
let OP_U32_SUB_WRAP: u32 = 23;
let OP_U32_MUL_WRAP: u32 = 24;
let OP_U32_EQ: u32 = 25;
let OP_U32_NE: u32 = 26;
let OP_U32_LT: u32 = 27;
let OP_U32_LE: u32 = 28;
let OP_U32_GT: u32 = 29;
let OP_U32_GE: u32 = 30;
let OP_U32_AND: u32 = 31;
let OP_U32_OR: u32 = 32;
let OP_U32_XOR: u32 = 33;
let OP_U32_SHL: u32 = 34;
let OP_U32_SHR: u32 = 35;
let OP_F32_ADD: u32 = 36;
let OP_F32_SUB: u32 = 37;
let OP_F32_MUL: u32 = 38;
let OP_F32_DIV: u32 = 39;
let OP_F32_NEG: u32 = 40;
let OP_F32_EQ: u32 = 41;
let OP_F32_NE: u32 = 42;
let OP_F32_LT: u32 = 43;
let OP_F32_LE: u32 = 44;
let OP_F32_GT: u32 = 45;
let OP_F32_GE: u32 = 46;
let OP_BOOL_NOT: u32 = 47;
let OP_ADD_FITS: u32 = 48;
let OP_SUB_FITS: u32 = 49;
let OP_MUL_FITS: u32 = 50;
let OP_CHECKED_ADD: u32 = 51;
let OP_CHECKED_SUB: u32 = 52;
let OP_CHECKED_MUL: u32 = 53;
let OP_RESERVE: u32 = 54;
let OP_REGION_CLOSE: u32 = 55;
let OP_REGION_RESET: u32 = 56;
let OP_SPACE_END: u32 = 57;
let OP_TRY_ALLOC: u32 = 58;
let OP_DEST_SPLIT: u32 = 59;
let OP_DEST_DISCARD: u32 = 60;
let OP_BUILDER_BEGIN: u32 = 61;
let OP_BUILDER_APPEND: u32 = 62;
let OP_BUILDER_TRY_APPEND: u32 = 63;
let OP_BUILDER_SET: u32 = 64;
let OP_BUILDER_TRUNCATE: u32 = 65;
let OP_BUILDER_FREEZE: u32 = 66;
let OP_BUILDER_DISCARD: u32 = 67;
let OP_VIEW_LEN: u32 = 68;
let OP_VIEW_INDEX: u32 = 69;
let OP_VIEW_SLICE: u32 = 70;
let OP_TRY_INDEX: u32 = 71;
let OP_INDEX_VALUE: u32 = 72;
let OP_OWNED_BEGIN: u32 = 73;
let OP_OWNED_SEAL: u32 = 74;
let OP_OWNED_ABORT: u32 = 75;
let OP_OWNED_OPEN: u32 = 76;
let OP_OWNED_CLOSE: u32 = 77;
let OP_LOAN_END: u32 = 78;
let OP_DISCARD_ONCE: u32 = 79;
let OP_STATIC: u32 = 80;
let OP_U32_TO_F32: u32 = 81;
let OP_F32_TO_U32: u32 = 82;
let OP_LAYOUT_SIZE: u32 = 83;
let OP_LAYOUT_ALIGN: u32 = 84;
let OP_BOOL_AND: u32 = 85;
let OP_BOOL_OR: u32 = 86;

let OP_ENV_TRY_ALLOC: u32 = 87;
let OP_FN_PLACE: u32 = 88;
let OP_BUILDER_LEN: u32 = 89;
let OP_BUILDER_CAP: u32 = 90;
let OP_BUILDER_GET: u32 = 91;
let OP_DEST_CAP: u32 = 92;
let OP_F32_SQRT: u32 = 93;
let OP_F32_ABS: u32 = 94;
let OP_F32_MIN: u32 = 95;
let OP_F32_MAX: u32 = 96;
let OP_F32_CEIL: u32 = 97;
let OP_F32_FLOOR: u32 = 98;
let OP_F32_TRUNC: u32 = 99;
let OP_F32_NEAREST: u32 = 100;
let OP_F32_FROM_BITS: u32 = 101;
let OP_F32_TO_BITS: u32 = 102;
let OP_U32_NOT: u32 = 103;

// Bit-pattern conversion tags are internal ABI/static-evaluator operations,
// never source bitcasts. F32_TO_U32 is fallible Result, not trapping truncation.
let OP_CHECKED_DIV: u32 = 104;
let OP_CHECKED_SHL: u32 = 105;
let OP_CHECKED_SHR: u32 = 106;

let OP_DESTRUCTURE: u32 = 107;

let OP_NAT_VALUE: u32 = 108;

let OP_REFINE: u32 = 109;

let OP_FN_WEAKEN: u32 = 110;

// Lexical rank-1 declaration boundary. No first-class value or runtime code.
// args are immutable Share captures; imm0 names the once-checked generic body.
let OP_GENERIC_BIND: u32 = 111;

let TERM_INVALID: u32 = 0;
let TERM_JUMP: u32 = 1;
let TERM_BRANCH: u32 = 2;
let TERM_SWITCH: u32 = 3;
let TERM_RETURN: u32 = 4;
let TERM_UNREACHABLE: u32 = 5;

let FACT_INVALID: u32 = 0;
let FACT_EQ: u32 = 1;
let FACT_LT: u32 = 2;
let FACT_LE: u32 = 3;
let FACT_ADD_FITS: u32 = 4;
let FACT_SUB_FITS: u32 = 5;
let FACT_MUL_FITS: u32 = 6;
let FACT_INDEX: u32 = 7;

let EXPR_INVALID: u32 = 0;
let EXPR_LITERAL: u32 = 1;
let EXPR_VALUE: u32 = 2;
let EXPR_BINDER: u32 = 3;
let EXPR_LEN: u32 = 4;
let EXPR_CAP: u32 = 5;
let EXPR_INIT: u32 = 6;
let EXPR_MAX_MINUS: u32 = 7;
let EXPR_FIELD: u32 = 8;
let EXPR_ADD: u32 = 9;
let EXPR_SUB: u32 = 10;
let EXPR_MUL: u32 = 11;

let EXPR_ARG: u32 = 12;
let EXPR_RESULT: u32 = 13;

let RULE_INVALID: u32 = 0;
let RULE_REFLEXIVE: u32 = 1;
let RULE_LITERAL: u32 = 2;
let RULE_U32_BOUNDS: u32 = 3;
let RULE_ASSUMPTION: u32 = 4;
let RULE_EQUALITY: u32 = 5;
let RULE_TRANSITIVE: u32 = 6;
let RULE_COMPARE_TRUE: u32 = 7;
let RULE_COMPARE_FALSE: u32 = 8;
let RULE_SUB_FROM_LE: u32 = 9;
let RULE_ADD_FROM_COMPLEMENT: u32 = 10;
let RULE_MUL_CONSTANT: u32 = 11;
let RULE_CHECKED_SUCCESS: u32 = 12;
let RULE_SUCCESSOR: u32 = 13;
let RULE_INDEX_BOUND: u32 = 14;
let RULE_CONTRACT: u32 = 15;
let RULE_LOOP_INVARIANT: u32 = 16;
let RULE_JOIN: u32 = 17;
let RULE_LEN: u32 = 18;
let RULE_CONST_EVAL: u32 = 19;

let RULE_LOOP_RANGE: u32 = 20;
let RULE_ADD_SYMMETRY: u32 = 21;
let RULE_COMPLEMENT_ORDER: u32 = 22;
let RULE_CAPTURE: u32 = 23;
let RULE_BOOL_PATH: u32 = 24;

let SCOPE_INVALID: u32 = 0;
let SCOPE_MODULE: u32 = 1;
let SCOPE_FUNCTION: u32 = 2;
let SCOPE_BLOCK: u32 = 3;
let SCOPE_REGION: u32 = 4;
let SCOPE_PACKAGE: u32 = 5;
let SCOPE_LOAN: u32 = 6;
let SCOPE_OWNED: u32 = 7;

let EFFECT_INVALID: u32 = 0;
let EFFECT_READ: u32 = 1;
let EFFECT_WRITE: u32 = 2;
let EFFECT_PLACE: u32 = 3;
let EFFECT_RESET: u32 = 4;
let EFFECT_RESERVE: u32 = 5;
let EFFECT_RELEASE: u32 = 6;
let EFFECT_HOST: u32 = 7;

let ABI_INVALID: u32 = 0;
let ABI_UNIT: u32 = 1;
let ABI_I32: u32 = 2;
let ABI_F32: u32 = 3;
let ABI_INDIRECT: u32 = 4;

let EDGE_INVALID: u32 = 0;
let EDGE_NORMAL: u32 = 1;
let EDGE_TRUE: u32 = 2;
let EDGE_FALSE: u32 = 3;
let EDGE_CASE: u32 = 4;
let EDGE_LOOP_ENTRY: u32 = 5;
let EDGE_LOOP_NEXT: u32 = 6;
let EDGE_LOOP_STOP: u32 = 7;

let DEP_INVALID: u32 = 0;
let DEP_INTERFACE: u32 = 1;
let DEP_BODY: u32 = 2;
let DEP_STATIC: u32 = 3;
let DEP_ABI: u32 = 4;
let DEP_CAPTURE: u32 = 5;
let DEP_OPERATION: u32 = 6;
let DEP_NEGATIVE: u32 = 7;

let PHASE_BUILD: u32 = 0;
let PHASE_COMPLETE: u32 = 1;
let PHASE_SEALED: u32 = 2;
let PHASE_LOWERING: u32 = 3;

struct Span { start: u32, count: u32 }
struct Diagnostic { code: u32, origin: u32, detail: u32, related: u32 }
struct Work { visits: u64, proof_visits: u64, opt_visits: u64, rewrites: u64, allocations: u64, allocation_limit: u64, exhausted: bool, static_steps: u64, static_bytes: u64, interface_instantiations: u64 }
struct PhaseGuard { phase: u32, active: u32, created: u64, completed: u64, sealed_created: u64 }
struct Name { bytes: Span }
struct Origin { module: u32, start: u32, end: u32 }
struct Module { name: u32, path: u32, imports: Span, declarations: Span, source: Span }
let INTRO_NONE: u32 = 0;
let INTRO_FUNCTION: u32 = 1;
let INTRO_OPERATION: u32 = 2;
struct Binder { introduction_kind: u32, kind: u32, constraints: u32, scope: u32, introduction: u32, name: u32, origin: u32 }
struct Scope { parent: u32, kind: u32, binder: u32, origin: u32 }
struct TypeNode { tag: u32, children: Span, fields: Span, binders: Span, region: u32, nat: u32, domain: u32, capacity: u32, mode: u32, contract: u32, binder: u32, origin: u32 }
struct Field { name: u32, type_id: u32, offset: u32, tag: u32 }
struct Contract { layout_premises: Span, arg: u32, result: u32, binders: Span, requires: Span, ensures: Span, on_true: Span, on_false: Span, effects: Span, depth: u32, frame: u32, origin: u32 }
struct Effect { kind: u32, region: u32 }
struct Value { type_id: u32, block_id: u32, op: u32, version: u32, scope: u32, origin: u32 }
struct Operation { tag: u32, registry: u32, args: Span, results: Span, evidence: Span, substitutions: Span, scope: u32, origin: u32, imm0: u32, imm1: u32 }
struct Block { merge: u32, params: Span, evidence_params: Span, ops: Span, term: u32, scope: u32, function: u32, origin: u32 }
struct Terminator { evidence: Span, tag: u32, subject: u32, edges: Span, discharge: Span, origin: u32 }
struct Edge { from: u32, to: u32, args: Span, evidence: Span, kind: u32, loop_id: u32, case_tag: u32 }
struct Term { tag: u32, type_id: u32, value: u32, binder: u32, args: Span, literal: u32, version: u32, scope: u32 }
struct Fact { tag: u32, left: u32, right: u32, third: u32, domain: u32, version: u32 }
struct Evidence { rule: u32, fact: u32, contract: u32, formal_fact: u32, call: u32, scope: u32, edge: u32, operands: Span, premises: Span, origin: u32 }
struct Loop { header: u32, body: u32, exit: u32, index: u32, lower: u32, upper: u32, carries: Span, invariant: Span, backedges: Span, exits: Span }
struct Function { evaluator_only: bool, environment_bindings: Span, visibility: u32, name: u32, module: u32, type_id: u32, contract: u32, param: u32, entry: u32, blocks: Span, captures: Span, calls: Span, binders: Span, export_id: u32, producer: u32, origin: u32 }
struct Call { op: u32, caller: u32, callee: u32, contract: u32, substitutions: Span }
struct Substitution { binder: u32, kind: u32, value: u32 }
struct Capture { function: u32, value: u32, local_value: u32, field: u32, scope: u32 }
struct Loan { value: u32, owner: u32, scope: u32, kind: u32, begin_op: u32, end_op: u32 }
struct Transition { op: u32, value: u32, before: u32, after: u32, authority: u32, scope: u32 }
struct Layout { type_id: u32, size: u32, align: u32, flags: u32, abi: u32, schema: u32, fields: Span, depth: u32, leaves: u32, guards: u32 }
struct Interface { abi_digest: Span, function: u32, type_id: u32, contract: u32, dependencies: Span, digest: Span, producer: u32 }
struct Dependency { query_kind: u32, kind: u32, producer: u32, identity: Span, digest: Span, present: bool }
struct Receipt { producer: u32, source_digest: Span, semantic_digest: Span, dependencies: Span, completed_visits: u64 }
struct Export { function: u32, name: u32, kind: u32, arg_type: u32, result_type: u32, substitutions: Span, fields: Span, input_maxima: Span, output_capacity: u32, work_bytes: u32, frame: u32, depth: u32, abi_digest: Span }

let EXPORT_SCALAR: u32 = 1;
let EXPORT_BRIDGE: u32 = 2;

let VIS_PRIVATE: u32 = 0;
let VIS_PUBLIC: u32 = 1;
let DEF_FUNCTION: u32 = 1;
let DEF_TYPE: u32 = 2;
let DEF_STATIC: u32 = 3;
let NAT_HIDDEN: u32 = 0;
let NAT_VIEW_LEN: u32 = 1;
let NAT_DEST_CAP: u32 = 2;
let NAT_BUILDER_INIT: u32 = 3;
let NAT_BUILDER_CAP: u32 = 4;
let NAT_PACKAGE_PREFIX: u32 = 5;
struct Definition { kind: u32, name: u32, module: u32, type_id: u32, value: u32, function: u32, binders: Span, visibility: u32, origin: u32 }
struct AbiPlan { contract: u32, function: u32, arg_layout: u32, result_layout: u32, env_layout: u32, dictionaries: Span, nat_witnesses: Span, frame: u32, depth: u32, version: u32 }
struct NatWitness { binder: u32, argument_path: Span, selector: u32, prefix_index: u32 }

struct EnvironmentBinding { function: u32, kind: u32, binder: u32, offset: u32, source_value: u32 }

struct Schema { bytes: Span, digest: Span }

struct DictionaryRealization { type_id: u32, parameters: Span, arguments: Span, concrete_type: u32, layout: u32 }

struct CallableAdapter { op: u32, target_function: u32, callback_contract: u32, captures: Span, environment_layout: u32, target_environment_offset: u32 }
struct AdapterCapture { kind: u32, source: u32, offset: u32 }

let STATIC_ARRAY: u32 = 1;
let STATIC_VALUE: u32 = 2;
let STATIC_ENVIRONMENT: u32 = 3;
let STATIC_ADDRESS: u32 = 1;
let STATIC_FUNCTION: u32 = 2;
let STATIC_CLOSURE: u32 = 3;
let STATIC_DICTIONARY: u32 = 4;
struct StaticObject { function: u32, constructor: u32, kind: u32, type_id: u32, element_type: u32, count: u32, domain: u32, bytes: Span, relocations: Span, producer: u32, steps: u32 }
struct StaticRelocation { offset: u32, kind: u32, target: u32, addend: u32 }

let LAYOUT_AGGREGATE: u32 = 1;
let LAYOUT_PLAIN: u32 = 2;
struct LayoutPremise { type_id: u32, kind: u32 }

struct Core {
    layout_premises: const LayoutPremise[:],
    dictionary_realizations: const DictionaryRealization[:],
    static_relocations: const StaticRelocation[:],
    static_objects: const StaticObject[:],
    adapter_captures: const AdapterCapture[:],
    callable_adapters: const CallableAdapter[:],
    schemas: const Schema[:],
    environment_bindings: const EnvironmentBinding[:],
    nat_witnesses: const NatWitness[:],
    abi_plans: const AbiPlan[:],
    definitions: const Definition[:],
    names: const Name[:],
    origins: const Origin[:],
    modules: const Module[:],
    binders: const Binder[:],
    scopes: const Scope[:],
    types: const TypeNode[:],
    fields: const Field[:],
    contracts: const Contract[:],
    effects: const Effect[:],
    values: const Value[:],
    ops: const Operation[:],
    blocks: const Block[:],
    terminators: const Terminator[:],
    edges: const Edge[:],
    terms: const Term[:],
    facts: const Fact[:],
    evidence: const Evidence[:],
    loops: const Loop[:],
    functions: const Function[:],
    calls: const Call[:],
    substitutions: const Substitution[:],
    captures: const Capture[:],
    loans: const Loan[:],
    transitions: const Transition[:],
    layouts: const Layout[:],
    interfaces: const Interface[:],
    dependencies: const Dependency[:],
    receipts: const Receipt[:],
    exports: const Export[:],
    refs: const u32[:],
    bytes: const u8[:],
    phase: PhaseGuard,
}

struct CoreBuilder {
    layout_premises: LayoutPremise[>..]&,
    dictionary_realizations: DictionaryRealization[>..]&,
    static_relocations: StaticRelocation[>..]&,
    static_objects: StaticObject[>..]&,
    adapter_captures: AdapterCapture[>..]&,
    callable_adapters: CallableAdapter[>..]&,
    schemas: Schema[>..]&,
    environment_bindings: EnvironmentBinding[>..]&,
    nat_witnesses: NatWitness[>..]&,
    abi_plans: AbiPlan[>..]&,
    definitions: Definition[>..]&,
    names: Name[>..]&,
    origins: Origin[>..]&,
    modules: Module[>..]&,
    binders: Binder[>..]&,
    scopes: Scope[>..]&,
    types: TypeNode[>..]&,
    fields: Field[>..]&,
    contracts: Contract[>..]&,
    effects: Effect[>..]&,
    values: Value[>..]&,
    ops: Operation[>..]&,
    blocks: Block[>..]&,
    terminators: Terminator[>..]&,
    edges: Edge[>..]&,
    terms: Term[>..]&,
    facts: Fact[>..]&,
    evidence: Evidence[>..]&,
    loops: Loop[>..]&,
    functions: Function[>..]&,
    calls: Call[>..]&,
    substitutions: Substitution[>..]&,
    captures: Capture[>..]&,
    loans: Loan[>..]&,
    transitions: Transition[>..]&,
    layouts: Layout[>..]&,
    interfaces: Interface[>..]&,
    dependencies: Dependency[>..]&,
    receipts: Receipt[>..]&,
    exports: Export[>..]&,
    refs: u32[>..]&,
    bytes: u8[>..]&,
    phase: PhaseGuard&,
}

fn core_view(b: CoreBuilder) -> Core {
    Core {
        layout_premises: b.layout_premises[..],
        dictionary_realizations: b.dictionary_realizations[..],
        static_relocations: b.static_relocations[..],
        static_objects: b.static_objects[..],
        adapter_captures: b.adapter_captures[..],
        callable_adapters: b.callable_adapters[..],
        schemas: b.schemas[..],
        environment_bindings: b.environment_bindings[..],
        nat_witnesses: b.nat_witnesses[..],
        abi_plans: b.abi_plans[..],
        definitions: b.definitions[..],
        names: b.names[..],
        origins: b.origins[..],
        modules: b.modules[..],
        binders: b.binders[..],
        scopes: b.scopes[..],
        types: b.types[..],
        fields: b.fields[..],
        contracts: b.contracts[..],
        effects: b.effects[..],
        values: b.values[..],
        ops: b.ops[..],
        blocks: b.blocks[..],
        terminators: b.terminators[..],
        edges: b.edges[..],
        terms: b.terms[..],
        facts: b.facts[..],
        evidence: b.evidence[..],
        loops: b.loops[..],
        functions: b.functions[..],
        calls: b.calls[..],
        substitutions: b.substitutions[..],
        captures: b.captures[..],
        loans: b.loans[..],
        transitions: b.transitions[..],
        layouts: b.layouts[..],
        interfaces: b.interfaces[..],
        dependencies: b.dependencies[..],
        receipts: b.receipts[..],
        exports: b.exports[..],
        refs: b.refs[..],
        bytes: b.bytes[..],
        phase: b.phase,
    }
}

fn with_core<F>() {
    var layout_premises: LayoutPremise[>..] = [LayoutPremise { .. }];
    var dictionary_realizations: DictionaryRealization[>..] = [DictionaryRealization { .. }];
    var static_relocations: StaticRelocation[>..] = [StaticRelocation { .. }];
    var static_objects: StaticObject[>..] = [StaticObject { .. }];
    var adapter_captures: AdapterCapture[>..] = [AdapterCapture { .. }];
    var callable_adapters: CallableAdapter[>..] = [CallableAdapter { .. }];
    var schemas: Schema[>..] = [Schema { .. }];
    var environment_bindings: EnvironmentBinding[>..] = [EnvironmentBinding { .. }];
    var nat_witnesses: NatWitness[>..] = [NatWitness { .. }];
    var abi_plans: AbiPlan[>..] = [AbiPlan { .. }];
    var definitions: Definition[>..] = [Definition { .. }];
    var names: Name[>..] = [Name { .. }];
    var origins: Origin[>..] = [Origin { .. }];
    var modules: Module[>..] = [Module { .. }];
    var binders: Binder[>..] = [Binder { .. }];
    var scopes: Scope[>..] = [Scope { .. }];
    var types: TypeNode[>..] = [TypeNode { .. }];
    var fields: Field[>..] = [Field { .. }];
    var contracts: Contract[>..] = [Contract { .. }];
    var effects: Effect[>..] = [Effect { .. }];
    var values: Value[>..] = [Value { .. }];
    var ops: Operation[>..] = [Operation { .. }];
    var blocks: Block[>..] = [Block { .. }];
    var terminators: Terminator[>..] = [Terminator { .. }];
    var edges: Edge[>..] = [Edge { .. }];
    var terms: Term[>..] = [Term { .. }];
    var facts: Fact[>..] = [Fact { .. }];
    var evidence: Evidence[>..] = [Evidence { .. }];
    var loops: Loop[>..] = [Loop { .. }];
    var functions: Function[>..] = [Function { .. }];
    var calls: Call[>..] = [Call { .. }];
    var substitutions: Substitution[>..] = [Substitution { .. }];
    var captures: Capture[>..] = [Capture { .. }];
    var loans: Loan[>..] = [Loan { .. }];
    var transitions: Transition[>..] = [Transition { .. }];
    var layouts: Layout[>..] = [Layout { .. }];
    var interfaces: Interface[>..] = [Interface { .. }];
    var dependencies: Dependency[>..] = [Dependency { .. }];
    var receipts: Receipt[>..] = [Receipt { .. }];
    var exports: Export[>..] = [Export { .. }];
    var refs: u32[>..] = [];
    var bytes: u8[>..] = [];
    var phase = PhaseGuard { .. };
    let b = CoreBuilder {
        layout_premises: layout_premises,
        dictionary_realizations: dictionary_realizations,
        static_relocations: static_relocations,
        static_objects: static_objects,
        adapter_captures: adapter_captures,
        callable_adapters: callable_adapters,
        schemas: schemas,
        environment_bindings: environment_bindings,
        nat_witnesses: nat_witnesses,
        abi_plans: abi_plans,
        definitions: definitions,
        names: names,
        origins: origins,
        modules: modules,
        binders: binders,
        scopes: scopes,
        types: types,
        fields: fields,
        contracts: contracts,
        effects: effects,
        values: values,
        ops: ops,
        blocks: blocks,
        terminators: terminators,
        edges: edges,
        terms: terms,
        facts: facts,
        evidence: evidence,
        loops: loops,
        functions: functions,
        calls: calls,
        substitutions: substitutions,
        captures: captures,
        loans: loans,
        transitions: transitions,
        layouts: layouts,
        interfaces: interfaces,
        dependencies: dependencies,
        receipts: receipts,
        exports: exports,
        refs: refs,
        bytes: bytes,
        phase: phase,
    };
    F(b);
}

fn span_ok(s: Span, length: i64) -> bool {
    (s.start as u64) <= length as u64 && (s.count as u64) <= length as u64 - s.start as u64
}
fn id_ok(id: u32, length: i64) -> bool { id != 0 && (id as u64) < length as u64 }
fn ref_span(b: CoreBuilder, values: const u32[:]) -> Span {
    let s = Span { start: b.refs.len as u32, count: values.len as u32 };
    b.refs.append(values);
    return s;
}
fn add_name(b: CoreBuilder, value: const u8[:]) -> u32 {
    // Names are interned; source-byte identity does not depend on addresses.
    for n, i in b.names {
        if i != 0 && b.bytes[n.bytes.start..n.bytes.start + n.bytes.count] == value { return i as u32; }
    }
    let id = b.names.len as u32;
    b.names.push(Name { bytes: Span { start: b.bytes.len as u32, count: value.len as u32 } });
    b.bytes.append(value);
    return id;
}
fn name_bytes(c: Core, id: u32) -> const u8[:] {
    if !id_ok(id, c.names.len) { return c.bytes[..0]; }
    let s = c.names[id].bytes;
    if !span_ok(s, c.bytes.len) { return c.bytes[..0]; }
    return c.bytes[s.start..s.start + s.count];
}
fn begin_completion(b: CoreBuilder) -> bool {
    if b.phase.phase >= PHASE_SEALED { return false; }
    b.phase.phase = PHASE_COMPLETE;
    b.phase.active++;
    b.phase.created++;
    return true;
}
fn end_completion(b: CoreBuilder) -> bool {
    if b.phase.active == 0 { return false; }
    b.phase.active--;
    b.phase.completed++;
    return true;
}
fn seal_completion(b: CoreBuilder) -> bool {
    if b.phase.active != 0 || b.phase.completed != b.phase.created { return false; }
    b.phase.sealed_created = b.phase.created;
    b.phase.phase = PHASE_SEALED;
    return true;
}
fn charge(work: Work&, amount: u64, limit: u64) -> bool {
    if work.visits > limit || amount > limit - work.visits { work.exhausted = true; return false; }
    work.visits += amount;
    return true;
}
fn allocation(work: Work&) -> bool {
    if work.allocation_limit != 0 && work.allocations >= work.allocation_limit { work.exhausted = true; return false; }
    work.allocations++;
    return true;
}
