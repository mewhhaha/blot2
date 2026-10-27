import src.validate;
import src.artifact;
import std;

fn validator_scalar_fixture(b: CoreBuilder) {
    b.types.push(TypeNode { tag: TY_U32, .. });
    b.scopes.push(Scope { kind: SCOPE_FUNCTION, .. });
    b.contracts.push(Contract { arg: 1, result: 1, depth: 1, .. });
    b.types.push(TypeNode { tag: TY_FN, children: ref_span(b, [1, 1]), contract: 1, mode: MODE_MANY, .. });
    b.values.push(Value { type_id: 1, block_id: 1, version: 1, scope: 1, .. });
    b.terminators.push(Terminator { tag: TERM_RETURN, subject: 1, .. });
    b.blocks.push(Block { params: ref_span(b, [1]), term: 1, scope: 1, function: 1, .. });
    b.functions.push(Function { type_id: 2, contract: 1, param: 1, entry: 1, blocks: ref_span(b, [1]), .. });
    b.phase.phase = PHASE_SEALED;
}
fn validator_expect(b: CoreBuilder, good: bool, cause: u32) {
    var work = Work { .. }; var diagnostics: Diagnostic[>..] = [];
    let accepted = validator::validate_core(core_view(b), validator::REQUIRED, work, diagnostics);
    if accepted != good { print("unexpected validator result ", accepted, " diagnostics ", diagnostics); }
    assert(accepted == good);
    if !good { assert(diagnostics.len > 0); assert(diagnostics[diagnostics.len - 1].code == 2034); assert(diagnostics[diagnostics.len - 1].detail == cause); }
}
fn test_validator() {
    with_core() { let b = it; validator_scalar_fixture(b); validator_expect(b, true, 0); };
    with_core() { let b = it; validator_scalar_fixture(b); b.blocks[1].params = Span {0xffffffff, 2}; validator_expect(b, false, 2034); };
    with_core() { let b = it; validator_scalar_fixture(b); b.values[1].type_id = 999; validator_expect(b, false, 2034); };
    with_core() { let b = it; validator_scalar_fixture(b); b.scopes[1].parent = 1; validator_expect(b, false, 2034); };
    with_core() { let b = it; validator_scalar_fixture(b); b.contracts[1].depth = 0; validator_expect(b, false, 2023); };
    with_core() { let b = it; validator_scalar_fixture(b); b.types[1].tag = TY_ALIAS; b.types[1].children = ref_span(b, [1]); validator_expect(b, false, 2024); };
    with_core() { let b = it; validator_scalar_fixture(b);
        b.terms.push(Term {tag: EXPR_VALUE, type_id: 1, value: 1, version: 999, ..});
        validator_expect(b, false, 2034);
    };
    with_core() { let b = it; validator_scalar_fixture(b);
        b.terms.push(Term {tag: EXPR_LITERAL, type_id: 1, literal: 5, ..});
        b.terms.push(Term {tag: EXPR_LITERAL, type_id: 1, literal: 3, ..});
        b.facts.push(Fact {tag: FACT_LT, left: 1, right: 2, ..});
        b.evidence.push(Evidence {rule: RULE_LITERAL, fact: 1, ..});
        validator_expect(b, false, 2034);
    };
    print("SEC-01/02 structural, recursive type, resource and forged evidence controls passed");
}
fn test_artifact() {
    var encoded: u8[>..] = [];
    with_core() { let producer = it; validator_scalar_fixture(producer); assert(artifact::artifact_encode(core_view(producer), encoded)); };
    // The producer and every builder reference have died before decoding/validation.
    with_core() { let imported = it; var diags: Diagnostic[>..] = [];
        assert(artifact::artifact_decode(encoded, imported, diags)); validator_expect(imported, true, 0);
        var encoded_again: u8[>..] = []; assert(artifact::artifact_encode(core_view(imported), encoded_again)); assert(encoded == encoded_again);
    };
    with_core() { let imported = it; var diags: Diagnostic[>..] = [];
        encoded[0] ^= 1; assert(!artifact::artifact_decode(encoded, imported, diags)); encoded[0] ^= 1;
    };
    with_core() { let imported = it; var diags: Diagnostic[>..] = [];
        encoded[4] ^= 1; assert(!artifact::artifact_decode(encoded, imported, diags)); assert(diags[0].code == 2035); encoded[4] ^= 1;
    };
    with_core() { let imported = it; var diags: Diagnostic[>..] = [];
        encoded[encoded.len - 1] ^= 1; assert(!artifact::artifact_decode(encoded, imported, diags)); encoded[encoded.len - 1] ^= 1;
    };
    print("CMP-03 owned portable roundtrip after producer death; corrupt headers/body rejected");
}

