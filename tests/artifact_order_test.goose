import tests.frontend_lifecycle_test;
import tests.validator_test;
fn artifact_order_law(path: const u8[:]) {
    var source: u8[>..] = []; assert(read_file(path, source)); var bytes: u8[>..] = [];
    with_core() { b =>
        var work = Work { .. }; var diags: Diagnostic[>..] = [];
        assert(frontend_complete(source, path, b, work, diags)); assert(build_plans(b, "", diags)); assert(canonical_schemas(b, diags)); assert(seal_completion(b)); validator_expect(b, true, 0);
        assert(artifact::artifact_encode(core_view(b), bytes));
    };
    with_core() { decoded =>
        var diags: Diagnostic[>..] = []; assert(artifact::artifact_decode(bytes, decoded, diags)); validator_expect(decoded, true, 0);
        var again: u8[>..] = []; assert(artifact::artifact_encode(core_view(decoded), again)); if bytes != again { print("non-idempotent canonical artifact ", path, " bytes ", bytes.len, " vs ", again.len); } assert(bytes == again);
        // Arena Name IDs carry no producer identity; all references are rebound.
        let count = decoded.names.len as u32;
        for i in 1..count { let other = count - i; if i < other { let old = decoded.names[i]; decoded.names[i] = decoded.names[other]; decoded.names[other] = old; } }
        fn renamed(id: u32) -> u32 { if id == 0 { return 0; } return count - id; }
        for row, i in decoded.modules { if i != 0 { decoded.modules[i].name = renamed(row.name); decoded.modules[i].path = renamed(row.path); } }
        for row, i in decoded.definitions { if i != 0 { decoded.definitions[i].name = renamed(row.name); } }
        for row, i in decoded.binders { if i != 0 { decoded.binders[i].name = renamed(row.name); } }
        for row, i in decoded.functions { if i != 0 { decoded.functions[i].name = renamed(row.name); } }
        for row, i in decoded.fields { if i != 0 { decoded.fields[i].name = renamed(row.name); } }
        for row, i in decoded.exports { if i != 0 { decoded.exports[i].name = renamed(row.name); } }
        validator_expect(decoded, true, 0); var renamed_bytes: u8[>..] = []; assert(artifact::artifact_encode(core_view(decoded), renamed_bytes)); assert(bytes == renamed_bytes);
        // Proof rows are an explicit graph; their arena allocation order is not
        // an identity. Rebind every owner span after reversing the table.
        let proofs = decoded.evidence.len as u32;
        fn proof_span(old: Span) -> Span { var ids: u32[>..] = []; for i in old.count { let id = decoded.refs[old.start + i]; ids.push(if id == 0 { 0 } else { proofs - id }); } return ref_span(decoded, ids); }
        for row, i in decoded.evidence { if i != 0 { decoded.evidence[i].premises = proof_span(row.premises); } }
        for row, i in decoded.blocks { if i != 0 { decoded.blocks[i].evidence_params = proof_span(row.evidence_params); } }
        for row, i in decoded.ops { if i != 0 { decoded.ops[i].evidence = proof_span(row.evidence); } }
        for row, i in decoded.edges { if i != 0 { decoded.edges[i].evidence = proof_span(row.evidence); } }
        for row, i in decoded.terminators { if i != 0 { decoded.terminators[i].evidence = proof_span(row.evidence); } }
        for row, i in decoded.loops { if i != 0 { decoded.loops[i].invariant = proof_span(row.invariant); } }
        for i in 1..proofs { let other = proofs - i; if i < other { let old = decoded.evidence[i]; decoded.evidence[i] = decoded.evidence[other]; decoded.evidence[other] = old; } }
        for row, i in decoded.functions { if i != 0 { var blocks: u32[>..] = []; for j in row.blocks.count { blocks.push(decoded.refs[row.blocks.start + row.blocks.count - 1 - j]); } decoded.functions[i].blocks = ref_span(decoded, blocks); } }
        validator_expect(decoded, true, 0); var reordered: u8[>..] = []; assert(artifact::artifact_encode(core_view(decoded), reordered)); assert(bytes == reordered);
    };
}
fn test_artifact_canonical_order() {
    for path in ["examples/counted_loop.blot", "examples/particles.blot", "examples/generic_result.blot", "examples/static_closure.blot", "tests/runtime_static_generic.blot", "tests/runtime_static_nested.blot"] { artifact_order_law(path); }
    print("CACHE-01 canonical owned graph survives producer death, DAG relocation, repeated encoding and Name/proof/owner-block arena renumbering");
}

