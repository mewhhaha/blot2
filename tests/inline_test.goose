import tests.optimizer_differential_test;

fn inline_prepare(source:const u8[:],b:CoreBuilder) {
    var work=Work{..};var diagnostics:Diagnostic[>..]=[];
    let completed=frontend_complete(source,"inline-laws",b,work,diagnostics);
    if !completed {print("inline completion ",diagnostics);}assert(completed);
    assert(build_plans(b,"",diagnostics));assert(canonical_schemas(b,diagnostics));assert(seal_completion(b));
    validator_expect(b,true,0);
}
fn inline_function(c:Core,name:const u8[:])->u32 {
    for f,fid in c.functions { if fid!=0 && name_bytes(c,f.name)==name {return fid as u32;} }abort("missing inline test function");
}
fn inline_call_count(c:Core,fid:u32)->u32 {
    var count:u32=0;
    for bi in c.functions[fid].blocks.count {let basic=c.blocks[c.refs[c.functions[fid].blocks.start+bi]];
        for oi in basic.ops.count {if c.ops[c.refs[basic.ops.start+oi]].tag==OP_CALL {count++;}}
    }return count;
}
fn inline_candidate(b:CoreBuilder,out:CoreBuilder,stats:optimize::Stats&,limits:optimize::Limits)->bool {
    var diagnostics:Diagnostic[>..]=[];let ok=optimize::optimize(core_view(b),limits,out,stats,diagnostics);
    if diagnostics.len!=0 {print("inline candidate diagnostics ",diagnostics);}assert(diagnostics.len==0);return ok;
}
fn test_inline_zero_growth_and_depth() {
    let source="let square: F32 -> F32 ! {} resources {depth:1,frame:0} = fn x => return x*x\nlet one: F32 -> F32 ! {} resources {depth:2,frame:0} = fn x => return square(x)\nlet two: F32 -> F32 ! {} resources {depth:3,frame:0} = fn x => return one(x)\npub let run: F32 -> F32 ! {} resources {depth:4,frame:0} = fn x => return two(x)\n";
    with_core() {b=>inline_prepare(source,b);
        with_core() {out=>var stats=optimize::Stats{};assert(inline_candidate(b,out,stats,optimize::Limits{}));assert(stats.inline_sites==0);assert(inline_call_count(core_view(out),inline_function(core_view(out),"run"))==1);};
        with_core() {out=>var stats=optimize::Stats{};assert(inline_candidate(b,out,stats,optimize::Limits{release:true}));
            assert(stats.inline_sites==5 && stats.inline_growth==0 && stats.inline_max_depth==2 && stats.inline_max_callee==2);
            let run=inline_function(core_view(out),"run");assert(inline_call_count(core_view(out),run)==1);
            let basic=out.blocks[out.functions[run].entry];let op=out.ops[out.refs[basic.ops.start]];
            assert(op.tag==OP_CALL && name_bytes(core_view(out),out.functions[op.imm0].name)=="square");
            assert(out.functions[run].calls.count==1);let metadata=out.calls[out.refs[out.functions[run].calls.start]];
            assert(metadata.op==out.refs[basic.ops.start] && metadata.callee==op.imm0 && metadata.contract==out.functions[op.imm0].contract);
            validator_expect(out,true,0);
        };
    };
    print("INLINE release-only zero-growth forwarding uses original templates and stops at depth two; live call metadata exact");
}
fn inline_chain_source(count:u32,padding:u32,extra:u32)->u8[>..] {
    var source:u8[>..]=[];
    format(source,"let bump: U32 -> U32 ! {} resources {depth:1,frame:0} = fn x => do:\n");
    for i in count {format(source,"  let v",i," = U32.wrapping_add(",if i==0 {str("x")} else {str("v",i-1)},",1)\n");}
    for i in extra {format(source,"  let _ = ",99+i,"\n");}
    format(source,"  return v",count-1,"\npub let run: U32 -> U32 ! {} resources {depth:2,frame:0} = fn x => do:\n");
    for i in padding {format(source,"  let _ = ",i,"\n");}format(source,"  return bump(x)\n");return source;
}
fn test_inline_callee_and_growth_boundaries() {
    for extra in 2 {with_core() {b=>var source=inline_chain_source(15,120,extra as u32+1);
        inline_prepare(source,b);with_core() {out=>var stats=optimize::Stats{};assert(inline_candidate(b,out,stats,optimize::Limits{release:true}));
            if extra==0 {assert(stats.inline_sites==1 && stats.inline_max_callee==32 && stats.inline_growth==30);}
            else {assert(stats.inline_sites==0 && stats.inline_declines>0);}
            validator_expect(out,true,0);
        };
    }}
    for padding in 4 {with_core() {b=>var source:u8[>..]=[];
        format(source,"let bump: U32 -> U32 ! {} resources {depth:1,frame:0} = fn x => return U32.wrapping_add(x,1)\npub let run: U32 -> U32 ! {} resources {depth:2,frame:0} = fn x => do:\n");
        for i in padding {format(source,"  let _ = ",i,"\n");}format(source,"  return bump(x)\n");inline_prepare(source,b);
        with_core() {out=>var stats=optimize::Stats{};assert(inline_candidate(b,out,stats,optimize::Limits{release:true}));assert(stats.inline_sites==(if padding>=2 {1 as u64}else{0}));assert(stats.inline_growth==(if padding>=2 {1 as u64}else{0}));};
    }}
    print("INLINE exact32/33-operation callee cutoff and floor25%-of-admitted-caller growth boundary");
}
fn test_inline_sites_and_global_prefix() {
    for count in [16 as u32,17] {with_core() {b=>var source:u8[>..]=[];
        format(source,"let twice: U32 -> U32 ! {} resources {depth:1,frame:0} = fn x => return U32.wrapping_add(x,x)\npub let run: U32 -> U32 ! {} resources {depth:2,frame:0} = fn x => do:\n");
        for i in count {format(source,"  let v",i," = twice(",if i==0 {str("x")} else {str("v",i-1)},")\n");}format(source,"  return v",count-1,"\n");inline_prepare(source,b);
        with_core() {out=>var stats=optimize::Stats{};assert(inline_candidate(b,out,stats,optimize::Limits{release:true}));assert(stats.inline_sites==16 && stats.inline_growth==0);assert(inline_call_count(core_view(out),inline_function(core_view(out),"run"))==count-16);};
    }}
    with_core() {b=>var source:u8[>..]=[];
        format(source,"let bump: U32 -> U32 ! {} resources {depth:1,frame:0} = fn x => return U32.wrapping_add(x,1)\n");
        for caller in 70 {format(source,"pub let ",if caller==0 {str("run")} else {str("run_",caller)},": U32 -> U32 ! {} resources {depth:2,frame:0} = fn x => do:\n");for i in 12 {format(source,"  let _ = ",i,"\n");}format(source,"  return bump(x)\n");}
        inline_prepare(source,b);with_core() {out=>var stats=optimize::Stats{};assert(inline_candidate(b,out,stats,optimize::Limits{release:true}));assert(stats.inline_sites==64 && stats.inline_growth==64 && stats.inline_declines==6);assert(out.ops.len==b.ops.len+64);validator_expect(out,true,0);};
    };
    print("INLINE 16-site caller cap and useful validated prefix at global N+64 cap over70 eligible callers");
}
fn test_inline_pinning_and_budget_decline() {
    let source="let twice: U32 -> U32 ! {} resources {depth:1,frame:0} = fn x => return U32.wrapping_add(x,x)\npub let run: U32 -> U32 ! {} resources {depth:2,frame:0} = fn x => return twice(x)\n";
    for pin_callee in 2 {with_core() {b=>inline_prepare(source,b);let fid=inline_function(core_view(b),if pin_callee==0 {"run"}else{"twice"});let oid=b.refs[b.blocks[b.functions[fid].entry].ops.start];let value=b.refs[b.ops[oid].results.start];let row=b.values[value];b.terms.push(Term{tag:EXPR_VALUE,type_id:row.type_id,value:value,version:row.version,scope:row.scope,..});validator_expect(b,true,0);
        with_core() {out=>var stats=optimize::Stats{};assert(inline_candidate(b,out,stats,optimize::Limits{release:true}));assert(stats.inline_sites==0 && stats.inline_declines>0);assert(inline_call_count(core_view(out),inline_function(core_view(out),"run"))==1);};
    }}
    with_core() {b=>inline_prepare(source,b);
        for limits in [optimize::Limits{release:true,visits:1},optimize::Limits{release:true,output:1}] {with_core() {out=>var stats=optimize::Stats{};assert(!inline_candidate(b,out,stats,limits));assert(stats.declines==1);assert(inline_call_count(core_view(b),inline_function(core_view(b),"run"))==1);validator_expect(b,true,0);};}
        with_core() {out=>var stats=optimize::Stats{};assert(inline_candidate(b,out,stats,optimize::Limits{release:true,rewrites:1}));assert(stats.inline_sites==1 && stats.applications==1);};
    };
    print("INLINE proof-pinned caller/callee declined; global exhaustion preserves baseline and admitted input stays immutable");
}

