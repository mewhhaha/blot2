import tests.frontend_lifecycle_test;
import src.artifact;
import tests.validator_test;

fn scratch_module(b: CoreBuilder, name: const u8[:], source: const u8[:], imports: const u32[:]) -> u32 {
    let label = add_name(b, name); let bytes = Span { start: b.bytes.len as u32, count: source.len as u32 }; b.bytes.append(source);
    let id = b.modules.len as u32; b.modules.push(Module { name: label, path: label, imports: ref_span(b, imports), source: bytes, .. }); return id;
}
fn scratch_modules(shared: bool, encoded: u8[>..]&, counts: u64[>..]&) {
    with_core() { b =>
        let first = scratch_module(b, "first", "pub type Pair[T:Type] = (T,T)\npub let identity: forall [T:Type] where [Share(T)] => T -> T ! {} resources {depth:1,frame:256} = fn x => return x\npub let bump: U32 -> U32 ! {} resources {depth:1,frame:0} = fn x => return U32.wrapping_add(x,1)\n", []);
        let second = scratch_module(b, "second", "import \"./first.blot\" as a\npub type Pair[T:Type] = (T,T)\npub let bump: U32 -> U32 ! {} resources {depth:2,frame:0} = fn x => return a.bump(x)\n", [first]);
        let third = scratch_module(b, "third", "import \"./first.blot\" as a\nimport \"./second.blot\" as z\npub let run: U32 -> U32 ! {} resources {depth:3,frame:512} = fn x => return z.bump(a.identity@[U32](x))\n", [first, second]);
        var diags: Diagnostic[>..] = [];
        with_frontend_scratch() { scratch =>
            for module_id in [first, second, third] {
                let m = b.modules[module_id]; let source = b.bytes[m.source.start..m.source.start + m.source.count]; var work = Work { .. };
                let ok = if shared { frontend_complete_in(source, name_bytes(core_view(b), m.path), b, work, diags, scratch) } else { frontend_complete(source, name_bytes(core_view(b), m.path), b, work, diags) };
                if !ok { print(diags); } assert(ok);
                counts.append([work.visits, work.proof_visits, work.interface_instantiations, b.types.len as u64, b.terms.len as u64, b.facts.len as u64]);
            }
        };
        let planned = build_plans(b, "", diags); if !planned { print("scratch planning ", diags); } assert(planned); assert(canonical_schemas(b, diags)); assert(fingerprint_interfaces(b, diags)); assert(seal_completion(b)); validator_expect(b, true, 0);
        assert(artifact::artifact_encode(core_view(b), encoded));
    };
}
fn test_frontend_module_scratch_parity() {
    var fresh: u8[>..] = []; var shared: u8[>..] = []; var fresh_counts: u64[>..] = []; var shared_counts: u64[>..] = [];
    scratch_modules(false, fresh, fresh_counts); scratch_modules(true, shared, shared_counts);
    assert(fresh == shared && fresh_counts == shared_counts);
    print("FRONT module scratch preserves exact artifacts, declaration work, imported producers and generic binder identity");
}
fn test_frontend_module_scratch_suffix_and_failure() {
    with_frontend_scratch() { scratch =>
        with_core() { b =>
            var work = Work { .. }; var diags: Diagnostic[>..] = [];
            assert(frontend_complete_in("pub let first: U32 -> U32 ! {} resources {depth:1,frame:0} = fn x => return x\n", "first", b, work, diags, scratch));
            // Replay may append finalized duplicates without using this index.
            // The next module must select the latest row, just as full seeding.
            let duplicate = b.types.len as u32; b.types.push(TypeNode { tag: TY_U32, .. });
            let term = b.terms.len as u32; b.terms.push(Term { tag: EXPR_LITERAL, type_id: duplicate, literal: 17, .. });
            let fact = b.facts.len as u32; b.facts.push(Fact { tag: FACT_EQ, left: term, right: term, .. });
            frontend_seed(b, scratch);
            assert(key_index_get(scratch.types, front_type_key(core_view(b), b.types[duplicate], scratch.lists)) == duplicate);
            assert(key_index_get(scratch.terms, proof_key(b, b.terms[term])) == term && key_index_get(scratch.facts, b.facts[fact]) == fact);
            var failed = Work { .. };
            assert(!frontend_complete_in("let bad: U32 -> U32 = fn x => return x+1\n", "failed", b, failed, diags, scratch));
            assert(scratch.loaded.types == 0 && scratch.loaded.terms == 0 && scratch.loaded.facts == 0);
            assert(scratch.types.slots.len == 0 && scratch.terms.slots.len == 0 && scratch.facts.slots.len == 0);
        };
        with_core() { next =>
            var work = Work { .. }; var diags: Diagnostic[>..] = [];
            assert(frontend_complete_in("pub let first: Bool -> Bool ! {} resources {depth:1,frame:0} = fn x => return x\n", "first", next, work, diags, scratch));
            assert(seal_completion(next)); validator_expect(next, true, 0);
            assert(next.types[next.contracts[next.functions[next.definitions[1].function].contract].arg].tag == TY_BOOL);
        };
    };
    print("FRONT module scratch reloads finalized suffixes and discards failed candidate indexes");
}
