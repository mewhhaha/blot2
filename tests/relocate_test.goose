import src.frontend;
import src.relocate;
import tests.validator_test;
fn test_relocation() {
    let old_source="pub let dependency: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn value => return U32.wrapping_add(value,1)\npub let caller: U32 -> U32 ! {} resources {depth: 2, frame: 0} = fn value => return dependency(value)\n";
    let new_source="pub let dependency: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn value => return U32.wrapping_add(value,2)\n";
    with_core() { old =>
        var completion=Work{..}; var diags:Diagnostic[>..]=[];
        let completed=frontend_complete(old_source,"relocation",old,completion,diags); if !completed { print(diags); } assert(completed); assert(seal_completion(old));
        validator_expect(old,true,0);
        with_core() { target =>
            var target_work=Work{..}; assert(frontend_complete(new_source,"relocation",target,target_work,diags)); assert(seal_completion(target));
            let dep=target.functions[target.definitions[1].function]; let dc=target.contracts[dep.contract];
            let contract=target.contracts.len as u32; target.contracts.push(Contract {arg:dc.arg,result:dc.result,depth:2,frame:0,..});
            let ty=target.types.len as u32; target.types.push(TypeNode {tag:TY_FN,children:ref_span(target,[dc.arg,dc.result]),mode:MODE_MANY,contract:contract,..});
            let origin=target.origins.len as u32; target.origins.push(Origin {module:1,start:1000,end:2000});
            let definition=target.definitions.len as u32; target.definitions.push(Definition {kind:DEF_FUNCTION,name:add_name(target,"caller"),module:1,type_id:ty,visibility:VIS_PUBLIC,origin:origin,..});
            target.modules[1].declarations=ref_span(target,[1 as u32,definition]);
            let functions_before=target.functions.len; let values_before=target.values.len; let refs_before=target.refs.len; let bytes_before=target.bytes.len;
            var missing_work=Work{..}; assert(!relocation::relocate_function(core_view(old),2,target,definition,[],missing_work));
            assert(target.functions.len==functions_before && target.values.len==values_before && target.refs.len==refs_before && target.bytes.len==bytes_before);
            var exhausted=Work{visits:LIMIT_VISITS,..}; assert(!relocation::relocate_function(core_view(old),2,target,definition,[relocation::Projection {1,1}],exhausted)); assert(exhausted.exhausted);
            assert(target.functions.len==functions_before && target.values.len==values_before && target.refs.len==refs_before && target.bytes.len==bytes_before);
            target.contracts[dep.contract].depth=2;
            var stale_work=Work{..}; assert(!relocation::relocate_function(core_view(old),2,target,definition,[relocation::Projection {1,1}],stale_work));
            target.contracts[dep.contract].depth=1;
            assert(target.functions.len==functions_before && target.values.len==values_before && target.refs.len==refs_before && target.bytes.len==bytes_before);
            var reuse_work=Work{..};
            assert(relocation::relocate_function(core_view(old),2,target,definition,[relocation::Projection {1,1}],reuse_work));
            validator_expect(target,true,0);
            let function=target.functions[target.definitions[definition].function];
            let block_id=target.refs[function.blocks.start]; var call:u32=0;
            for i in target.blocks[block_id].ops.count { let operation=target.ops[target.refs[target.blocks[block_id].ops.start+i]]; if operation.tag==OP_CALL { call=operation.imm0; } }
            assert(call==target.definitions[1].function);
            assert(target.functions.len==3); // Current dependency plus one retained caller.
            var twos:u32=0; var ones:u32=0;
            for operation in target.ops { if operation.tag==OP_U32 && operation.imm0==2 { twos++; } if operation.tag==OP_U32 && operation.imm0==1 { ones++; } }
            assert(twos==1 && ones==0);
        };
    };
    print("CACHE-02 relocated caller uses current dependency body and retains no historical callee implementation");
}

fn test_relocation_proofs() {
    let source="pub let count: Unit -> U32 ! {} ensures [Eq(result,10)] resources {depth: 1, frame: 256} = fn () => do:\n  let answer = for i in 0..10 carry (n = 0) invariant [Eq(n,i)] do:\n    next (n+1)\n  return answer\n";
    with_core() { old =>
        var work=Work{..}; var diags:Diagnostic[>..]=[];
        assert(frontend_complete(source,"loop-relocate",old,work,diags)); assert(seal_completion(old));
        with_core() { target =>
            // Build an independently owned equivalent interface before replay.
            var tw=Work{..};
            assert(frontend_complete(source,"loop-relocate",target,tw,diags)); assert(seal_completion(target));
            let original_function=target.definitions[1].function; target.definitions[1].function=0;
            var rw=Work{..}; assert(relocation::relocate_function(core_view(old),1,target,1,[],rw));
            assert(target.definitions[1].function != original_function);
            validator_expect(target,true,0);
            assert(target.loops.len==3);
        };
    };
    print("CACHE-02 relocated finite loop retains independent entry/induction/exhaustion evidence");
}
