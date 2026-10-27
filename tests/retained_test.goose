import src.retained;
import src.plan;
import src.fingerprint;
import tests.validator_test;
fn test_retained_body_cutoff() {
    let source = "pub let dependency: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn value => return U32.wrapping_add(value,1)\npub let caller: U32 -> U32 ! {} resources {depth: 2, frame: 0} = fn value => return dependency(value)\n";
    let changed = "pub let dependency: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn value => return U32.wrapping_add(value,2)\npub let caller: U32 -> U32 ! {} resources {depth: 2, frame: 0} = fn value => return dependency(value)\n";
    with_core() { prior =>
        var diags: Diagnostic[>..] = []; var work = Work { .. };
        assert(frontend_complete(source, "retained", prior, work, diags));
        assert(build_plans(prior, "", diags)); assert(canonical_schemas(prior, diags)); assert(fingerprint_interfaces(prior, diags)); assert(seal_completion(prior)); validator_expect(prior, true, 0);
        with_core() { next =>
            var next_work = Work { .. }; var stats = ReuseStats { .. };
            let ok = complete_retained_module(core_view(prior), changed, "retained", next, next_work, stats, diags); if !ok { print(diags); } assert(ok);
            assert(stats.hits == 1 && next.phase.completed == 1);
            assert(build_plans(next, "", diags)); assert(canonical_schemas(next, diags)); assert(fingerprint_interfaces(next, diags)); assert(seal_completion(next)); validator_expect(next, true, 0);
            var eval_stats = StaticStats { .. }; let value, evaluated = static_evaluate(core_view(next), next.definitions[2].function, static_scalar(40), eval_stats, diags); assert(evaluated && value.words[0] == 42);
        };
    };
    print("CACHE body-only dependency edit preserves caller judgment and executes current callee");
}

fn test_retained_digest_collision() {
    let before = "pub let dependency: U32 -> U32 ! {} resources {depth:1,frame:0} = fn value => return U32.wrapping_add(value,1)\npub let caller: U32 -> U32 ! {} resources {depth:3,frame:0} = fn value => return dependency(value)\n";
    let after = "pub let dependency: U32 -> U32 ! {} resources {depth:2,frame:0} = fn value => return U32.wrapping_add(value,2)\npub let caller: U32 -> U32 ! {} resources {depth:3,frame:0} = fn value => return dependency(value)\n";
    with_core() { old => with_core() { current =>
        var diagnostics: Diagnostic[>..] = []; var ow = Work { .. }; var cw = Work { .. };
        assert(frontend_complete(before, "collision", old, ow, diagnostics)); assert(frontend_complete(after, "collision", current, cw, diagnostics));
        // All candidate digests collide. Exact completed contracts still differ.
        fn collide(builder: CoreBuilder) {
            let digest = Span {builder.bytes.len as u32,32}; for i in 32 { builder.bytes.push(0x5a); }
            for i in builder.interfaces.len { if i != 0 { builder.interfaces[i].digest = digest; } }
            for i in builder.dependencies.len { if i != 0 { builder.dependencies[i].digest = digest; } }
        }
        collide(old); collide(current);
        assert(old.interfaces[1].digest.count == 32 && current.interfaces[1].digest.count == 32);
        assert(old.bytes[old.interfaces[1].digest.start..old.interfaces[1].digest.start+32] == current.bytes[current.interfaces[1].digest.start..current.interfaces[1].digest.start+32]);
        current.definitions[2].function = 0;
        let functions = current.functions.len; let values = current.values.len; let refs = current.refs.len; let bytes = current.bytes.len;
        var rejected = Work { .. };
        assert(!relocation::relocate_function(core_view(old),2,current,2,[relocation::Projection {1,1}],rejected));
        assert(current.functions.len == functions && current.values.len == values && current.refs.len == refs && current.bytes.len == bytes);
        // Restore only the exact contract. The new implementation stays selected.
        current.contracts[current.functions[current.definitions[1].function].contract].depth = 1;
        var accepted = Work { .. }; assert(relocation::relocate_function(core_view(old),2,current,2,[relocation::Projection {1,1}],accepted));
        assert(build_plans(current,"",diagnostics)); assert(canonical_schemas(current,diagnostics)); assert(fingerprint_interfaces(current,diagnostics)); assert(seal_completion(current)); validator_expect(current,true,0);
        var evaluated = StaticStats { .. }; let result, ok = static_evaluate(core_view(current),current.definitions[2].function,static_scalar(40),evaluated,diagnostics);
        assert(ok && result.words[0] == 42);
    }; };
    print("CMP-03 colliding candidate digests never replace exact interface comparison or current dependency binding");
}

