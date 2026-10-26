import src.model;
import src.validate;
import std;
fn test_layout_scratch_epochs() {
    with_core() { b =>
        b.types.push(TypeNode {tag:TY_U32,..}); b.types.push(TypeNode {tag:TY_UNIT,..});
        b.types.push(TypeNode {tag:TY_TUPLE,children:ref_span(b,[1 as u32,2 as u32]),..});
        // Aliases share children. Every root must still see its full work and
        // depth checks after scratch from a previous root has been populated.
        for i in 48 { b.types.push(TypeNode {tag:TY_ALIAS,children:ref_span(b,[b.types.len as u32-1]),..}); }
        var colors:u32[>..]=[]; var geometry:validator::Geometry[>..]=[];
        for t in b.types { colors.push(0); geometry.push(validator::Geometry {..}); }
        var diags:Diagnostic[>..]=[];
        for i in 1..b.types.len {
            var fresh=Work{..}; var reused=Work{..};
            let a,aok=validator::derive_layout(core_view(b),i as u32,fresh,diags);
            let z,zok=validator::derive_layout_scratch(core_view(b),i as u32,reused,diags,colors,geometry,i as u32*2+1);
            assert(aok && zok && a==z && fresh.visits==reused.visits && fresh.proof_visits==reused.proof_visits);
        }
        assert(validator::append_layouts(b,1,false,diags));
        for row,i in b.layouts { if i!=0 { var work=Work{..}; let expected,ok=validator::derive_layout(core_view(b),i as u32,work,diags); assert(ok && row==expected); } }
        // The same workspace must not hide a root's exhausted account.
        var limited=Work{visits:LIMIT_VISITS-1,..};
        let ignored,ok=validator::derive_layout_scratch(core_view(b),3,limited,diags,colors,geometry,1001);
        assert(!ok && limited.exhausted && diags[diags.len-1].code==2030);
        // A malformed cycle is detected after the formerly valid geometry was
        // computed. Scratch epochs never authorize a stale successful result.
        b.types[3].children=ref_span(b,[3 as u32]); var cyclic=Work{..};
        let ignored_cycle,cycle_ok=validator::derive_layout_scratch(core_view(b),3,cyclic,diags,colors,geometry,1003);
        assert(!cycle_ok && diags[diags.len-1].code==2024);
    };
    print("LAYOUT scratch epochs preserve per-root geometry, visit budget and cycle rejection");
}