fn test_inline_empty_return_and_physical_preflight() {
    let source="let identity: U32 -> U32 ! {} resources {depth:1,frame:0} = fn x => return x\npub let run: U32 -> U32 ! {} resources {depth:2,frame:0} = fn x => return identity(x)\n";
    with_core() {b=>inline_prepare(source,b);var encoded:u8[>..]=[];assert(artifact::encode_tables(core_view(b),encoded));
        for no_room in 2 {with_core() {out=>var diagnostics:Diagnostic[>..]=[];assert(artifact::artifact_decode(encoded,out,diagnostics));out.phase=b.phase;
            var pinned:bool[>..]=[];for row in b.ops {pinned.push(false);}var stats=inlining::Stats{};
            let input=core_view(b);assert(inlining::run(input,out,pinned,inlining::Limits{10000,100,64,if no_room==0 {encoded.len as u64}else{LIMIT_ARTIFACT as u64}},stats));
            if no_room==0 {assert(stats.sites==1 && stats.growth==0);assert(inline_call_count(core_view(out),inline_function(core_view(out),"run"))==0);}
            else {assert(stats.sites==0 && stats.declines==1 && out.ops.len==b.ops.len && out.values.len==b.values.len && out.refs.len==b.refs.len);}
            validator_expect(out,true,0);
        }}
    };
    print("INLINE empty returned-parameter transport is an explicit zero-growth copy; physical-byte preflight adds no rows on refusal");
}
fn inline_executed_guest(path:const u8[:],name:const u8[:]) {
    var source:u8[>..]=[];assert(read_file(path,source));
    with_core() {b=>inline_prepare(source,b);with_core() {out=>var stats=optimize::Stats{};
        assert(inline_candidate(b,out,stats,optimize::Limits{release:true}));assert(stats.inline_sites>0 && b.functions.len==out.functions.len);
        validator_expect(out,true,0);var diagnostics:Diagnostic[>..]=[];var baseline:u8[>..]=[];var candidate:u8[>..]=[];
        assert(wasm_emit_manifest_telemetry(core_view(b),baseline,"",diagnostics));assert(wasm_emit_manifest_telemetry(core_view(out),candidate,"",diagnostics));
        assert(write_file(str("/tmp/blot-k1-inline-",name,"-baseline.wasm"),baseline));assert(write_file(str("/tmp/blot-k1-inline-",name,"-candidate.wasm"),candidate));
        assert(write_file(str("/tmp/blot-k1-inline-",name,"-stats.json"),str("{\"sites\":",stats.inline_sites,",\"growth\":",stats.inline_growth,",\"max_callee\":",stats.inline_max_callee,",\"max_depth\":",stats.inline_max_depth,"}")));
        if name=="scalar" {
            let caller=inline_function(core_view(out),"run_early");let basic=out.blocks[out.functions[caller].entry];
            var producer:u32=0;var after=false;
            for oi in basic.ops.count {let op=out.refs[basic.ops.start+oi];if op==out.values[out.terminators[basic.term].subject].op {producer=op;}else if producer!=0 {after=true;}}
            assert(producer!=0 && after); // The returned producer precedes later dead total operations.
        } else {
            assert(inline_call_count(core_view(out),inline_function(core_view(out),"run"))==1); // acquire remains effectful and executes once.
        }
    }};
}
fn test_inline_executed_guests() {
    inline_executed_guest("tests/inline_runtime.blot","scalar");
    inline_executed_guest("tests/inline_effect.blot","effect");
    print("INLINE qualified scalar/effect guests emitted with conservative source bodies and resource certificates intact");
}

