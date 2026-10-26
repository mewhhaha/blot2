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
        for over in 2 {var work=Work{..};var diagnostics:Diagnostic[>..]=[];let limit:u64=34-over as u64;let context=validator::Context{core_view(b),validator::FRESH,work,diagnostics,limit,LIMIT_PROOF_VISITS};
            let same=validator::nat_match(context,1,2,substitutions);assert(same==(over==0));assert(work.visits==limit);assert(work.exhausted==(over==1));if over==1 {assert(diagnostics.len==1 && diagnostics[0].code==2030);}
        }
        for over in 2 {var work=Work{..};var diagnostics:Diagnostic[>..]=[];let context=validator::proof_context(validator::Context{core_view(b),validator::FRESH,work,diagnostics,128,34-over as u64});
            assert(validator::nat_match(context,1,2,substitutions)==(over==0));assert(work.proof_visits==34-over as u64);if over==1 {assert(work.exhausted && diagnostics.len==1 && diagnostics[0].code==2032);}else{assert(work.visits==work.proof_visits);}
        }
        for i in 31 {b.types.push(TypeNode{tag:TY_ALIAS,children:ref_span(b,[b.types.len as u32-1]),..});}
        for over in 2 {if over==1 {b.types.push(TypeNode{tag:TY_ALIAS,children:ref_span(b,[b.types.len as u32-1]),..});}var work=Work{..};var diagnostics:Diagnostic[>..]=[];let context=validator::Context{core_view(b),validator::FRESH,work,diagnostics,33,LIMIT_PROOF_VISITS};
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
        var work=Work{..};var diagnostics:Diagnostic[>..]=[];var counts=validator::InventoryCounts{..};let context=validator::Context{core_view(b),validator::FRESH,work,diagnostics};
        let accepted=validator::declaration_inventory(context,0,1,counts,validator::InventoryMarks{tm,terms,facts,proofs,contracts},0,[0],root);
        assert(accepted==(over==0));assert(counts.types==LIMIT_TYPES+over);if over==1 {assert(work.exhausted && diagnostics.len!=0 && diagnostics[diagnostics.len-1].code==2031);}
    }}
    print("CMP-04 type-only artifact definitions enforce the exact frozen graph limit without requiring a Function row");
}
