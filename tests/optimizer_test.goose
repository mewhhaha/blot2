import tests.validator_test;
import src.optimize;
import src.frontend;
fn optimizer_fixture(b: CoreBuilder) {
    validator_scalar_fixture(b);
    for i in 3 { b.values.push(Value {type_id: 1, block_id: 1, op: (i + 1) as u32, version: (i + 2) as u32, scope: 1, ..}); }
    b.ops.push(Operation {tag: OP_U32, registry: OP_U32, results: ref_span(b, [2]), scope: 1, imm0: 7, ..});
    b.ops.push(Operation {tag: OP_U32, registry: OP_U32, results: ref_span(b, [3]), scope: 1, imm0: 9, ..});
    b.ops.push(Operation {tag: OP_U32_ADD_WRAP, registry: OP_U32_ADD_WRAP, args: ref_span(b, [2, 3]), results: ref_span(b, [4]), scope: 1, ..});
    b.blocks[1].ops = ref_span(b, [1, 2, 3]); b.terminators[1].subject = 4;
}
fn test_optimizer() {
    with_core() { let b = it; optimizer_fixture(b); validator_expect(b, true, 0);
        with_core() { let output = it; var stats = optimize::Stats {..}; var diags: Diagnostic[>..] = [];
            assert(optimize::optimize(core_view(b), optimize::Limits {..}, output, stats, diags));
            assert(output.ops[3].tag == OP_U32 && output.ops[3].imm0 == 16);
            assert(stats.r07 == 1); validator_expect(output, true, 0);
        };
        with_core() { let output = it; var stats = optimize::Stats {..}; var diags: Diagnostic[>..] = [];
            assert(!optimize::optimize(core_view(b), optimize::Limits {visits: 1, ..}, output, stats, diags));
            assert(diags.len == 0 && stats.declines == 1);
            assert(b.ops[3].tag == OP_U32_ADD_WRAP); validator_expect(b, true, 0);
        };
    };
    print("OPT-03 bounded candidate decline preserves admitted baseline; R07 exact U32 folding validated");
}

fn test_optimizer_wrap() {
    for operation in [OP_U32_ADD_WRAP, OP_U32_SUB_WRAP, OP_U32_MUL_WRAP] {
        with_core() { b =>
            optimizer_fixture(b); b.ops[1].imm0 = 0xffffffff; b.ops[2].imm0 = 2;
            b.ops[3].tag = operation; b.ops[3].registry = operation;
            with_core() { out =>
                var stats=optimize::Stats{..}; var diags:Diagnostic[>..]=[];
                assert(optimize::optimize(core_view(b),optimize::Limits{..},out,stats,diags));
                var expected:u32=1;
                if operation==OP_U32_SUB_WRAP { expected=0xfffffffd; }
                if operation==OP_U32_MUL_WRAP { expected=0xfffffffe; }
                assert(out.ops[3].tag==OP_U32 && out.ops[3].imm0==expected);
            };
        };
    }
    print("OPT-01 wrapping U32 boundary folding preserves exact bits in debug compiler");
}

fn test_optimizer_evidence() {
    let source = "pub let choose: Unit -> U32 ! {} resources {depth: 1, frame: 64} = fn () => do:\n  let value = U32.wrapping_add(0,1)\n  if value < 2:\n    return value+1\n  else:\n    return 4\n";
    with_core() { b =>
        var completion = Work {..}; var diags: Diagnostic[>..] = [];
        assert(frontend_complete(source, "optimizer-proof", b, completion, diags)); assert(seal_completion(b));
        validator_expect(b, true, 0);
        with_core() { output =>
            var stats = optimize::Stats {..};
            assert(optimize::optimize(core_view(b), optimize::Limits {..}, output, stats, diags));
            var retained = false;
            for op in output.ops { if op.tag == OP_U32_LT { retained = true; } }
            assert(retained); validator_expect(output, true, 0);
        };
    };
    print("OPT-01 proof-anchored compare producers retain exact edge justification");
}