fn test_inline_visit_budget_prefix() {
    var source:u8[>..]=[];
    for i in 128 {format(source,
        "let leaf_",i,": U32 -> U32 ! {} resources {depth:1,frame:0} = fn x => return U32.wrapping_add(x,1)\n",
        "let left_",i,": U32 -> U32 ! {} resources {depth:2,frame:0} = fn x => return leaf_",i,"(x)\n",
        "let right_",i,": U32 -> U32 ! {} resources {depth:2,frame:0} = fn x => return leaf_",i,"(x)\n",
        "pub let run_",i,": U32 -> U32 ! {} resources {depth:3,frame:0} = fn x => return U32.wrapping_add(left_",i,"(x),right_",i,"(x))\n");}
    with_core() {b=>inline_prepare(source,b);with_core() {out=>var stats=optimize::Stats{};assert(inline_candidate(b,out,stats,optimize::Limits{release:true}));
        let n=b.ops.len+b.terminators.len-2;assert(stats.inline_sites>0 && stats.inline_growth>0 && stats.declines==0 && stats.visits<=n as u64*8+1024);
        validator_expect(out,true,0);print("INLINE distinct-callee prefix: N=",n," visits=",stats.visits," sites=",stats.inline_sites," growth=",stats.inline_growth);
    }};
}

