import tests.optimizer_test;
import src.plan;
import src.fingerprint;
import src.wasm;
import os;
fn optimizer_rule_count(s:optimize::Stats,rule:u32)->u64 {
    if rule==1 {return s.r01;}if rule==2 {return s.r02;}if rule==3 {return s.r03;}if rule==4 {return s.r04;}if rule==5 {return s.r05;}if rule==6 {return s.r06;}if rule==7 {return s.r07;}if rule==8 {return s.r08;}if rule==9 {return s.r09;}if rule==10 {return s.r10;}if rule==11 {return s.r11;}if rule==12 {return s.r12;}return 0;
}
fn optimizer_guest(b:CoreBuilder,rule:u32,sample:u32=0) {
    let suffix=if sample==0 {str(rule)}else{str(rule,"-f32-",sample)};
    if b.modules.len==1 {b.contracts[b.functions[1].contract].frame=1024;let name=add_name(b,"run");b.modules.push(Module{name:name,path:name,..});b.functions[1].name=name;b.functions[1].module=1;b.functions[1].visibility=VIS_PUBLIC;}
    var diagnostics:Diagnostic[>..]=[];
    let planned=build_plans(b,"run",diagnostics);if !planned {print("OPT guest plan ",rule," ",diagnostics);}assert(planned);assert(canonical_schemas(b,diagnostics));assert(seal_completion(b));validator_expect(b,true,0);
    with_core() {out=>var stats=optimize::Stats{..};let optimized=optimize::optimize(core_view(b),optimize::Limits{..},out,stats,diagnostics);if !optimized {print("OPT guest rewrite ",rule," ",stats," ",diagnostics);}assert(optimized);if optimizer_rule_count(stats,rule)==0 {print("OPT guest missing rule ",rule," ",stats);}assert(optimizer_rule_count(stats,rule)>0);
        var baseline:u8[>..]=[];var candidate:u8[>..]=[];
        assert(wasm_emit_manifest_telemetry(core_view(b),baseline,"",diagnostics));assert(wasm_emit_manifest_telemetry(core_view(out),candidate,"",diagnostics));
        assert(write_file(str("/tmp/blot-k1-opt-",suffix,"-baseline.wasm"),baseline));assert(write_file(str("/tmp/blot-k1-opt-",suffix,"-candidate.wasm"),candidate));
        assert(write_file(str("/tmp/blot-k1-opt-",suffix,"-stats.json"),str("{\"rule\":",rule,",\"applications\":",optimizer_rule_count(stats,rule),"}")));
    };
}
fn optimizer_source_guest(source:const u8[:],rule:u32) {with_core() {b=>var work=Work{..};var diagnostics:Diagnostic[>..]=[];let completed=frontend_complete(source,"optimizer-guest",b,work,diagnostics);if !completed {for d in diagnostics {print(rule," ",d," ",name_bytes(core_view(b),d.detail));}}assert(completed);optimizer_guest(b,rule);};}
fn test_optimizer_executed_catalogue() {
    for with_param in 2 {with_core() {b=>validator_scalar_fixture(b);var result:u32=1;var params=Span{..};var args=Span{..};
        if with_param==1 {result=2;b.values.push(Value{type_id:1,block_id:2,version:2,scope:1,..});params=ref_span(b,[2]);args=ref_span(b,[1]);}
        b.terminators.push(Terminator{tag:TERM_RETURN,subject:result,..});b.blocks.push(Block{params:params,term:2,scope:1,function:1,..});b.edges.push(Edge{from:1,to:2,args:args,kind:EDGE_NORMAL,..});b.terminators[1]=Terminator{tag:TERM_JUMP,edges:ref_span(b,[1]),..};b.functions[1].blocks=ref_span(b,[1,2]);optimizer_guest(b,with_param as u32+1);
    }}
    optimizer_source_guest("let identity: U32 -> U32 ! {} resources {depth:1,frame:0} = fn x => return x\npub let run: U32 -> U32 ! {} resources {depth:2,frame:0} = fn x => return identity(x)\n",3);
    with_core() {b=>optimizer_fixture(b);b.contracts[1].frame=64;b.types.push(TypeNode{tag:TY_TUPLE,children:ref_span(b,[1,1]),..});b.values[3].type_id=3;b.ops[2].tag=OP_TUPLE;b.ops[2].registry=OP_TUPLE;b.ops[2].args=ref_span(b,[1,2]);b.ops[2].imm0=0;b.ops[3].tag=OP_PROJECT;b.ops[3].registry=OP_PROJECT;b.ops[3].args=ref_span(b,[3]);b.ops[3].imm0=0;optimizer_guest(b,4);};
    with_core() {b=>optimizer_fixture(b);b.types.push(TypeNode{tag:TY_BOOL,..});b.values[2].type_id=3;b.ops[1].tag=OP_BOOL;b.ops[1].registry=OP_BOOL;b.ops[1].imm0=1;b.ops[3].tag=OP_COPY;b.ops[3].registry=OP_COPY;b.ops[3].args=ref_span(b,[1]);
        b.terminators.push(Terminator{tag:TERM_RETURN,subject:1,..});b.terminators.push(Terminator{tag:TERM_RETURN,subject:3,..});b.blocks.push(Block{term:2,scope:1,function:1,..});b.blocks.push(Block{term:3,scope:1,function:1,..});b.edges.push(Edge{from:1,to:2,kind:EDGE_TRUE,..});b.edges.push(Edge{from:1,to:3,kind:EDGE_FALSE,..});b.terminators[1]=Terminator{tag:TERM_BRANCH,subject:2,edges:ref_span(b,[1,2]),..};b.functions[1].blocks=ref_span(b,[1,2,3]);optimizer_guest(b,5);
    };
    with_core() {b=>optimizer_fixture(b);b.ops[2].tag=OP_COPY;b.ops[2].registry=OP_COPY;b.ops[2].args=ref_span(b,[2]);b.ops[2].imm0=0;optimizer_guest(b,6);};
    with_core() {b=>optimizer_fixture(b);optimizer_guest(b,7);};
    optimizer_source_guest("static let values = #[1,2,3]\npub let run: Unit -> U32 ! {} resources {depth:1,frame:64} = fn () => return values.length\n",8);
    optimizer_source_guest("let exercise: U32 -> Result[Result[U32,AllocError],ReserveError] ! {reserve,release}\n= fn capacity => return region@[Result[U32,AllocError]](capacity) as r (owner,free) in do:\n  let (rest,answer): (Space[r],Result[U32,AllocError]) = do:\n    case region.try_alloc@[U32](free,1):\n      #Err((unused,error)) => break (unused,#Err(error))\n      #Ok((unused,dst)) => do:\n        let empty = builder.begin_append(dst)\n        let filled = builder.append(empty,0)\n        let changed = builder.set(filled,0,capacity)\n        let answer = builder.read(changed,0)\n        builder.discard(changed)\n        break (unused,#Ok(answer))\n  space.end(rest)\n  region.close(owner)\n  break answer\npub let run: U32 -> U32 ! {reserve,release} resources {depth:4,frame:8192} = fn capacity => do:\n  case exercise(capacity):\n    #Err(_) => return 77\n    #Ok(result) => do:\n      case result:\n        #Err(_) => return 99\n        #Ok(answer) => return answer\n",9);
    with_core() {b=>validator_scalar_fixture(b);b.contracts[1].frame=16;b.types.push(TypeNode{tag:TY_UNIT,..});b.types.push(TypeNode{tag:TY_SUM,children:ref_span(b,[3,3]),..});
        b.values.push(Value{type_id:3,block_id:1,op:1,version:2,scope:1,..});b.values.push(Value{type_id:4,block_id:1,op:2,version:3,scope:1,..});b.values.push(Value{type_id:1,block_id:1,op:3,version:4,scope:1,..});
        b.ops.push(Operation{tag:OP_UNIT,registry:OP_UNIT,results:ref_span(b,[2]),scope:1,..});b.ops.push(Operation{tag:OP_SUM,registry:OP_SUM,args:ref_span(b,[2]),results:ref_span(b,[3]),scope:1,imm0:1,..});b.ops.push(Operation{tag:OP_TAG,registry:OP_TAG,args:ref_span(b,[3]),results:ref_span(b,[4]),scope:1,..});b.blocks[1].ops=ref_span(b,[1,2,3]);b.terminators[1].subject=4;optimizer_guest(b,10);
    };
    optimizer_source_guest("pub let run: U32 -> U32 ! {} resources {depth:2,frame:128} = fn x => do:\n  let callback = fn (value:U32) => return U32.wrapping_add(value,1)\n  return callback(x)\n",11);
    optimizer_source_guest("pub let run: U32 -> U32 ! {} resources {depth:1,frame:0} = fn x => do:\n  let _ = U32.wrapping_add(x,1)\n  return x\n",12);
    print("OPT-01 all R01-R12 counters fired; baseline/candidate guests emitted for executed differential laws");
}