fn test_retained_optional_corruption() {
    let source = "pub let run: U32 -> U32 ! {} resources {depth:1,frame:0} = fn value => return U32.wrapping_add(value,2)\n";
    var valid: u8[>..] = []; var semantic_corruption: u8[>..] = [];
    with_core() { producer =>
        var work = Work { .. }; var diagnostics: Diagnostic[>..] = [];
        assert(frontend_complete(source,"optional",producer,work,diagnostics)); assert(build_plans(producer,"",diagnostics)); assert(canonical_schemas(producer,diagnostics)); assert(fingerprint_interfaces(producer,diagnostics)); assert(seal_completion(producer)); validator_expect(producer,true,0);
        assert(artifact::artifact_encode(core_view(producer),valid));
        producer.values[1].type_id = 0xffffffff;
        // A matching digest proves byte integrity, not semantic validity.
        assert(artifact::encode_tables(core_view(producer),semantic_corruption));
    };
    for variant in 3 {
        var candidate: u8[>..] = []; candidate.append(if variant == 2 { semantic_corruption[..] } else { valid[..] });
        if variant == 1 { candidate[0] ^= 1; }
        var stats = ReuseStats { .. }; var calls: u32 = 0;
        with_retained_revision(candidate,RETAINED_CURRENT_PROCESS,stats) { prior =>
            calls++; assert((prior.receipts.len > 1) == (variant == 0));
            with_core() { fresh =>
                var work = Work { .. }; var diagnostics: Diagnostic[>..] = [];
                assert(complete_retained_module(prior,source,"optional",fresh,work,stats,diagnostics));
                assert(build_plans(fresh,"",diagnostics)); assert(canonical_schemas(fresh,diagnostics)); assert(fingerprint_interfaces(fresh,diagnostics)); assert(seal_completion(fresh)); validator_expect(fresh,true,0);
                assert(fresh.phase.completed == (if variant == 0 {0} else {1}));
                var evaluated = StaticStats { .. }; let result, ok = static_evaluate(core_view(fresh),fresh.definitions[1].function,static_scalar(40),evaluated,diagnostics); assert(ok && result.words[0] == 42);
            };
        };
        assert(calls == 1 && stats.hits == (if variant == 0 {1} else {0})); assert(stats.declines == (if variant == 0 {0} else {1}));
        assert((stats.admission_visits != 0) == (variant != 1));
    }
    print("ART-A01 malformed optional bytes and checksum-valid invalid Core decline to fresh equivalent completion");
}

fn test_retained_external_receipt() {
    let admitted = "let f: Unit -> Unit = fn () => do:\n  return ()\n";
    var excessive: u8[>..] = []; excessive.append("let f: Unit -> Unit = fn () => do:\n");
    for i in LIMIT_OPS - 1 { excessive.append("  ()\n"); } excessive.append("  return ()\n");
    var forged: u8[>..] = [];
    with_core() { producer =>
        var work = Work { .. }; var diagnostics: Diagnostic[>..] = []; assert(frontend_complete(admitted,"receipt",producer,work,diagnostics));
        assert(build_plans(producer,"",diagnostics)); assert(canonical_schemas(producer,diagnostics)); assert(fingerprint_interfaces(producer,diagnostics)); assert(seal_completion(producer));
        let bytes = Span {producer.bytes.len as u32,excessive.len as u32}; producer.bytes.append(excessive); producer.modules[1].source = bytes;
        producer.origins[producer.definitions[1].origin].end = excessive.len as u32 - 1;
        for i in producer.receipts.len { if i != 0 { producer.receipts[i].completed_visits = 1; } }
        assert(artifact::artifact_encode(core_view(producer),forged));
    };
    // The embedded source text/cheap receipt may be structurally valid while
    // lying about fresh source work. Decode can never confer source provenance.
    with_core() { decoded => var diagnostics: Diagnostic[>..] = []; assert(artifact::artifact_decode(forged,decoded,diagnostics)); validator_expect(decoded,true,0); assert(decoded.receipts[1].completed_visits == 1); };
    var cold_code: u32 = 0;
    with_core() { cold => var work = Work { .. }; var diagnostics: Diagnostic[>..] = []; assert(!frontend_complete(excessive,"receipt",cold,work,diagnostics)); cold_code = diagnostics[diagnostics.len-1].code; assert(cold_code == FE_CORE_LIMIT); };
    var stats = ReuseStats { .. }; var calls: u32 = 0;
    with_retained_revision(forged,RETAINED_EXTERNAL,stats) { prior =>
        calls++; assert(prior.receipts.len == 0 && prior.functions.len == 0);
        with_core() { fresh => var work = Work { .. }; var diagnostics: Diagnostic[>..] = []; assert(!complete_retained_module(prior,excessive,"receipt",fresh,work,stats,diagnostics)); assert(diagnostics[diagnostics.len-1].code == cold_code); };
    };
    assert(calls == 1 && stats.declines == 1 && stats.hits == 0 && stats.admission_visits == 0);
    print("SEC-04 a structurally valid cheap external receipt cannot bypass one-over-limit fresh source admission");
}
import src.evaluate;