fn test_optimizer_control() {
    for parameters in 2 {
        with_core() { b =>
            validator_scalar_fixture(b);
            var result:u32=1; var params=Span{..}; var args=Span{..};
            if parameters==1 { result=2; b.values.push(Value{type_id:1,block_id:2,version:2,scope:1,..}); params=ref_span(b,[2]); args=ref_span(b,[1]); }
            b.terminators.push(Terminator{tag:TERM_RETURN,subject:result,..});
            b.blocks.push(Block{params:params,term:2,scope:1,function:1,..});
            b.edges.push(Edge{from:1,to:2,args:args,kind:EDGE_NORMAL,..});
            b.terminators[1]=Terminator{tag:TERM_JUMP,edges:ref_span(b,[1]),..}; b.functions[1].blocks=ref_span(b,[1,2]);
            validator_expect(b,true,0);
            with_core() { out => var stats=optimize::Stats{..}; var diagnostics:Diagnostic[>..]=[];
                assert(optimize::optimize(core_view(b),optimize::Limits{..},out,stats,diagnostics));
                assert(out.terminators[1].tag==TERM_RETURN && out.terminators[1].subject==1);
                assert(if parameters==0 {stats.r01==1}else{stats.r02==1});
            };
        };
    }
    with_core() { b =>
        validator_scalar_fixture(b); b.types.push(TypeNode{tag:TY_BOOL,..});
        b.values.push(Value{type_id:3,block_id:1,op:1,version:2,scope:1,..});
        b.values.push(Value{type_id:1,block_id:2,op:2,version:3,scope:1,..});
        b.values.push(Value{type_id:1,block_id:3,op:3,version:4,scope:1,..});
        b.ops.push(Operation{tag:OP_BOOL,registry:OP_BOOL,results:ref_span(b,[2]),scope:1,imm0:1,..});
        b.ops.push(Operation{tag:OP_U32,registry:OP_U32,results:ref_span(b,[3]),scope:1,imm0:11,..});
        b.ops.push(Operation{tag:OP_U32,registry:OP_U32,results:ref_span(b,[4]),scope:1,imm0:22,..});
        b.terminators.push(Terminator{tag:TERM_RETURN,subject:3,..}); b.terminators.push(Terminator{tag:TERM_RETURN,subject:4,..});
        b.blocks.push(Block{ops:ref_span(b,[2]),term:2,scope:1,function:1,..}); b.blocks.push(Block{ops:ref_span(b,[3]),term:3,scope:1,function:1,..});
        b.edges.push(Edge{from:1,to:2,kind:EDGE_TRUE,..}); b.edges.push(Edge{from:1,to:3,kind:EDGE_FALSE,..});
        b.blocks[1].ops=ref_span(b,[1]); b.terminators[1]=Terminator{tag:TERM_BRANCH,subject:2,edges:ref_span(b,[1,2]),..}; b.functions[1].blocks=ref_span(b,[1,2,3]);
        validator_expect(b,true,0);
        with_core() { out => var stats=optimize::Stats{..}; var diagnostics:Diagnostic[>..]=[];
            assert(optimize::optimize(core_view(b),optimize::Limits{..},out,stats,diagnostics));
            assert(stats.r05==1 && out.terminators[1].tag==TERM_JUMP && out.refs[out.terminators[1].edges.start]==1);
        };
    };
    print("OPT-01 R01/R02 direct terminal forwarding and R05 exact literal branch selection validated");
}

fn test_optimizer_store_read() {
    let source="pub let replace: forall [r: Region] => Fn[static,Many,(Builder[r,U32,1,1,Resize],U32),(Builder[r,U32,1,1,Resize],U32)] ! {read r,write r} resources {depth:1,frame:512} = fn (buffer,value) => do:\n  let changed = builder.set(buffer,0,value)\n  let result = builder.read(changed,0)\n  return (changed,result)\n";
    with_core() { b =>
        var work=Work{..}; var diagnostics:Diagnostic[>..]=[];
        let completed=frontend_complete(source,"store-read",b,work,diagnostics); if !completed { for d in diagnostics { print(d, " ",name_bytes(core_view(b),d.detail)); } } assert(completed); assert(seal_completion(b));
        validator_expect(b,true,0);
        with_core() { out => var stats=optimize::Stats{..};
            let ok=optimize::optimize(core_view(b),optimize::Limits{..},out,stats,diagnostics); if !ok { print(diagnostics); } assert(ok);
            assert(stats.r09==1);
            var writes:u32=0; var reads:u32=0; for op in out.ops { if op.tag==OP_BUILDER_SET { writes++; } if op.tag==OP_BUILDER_GET { reads++; } }
            assert(writes==1 && reads==0);
        };
    };
    print("OPT-01 R09 exact exclusive successor store/read forwarding preserves mutation and ownership");
}

