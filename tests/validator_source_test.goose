import src.plan;
import src.fingerprint;
import os;
import src.frontend;
import src.validate;
import tests.validator_test;
fn validator_source(source: const u8[:]) {
    with_core() { b =>
        var completion = Work {..}; var diags: Diagnostic[>..] = [];
        let completed = frontend_complete(source, "validator-source", b, completion, diags);
        if !completed { print("frontend failure: ", diags); }
        assert(completed); assert(seal_completion(b));
        var work = Work {..};
        let admitted = validator::validate_core(core_view(b), validator::FRESH, work, diags);
        if !admitted { print("validator source failure: ", diags, " source ", source, " contracts ", b.contracts); }
        assert(admitted);
    };
}
fn test_validator_source() {
    validator_source("let identity: Fn[static, Many, U32, U32] ! {} resources {depth: 1, frame: 0} = fn x => return x\n");
    validator_source("let sum: Fn[static, Many, Unit, U32] ! {} resources {depth: 1, frame: 0} = fn () => return 7 + 9\n");
    validator_source("let choose: Fn[static, Many, U32, U32] ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x < 5:\n    return x\n  else:\n    return 0\n");
    validator_source("let identity: forall [T: Type] => Fn[static, Many, T, T] ! {} resources {depth: 1, frame: 256} = fn x => return x\n");
    print("Independent source scalar/branch/generic affine identity validation passed");
}

fn test_validator_loops() {
    let source = "pub let count: Unit -> U32 ! {} ensures [Eq(result,10)] resources {depth: 1, frame: 256} = fn () => do:\n  let answer = for i in 0..10 carry (n = 0) invariant [Eq(n,i)] do:\n    next (n+1)\n  return answer\n";
    validator_source(source);
    with_core() { b =>
        var completion = Work {..}; var diags: Diagnostic[>..] = [];
        assert(frontend_complete(source,"loop-forgery",b,completion,diags)); assert(seal_completion(b));
        let loop_info = b.loops[1];
        for edge, id in b.edges {
            if id != 0 && edge.kind == EDGE_LOOP_ENTRY { b.edges[id].evidence = loop_info.invariant; }
        }
        var work = Work {..}; assert(!validator::validate_core(core_view(b),validator::REQUIRED,work,diags));
    };
    with_core() { b =>
        var completion = Work {..}; var diags: Diagnostic[>..] = [];
        assert(frontend_complete(source,"stop-forgery",b,completion,diags)); assert(seal_completion(b));
        let loop_info = b.loops[1]; let next = b.refs[loop_info.backedges.start];
        b.edges[next].kind = EDGE_LOOP_STOP; b.edges[next].to = loop_info.exit;
        var args: u32[>..] = []; args.push(loop_info.index);
        for i in loop_info.carries.count { args.push(b.refs[loop_info.carries.start + i]); }
        b.edges[next].args = ref_span(b,args);
        b.loops[1].backedges = Span {..}; b.loops[1].exits = ref_span(b,[b.refs[loop_info.exits.start],next]);
        var work = Work {..}; assert(!validator::validate_core(core_view(b),validator::REQUIRED,work,diags));
    };
    print("CTL-01 loop induction rejects self-proved entry and stopped-path exhaustion forgery");
}

fn test_validator_predicate_contract() {
    let source="pub let predicate: (U32,U32) -> Bool ! {} on_true [Lt(arg.0,arg.1)] on_false [Le(arg.1,arg.0)] resources {depth: 1, frame: 256} = fn (x,y) => return x<y\n";
    validator_source(source);
    with_core() { b =>
        var completion=Work{..}; var diags:Diagnostic[>..]=[];
        assert(frontend_complete(source,"predicate-forgery",b,completion,diags)); assert(seal_completion(b));
        for op,id in b.ops { if id != 0 && op.tag == OP_BOOL { b.ops[id].imm0 ^= 1; } }
        var work=Work{..}; assert(!validator::validate_core(core_view(b),validator::REQUIRED,work,diags));
    };
    print("SEC-02 forged Boolean postcondition rejected independently of producer");
}

