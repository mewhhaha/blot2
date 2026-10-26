import std;
import os;
import src.wasm;
import src.frontend;
import src.plan;
import src.fingerprint;
import src.coverage;
import .wasm_validation_test;

fn bridge_layout(b: CoreBuilder, type_id: u32, size: u32, flags: u32, abi: u32) {
  b.layouts.push(Layout {type_id: type_id, size: size, align: if size == 0 {1} else {4}, flags: flags, abi: abi, schema: type_id, ..});
}
fn bridge_fixture(b: CoreBuilder) {
  // Source-independent backend fixture; source admission has separate tests.
  b.scopes.push(Scope {kind: SCOPE_FUNCTION, ..});
  for kind in [KIND_REGION, KIND_NAT, KIND_DOMAIN, KIND_NAT, KIND_NAT, KIND_DOMAIN] {
    b.binders.push(Binder {kind: kind, scope: 1, ..});
  }
  b.terms.push(Term {tag: EXPR_BINDER, binder: 2, ..});
  b.terms.push(Term {tag: EXPR_BINDER, binder: 4, ..});
  b.terms.push(Term {tag: EXPR_BINDER, binder: 5, ..});
  b.types.push(TypeNode {tag: TY_UNIT, ..});
  b.types.push(TypeNode {tag: TY_U32, ..});
  b.types.push(TypeNode {tag: TY_VIEW, children: ref_span(b, [2]), region: 1, nat: 1, domain: 3, ..});
  b.types.push(TypeNode {tag: TY_DEST, children: ref_span(b, [2]), region: 1, capacity: 2, ..});
  b.fields.push(Field {name: add_name(b, "src"), type_id: 3, offset: 0, ..});
  b.fields.push(Field {name: add_name(b, "dst"), type_id: 4, offset: 8, ..});
  b.types.push(TypeNode {tag: TY_RECORD, fields: ref_span(b, [1, 2]), ..});
  b.types.push(TypeNode {tag: TY_VIEW, children: ref_span(b, [2]), region: 1, nat: 3, domain: 6, ..});
  b.types.push(TypeNode {tag: TY_EXISTS, children: ref_span(b, [6]), binders: ref_span(b, [5, 6]), ..});
  b.types.push(TypeNode {tag: TY_RESULT, children: ref_span(b, [7, 1]), ..});
  b.contracts.push(Contract {arg: 5, result: 8, binders: ref_span(b, [1, 2, 3, 4]), frame: 60, depth: 1, ..});
  b.types.push(TypeNode {tag: TY_FN, children: ref_span(b, [5, 8]), contract: 1, mode: MODE_MANY, ..});
  bridge_layout(b, 1, 0, 7, ABI_UNIT); bridge_layout(b, 2, 4, 3, ABI_I32);
  bridge_layout(b, 3, 8, 2, ABI_INDIRECT); bridge_layout(b, 4, 8, 0, ABI_INDIRECT);
  bridge_layout(b, 5, 16, 0, ABI_INDIRECT); bridge_layout(b, 6, 8, 2, ABI_INDIRECT);
  bridge_layout(b, 7, 12, 2, ABI_INDIRECT); bridge_layout(b, 8, 16, 0, ABI_INDIRECT);
  bridge_layout(b, 9, 8, 2, ABI_INDIRECT);
  b.nat_witnesses.push(NatWitness {binder: 2, argument_path: ref_span(b, [0]), selector: NAT_VIEW_LEN, ..});
  b.nat_witnesses.push(NatWitness {binder: 4, argument_path: ref_span(b, [1]), selector: NAT_DEST_CAP, ..});
  for index in 2 {
    let fid = index as u32 + 1; let start = b.values.len as u32; let first_op = b.ops.len as u32;
    let function_name = add_name(b, if index == 0 { "identity_array" } else { "typed_failure" });
    for type_id, value_index in [5 as u32, 3, 4, 1, 2, 7, 8] {
      let operation = if value_index == 0 { 0 } else if value_index <= 2 { first_op }
        else { first_op + value_index as u32 - 2 };
      b.values.push(Value {type_id: type_id, block_id: fid, op: operation, scope: 1, version: 1, ..});
    }
    b.ops.push(Operation {tag: OP_DESTRUCTURE, registry: OP_DESTRUCTURE, args: ref_span(b, [start]), results: ref_span(b, [start + 1, start + 2]), ..});
    b.ops.push(Operation {tag: OP_DEST_DISCARD, registry: OP_DEST_DISCARD, args: ref_span(b, [start + 2]), results: ref_span(b, [start + 3]), ..});
    b.ops.push(Operation {tag: OP_VIEW_LEN, registry: OP_VIEW_LEN, args: ref_span(b, [start + 1]), results: ref_span(b, [start + 4]), ..});
    b.ops.push(Operation {tag: OP_PACK, registry: OP_PACK, args: ref_span(b, [start + 4, start + 1]), results: ref_span(b, [start + 5]), ..});
    b.ops.push(Operation {tag: OP_SUM, registry: OP_SUM, args: ref_span(b, [if index == 0 {start + 5} else {start + 3}]), results: ref_span(b, [start + 6]), imm0: index as u32, ..});
    b.terminators.push(Terminator {tag: TERM_RETURN, subject: start + 6, ..});
    b.blocks.push(Block {params: ref_span(b, [start]), ops: ref_span(b, [first_op, first_op + 1, first_op + 2, first_op + 3, first_op + 4]), term: fid, function: fid, scope: 1, ..});
    b.functions.push(Function {name: function_name, type_id: 9, contract: 1, param: start, entry: fid, blocks: ref_span(b, [fid]), ..});
    b.abi_plans.push(AbiPlan {function: fid, arg_layout: 5, result_layout: 8, env_layout: 1, nat_witnesses: ref_span(b, [1, 2]), frame: 60, depth: 1, version: ABI_VERSION, ..});
    b.exports.push(Export {function: fid, name: function_name, kind: EXPORT_BRIDGE, arg_type: 5, result_type: 8,
      fields: ref_span(b, [1, 2]), input_maxima: ref_span(b, [4]), output_capacity: 4, work_bytes: 32, frame: 112, depth: 4, ..});
  }
  b.phase.phase = PHASE_SEALED;
}