fn test_validator_incomplete_product() {
    with_core() { b =>
        validator_scalar_fixture(b);
        b.types.push(TypeNode {tag: TY_TUPLE, children: ref_span(b,[1,1]), ..});
        b.types[2].children = ref_span(b,[1,3]); b.contracts[1].result = 3; b.contracts[1].frame = 256;
        b.values.push(Value {type_id: 3, block_id: 1, op: 1, version: 2, scope: 1, ..});
        b.ops.push(Operation {tag: OP_TUPLE, registry: OP_TUPLE, args: ref_span(b,[1,1]), results: ref_span(b,[2]), scope: 1, ..});
        b.blocks[1].ops = ref_span(b,[1]); b.terminators[1].subject = 2;
        validator_expect(b,true,0);
        b.ops[1].args = ref_span(b,[1]);
        var work = Work { .. }; var diagnostics: Diagnostic[>..] = [];
        assert(!validator::validate_core(core_view(b),validator::FRESH,work,diagnostics));
        assert(diagnostics[diagnostics.len-1].code == 2018);
        assert(validator::validator_diagnostic_name(diagnostics[diagnostics.len-1].code) == "k1_incomplete_initialization");
        validator_expect(b,false,2018);
    };
    print("MEM-R01 a typed product missing a field cannot be published; required artifact preserves initialization cause");
}

fn test_validator_consumed_observation() {
    with_core() { b =>
        validator_scalar_fixture(b);
        b.binders.push(Binder {kind: KIND_REGION, scope: 1, ..});
        b.terms.push(Term {tag: EXPR_LITERAL, type_id: 1, literal: 10, ..});
        b.types.push(TypeNode {tag: TY_DEST, children: ref_span(b,[1]), region: 1, capacity: 1, ..});
        b.types.push(TypeNode {tag: TY_UNIT, ..});
        b.types[2].children=ref_span(b,[3,1]); b.contracts[1].arg=3; b.contracts[1].frame=256;
        b.functions[1].binders=ref_span(b,[1]); b.contracts[1].binders=b.functions[1].binders; b.values[1].type_id=3;
        b.values.push(Value {type_id: 4, block_id: 1, op: 1, version: 2, scope: 1, ..});
        b.values.push(Value {type_id: 1, block_id: 1, op: 2, version: 3, scope: 1, ..});
        b.ops.push(Operation {tag: OP_DEST_DISCARD, registry: OP_DEST_DISCARD, args: ref_span(b,[1]), results: ref_span(b,[2]), scope: 1, ..});
        b.ops.push(Operation {tag: OP_DEST_CAP, registry: OP_DEST_CAP, args: ref_span(b,[1]), results: ref_span(b,[3]), scope: 1, ..});
        b.blocks[1].ops=ref_span(b,[1,2]); b.terminators[1].subject=3;
        validator_expect(b,false,2013);
    };
    print("MEM-R02 observing a consumed destination is rejected");
}

fn test_validator_static() {
    with_core() { b =>
        validator_scalar_fixture(b);
        let bytes=Span{start:b.bytes.len as u32,count:4}; b.bytes.append([12 as u8,0 as u8,0 as u8,0 as u8]);
        b.static_objects.push(StaticObject{kind:STATIC_VALUE,type_id:1,count:1,bytes:bytes,steps:1,..});
        b.values.push(Value{type_id:1,block_id:1,op:1,version:2,scope:1,..});
        b.ops.push(Operation{tag:OP_STATIC,registry:OP_STATIC,results:ref_span(b,[2]),scope:1,imm0:1,..});
        b.blocks[1].ops=ref_span(b,[1]); b.terminators[1].subject=2;
        validator_expect(b,true,0);
        // A code-address relocation cannot hide inside an ordinary U32 constant.
        b.static_relocations.push(StaticRelocation{offset:0,kind:STATIC_FUNCTION,target:1,..});
        b.static_objects[1].relocations=ref_span(b,[1]);
        validator_expect(b,false,2034);
    };
    with_core() { b =>
        validator_scalar_fixture(b);
        b.types.push(TypeNode{tag:TY_BOOL,..});
        let bytes=Span{start:b.bytes.len as u32,count:4}; b.bytes.append([2 as u8,0 as u8,0 as u8,0 as u8]);
        b.static_objects.push(StaticObject{kind:STATIC_VALUE,type_id:3,count:1,bytes:bytes,steps:1,..});
        validator_expect(b,false,2034);
    };
    print("SEC-03 static canonical bytes reject non-Bool words and pointer relocation laundering");
}

fn validator_quota_fixture(b:CoreBuilder,functions:u32,terms_per_function:u32) {
    b.types.push(TypeNode{tag:TY_U32,..});
    b.contracts.push(Contract{arg:1,result:1,depth:1,..});
    b.types.push(TypeNode{tag:TY_FN,children:ref_span(b,[1,1]),contract:1,mode:MODE_MANY,..});
    for i in functions {
        let id=i+1;
        b.scopes.push(Scope{kind:SCOPE_FUNCTION,..});
        b.values.push(Value{type_id:1,block_id:id,version:id,scope:id,..});
        b.terminators.push(Terminator{tag:TERM_RETURN,subject:id,..});
        b.blocks.push(Block{params:ref_span(b,[id]),term:id,scope:id,function:id,..});
        b.functions.push(Function{type_id:2,contract:1,param:id,entry:id,blocks:ref_span(b,[id]),..});
        for literal in terms_per_function {
            let term=b.terms.len as u32; b.terms.push(Term{tag:EXPR_LITERAL,type_id:1,literal:literal,scope:id,..});
            let fact=b.facts.len as u32; b.facts.push(Fact{tag:FACT_EQ,left:term,right:term,..});
            b.evidence.push(Evidence{rule:RULE_REFLEXIVE,fact:fact,scope:id,..});
        }
    }
    b.phase.phase=PHASE_SEALED;
}
fn test_validator_declaration_budgets() {
    with_core() { b =>
        validator_quota_fixture(b,10,3000);
        var work=Work{..}; var diagnostics:Diagnostic[>..]=[];
        let ok=validator::validate_core(core_view(b),validator::FRESH,work,diagnostics);
        if !ok { print(diagnostics); } assert(ok);
        assert(work.proof_visits>LIMIT_PROOF_VISITS);
    };
    with_core() { b =>
        validator_quota_fixture(b,1,LIMIT_TERMS+1);
        validator_expect(b,false,2032);
    };
    with_core() { b =>
        validator_quota_fixture(b,2,3000);
        b.definitions.push(Definition{kind:DEF_FUNCTION,type_id:2,function:1,..});
        b.functions[1].producer=1; b.functions[2].producer=1;
        validator_expect(b,false,2032);
    };
    print("LIM-01 many valid declarations do not share a proof budget; one oversized declaration still rejects");
}