fn test_validator_boolean_paths() {
    var source:u8[>..]=[]; assert(read_file("examples/short_circuit.blot",source));
    with_core() { b =>
        var work=Work{..}; var diags:Diagnostic[>..]=[];
        assert(frontend_complete(source,"boolean-path-forgery",b,work,diags)); assert(build_plans(b,"",diags)); assert(canonical_schemas(b,diags)); assert(seal_completion(b)); validator_expect(b,true,0);
        var changed=false;
        for evidence,ei in b.evidence {
            if ei==0 || evidence.rule!=RULE_BOOL_PATH || changed { continue; }
            let value=b.refs[evidence.operands.start]; let target=b.values[value].block_id;
            if b.values[value].op!=0 { continue; } let basic=b.blocks[target]; var ordinal:u32=0;
            for i in basic.params.count { if b.refs[basic.params.start+i]==value { ordinal=i; } }
            for edge,id in b.edges {
                if id==0 || edge.to!=target { continue; } let input=b.refs[edge.args.start+ordinal]; let producer=b.values[input].op;
                if producer!=0 && b.ops[producer].tag==OP_BOOL { b.ops[producer].imm0^=1; changed=true; break; }
            }
        }
        assert(changed); validator_expect(b,false,2034);
    };
    print("SEC-02 short-circuit phi cannot forge facts when its constant bypass arm changes");
}

fn test_validator_static_capture() {
    let source="let identity: U32 -> U32 ! {} resources {depth:1,frame:0} = fn value => return value\nstatic let callback: Unit -> U32 ! {} resources {depth:1,frame:64} = do:\n  let seed = identity(2)\n  if seed < 100:\n    break fn () => return seed+1\n  else:\n    break fn () => return 0\npub let run: Unit -> U32 ! {} resources {depth:2,frame:128} = fn () => return callback(())\n";
    with_core() { b =>
        var work=Work{..}; var diags:Diagnostic[>..]=[];
        assert(frontend_complete(source,"static-proof-forgery",b,work,diags)); assert(build_plans(b,"",diags)); assert(canonical_schemas(b,diags)); assert(seal_completion(b)); validator_expect(b,true,0);
        var forged=false;
        for object,id in b.static_objects { if id!=0 && object.kind==STATIC_ENVIRONMENT && object.bytes.count==4 {
            for i in 4 { b.bytes[object.bytes.start+i]=255; } forged=true; break;
        } }
        assert(forged); validator_expect(b,false,2034);
    };
    print("SEC-03 static capture bytes cannot inherit a transported proof for a different value");
}

fn test_validator_ambient_nat() {
    var source:u8[>..]=[];assert(read_file("examples/local_generic_nat.blot",source));
    with_core() { b=>
        var work=Work{..};var diagnostics:Diagnostic[>..]=[];
        assert(frontend_complete(source,"ambient-nat",b,work,diagnostics));assert(build_plans(b,"",diagnostics));assert(canonical_schemas(b,diagnostics));assert(seal_completion(b));validator_expect(b,true,0);
        var literal:u32=0;for op in b.ops {if op.tag==OP_U32 && op.results.count==1 {literal=b.refs[op.results.start];break;}}assert(literal!=0);
        var changed=false;for binding,id in b.environment_bindings {if id!=0 && binding.kind==KIND_NAT && binding.source_value!=0 {b.environment_bindings[id].source_value=literal;changed=true;break;}}
        assert(changed);validator_expect(b,false,2019);
    };
    print("SEC-02 ambient Nat environments reject unrelated U32 witness substitution");
}