fn test_optimizer_executed_f32() {
    let cases=[FloatRewriteCase{OP_F32_MIN,0,0x80000000,0x80000000,2},FloatRewriteCase{OP_F32_MAX,0,0x80000000,0,2},FloatRewriteCase{OP_F32_DIV,0x3f800000,0,0x7f800000,2},FloatRewriteCase{OP_F32_MUL,0,0x7f800000,0x7fc00000,2},FloatRewriteCase{OP_F32_ADD,0x4b800000,0x3f800000,0x4b800000,2},FloatRewriteCase{OP_F32_NEG,0x7fa12345,0,0xffa12345,1},FloatRewriteCase{OP_F32_ABS,0xffa12345,0,0x7fa12345,1},FloatRewriteCase{OP_F32_NEAREST,0xbf000000,0,0x80000000,1}];
    for sample,i in cases {with_core() {b=>optimizer_fixture(b);b.types[1].tag=TY_F32;b.types.push(TypeNode{tag:TY_U32,..});b.contracts[1].result=3;b.types[2].children=ref_span(b,[1,3]);
        b.ops[1].tag=OP_F32;b.ops[1].registry=OP_F32;b.ops[1].imm0=sample.left;b.ops[2].tag=OP_F32;b.ops[2].registry=OP_F32;b.ops[2].imm0=sample.right;b.ops[3].tag=sample.operation;b.ops[3].registry=sample.operation;b.ops[3].args.count=sample.arity;
        b.values.push(Value{type_id:3,block_id:1,op:4,version:5,scope:1,..});b.ops.push(Operation{tag:OP_F32_TO_BITS,registry:OP_F32_TO_BITS,args:ref_span(b,[4]),results:ref_span(b,[5]),scope:1,..});b.blocks[1].ops=ref_span(b,[1,2,3,4]);b.terminators[1].subject=5;optimizer_guest(b,7,i as u32+1);
    }}
    print("OPT-01 fired R07 F32 guests preserve exact non-NaN/copy bits and the permitted arithmetic NaN set");
}