fn test_validator_field_identity() {
    with_core() { b =>
        validator_scalar_fixture(b);
        b.fields.push(Field{name:add_name(b,"left"),type_id:1,..});
        b.fields.push(Field{name:add_name(b,"right"),type_id:1,..});
        b.types.push(TypeNode{tag:TY_RECORD,fields:ref_span(b,[1]),..});
        b.types.push(TypeNode{tag:TY_RECORD,fields:ref_span(b,[2]),..});
        b.contracts[1].arg=3; b.contracts[1].result=4; b.contracts[1].frame=16;
        b.types[2].children=ref_span(b,[3,4]); b.values[1].type_id=3;
        b.values.push(Value{type_id:4,block_id:1,op:1,version:2,scope:1,..});
        b.ops.push(Operation{tag:OP_COPY,registry:OP_COPY,args:ref_span(b,[1]),results:ref_span(b,[2]),scope:1,..});
        b.blocks[1].ops=ref_span(b,[1]); b.terminators[1].subject=2;
        validator_expect(b,false,2003);
    };
    print("SEC-02 equal storage shape does not authorize a forged record field identity");
}

fn test_validator_static_packages() {
    with_core() { b =>
        validator_scalar_fixture(b);
        b.binders.push(Binder{kind:KIND_NAT,..}); b.binders.push(Binder{kind:KIND_DOMAIN,..});
        b.terms.push(Term{tag:EXPR_BINDER,type_id:1,binder:1,..});
        b.types.push(TypeNode{tag:TY_INDEX,nat:1,domain:2,..});
        b.types.push(TypeNode{tag:TY_EXISTS,children:ref_span(b,[3]),binders:ref_span(b,[1,2]),..});
        let bytes=Span{start:b.bytes.len as u32,count:8}; b.bytes.append([6 as u8,0 as u8,0 as u8,0 as u8,5 as u8,0 as u8,0 as u8,0 as u8]);
        b.static_objects.push(StaticObject{kind:STATIC_VALUE,type_id:4,count:1,bytes:bytes,steps:1,..});
        validator_expect(b,true,0);
        b.bytes[bytes.start]=5; validator_expect(b,false,2034);
    };
    with_core() { b =>
        validator_scalar_fixture(b);
        b.binders.push(Binder{kind:KIND_DOMAIN,..}); b.binders.push(Binder{kind:KIND_NAT,..}); b.binders.push(Binder{kind:KIND_DOMAIN,..});
        b.terms.push(Term{tag:EXPR_LITERAL,type_id:1,literal:3,..}); b.terms.push(Term{tag:EXPR_BINDER,type_id:1,binder:2,..});
        b.types.push(TypeNode{tag:TY_VIEW,children:ref_span(b,[1]),nat:1,domain:1,..});
        b.types.push(TypeNode{tag:TY_VIEW,children:ref_span(b,[1]),nat:2,domain:3,..});
        b.types.push(TypeNode{tag:TY_TUPLE,children:ref_span(b,[4,4]),..});
        b.types.push(TypeNode{tag:TY_EXISTS,children:ref_span(b,[5]),binders:ref_span(b,[2,3]),..});
        let array_bytes=Span{start:b.bytes.len as u32,count:12}; for i in 12 { b.bytes.push(0); }
        b.static_objects.push(StaticObject{kind:STATIC_ARRAY,type_id:3,element_type:1,count:3,domain:1,bytes:array_bytes,steps:1,..});
        let bytes=Span{start:b.bytes.len as u32,count:20}; for i in 20 { b.bytes.push(0); } b.bytes[bytes.start]=2; b.bytes[bytes.start+8]=2; b.bytes[bytes.start+16]=2;
        b.static_relocations.push(StaticRelocation{offset:4,kind:STATIC_ADDRESS,target:1,..});
        b.static_relocations.push(StaticRelocation{offset:12,kind:STATIC_ADDRESS,target:1,..});
        b.static_objects.push(StaticObject{kind:STATIC_VALUE,type_id:6,count:1,bytes:bytes,relocations:ref_span(b,[1,2]),steps:1,..});
        validator_expect(b,true,0);
        b.static_relocations[2].addend=4; validator_expect(b,false,2034);
    };
    print("SEC-03 static existential witnesses reject out-of-range Index and forged shared slice domains");
}