fn static_projection_object(c: Core) -> u32 {
    for definition, id in c.definitions {
        if id != 0 && definition.kind == DEF_STATIC && name_bytes(c, definition.name) == "a" {
            let value = c.values[definition.value]; assert(value.op != 0 && c.ops[value.op].tag == OP_STATIC); return c.ops[value.op].imm0;
        }
    }
    assert(false); return 0;
}
fn test_artifact_static_pattern_fingerprint() {
    let source = "static let (z,a): (U32, Fn[static,Many,U32,U32] ! {} resources {depth:1,frame:64}) = do:\n  let seed = 2\n  break (0,fn (value:U32) => return U32.wrapping_add(value,seed))\npub let run: U32 -> U32 ! {} resources {depth:2,frame:1024} = fn value => return a(value)\n";
    var encoded: u8[>..] = []; var original: u8[>..] = []; var old_owner: u32 = 0;
    with_core() { b =>
        var work = Work { .. }; var diagnostics: Diagnostic[>..] = [];
        let completed = frontend_complete(source, "static-pattern-transport", b, work, diagnostics); if !completed { for d in diagnostics { print(d, " ", name_bytes(core_view(b), d.detail)); } } assert(completed);
        assert(build_plans(b, "", diagnostics)); assert(canonical_schemas(b, diagnostics)); assert(fingerprint_interfaces(b, diagnostics)); assert(seal_completion(b)); validator_expect(b, true, 0);
        old_owner = b.refs[b.modules[1].declarations.start]; assert(starts_with(name_bytes(core_view(b), b.definitions[old_owner].name), "<pattern:"));
        var captured = false; for function in b.functions { if function.captures.count != 0 { captured = true; } } assert(captured);
        assert(canonical_static(core_view(b), static_projection_object(core_view(b)), original)); assert(artifact::artifact_encode(core_view(b), encoded));
    };
    with_core() { decoded =>
        var diagnostics: Diagnostic[>..] = []; assert(artifact::artifact_decode(encoded, decoded, diagnostics)); validator_expect(decoded, true, 0);
        let owner = decoded.refs[decoded.modules[1].declarations.start]; assert(owner != old_owner); assert(starts_with(name_bytes(core_view(decoded), decoded.definitions[owner].name), "<pattern:"));
        // The first containing arena row is now a projected name, while the
        // preserved declaration order still identifies the synthetic producer.
        let span = decoded.origins[decoded.definitions[owner].origin]; var first: u32 = 0;
        for definition, id in decoded.definitions { if id != 0 { let origin = decoded.origins[definition.origin]; if origin.module == span.module && origin.start == span.start && origin.end == span.end { first = id as u32; break; } } } assert(first != owner);
        var transported: u8[>..] = []; assert(canonical_static(core_view(decoded), static_projection_object(core_view(decoded)), transported)); assert(original == transported); assert(k1hash::equal(k1hash::blake3(original), k1hash::blake3(transported)));
        assert(fingerprint_interfaces(decoded, diagnostics)); validator_expect(decoded, true, 0);
    };
    with_core() { shifted =>
        var work = Work { .. }; var diagnostics: Diagnostic[>..] = [];
        assert(frontend_complete(str("// origins moved without changing the declaration\n\n", source), "static-pattern-transport", shifted, work, diagnostics));
        assert(build_plans(shifted, "", diagnostics)); assert(canonical_schemas(shifted, diagnostics)); assert(fingerprint_interfaces(shifted, diagnostics)); assert(seal_completion(shifted)); validator_expect(shifted, true, 0);
        var relocated: u8[>..] = []; assert(canonical_static(core_view(shifted), static_projection_object(core_view(shifted)), relocated)); assert(original == relocated);
    };
    print("CACHE-01 static destructured captured closure fingerprints survive reordered producer tables and moved origins");
}