fn test_wasm() {
  var bytes: u8[>..] = [];
  let map = wasm::runtime_fixture(bytes);
  assert(bytes.len > 8 && bytes[0] == 0 && bytes[1] == 97);
  assert(write_file("/tmp/blot-k1-runtime.wasm", bytes));
  var metadata: u8[>..] = [];
  format(metadata, "{\"owners\":", map.owners, ",\"bitmap\":", map.bitmap,
    ",\"pool\":", map.pool, ",\"ingress\":", map.ingress,
    ",\"egress\":", map.egress, ",\"frame\":", map.frame, "}");
  assert(write_file("/tmp/blot-k1-runtime-map.json", metadata));
  var trace_bytes:u8[>..]=[]; let trace_map=wasm::runtime_fixture_telemetry(trace_bytes);
  assert(write_file("/tmp/blot-k1-runtime-telemetry.wasm",trace_bytes));
  var trace_metadata:u8[>..]=[]; format(trace_metadata,"{\"control\":",trace_map.control,",\"owners\":",trace_map.owners,",\"frame\":",trace_map.frame,"}");
  assert(write_file("/tmp/blot-k1-runtime-telemetry-map.json",trace_metadata));
  wasm::with_module(map) { m =>
    let sig = wasm::signature(m, [], 0);
    var legal: u8[>..] = [0, 0x43, 0x40, 0x40, 0x40, 0x40, 0x1a, 0x0b];
    let accepted = wasm::function(m, sig, legal);
    var direct: u32[>..] = []; var indirect: u32[>..] = [];
    assert(wasm::scan_function(m, m.functions[accepted], direct, indirect));
    var growth: u8[>..] = [0, 0x41, 0, 0x40, 0, 0x1a, 0x0b];
    let rejected = wasm::function(m, sig, growth);
    assert(!wasm::scan_function(m, m.functions[rejected], direct, indirect));
    var unknown: u8[>..] = [0, 0x10, 0xff, 0x7f, 0x0b];
    let invalid_call = wasm::function(m, sig, unknown);
    assert(!wasm::scan_function(m, m.functions[invalid_call], direct, indirect));
  }
  with_core() { let b = it; bridge_fixture(b);
    var output: u8[>..] = []; var diagnostics: Diagnostic[>..] = [];
    let accepted = wasm_emit(core_view(b), output, diagnostics);
    if !accepted { print("bridge fixture diagnostics ", diagnostics); }
    assert(accepted && diagnostics.len == 0);
    assert(write_file("/tmp/blot-k1-bridge.wasm", output));
    let bridge_map, valid = runtime::make_map(runtime::Config {static_bytes: b.layouts.len as u32 * 16}); assert(valid);
    var info: u8[>..] = [];
    format(info, "{\"control\":", bridge_map.control, ",\"owners\":", bridge_map.owners,
      ",\"bitmap\":", bridge_map.bitmap, ",\"bitmapBytes\":", bridge_map.bitmap_bytes,
      ",\"frameBytes\":", bridge_map.frame_bytes, ",\"ingress\":", bridge_map.ingress,
      ",\"egress\":", bridge_map.egress, "}");
    assert(write_file("/tmp/blot-k1-bridge-map.json", info));
    let root = b.terms.len as u32;
    b.terms.push(Term {tag: EXPR_ARG, type_id: 5, binder: 1, ..});
    b.terms.push(Term {tag: EXPR_FIELD, type_id: 3, args: ref_span(b, [root]), literal: 0, ..});
    b.terms.push(Term {tag: EXPR_LEN, type_id: 2, args: ref_span(b, [root + 1]), ..});
    b.terms.push(Term {tag: EXPR_FIELD, type_id: 4, args: ref_span(b, [root]), literal: 1, ..});
    b.terms.push(Term {tag: EXPR_CAP, type_id: 2, args: ref_span(b, [root + 3]), ..});
    b.terms.push(Term {tag: EXPR_LITERAL, type_id: 2, literal: 2, ..});
    b.terms.push(Term {tag: EXPR_LITERAL, type_id: 2, literal: 3, ..});
    b.terms.push(Term {tag: EXPR_LITERAL, type_id: 2, literal: 4, ..});
    b.terms.push(Term {tag: EXPR_LITERAL, type_id: 2, literal: 0xfffffffb, ..});
    b.facts.push(Fact {tag: FACT_LE, left: root + 2, right: root + 5, ..});
    b.facts.push(Fact {tag: FACT_EQ, left: root + 4, right: root + 7, ..});
    b.facts.push(Fact {tag: FACT_LT, left: root + 2, right: root + 6, ..});
    b.facts.push(Fact {tag: FACT_ADD_FITS, left: root + 2, right: root + 8, ..});
    b.facts.push(Fact {tag: FACT_SUB_FITS, left: root + 7, right: root + 2, ..});
    b.facts.push(Fact {tag: FACT_MUL_FITS, left: root + 2, right: root + 7, ..});
    b.contracts[1].requires = ref_span(b, [1, 2, 3, 4, 5, 6]);
    var guarded: u8[>..] = []; assert(wasm_emit(core_view(b), guarded, diagnostics));
    assert(write_file("/tmp/blot-k1-bridge-guard.wasm", guarded));
    b.contracts[1].requires = Span {0, 0};
    b.types[4].capacity = 1;
    b.contracts[1].binders = ref_span(b, [1, 2, 3]);
    for i in 1..b.abi_plans.len { b.abi_plans[i].nat_witnesses = ref_span(b, [1]); }
    var repeated: u8[>..] = []; assert(wasm_emit(core_view(b), repeated, diagnostics));
    assert(write_file("/tmp/blot-k1-bridge-repeated.wasm", repeated));
    b.types[4].capacity = 2;
    b.contracts[1].binders = ref_span(b, [1, 2, 3, 4]);
    for i in 1..b.abi_plans.len { b.abi_plans[i].nat_witnesses = ref_span(b, [1, 2]); }
    b.types[3].children = ref_span(b, [1]); b.types[4].children = ref_span(b, [1]); b.types[6].children = ref_span(b, [1]);
    for i in 1..b.exports.len {
      b.exports[i].input_maxima = ref_span(b, [0xffffffff]);
      b.exports[i].output_capacity = 0xffffffff; b.exports[i].work_bytes = 0;
    }
    var unit: u8[>..] = []; assert(wasm_emit(core_view(b), unit, diagnostics));
    assert(write_file("/tmp/blot-k1-bridge-unit.wasm", unit));
  }
  print("K1_WASM_TEST encoder fixture: PASS");
}