fn test_validator_reachability() {
    with_core() { b =>
        validator_scalar_fixture(b);
        b.terms.push(Term{tag:EXPR_ARG,type_id:1,binder:1,..}); b.facts.push(Fact{tag:FACT_LT,left:1,right:1,..}); b.contracts[1].requires=ref_span(b,[1]);
        b.terms.push(Term{tag:EXPR_VALUE,type_id:1,value:1,version:1,scope:1,..}); b.facts.push(Fact{tag:FACT_LT,left:2,right:2,..});
        b.evidence.push(Evidence{rule:RULE_ASSUMPTION,fact:2,contract:1,formal_fact:1,scope:1,operands:ref_span(b,[1]),..});
        b.terminators[1]=Terminator{evidence:ref_span(b,[1]),tag:TERM_UNREACHABLE,..}; validator_expect(b,true,0);
        b.terminators[1].evidence=Span{..}; validator_expect(b,false,2008);
    };
    with_core() { b =>
        validator_scalar_fixture(b); b.types.push(TypeNode{tag:TY_BOOL,..});
        b.values.push(Value{type_id:3,block_id:1,op:1,version:2,scope:1,..}); b.ops.push(Operation{tag:OP_BOOL,registry:OP_BOOL,results:ref_span(b,[2]),scope:1,..}); b.blocks[1].ops=ref_span(b,[1]);
        b.edges.push(Edge{from:1,to:2,kind:EDGE_TRUE,..}); b.edges.push(Edge{from:1,to:3,kind:EDGE_FALSE,..});
        b.terminators[1]=Terminator{tag:TERM_BRANCH,subject:2,edges:ref_span(b,[1,2]),..};
        b.terminators.push(Terminator{tag:TERM_UNREACHABLE,..}); b.terminators.push(Terminator{tag:TERM_RETURN,subject:1,..});
        b.blocks.push(Block{term:2,scope:1,function:1,..}); b.blocks.push(Block{term:3,scope:1,function:1,..}); b.functions[1].blocks=ref_span(b,[1,2,3]);
        validator_expect(b,true,0); b.ops[1].imm0=1; validator_expect(b,false,2008);
    };
    print("CTL-01 required reachability validates contradictory facts and rejects a newly reachable missing return");
}

fn test_artifact_hostile_structure() {
    // Recompute the checksum: structural admission must reject the payload even
    // when an attacker has supplied a matching digest and all compatible IDs.
    for variant in 4 {
        var encoded:u8[>..]=[];
        with_core() {b=>validator_scalar_fixture(b);assert(artifact::artifact_encode(core_view(b),encoded));};
        if variant==0 {artifact::set32(encoded,96,4294967295);}
        if variant==1 {artifact::set32(encoded,artifact::HEADER,1);}
        if variant==2 {artifact::set32(encoded,24,encoded.len as u32-1);}
        if variant==3 {encoded.push(0);artifact::set32(encoded,24,encoded.len as u32);}
        let digest=k1hash::blake3(encoded[64..]);for i in 8 {artifact::set32(encoded,(32+i*4) as u32,digest.words[i]);}
        with_core() {b=>var diagnostics:Diagnostic[>..]=[];assert(!artifact::artifact_decode(encoded,b,diagnostics));assert(diagnostics.len!=0);};
    }
    for mutation in 4 {with_core() {b=>validator_scalar_fixture(b);
        if mutation==0 {b.values.push(b.values[1]);b.blocks[1].params=ref_span(b,[1,1]);}
        if mutation==1 {b.terminators[1].subject=0xffffffff;}
        if mutation==2 {b.functions[1].entry=0xffffffff;}
        if mutation==3 {b.terms.push(Term{tag:EXPR_LITERAL,type_id:1,..});b.facts.push(Fact{tag:FACT_EQ,left:1,right:1,..});b.evidence.push(Evidence{rule:RULE_EQUALITY,fact:1,premises:ref_span(b,[1]),..});}
        var encoded:u8[>..]=[];assert(artifact::encode_tables(core_view(b),encoded));
        with_core() {decoded=>var diagnostics:Diagnostic[>..]=[];assert(artifact::artifact_decode(encoded,decoded,diagnostics));var work=Work{..};assert(!validator::validate_core(core_view(decoded),validator::REQUIRED,work,diagnostics));assert(diagnostics.len!=0 && diagnostics[diagnostics.len-1].code==2034);};
    }}
    print("SEC-01 matching checksums cannot authorize overflowed tables, forged sentinels, extra bytes, foreign IDs or cyclic proofs");
}