fn test_inline_multiblock_reservation_stop() {
    let source="let twice: U32 -> U32 ! {} resources {depth:1,frame:0} = fn x => return U32.wrapping_add(x,x)\npub let run: U32 -> U32 ! {} resources {depth:2,frame:0} = fn x => do:\n  let first = twice(x)\n  if x < 100:\n    return twice(first)\n  else:\n    return twice(first)\n";
    with_core() {b=>inline_prepare(source,b);var encoded:u8[>..]=[];assert(artifact::encode_tables(core_view(b),encoded));var partial=false;
        for limit in 256 {with_core() {out=>var diagnostics:Diagnostic[>..]=[];assert(artifact::artifact_decode(encoded,out,diagnostics));out.phase=b.phase;
            var pinned:bool[>..]=[];for row in b.ops {pinned.push(false);}var stats=inlining::Stats{};let allowed=limit as u64+1;
            let input=core_view(b);let accepted=inlining::run(input,out,pinned,inlining::Limits{allowed,100,64,encoded.len as u64},stats);
            assert(stats.visits<=allowed);
            if accepted {assert(!stats.exhausted && !stats.stopped);validator_expect(out,true,0);if stats.sites>0 && stats.sites<3 {partial=true;}}
            else {assert(stats.exhausted);}
        }}assert(partial);
    };
    print("INLINE tight visit sweep preserves valid multi-block prefixes and finalizes live calls before stopping");
}
fn test_inline_unexpected_mapping_failure() {
    let source="let twice: U32 -> U32 ! {} resources {depth:1,frame:0} = fn x => return U32.wrapping_add(x,x)\npub let run: U32 -> U32 ! {} resources {depth:2,frame:0} = fn x => return twice(x)\n";
    with_core() {b=>inline_prepare(source,b);
        let twice=inline_function(core_view(b),"twice");let run=inline_function(core_view(b),"run");let op=b.refs[b.blocks[b.functions[twice].entry].ops.start];
        // Deliberately violate the private helper's admitted-input premise: a
        // foreign SSA argument must surface as an invariant error, never decline.
        b.refs[b.ops[op].args.start]=b.functions[run].param;
        var encoded:u8[>..]=[];assert(artifact::encode_tables(core_view(b),encoded));
        with_core() {out=>var diagnostics:Diagnostic[>..]=[];assert(artifact::artifact_decode(encoded,out,diagnostics));out.phase=b.phase;
            var pinned:bool[>..]=[];for row in b.ops {pinned.push(false);}var stats=inlining::Stats{};
            let input=core_view(b);assert(!inlining::run(input,out,pinned,inlining::Limits{10000,100,64,encoded.len as u64},stats));
            assert(!stats.exhausted && !stats.stopped);
        };
    };
    print("INLINE unexpected SSA mapping failure propagates as internal failure rather than optional budget refusal");
}
