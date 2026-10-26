import frontend;
import scalar_core;
import artifact;
import artifact_v2;

fn core_for(source: u8[:]) -> scalar_core::ScalarCore {
    let p = frontend::parse_scalar(source);
    assert(p.status == 0);
    var c = scalar_core::build(p.result_type, p.binary_op, p.kind, p.literal, p.right_kind, p.right_literal);
    c.name_start = p.name_start; c.name_end = p.name_end;
    c.parameter_start = p.parameter_start; c.parameter_end = p.parameter_end;
    c.left_start = p.start; c.left_end = p.end;
    c.operator_start = p.operator_start; c.operator_end = p.operator_end;
    c.right_start = p.right_start; c.right_end = p.right_end;
    return c;
}

fn main() {
    let tiny: u8[] = [1, 2, 3];
    assert(artifact_v2::get32(tiny, -1) == 0);
    assert(artifact_v2::get32(tiny, 0) == 0);
    assert(artifact_v2::get32(tiny, 999) == 0);
    let source = "let flags: U32 -> U32 = fn x => return 3 & 5\n";
    let core = core_for(source);
    let a = artifact_v2::encode(source, core);
    let b = artifact_v2::encode(source, core);
    assert(a.len > 0 && a == b);
    let d = artifact_v2::decode(a);
    assert(d.status == 0 && a[d.source_start..d.source_end] == source);
    assert(d.core.result_type == 1 && d.core.value_count == 4 &&
           d.core.values[1].literal == 3 && d.core.values[2].literal == 5 &&
           d.core.values[3].op_id == 1);
    for n in a.len { assert(artifact_v2::decode(a[0..n]).status != 0); }
    for n in artifact_v2::header().len {
        var changed: u8[>..] = [];
        changed.append(a); changed[n] ^= 1;
        assert(artifact_v2::decode(changed).status != 0);
    }
    var bad_policy: u8[>..] = [];
    bad_policy.append(a); bad_policy[9] ^= 1;
    assert(artifact_v2::decode(bad_policy).status == 2);
    // Every serialized word is bounded or independently matched to source.
    let h = artifact_v2::header().len;
    for field in 39 {
        var changed: u8[>..] = [];
        changed.append(a);
        for i in 4 { changed[h + field * 4 + i] = 255; }
        assert(artifact_v2::decode(changed).status != 0);
    }
    var changed_source: u8[>..] = [];
    changed_source.append(a);
    changed_source[d.source_start + core.left_start] = '4';
    assert(artifact_v2::decode(changed_source).status != 0);
    var extra: u8[>..] = [];
    extra.append(a); extra.push(0);
    assert(artifact_v2::decode(extra).status != 0);
    var forged = core;
    forged.values[3].op_id = 2;
    assert(artifact_v2::encode(source, forged).len == 0);
    forged = core; forged.name_end = 99999;
    assert(artifact_v2::encode(source, forged).len == 0);

    let bool_source = "let test: U32 -> Bool = fn x => return do:\n  break x < 4294967295\n";
    let bool_core = core_for(bool_source);
    let encoded_bool = artifact_v2::encode(bool_source, bool_core);
    let decoded_bool = artifact_v2::decode(encoded_bool);
    assert(decoded_bool.status == 0 && decoded_bool.core.result_type == 2 &&
           decoded_bool.core.values[2].op_id == 2 && decoded_bool.core.values[1].literal == 4294967295);

    // SC01 and SC02 never decode as each other even for a shared unary case.
    let unary = "let id: U32 -> U32 = fn x => return x";
    let p = frontend::parse_scalar(unary);
    let sc01 = artifact::encode(unary, p.start, p.end, p.name_start, p.name_end, p.kind, p.literal);
    let sc02 = artifact_v2::encode(unary, core_for(unary));
    assert(artifact_v2::decode(sc01).status != 0 && artifact::decode(sc02).status != 0);

    // Check inclusive total-record boundary, then one byte beyond it.
    var large: u8[>..] = [];
    large.append(unary); large.append(" //");
    let max_source = 16777216 - h - 156;
    while large.len < max_source { large.push(' '); }
    let large_core = core_for(large);
    let max_record = artifact_v2::encode(large, large_core);
    assert(max_record.len == 16777216 && artifact_v2::decode(max_record).status == 0);
    large.push(' ');
    assert(artifact_v2::encode(large, large_core).len == 0);
    var oversized: u8[>..] = [];
    oversized.append(max_record); oversized.push(0);
    assert(artifact_v2::decode(oversized).status != 0);
    print("SC02 scalar artifact: passed");
}