fn test_validator_helper_budget() {
    with_core() {b=>
        b.types.push(TypeNode{tag:TY_U32,..});b.terms.push(Term{tag:EXPR_BINDER,type_id:1,binder:32,..});b.terms.push(Term{tag:EXPR_LITERAL,type_id:1,literal:42,..});
        var ids:u32[>..]=[];for i in 32 {b.binders.push(Binder{kind:KIND_NAT,..});b.substitutions.push(Substitution{binder:i as u32+1,kind:KIND_NAT,value:2});ids.push(i as u32+1);}let substitutions=ref_span(b,ids);
        for over in 2 {var work=Work{..};var diagnostics:Diagnostic[>..]=[];let limit:u64=34-over as u64;let core=core_view(b);let context=validator::Context{core,validator::FRESH,work,diagnostics,limit,LIMIT_PROOF_VISITS};
            let same=validator::nat_match(context,1,2,substitutions);assert(same==(over==0));assert(work.visits==limit);assert(work.exhausted==(over==1));if over==1 {assert(diagnostics.len==1 && diagnostics[0].code==2030);}
        }
        for over in 2 {var work=Work{..};var diagnostics:Diagnostic[>..]=[];let core=core_view(b);let context=validator::proof_context(validator::Context{core,validator::FRESH,work,diagnostics,128,34-over as u64});
            assert(validator::nat_match(context,1,2,substitutions)==(over==0));assert(work.proof_visits==34-over as u64);if over==1 {assert(work.exhausted && diagnostics.len==1 && diagnostics[0].code==2032);}else{assert(work.visits==work.proof_visits);}
        }
        for i in 31 {b.types.push(TypeNode{tag:TY_ALIAS,children:ref_span(b,[b.types.len as u32-1]),..});}
        for over in 2 {if over==1 {b.types.push(TypeNode{tag:TY_ALIAS,children:ref_span(b,[b.types.len as u32-1]),..});}var work=Work{..};var diagnostics:Diagnostic[>..]=[];let core=core_view(b);let context=validator::Context{core,validator::FRESH,work,diagnostics,33,LIMIT_PROOF_VISITS};
            assert(validator::terminal(context,b.types.len as u32-1)==(if over==0 {1 as u32}else{0}));assert(work.visits==33 && work.exhausted==(over==1));
        }
    };
    print("CMP-04 exact nested substitution and alias helper visits exhaust their own declaration account");
}

fn test_validator_type_definition_budget() {
    for over in 2 {with_core() {b=>
        b.types.push(TypeNode{tag:TY_U32,..});var children:u32[>..]=[];
        for i in LIMIT_TYPES-2+over {let id=b.types.len as u32;b.types.push(TypeNode{tag:TY_ALIAS,children:ref_span(b,[1]),..});children.push(id);}
        let root=b.types.len as u32;b.types.push(TypeNode{tag:TY_TUPLE,children:ref_span(b,children),..});
        var tm:u32[>..]=[];for row in b.types {tm.push(0);}var terms:u32[>..]=[0];var facts:u32[>..]=[0];var proofs:u32[>..]=[0];var contracts:u32[>..]=[0];
        var work=Work{..};var diagnostics:Diagnostic[>..]=[];var counts=validator::InventoryCounts{..};let core=core_view(b);let context=validator::Context{core,validator::FRESH,work,diagnostics};
        let accepted=validator::declaration_inventory(context,0,1,counts,validator::InventoryMarks{tm,terms,facts,proofs,contracts},0,[0],root);
        assert(accepted==(over==0));assert(counts.types==LIMIT_TYPES+over);if over==1 {assert(work.exhausted && diagnostics.len!=0 && diagnostics[diagnostics.len-1].code==2031);}
    }}
    print("CMP-04 type-only artifact definitions enforce the exact frozen graph limit without requiring a Function row");
}

