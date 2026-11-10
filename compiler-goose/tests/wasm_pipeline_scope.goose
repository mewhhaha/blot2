import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import backend.wasm;
import backend.runtime_pipeline;
import backend.cohort_candidate;
import driver.compile_workspace;
import support.error;
fn observeDecoded(count: u32&,module: blot_backend_wasm::Module&) -> blot_error::Error {
    assert(module.functions.len == 1);
    let function = module.functions[0];
    assert(module.parameters(function) == [blot_backend_runtime_ir::VT_i32]);
    assert(module.locals(function) == [blot_backend_runtime_ir::VT_i32]);
    let code = blot_backend_wasm::instructions(module,function);
    assert(code.len == 2 && code[0].op == blot_backend_runtime_ir::OP_i32_const && code[0].operand == 42 && code[1].op == blot_backend_runtime_ir::OP_end);
    count++;
    return blot_error::Error.none;
}
fn profileDigests(module: const blot_backend_wasm::Module&) {
    var source_profile = blot_backend_memory_profile::Profile{module:module,..};
    var source_bodies: blot_backend_wasm::Prepared[1] = [blot_backend_wasm::Prepared{..}];
    assert(source_profile.bind(source_bodies[..]) == blot_error::Error.none);
    let function = module.functions[0];
    var detached,error = blot_backend_runtime_ir::cloneBody(module.locals(function),blot_backend_wasm::instructions(module,function));
    assert(error == blot_error::Error.none);
    var detached_bodies: blot_backend_wasm::Prepared[1] = [blot_backend_wasm::Prepared{body:blot_support::Option<blot_backend_runtime_ir::DetachedBody>{true,detached},..}];
    var equal_profile = blot_backend_memory_profile::Profile{module:module,..};
    assert(equal_profile.bind(detached_bodies[..]) == blot_error::Error.none && equal_profile.identity == source_profile.identity);
    detached.instructions[0].operand = 43;
    var changed_profile = blot_backend_memory_profile::Profile{module:module,..};
    assert(changed_profile.bind(detached_bodies[..]) == blot_error::Error.none && changed_profile.identity != source_profile.identity);
    changed_profile.deinit(); equal_profile.deinit(); source_profile.deinit(); detached.deinit();
}
fn assembleCase(mode: u32) {
    let nonempty = mode != 0;
    var types: blot_backend_wasm::ValueType[>..<] = [];
    var instructions: blot_backend_wasm::Instruction[>..<] = [];
    var names: u8[>..<] = [];
    var functions: blot_backend_wasm::Function[>..<] = [];
    var signatures: blot_backend_wasm::Signature[>..<] = [];
    var imports: blot_backend_wasm::Import[>..<] = [];
    var globals: blot_backend_wasm::Global[>..<] = [];
    var exports: blot_backend_wasm::Export[>..<] = [];
    var data: u8[>..<] = [];
    var static_fields: u32[>..<] = [];
    var table_functions: u32[>..<] = [];
    var table_origins: blot_backend_wasm::TableOrigin[>..<] = [];
    var semantic_sites: blot_backend_wasm::SemanticSite[>..<] = [];
    var module = blot_backend_wasm::init(types,instructions,names,functions,signatures,imports,globals,exports,data,static_fields,table_functions,table_origins,semantic_sites);
    module.memory_model = blot_backend_wasm::MemoryModel.data_stacks;
    if nonempty {
        let function,error = module.addTypedFunction([blot_backend_runtime_ir::VT_i32],blot_backend_runtime_ir::VT_i32,blot_backend_runtime_ir::ROLE_scalar);
        assert(error == blot_error::Error.none);
        let local,local_error = module.addLocal(function,blot_backend_runtime_ir::VT_i32); assert(local_error == blot_error::Error.none && local == 1);
        assert(module.emit(function,blot_backend_runtime_ir::Instruction{op:blot_backend_runtime_ir::OP_i32_const,operand:42,..}) == blot_error::Error.none);
        assert(module.emit(function,blot_backend_runtime_ir::Instruction{op:blot_backend_runtime_ir::OP_end,..}) == blot_error::Error.none);
    }
    // Mode 2 requires a collector certificate from the unchecked assembly API.
    if mode != 2 {
        var session,error = blot_backend_runtime_pipeline::init(module);
        assert(error == blot_error::Error.none && session.module .== module && !session.roots);
        if nonempty { let body,error = session.optimize(0); assert(error == blot_error::Error.none); if body.present { var owned = body.value; owned.deinit(); } }
        session.deinit(); assert(session.module == null);
    }
    var output: u8[>..<] = [];
    var stats = blot_backend_optimized_bodies::Stats{..};
    let assembled = module.assembleWithOptions(blot_backend_wasm::AssembleOptions{require_collector_free:mode == 2,workers:1,stats:stats,..},output);
    if mode == 2 { assert(assembled == blot_error::Error.collector_free_unproven); }
    else {
        assert(assembled == blot_error::Error.none && output.len >= 8);
        assert(output[0] == 0 && output[1] == 97 && output[2] == 115 && output[3] == 109 && output[4] == 1);
        assert(stats.functions == module.functions.len);
    }
    if mode == 1 {
        profileDigests(module);
        let image = blot_backend_runtime_job::capture(module);
        var packet: u8[>..<] = [];
        assert(blot_backend_runtime_job::encode(module,packet) == blot_error::Error.none);
        module.deinit();
        // Reuse the retired source buffers before reading either owned image.
        types.push(blot_backend_runtime_ir::VT_f32);
        instructions.push(blot_backend_runtime_ir::Instruction{op:blot_backend_runtime_ir::OP_i32_const,operand:99,..});
        var observed: u32 = 0;
        assert(blot_backend_runtime_job::withModule(image,observed,observeDecoded) == blot_error::Error.none);
        assert(blot_backend_runtime_job::decodeWithModule(packet[..],observed,observeDecoded) == blot_error::Error.none);
        assert(observed == 2);
    } else { module.deinit(); }
}
fn populateCohort(view:blot_backend_cohort_candidate::Extension&) {
    var types: blot_backend_wasm::ValueType[>..<] = [];
    var instructions: blot_backend_wasm::Instruction[>..<] = [];
    var names: u8[>..<] = [];
    var functions: blot_backend_wasm::Function[>..<] = [];
    var signatures: blot_backend_wasm::Signature[>..<] = [];
    var imports: blot_backend_wasm::Import[>..<] = [];
    var globals: blot_backend_wasm::Global[>..<] = [];
    var exports: blot_backend_wasm::Export[>..<] = [];
    var data: u8[>..<] = [];
    var static_fields: u32[>..<] = [];
    var table_functions: u32[>..<] = [];
    var table_origins: blot_backend_wasm::TableOrigin[>..<] = [];
    var semantic_sites: blot_backend_wasm::SemanticSite[>..<] = [];
    var source = blot_backend_wasm::init(types,instructions,names,functions,signatures,imports,globals,exports,data,static_fields,table_functions,table_origins,semantic_sites);
    source.memory_model=blot_backend_wasm::MemoryModel.data_stacks;
    source.fixed_memory_bytes=65536;source.fixture_helpers_present=true;source.fixture_helpers=[7 as u32,8 as u32,9 as u32];
    source.public_arena=true;source.defer_cycles=true;source.mutable_static=true;source.indirect=true;
    source.cleanup_data=blot_backend_runtime_ir::Range{start:1,len:2};source.start=blot_support::Option<u32>{true,0};
    let normal,error=source.addTypedFunction([blot_backend_runtime_ir::VT_i32],blot_backend_runtime_ir::VT_i32,blot_backend_runtime_ir::ROLE_scalar);assert(error==blot_error::Error.none && normal==0);
    let local,error=source.addLocal(normal,blot_backend_runtime_ir::VT_i32);assert(error==blot_error::Error.none && local==1);
    assert(source.emit(normal,blot_backend_runtime_ir::Instruction{op:blot_backend_runtime_ir::OP_i32_const,operand:42,..})==blot_error::Error.none);
    assert(source.emit(normal,blot_backend_runtime_ir::Instruction{op:blot_backend_runtime_ir::OP_end,..})==blot_error::Error.none);
    let first=source.functions[normal];
    var borrowed,error=blot_backend_runtime_ir::cloneBody(source.locals(first),blot_backend_wasm::instructions(source,first));assert(error==blot_error::Error.none);
    let second,error=source.addTypedFunction([blot_backend_runtime_ir::VT_f32],blot_backend_runtime_ir::VT_i32,blot_backend_runtime_ir::ROLE_scalar);assert(error==blot_error::Error.none && second==1);
    let signature=source.functions[second].signature;let parameters=source.functions[second].parameters;
    source.functions[second]=blot_backend_runtime_ir::Function{parameters:parameters,result:blot_backend_runtime_ir::VT_i32,result_role:blot_backend_runtime_ir::ROLE_scalar,entry:true,provider_parameter:blot_backend_runtime_ir::no_provider,callable_layout:17,signature:signature,parameter_roles:5,annotations:0,locals:blot_backend_runtime_ir::Range{len:borrowed.locals.len,..},instructions:blot_backend_runtime_ir::Range{len:borrowed.instructions.len,..},borrowed_body:true,borrowed_locals:borrowed.locals,borrowed_instructions:borrowed.instructions};
    source.names.append("cohort");source.data.append([11 as u8,12 as u8]);source.static_fields.push(3);source.table_functions.push(normal);
    let members=blot_backend_region_candidate::member_runs.alloc_slice(1);members[0]=blot_runtime_region_runtime::Member{offset:4,bytes:4};let scopes=blot_backend_region_candidate::scope_runs.alloc_slice(1);scopes[0]=blot_runtime_region_runtime::Scope{function:0,parameter:0};
    source.regions=blot_support::some(blot_runtime_region_runtime::Prepared{runtime:blot_runtime_region_runtime::Runtime{allocate:21,project:22,store:23,close:24,frame_allocate:25,member_at:26},plan:blot_runtime_region_runtime::Plan{frame_bytes:4,bytes:8,mask:0,members:members},scopes:scopes});
    assert(blot_backend_cohort_candidate::detachedInto(view,source)==blot_error::Error.none);
    assert(view.original_functions==2 && view.original_signatures==source.signatures.len && view.owned.items==[true,true]);
    assert(!view.module.functions[normal].borrowed_body && !view.module.functions[second].borrowed_body);
    assert(view.module.functions[normal].locals==first.locals && view.module.functions[normal].instructions==first.instructions);
    let copied=view.module.functions[second];
    assert(copied.parameters==parameters && copied.signature==signature && copied.entry && copied.provider_parameter==blot_backend_runtime_ir::no_provider && copied.callable_layout==17 && copied.parameter_roles==5 && copied.result_role==blot_backend_runtime_ir::ROLE_scalar);
    assert(view.module.parameters(copied)==[blot_backend_runtime_ir::VT_f32] && view.module.locals(copied)==[blot_backend_runtime_ir::VT_i32]);
    // Neither the ordinary grow-array body nor the detached typed body stays borrowed.
    members[0].offset=8;scopes[0].parameter=7;assert(view.module.regions.present && view.module.regions.value.plan.members[0].offset==4 && view.module.regions.value.scopes[0].parameter==0);
    source.instructions[first.instructions.start].operand=99;source.types[first.locals.start]=blot_backend_runtime_ir::VT_f32;
    borrowed.instructions[0].operand=100;borrowed.locals[0]=blot_backend_runtime_ir::VT_f32;
    assert(blot_backend_wasm::instructions(view.module,normal)[0].operand==42 && blot_backend_wasm::instructions(view.module,second)[0].operand==42);
    assert(view.module.locals(normal)==[blot_backend_runtime_ir::VT_i32] && view.module.locals(second)==[blot_backend_runtime_ir::VT_i32]);
    let old_types=view.module.types.len;let old_code=view.module.instructions.len;
    var replacement:blot_backend_runtime_ir::Instruction[2]=[blot_backend_runtime_ir::Instruction{op:blot_backend_runtime_ir::OP_i32_const,operand:77,..},blot_backend_runtime_ir::Instruction{op:blot_backend_runtime_ir::OP_end,..}];
    assert(blot_backend_cohort_candidate::replaceBody(view,normal,replacement[..])==blot_error::Error.none);
    assert(view.module.types.len==old_types && view.module.instructions.len==old_code+replacement.len);
    assert(source.instructions[first.instructions.start].operand==99 && source.types[first.locals.start]==blot_backend_runtime_ir::VT_f32 && borrowed.instructions[0].operand==100);
    source.deinit();blot_backend_region_candidate::member_runs.free_slice(members);blot_backend_region_candidate::scope_runs.free_slice(scopes);borrowed.deinit();
}
fn cohortOwnership() {
    var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);
    let workspace_ref .=frame.borrow();assert(workspace_ref);let workspace:blot_backend_core_backend::CompileWorkspace& =workspace_ref;
    let view:blot_backend_cohort_candidate::Extension& =workspace.origins.code;
    populateCohort(view);
    assert(view.active && view.module.functions.len==2 && view.module.artifacts==null);
    assert(view.module.memory_model==blot_backend_wasm::MemoryModel.data_stacks && view.module.fixed_memory_bytes==65536 && view.module.fixture_helpers_present && view.module.fixture_helpers==[7 as u32,8 as u32,9 as u32]);
    assert(view.module.public_arena && view.module.defer_cycles && view.module.mutable_static && view.module.indirect && view.module.start.present && view.module.start.value==0);
    assert(view.module.cleanup_data==blot_backend_runtime_ir::Range{start:1,len:2});
    assert(view.module.names=="cohort" && view.module.data==[11 as u8,12 as u8] && view.module.static_fields==[3 as u32] && view.module.table_functions==[0 as u32]);
    assert(blot_backend_wasm::instructions(view.module,0)[0].operand==77 && blot_backend_wasm::instructions(view.module,1)[0].operand==42);
    assert(view.module.regions.present && view.module.regions.value.runtime.allocate==21 && view.module.regions.value.plan.members[0].offset==4 && view.module.regions.value.scopes[0].parameter==0);
    assert(view.module.locals(0)==[blot_backend_runtime_ir::VT_i32] && view.module.locals(1)==[blot_backend_runtime_ir::VT_i32]);
    view.deinit();view.deinit();assert(!view.active && view.owned.items.len==0 && view.original_functions==0 && view.module.functions.len==0 && view.module.instructions.len==0 && view.module.types.len==0);
    assert(frame.release()==blot_error::Error.none);
}
fn main() {
    for cycle in 0..3 { assembleCase(0); assembleCase(1); assembleCase(2); cohortOwnership(); }
    print("Wasm pipeline scope passed: empty/nonempty assembly, collector rejection cleanup, owned packet round trips, profile digests, detached cohort body ownership, repeated scratch cleanup");
}