fn test_validator_producer_identity() {
    let source="pub let first: U32 -> U32 ! {} resources {depth:1,frame:0} = fn x => return x\npub let second: U32 -> U32 ! {} resources {depth:1,frame:0} = fn x => return x\n";
    for mutation in 3 {with_core() {b=>var work=Work{..};var diagnostics:Diagnostic[>..]=[];assert(frontend_complete(source,"producer-identity",b,work,diagnostics));assert(seal_completion(b));validator_expect(b,true,0);
        if mutation==0 {b.definitions[2].name=b.definitions[1].name;}
        if mutation==1 {b.modules[1].declarations=ref_span(b,[1,1]);}
        if mutation==2 {b.modules.push(b.modules[1]);}
        validator_expect(b,false,2034);
    }}
    print("SEC-01 exact producer identities reject duplicate names, owner entries and module paths");
}

fn test_validator_source_origins() {
    let loan="let bad: forall [r:Region,n:Nat,d:Domain] => (RegionOwner[r],View[r,U32,n,d]) -> U32 ! {read r,release} requires [Lt(0,n)] resources {depth:4,frame:4096} = fn (owner,values) => do:\n  region.close(owner)\n  return values[0]\n";
    with_core() {b=>var work=Work{..};var diagnostics:Diagnostic[>..]=[];assert(frontend_complete(loan,"loan-origin",b,work,diagnostics));assert(build_plans(b,"",diagnostics));assert(canonical_schemas(b,diagnostics));assert(seal_completion(b));var validation=Work{..};assert(!validator::validate_core(core_view(b),validator::FRESH,validation,diagnostics));let d=diagnostics[diagnostics.len-1];assert(d.code==2017 && d.origin!=0);let origin=b.origins[d.origin];assert(origin.module==1 && origin.start<origin.end && origin.end<=loan.len);assert(loan[origin.start..origin.end]=="region.close(owner)");};
    let source="type P[r:Region] = Unit\nlet good: Owned[P[_]] -> Unit ! {release} resources {depth:3,frame:64} = fn handle => do:\n  owned.close(handle)\n  return ()\n";
    for kind in 3 {with_core() {b=>var work=Work{..};var diagnostics:Diagnostic[>..]=[];assert(frontend_complete(source,"owner-origin",b,work,diagnostics));assert(build_plans(b,"",diagnostics));assert(canonical_schemas(b,diagnostics));assert(seal_completion(b));
        var operation:u32=0;for op,id in b.ops {if id!=0 && op.tag==OP_OWNED_CLOSE {operation=id as u32;break;}}assert(operation!=0);let original=b.ops[operation];
        if kind==0 {let old_value=b.refs[original.results.start];var copied=b.values[old_value];let value=b.values.len as u32;let opid=b.ops.len as u32;copied.op=opid;copied.version=value;b.values.push(copied);var duplicate=original;duplicate.results=ref_span(b,[value]);b.ops.push(duplicate);let block_id=copied.block_id;var ids:u32[>..]=[];let old=b.blocks[block_id].ops;for i in old.count {let id=b.refs[old.start+i];ids.push(id);if id==operation {ids.push(opid);}}b.blocks[block_id].ops=ref_span(b,ids);}
        if kind==1 {b.contracts[b.functions[1].contract].depth=0;}
        if kind==2 {b.ops[operation].origin=0xffffffff;b.contracts[b.functions[1].contract].depth=0;}
        var validation=Work{..};assert(!validator::validate_core(core_view(b),if kind==2 {validator::REQUIRED}else{validator::FRESH},validation,diagnostics));let d=diagnostics[diagnostics.len-1];
        if kind==0 {assert(d.code==2013 && d.origin==original.origin);}
        if kind==1 {assert(d.code==2023 && d.origin!=0);let origin=b.origins[d.origin];assert(origin.module==1 && origin.start<origin.end && origin.end<=source.len);}
        if kind==2 {assert(d.code==2034 && d.origin==0);}
    }}
    print("I04 validator loan/ownership/resource diagnostics retain checked source spans; hostile artifact origins remain opaque");
}