fn validator_affine_edges_fixture(b: CoreBuilder) {
    validator_scalar_fixture(b);
    b.contracts.push(Contract {arg:1,result:1,depth:1,..});
    b.types.push(TypeNode {tag:TY_FN,children:ref_span(b,[1,1]),contract:2,mode:MODE_ONCE,..});
    b.types.push(TypeNode {tag:TY_TUPLE,children:ref_span(b,[3,3]),..});
    b.contracts[1].arg=4; b.contracts[1].result=4; b.contracts[1].frame=256;
    b.types[2].children=ref_span(b,[4,4]); b.values[1].type_id=4;
    b.values.push(Value {type_id:3,block_id:1,op:1,version:2,scope:1,..});
    b.values.push(Value {type_id:3,block_id:1,op:1,version:3,scope:1,..});
    b.types.push(TypeNode {tag:TY_BOOL,..});
    b.values.push(Value {type_id:5,block_id:1,op:2,version:4,scope:1,..});
    b.values.push(Value {type_id:3,block_id:2,version:5,scope:1,..});
    b.values.push(Value {type_id:3,block_id:2,version:6,scope:1,..});
    b.values.push(Value {type_id:4,block_id:2,op:3,version:7,scope:1,..});
    b.ops.push(Operation {tag:OP_DESTRUCTURE,registry:OP_DESTRUCTURE,args:ref_span(b,[1]),results:ref_span(b,[2,3]),scope:1,..});
    b.ops.push(Operation {tag:OP_BOOL,registry:OP_BOOL,results:ref_span(b,[4]),scope:1,..});
    b.ops.push(Operation {tag:OP_TUPLE,registry:OP_TUPLE,args:ref_span(b,[5,6]),results:ref_span(b,[7]),scope:1,..});
    b.edges.push(Edge {from:1,to:2,args:ref_span(b,[2,3]),kind:EDGE_TRUE,..});
    b.edges.push(Edge {from:1,to:2,args:ref_span(b,[2,3]),kind:EDGE_FALSE,..});
    b.terminators[1]=Terminator {tag:TERM_BRANCH,subject:4,edges:ref_span(b,[1,2]),..};
    b.terminators.push(Terminator {tag:TERM_RETURN,subject:7,..});
    b.blocks[1].ops=ref_span(b,[1,2]);
    b.blocks.push(Block {params:ref_span(b,[5,6]),ops:ref_span(b,[3]),term:2,scope:1,function:1,..});
    b.functions[1].blocks=ref_span(b,[1,2]);
}
fn validator_affine_unreachable_fixture(b: CoreBuilder) {
    validator_affine_edges_fixture(b);
    // The constant false branch proves block 2 impossible, despite its live
    // affine parameters. A later ordinary block must see clean scratch.
    b.blocks[2].ops=Span {..}; b.terminators[2]=Terminator {tag:TERM_UNREACHABLE,..};
    b.values.push(Value {type_id:3,block_id:3,version:8,scope:1,..});
    b.values.push(Value {type_id:3,block_id:3,version:9,scope:1,..});
    b.values[7].block_id=3; b.ops[3].args=ref_span(b,[8,9]); b.edges[2].to=3;
    b.terminators.push(Terminator {tag:TERM_RETURN,subject:7,..});
    b.blocks.push(Block {params:ref_span(b,[8,9]),ops:ref_span(b,[3]),term:3,scope:1,function:1,..});
    b.functions[1].blocks=ref_span(b,[1,2,3]);
}
fn test_validator_affine_scratch() {
    // Both mutually exclusive siblings transfer the same owners. Checking the
    // first edge must not consume the ownership state used to check the second.
    with_core() {b=>validator_affine_edges_fixture(b);validator_expect(b,true,0);};
    with_core() {b=>validator_affine_unreachable_fixture(b);validator_expect(b,true,0);};
    with_core() {b=>validator_affine_edges_fixture(b);b.edges[2].args=ref_span(b,[2,2]);validator_expect(b,false,2013);};
    with_core() {b=>validator_affine_edges_fixture(b);b.edges[1].args=ref_span(b,[2]);b.edges[2].args=ref_span(b,[2]);b.blocks[2].params=ref_span(b,[5]);validator_expect(b,false,2015);};
    print("SEC-02 affine sibling edges retain independent state; duplicate and dropped owners reject");
}
fn test_validator_unrelated_value_work() {
    var reference:u64=0;
    for affine_fixture in 3 {for expanded in 2 {with_core() {b=>
        if affine_fixture==0 {validator_scalar_fixture(b);}else if affine_fixture==1 {validator_affine_edges_fixture(b);}else{validator_affine_unreachable_fixture(b);}
        // Isolate function validation from whole-input structural accounting.
        // These unused rows model values belonging to unrelated declarations.
        if expanded!=0 {for i in 4096 {b.values.push(Value {type_id:1,block_id:1,version:i as u32+2,scope:1,..});}}
        var geometry:validator::Geometry[>..]=[];var colors:u32[>..]=[];
        for t in b.types {geometry.push(validator::Geometry {..});colors.push(0);}
        var definitions:u32[>..]=[];var live:u32[>..]=[];var outgoing:u32[>..]=[];
        for value in b.values {definitions.push(0);live.push(0);outgoing.push(0);}
        var operations:u32[>..]=[];for op in b.ops {operations.push(0);}
        var blocks:u32[>..]=[];for basic in b.blocks {blocks.push(0);}
        var work=Work{..};var diagnostics:Diagnostic[>..]=[];
        let core=core_view(b);let context=validator::Context{core,validator::FRESH,work,diagnostics};
        for t,id in b.types {if id!=0 {assert(validator::type_node(context,id as u32,colors,geometry,0));}}
        work.visits=0;work.proof_visits=0;
        assert(validator::validate_function(context,1,geometry,definitions,operations,blocks,live,outgoing));
        if expanded==0 {reference=work.visits;}else{assert(work.visits==reference);}
        for state in live {assert(state==0);}for state in outgoing {assert(state==0);}
    }}}
    print("CMP-04 function ownership work is independent of unrelated program values; indexed scratch resets after affine blocks");
}