fn test_optimizer_descriptor() {
    with_core() { b =>
        validator_scalar_fixture(b); b.contracts[1].frame=16;
        b.types.push(TypeNode{tag:TY_UNIT,..}); b.types.push(TypeNode{tag:TY_SUM,children:ref_span(b,[3,3]),..});
        b.values.push(Value{type_id:3,block_id:1,op:1,version:2,scope:1,..});
        b.values.push(Value{type_id:4,block_id:1,op:2,version:3,scope:1,..});
        b.values.push(Value{type_id:1,block_id:1,op:3,version:4,scope:1,..});
        b.ops.push(Operation{tag:OP_UNIT,registry:OP_UNIT,results:ref_span(b,[2]),scope:1,..});
        b.ops.push(Operation{tag:OP_SUM,registry:OP_SUM,args:ref_span(b,[2]),results:ref_span(b,[3]),scope:1,imm0:1,..});
        b.ops.push(Operation{tag:OP_TAG,registry:OP_TAG,args:ref_span(b,[3]),results:ref_span(b,[4]),scope:1,..});
        b.blocks[1].ops=ref_span(b,[1,2,3]); b.terminators[1].subject=4; validator_expect(b,true,0);
        with_core() { out => var stats=optimize::Stats{..}; var diagnostics:Diagnostic[>..]=[];
            assert(optimize::optimize(core_view(b),optimize::Limits{..},out,stats,diagnostics));
            assert(stats.r10==1 && out.ops[3].tag==OP_U32 && out.ops[3].imm0==1);
            assert(out.ops[2].tag==OP_SUM); // Constructor/operand evaluation preserved.
        };
    };
    print("OPT-01 R10 known descriptor observation preserves constructor evaluation");
}

struct FloatRewriteCase { operation:u32, left:u32, right:u32, expected:u32, arity:u32 }
fn test_optimizer_float() {
    let cases=[
        FloatRewriteCase{OP_F32_MIN,0,0x80000000,0x80000000,2},
        FloatRewriteCase{OP_F32_MAX,0,0x80000000,0,2},
        FloatRewriteCase{OP_F32_DIV,0x3f800000,0,0x7f800000,2},
        FloatRewriteCase{OP_F32_MUL,0,0x7f800000,0x7fc00000,2},
        FloatRewriteCase{OP_F32_ADD,0x4b800000,0x3f800000,0x4b800000,2},
        FloatRewriteCase{OP_F32_NEG,0x7fa12345,0,0xffa12345,1},
        FloatRewriteCase{OP_F32_ABS,0xffa12345,0,0x7fa12345,1},
        FloatRewriteCase{OP_F32_NEAREST,0xbf000000,0,0x80000000,1}
    ];
    for sample in cases {
        with_core() { b =>
            optimizer_fixture(b); b.types[1].tag=TY_F32;
            b.ops[1].tag=OP_F32; b.ops[1].registry=OP_F32; b.ops[1].imm0=sample.left;
            b.ops[2].tag=OP_F32; b.ops[2].registry=OP_F32; b.ops[2].imm0=sample.right;
            b.ops[3].tag=sample.operation; b.ops[3].registry=sample.operation; b.ops[3].args.count=sample.arity;
            validator_expect(b,true,0);
            with_core() { out => var stats=optimize::Stats{..}; var diagnostics:Diagnostic[>..]=[];
                assert(optimize::optimize(core_view(b),optimize::Limits{..},out,stats,diagnostics));
                assert(out.ops[3].tag==OP_F32 && out.ops[3].imm0==sample.expected && stats.r07==1);
            };
        };
    }
    print("OPT-01 R07 F32 signed zero, non-NaN rounding, canonical arithmetic NaN and payload-preserving negation");
}

fn test_optimizer_budget_controls() {
    with_core() {b=>optimizer_fixture(b);b.ops[2].tag=OP_COPY;b.ops[2].registry=OP_COPY;b.ops[2].args=ref_span(b,[2]);b.ops[2].imm0=0;validator_expect(b,true,0);
        with_core() {out=>var stats=optimize::Stats{..};var diagnostics:Diagnostic[>..]=[];assert(!optimize::optimize(core_view(b),optimize::Limits{rewrites:1,..},out,stats,diagnostics));assert(stats.applications==1 && stats.declines==1 && diagnostics.len==0);validator_expect(b,true,0);};
        with_core() {out=>var stats=optimize::Stats{..};var diagnostics:Diagnostic[>..]=[];assert(!optimize::optimize(core_view(b),optimize::Limits{output:1,..},out,stats,diagnostics));assert(stats.applications==0 && stats.declines==1 && diagnostics.len==0);validator_expect(b,true,0);};
        with_core() {out=>var stats=optimize::Stats{..};var diagnostics:Diagnostic[>..]=[];assert(optimize::optimize(core_view(b),optimize::Limits{..},out,stats,diagnostics));out.values[1].type_id=4294967295;var work=Work{..};assert(!validator::validate_core(core_view(out),validator::OPTIONAL,work,diagnostics));assert(!work.exhausted && diagnostics.len!=0);};
    };
    print("OPT-03 rewrite/output budget decline preserves baseline; malformed candidate is a hard validation error");
}
