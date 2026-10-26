import src.canonical;
fn test_canonical_interface_identity() {
    with_core() { b =>
        b.types.push(TypeNode { tag: TY_U32, .. }); b.types.push(TypeNode { tag: TY_BOOL, .. });
        b.types.push(TypeNode { tag: TY_TUPLE, children: ref_span(b, [1 as u32, 2 as u32]), .. });
        b.types.push(TypeNode { tag: TY_BOOL, origin: 42, .. }); b.types.push(TypeNode { tag: TY_U32, origin: 99, .. });
        b.types.push(TypeNode { tag: TY_ALIAS, children: ref_span(b, [5 as u32]), .. });
        b.types.push(TypeNode { tag: TY_TUPLE, children: ref_span(b, [6 as u32, 4 as u32]), origin: 11, .. });
        b.types.push(TypeNode { tag: TY_TUPLE, children: ref_span(b, [2 as u32, 1 as u32]), .. });
        var a: u8[>..] = []; var same: u8[>..] = []; var different: u8[>..] = [];
        assert(canonical_interface(core_view(b), 3, a)); assert(canonical_interface(core_view(b), 7, same)); assert(canonical_interface(core_view(b), 8, different)); assert(a == same && a != different);
        b.binders.push(Binder { kind: KIND_DOMAIN, .. }); b.binders.push(Binder { kind: KIND_DOMAIN, .. });
        b.terms.push(Term { tag: EXPR_VALUE, type_id: 1, value: 71, .. }); b.terms.push(Term { tag: EXPR_VALUE, type_id: 5, value: 102, .. });
        b.types.push(TypeNode { tag: TY_VIEW, children: ref_span(b, [1 as u32]), nat: 1, domain: 1, .. });
        b.types.push(TypeNode { tag: TY_VIEW, children: ref_span(b, [5 as u32]), nat: 2, domain: 2, .. });
        var view_a: u8[>..] = []; var view_b: u8[>..] = [];
        assert(canonical_interface(core_view(b), 9, view_a)); assert(canonical_interface(core_view(b), 10, view_b)); assert(view_a == view_b);
        b.types.push(TypeNode { tag: TY_TUPLE, children: ref_span(b, [9 as u32, 9 as u32]), .. });
        b.types.push(TypeNode { tag: TY_TUPLE, children: ref_span(b, [9 as u32, 10 as u32]), .. });
        var shared: u8[>..] = []; var distinct: u8[>..] = [];
        assert(canonical_interface(core_view(b), 11, shared)); assert(canonical_interface(core_view(b), 12, distinct)); assert(shared != distinct);
    };
    print("KEY canonical interfaces ignore allocation/origin/transparent aliases and preserve field order and binder equality");
}