fn validator_cfg_index_fixture(b:CoreBuilder) {
    validator_scalar_fixture(b);
    b.terminators[1]=Terminator{tag:TERM_BRANCH,subject:1,edges:ref_span(b,[1,2]),..};
    for i in 6 {
        b.terminators.push(Terminator{tag:TERM_RETURN,subject:1,..});
        b.blocks.push(Block{term:i as u32+2,scope:1,function:1,..});
    }
    b.functions[1].blocks=ref_span(b,[1,2,3,4,5,6,7]);
    b.edges.push(Edge{from:1,to:2,kind:EDGE_TRUE,..});
    b.edges.push(Edge{from:1,to:3,kind:EDGE_FALSE,..});
    b.edges.push(Edge{from:2,to:4,kind:EDGE_NORMAL,..});
    b.edges.push(Edge{from:3,to:4,kind:EDGE_NORMAL,..});
    b.edges.push(Edge{from:4,to:5,kind:EDGE_TRUE,..});
    b.edges.push(Edge{from:4,to:6,kind:EDGE_FALSE,..});
    b.edges.push(Edge{from:5,to:4,kind:EDGE_LOOP_NEXT,..});
    b.terminators[2]=Terminator{tag:TERM_JUMP,edges:ref_span(b,[3]),..};
    b.terminators[3]=Terminator{tag:TERM_JUMP,edges:ref_span(b,[4]),..};
    b.terminators[4]=Terminator{tag:TERM_BRANCH,subject:1,edges:ref_span(b,[5,6]),..};
    b.terminators[5]=Terminator{tag:TERM_JUMP,edges:ref_span(b,[7]),..};
    b.evidence.push(Evidence{edge:1,scope:1,..});
}
fn with_validator_index<F>(b:CoreBuilder) {
    var raw_work=Work{..}; var indexed_work=Work{..}; var diagnostics:Diagnostic[>..]=[];
    let core=core_view(b);let raw=validator::Context{core,validator::FRESH,raw_work,diagnostics};
    var op_blocks:u32[>..]=[]; var op_positions:u32[>..]=[]; var incoming:u32[>..]=[];
    assert(validator::index_core(raw,op_blocks,op_positions,incoming));
    // Two slots deliberately force collisions between exact block-pair keys.
    var dominance:validator::DominanceEntry[>..]=[validator::DominanceEntry{..},validator::DominanceEntry{..}];
    var seen:u64[>..]=[];var queue:u32[>..]=[];for basic in b.blocks {seen.push(0);queue.push(0);}
    var plan_heads:u32[>..]=[];var plan_next:u32[>..]=[];var adapter_heads:u32[>..]=[];var adapter_next:u32[>..]=[];
    assert(validator::index_layout_owners(raw,plan_heads,plan_next,adapter_heads,adapter_next));
    var stamp:u64[>..]=[0];var index=validator::ValidationIndex{op_blocks,op_positions,incoming,dominance,seen,queue,stamp,plan_heads,plan_next,adapter_heads,adapter_next};
    var indexed=validator::Context{core,validator::FRESH,indexed_work,diagnostics};indexed.indexes .= index;indexed.epoch=1;
    F(raw,indexed);
}
fn test_validator_cfg_indexes() {
    with_core(){b=>validator_cfg_index_fixture(b);with_validator_index(b){raw,indexed=>
        for repeat in 2 {for definition in 7 {for target in 7 {
            assert(validator::dominates(raw,definition as u32+1,target as u32+1)==validator::dominates(indexed,definition as u32+1,target as u32+1));
        }}}
        assert(!validator::dominates(indexed,2,4));assert(validator::dominates(indexed,4,6));
        assert(validator::dominates(indexed,2,7)); // Preserve unreachable-target semantics.
        assert(validator::evidence_available(raw,1,2) && validator::evidence_available(indexed,1,2));
        assert(!validator::evidence_available(raw,1,4) && !validator::evidence_available(indexed,1,4));
        indexed.work.visits=0;assert(validator::dominates(indexed,4,6));let miss=indexed.work.visits;
        indexed.work.visits=0;assert(validator::dominates(indexed,4,6));assert(indexed.work.visits==1);
        var other=indexed;other.epoch=2;other.work.visits=0;assert(validator::dominates(other,4,6));assert(other.work.visits==miss && miss>1);
        var exhausted=indexed;exhausted.epoch=3;exhausted.visit_limit=1;exhausted.work.visits=0;
        assert(!validator::dominates(exhausted,4,6));assert(exhausted.work.exhausted);
        exhausted.work.visits=0;exhausted.work.exhausted=false;exhausted.visit_limit=LIMIT_VISITS;
        assert(validator::dominates(exhausted,4,6));assert(exhausted.work.visits==miss);
    };};
    for hostile in 3 {with_core(){b=>validator_affine_edges_fixture(b);
        if hostile==0 {b.blocks[1].ops=ref_span(b,[1,2,1]);}
        if hostile==1 {b.blocks[1].ops=ref_span(b,[2]);}
        if hostile==2 {b.ops[1].args=ref_span(b,[2]);}
        validator_expect(b,false,if hostile==1 {2003}else{2034});
    }}
    print("SEC-02 indexed dominance matches explicit CFG walks across diamonds, loops, disconnected blocks, collisions and exhausted retries; forged producers reject");
}
fn test_validator_evidence_index_work() {
    var reference:u64=0;
    for expanded in 2 {with_core(){b=>validator_cfg_index_fixture(b);
        if expanded!=0 {for i in 4096 {b.edges.push(Edge{from:5,to:4,kind:EDGE_NORMAL,..});}}
        with_validator_index(b){raw,indexed=>
            indexed.work.visits=0;indexed.work.proof_visits=0;
            assert(validator::evidence_available(indexed,1,2));
            if expanded==0 {reference=indexed.work.visits;}else{assert(indexed.work.visits==reference);}
            assert(validator::evidence_available(raw,1,2));
        };
        // An additional stored edge into the guarded target invalidates direct
        // edge authority even if no terminator lists that edge.
        b.edges.push(Edge{from:3,to:2,kind:EDGE_NORMAL,..});
        with_validator_index(b){raw,indexed=>assert(!validator::evidence_available(raw,1,2));assert(!validator::evidence_available(indexed,1,2));};
    }}
    print("CMP-04 edge-evidence authority work ignores unrelated edges while hostile unused predecessors still invalidate it");
}