fn test_dictionary_coverage() {
  var source:u8[>..]=[]; assert(read_file("tests/runtime_compound_dictionary.blot",source));
  with_core() { b =>
    var work=Work {..}; var diagnostics:Diagnostic[>..]=[];
    assert(frontend_complete(source,"coverage",b,work,diagnostics));
    assert(build_plans(b,"",diagnostics)); assert(canonical_schemas(b,diagnostics)); assert(seal_completion(b));
    var validation=Work {..}; assert(validator::validate_core(core_view(b),0,validation,diagnostics));
    assert(b.dictionary_realizations.len>2);
    // Delete one valid admitted key while preserving every remaining row and
    // all stable table IDs; per-row checks alone would accept this artifact.
    b.dictionary_realizations[1]=b.dictionary_realizations[b.dictionary_realizations.len-1];
    b.dictionary_realizations.resize(b.dictionary_realizations.len-1);
    var missing=Work {..}; diagnostics.resize(0);
    assert(!check_dictionary_coverage(core_view(b),missing,diagnostics));
    assert(diagnostics.len!=0 && diagnostics[0].code==2034);
  }
}

fn test_scalar_export_requires_boundary() {
  with_core() { b =>
    var work=Work {..}; var diagnostics:Diagnostic[>..]=[];
    assert(frontend_complete("pub let identity: U32 -> U32 ! {} requires [Eq(arg,1)] resources {depth:1,frame:0} = fn x => return x\n","scalar-boundary",b,work,diagnostics));
    assert(build_plans(b,"",diagnostics)); assert(canonical_schemas(b,diagnostics)); assert(seal_completion(b));
    var validation=Work {..}; assert(validator::validate_core(core_view(b),0,validation,diagnostics));
    var output:u8[>..]=[]; assert(wasm_emit(core_view(b),output,diagnostics));
    let contract=b.functions[b.exports[1].function].contract;
    let requirement=b.refs[b.contracts[contract].requires.start];
    // Corrupt an otherwise completed scalar export to demand branded authority.
    // The lowering boundary must refuse it, never silently erase the demand.
    b.facts[requirement].tag=FACT_INDEX;
    diagnostics.resize(0); output.resize(0);
    assert(!wasm_emit(core_view(b),output,diagnostics));
    assert(diagnostics.len!=0 && diagnostics[0].code==3025);
  }
}

fn test_realization_project_budget() {
  var source:u8[>..]=[]; assert(read_file("tests/runtime_realization_budget.blot",source));
  with_core() { b =>
    var work=Work {..}; var diagnostics:Diagnostic[>..]=[];
    assert(frontend_complete(source,"realization-budget",b,work,diagnostics));
    var unsigned:u32=0; for ty,i in b.types { if ty.tag==TY_U32 { unsigned=i as u32; break; } } assert(unsigned!=0);
    // Unrelated owner-local rows model preceding independent declarations. The
    // tiny callable instantiation must not spend their remaining node budget.
    while b.types.len<=LIMIT_TYPES { b.types.push(TypeNode {tag:TY_UNIT,..}); }
    while b.terms.len<=LIMIT_TERMS { b.terms.push(Term {tag:EXPR_LITERAL,type_id:unsigned,literal:b.terms.len as u32,..}); }
    let old_types=b.types.len; let old_terms=b.terms.len;
    assert(build_plans(b,"",diagnostics));
    assert(b.types.len>old_types && b.terms.len>old_terms);
    assert(canonical_schemas(b,diagnostics)); assert(seal_completion(b));
    var validation=Work {..}; assert(validator::validate_core(core_view(b),0,validation,diagnostics));
  }
}