fn validator_layout_owner_fixture(b:CoreBuilder) {
    validator_scalar_fixture(b);
    b.values.push(Value{type_id:1,block_id:1,op:1,version:2,scope:1,..});
    b.ops.push(Operation{tag:OP_COPY,registry:OP_COPY,args:ref_span(b,[1]),results:ref_span(b,[2]),scope:1,..});
    b.blocks[1].ops=ref_span(b,[1]);b.terminators[1].subject=2;
    b.scopes.push(Scope{kind:SCOPE_FUNCTION,..});
    b.values.push(Value{type_id:1,block_id:2,version:3,scope:2,..});
    b.values.push(Value{type_id:1,block_id:2,op:2,version:4,scope:2,..});
    b.ops.push(Operation{tag:OP_COPY,registry:OP_COPY,args:ref_span(b,[3]),results:ref_span(b,[4]),scope:2,..});
    b.terminators.push(Terminator{tag:TERM_RETURN,subject:4,..});
    b.blocks.push(Block{params:ref_span(b,[3]),ops:ref_span(b,[2]),term:2,scope:2,function:2,..});
    b.functions.push(Function{type_id:2,contract:1,param:3,entry:2,blocks:ref_span(b,[2]),..});
    // Layout-premise validation consumes the environment types, independently
    // of the other ABI/adapter fields checked by the full artifact validator.
    b.layouts.push(Layout{type_id:1,..});
    b.abi_plans.push(AbiPlan{function:1,env_layout:1,..});
    b.callable_adapters.push(CallableAdapter{op:1,environment_layout:1,..});
    b.binders.push(Binder{kind:KIND_TYPE,..});
    b.types.push(TypeNode{tag:TY_PARAM,binder:1,..});
    b.types.push(TypeNode{tag:TY_TUPLE,children:ref_span(b,[3]),..});
    b.layouts.push(Layout{type_id:4,..});
}
fn test_validator_layout_owner_indexes() {
    var reference:u64=0;
    for expanded in 2 {with_core(){b=>validator_layout_owner_fixture(b);
        if expanded!=0 {for i in 2048 {
            b.abi_plans.push(AbiPlan{function:2,env_layout:1,..});
            b.callable_adapters.push(CallableAdapter{op:2,environment_layout:1,..});
        }}
        with_validator_index(b){raw,indexed=>
            var colors:u32[>..]=[];var geometry:validator::Geometry[>..]=[];
            for ty in b.types {colors.push(0);geometry.push(validator::Geometry{..});}
            for ty,id in b.types {if id!=0 {assert(validator::type_node(raw,id as u32,colors,geometry,0));}}
            indexed.work.visits=0;assert(validator::validate_layout_premises(indexed,1,geometry));
            if expanded==0 {reference=indexed.work.visits;}else{assert(indexed.work.visits==reference);}
            raw.work.visits=0;assert(validator::validate_layout_premises(raw,1,geometry));assert(raw.work.visits>indexed.work.visits);
            let index=indexed.indexes;assert(index);
            assert(index.plan_heads[1]==1 && index.plan_next[1]==0 && index.adapter_heads[1]==1 && index.adapter_next[1]==0);
            if expanded!=0 {assert(index.plan_heads[2]==2 && index.plan_next[2]==3 && index.adapter_heads[2]==2 && index.adapter_next[2]==3);}
        };
    }}
    for adapter in 2 {with_core(){b=>validator_layout_owner_fixture(b);
        // The first row is valid. A later row for the SAME owner introduces an
        // aggregate environment whose required dependent premise is missing.
        if adapter==0 {b.abi_plans.push(AbiPlan{function:1,env_layout:2,..});}
        else {b.callable_adapters.push(CallableAdapter{op:1,environment_layout:2,..});}
        with_validator_index(b){raw,indexed=>
            var colors:u32[>..]=[];var geometry:validator::Geometry[>..]=[];
            for ty in b.types {colors.push(0);geometry.push(validator::Geometry{..});}
            for ty,id in b.types {if id!=0 {assert(validator::type_node(raw,id as u32,colors,geometry,0));}}
            assert(!validator::validate_layout_premises(raw,1,geometry));
            assert(raw.diags[raw.diags.len-1].code==2024 && raw.diags[raw.diags.len-1].related==4);
            assert(!validator::validate_layout_premises(indexed,1,geometry));
            assert(indexed.diags[indexed.diags.len-1].code==2024 && indexed.diags[indexed.diags.len-1].related==4);
        };
    }}
    print("CMP-04 layout requirement work ignores unrelated ABI plans/adapters; every duplicate-owner environment still supplies an independently checked obligation");
}

fn test_validator_immutable_attempt_isolation() {
    for fixture in 3 {with_core(){b=>
        if fixture==0 {validator_scalar_fixture(b);}else if fixture==1 {validator_affine_edges_fixture(b);}else{validator_quota_fixture(b,2,8);}
        let core=core_view(b);var before:u8[>..]=[];assert(artifact::artifact_encode(core,before));
        var first=Work{..};var first_diags:Diagnostic[>..]=[];
        assert(validator::validate_core(core,validator::FRESH,first,first_diags) && first_diags.len==0);
        // A failed attempt shares the immutable tables, but owns its exhausted
        // budget, diagnostics and all traversal/ownership scratch.
        var failed=Work{visits:validator::validation_input_limit(core),..};var failed_diags:Diagnostic[>..]=[];
        assert(!validator::validate_core(core,validator::FRESH,failed,failed_diags));
        assert(failed.exhausted && failed_diags.len==1 && failed_diags[0].code==2030);
        var next=Work{..};var next_diags:Diagnostic[>..]=[];
        assert(validator::validate_core(core_view(b),validator::FRESH,next,next_diags) && next_diags.len==0);
        assert(next.visits==first.visits && next.proof_visits==first.proof_visits && !next.exhausted);
        var after:u8[>..]=[];assert(artifact::artifact_encode(core,after));assert(before==after);
    }}
    print("CMP-04 repeated validation preserves immutable artifacts and exact private budgets across failed attempts");
}
