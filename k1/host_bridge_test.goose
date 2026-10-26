import host_bridge;

fn put32(bytes: u8[>..]&, position: i64, value: u32) {
    bytes[position] = (value & 255) as u8;
    bytes[position + 1] = ((value >> 8) & 255) as u8;
    bytes[position + 2] = ((value >> 16) & 255) as u8;
    bytes[position + 3] = ((value >> 24) & 255) as u8;
}
fn main() {
    let manifest = host_bridge::Manifest {
        export_id: 9, ingress_bytes: 128, egress_bytes: 128,
        output_kind: 1, output_capacity: 2, result_max_count: 4,
        output_nat_binder: 1, required_nat_mask: 1, required_domain_mask: 3,
        work_bytes: 24, output_items_are_count: true
    };
    let fields: host_bridge::Field[] = [
        host_bridge::Field { kind: 1 },
        host_bridge::Field { role: 1, kind: 1, max_count: 2, nat_binder: 1, domain_binder: 1 },
        host_bridge::Field { role: 1, kind: 3, max_count: 2, nat_binder: 1, domain_binder: 2 },
        host_bridge::Field { kind: 3 }
    ];
    let predicates: host_bridge::Predicate[] = [
        host_bridge::Predicate { kind: 0, left: host_bridge::Term { kind: 1, field: 0 }, right: host_bridge::Term { literal: 10 } },
        host_bridge::Predicate { kind: 1, left: host_bridge::Term { kind: 2, field: 1 }, right: host_bridge::Term { kind: 1, field: 0 } },
        host_bridge::Predicate { kind: 3, left: host_bridge::Term { kind: 1, field: 0 }, right: host_bridge::Term { kind: 3 } },
        host_bridge::Predicate { kind: 4, left: host_bridge::Term { kind: 1, field: 0 }, right: host_bridge::Term { kind: 3 } },
        host_bridge::Predicate { kind: 5, left: host_bridge::Term { kind: 1, field: 0 }, right: host_bridge::Term { kind: 3 } }
    ];
    var input: u8[>..] = [];
    for i in 72 { input.push(0); }
    put32(input, 0, 0x4b310001); put32(input, 4, 9); put32(input, 12, 40);
    put32(input, 32, 10);             // fixed U32
    put32(input, 36, 2); put32(input, 40, 24); // U32 View
    put32(input, 44, 2); put32(input, 48, 32); // Bool View
    put32(input, 52, 1);             // fixed Bool
    put32(input, 56, 1); put32(input, 60, 2); // U32 elements
    put32(input, 64, 1); put32(input, 68, 0); // Bool elements
    var original: u8[>..] = [];
    original.append(input);
    let accepted = host_bridge::inspect(manifest, fields, predicates, input, 9, 72, 16, false);
    assert(accepted.status == 0 && accepted.fixed_bytes == 24 && accepted.payload_bytes == 40 && accepted.worst_work == 24);
    assert(input[..] == original[..]);
    let result = host_bridge::output(manifest, fields, predicates, 2, 16);
    assert(result.status == 0 && result.required_bytes == 16 && result.payload_bytes == 16 && result.item_count == 2 && result.data_offset == 8);
    let too_small = host_bridge::output(manifest, fields, predicates, 3, 16); // may alias an input with separately checked bound
    assert(too_small.status == 2 && too_small.required_bytes == 20 && too_small.payload_bytes == 0 && too_small.item_count == 3);
    assert(host_bridge::output(manifest, fields, predicates, 5, 16).status == 9);
    assert(host_bridge::output(manifest, fields, predicates, 0, 97).status == 9);
    let no_room = host_bridge::output(manifest, fields, predicates, 0, 0);
    assert(no_room.status == 2 && no_room.required_bytes == 8 && no_room.payload_bytes == 0);

    // Busy precedes every manifest/header/bounds check and does not mutate input.
    let invalid_manifest = host_bridge::Manifest {};
    assert(host_bridge::inspect(invalid_manifest, fields, predicates, input, 0, 0, 0, true).status == 4);
    assert(input[..] == original[..]);
    assert(host_bridge::inspect(invalid_manifest, fields, predicates, input, 0, 0, 0, false).status == 9);
    assert(host_bridge::inspect(manifest, fields, predicates, input, 9, 31, 0, false).status == 1);
    assert(host_bridge::inspect(manifest, fields, predicates, input, 9, 73, 0, false).status == 1); // buffer shorter than declaration
    for n in 72 {
        assert(host_bridge::inspect(manifest, fields, predicates, input[0..n], 9, 72, 0, false).status == 1);
    }
    assert(host_bridge::inspect(manifest, fields, predicates, input, 8, 72, 0, false).status == 1);
    assert(host_bridge::inspect(manifest, fields, predicates, input, 9, 72, 97, false).status == 1);
    // Every fixed header word has an independent negative control.
    for pos in [0, 4, 8, 12, 16, 20, 24, 28] {
        var bad = copy(original);
        bad[pos] ^= 1;
        assert(host_bridge::inspect(manifest, fields, predicates, bad, 9, 72, 16, false).status == 1);
    }
    var item_manifest = manifest;
    item_manifest.expected_items = 2;
    var items = copy(original);
    put32(items, 20, 2);
    assert(host_bridge::inspect(item_manifest, fields, predicates, items, 9, 72, 16, false).status == 0);

    var bad = copy(original);
    put32(bad, 36, 3); // max_count violation
    assert(host_bridge::inspect(manifest, fields, predicates, bad, 9, 72, 16, false).status == 1);
    put32(bad, 36, 2); put32(bad, 40, 25); // unaligned array offset
    assert(host_bridge::inspect(manifest, fields, predicates, bad, 9, 72, 16, false).status == 1);
    put32(bad, 40, 20); // data points into fixed area
    assert(host_bridge::inspect(manifest, fields, predicates, bad, 9, 72, 16, false).status == 1);
    put32(bad, 40, 36); // extent exceeds payload
    assert(host_bridge::inspect(manifest, fields, predicates, bad, 9, 72, 16, false).status == 1);
    put32(bad, 40, 4294967292); // offset arithmetic cannot wrap to valid
    assert(host_bridge::inspect(manifest, fields, predicates, bad, 9, 72, 16, false).status == 1);
    bad = copy(original);
    put32(bad, 44, 1); // shared Nat binder conflicts with output C and first View
    assert(host_bridge::inspect(manifest, fields, predicates, bad, 9, 72, 16, false).status == 1);
    bad = copy(original);
    put32(bad, 52, 2); // invalid fixed Bool
    assert(host_bridge::inspect(manifest, fields, predicates, bad, 9, 72, 16, false).status == 1);
    bad = copy(original);
    put32(bad, 64, 256); // invalid Bool element high byte
    assert(host_bridge::inspect(manifest, fields, predicates, bad, 9, 72, 16, false).status == 1);
    bad = copy(original);
    put32(bad, 32, 11); // Eq precondition false
    assert(host_bridge::inspect(manifest, fields, predicates, bad, 9, 72, 16, false).status == 1);

    // Immutable input ranges may overlap; each descriptor remains validated.
    var overlap = copy(original);
    put32(overlap, 48, 24); put32(overlap, 60, 0);
    put32(overlap, 64, 0); put32(overlap, 68, 0); // trailing padding
    assert(host_bridge::inspect(manifest, fields, predicates, overlap, 9, 72, 16, false).status == 0);
    overlap[71] = 1;
    assert(host_bridge::inspect(manifest, fields, predicates, overlap, 9, 72, 16, false).status == 1);
    var reverse = copy(original);
    put32(reverse, 40, 32); put32(reverse, 48, 24);
    put32(reverse, 56, 1); put32(reverse, 60, 0);
    put32(reverse, 64, 1); put32(reverse, 68, 0);
    assert(host_bridge::inspect(manifest, fields, predicates, reverse, 9, 72, 16, false).status == 0);
    var gap = copy(original);
    for i in 4 { gap.push(0); }
    put32(gap, 12, 44); put32(gap, 48, 36);
    put32(gap, 64, 0); put32(gap, 68, 1); put32(gap, 72, 0);
    assert(host_bridge::inspect(manifest, fields, predicates, gap, 9, 76, 16, false).status == 0);
    gap[64] = 1; // unreferenced byte between arrays is padding
    assert(host_bridge::inspect(manifest, fields, predicates, gap, 9, 76, 16, false).status == 1);

    // Ineligible schemas are caught before runtime invocation: bounds, binder
    // completeness/uniqueness, unsupported kinds/terms, and work reservation.
    var weak_work = manifest; weak_work.work_bytes = 23;
    assert(host_bridge::inspect(weak_work, fields, predicates, input, 9, 72, 16, false).status == 9);
    var bad_nat = manifest; bad_nat.required_nat_mask = 3;
    assert(host_bridge::inspect(bad_nat, fields, predicates, input, 9, 72, 16, false).status == 9);
    var bad_domain = manifest; bad_domain.required_domain_mask = 1;
    assert(host_bridge::inspect(bad_domain, fields, predicates, input, 9, 72, 16, false).status == 9);
    var duplicated: host_bridge::Field[>..] = [];
    duplicated.append(fields);
    duplicated[2].domain_binder = 1;
    assert(host_bridge::inspect(manifest, duplicated, predicates, input, 9, 72, 16, false).status == 9);
    duplicated[2].domain_binder = 2;
    duplicated[0].kind = 4; // unsupported Index / compound schema
    assert(host_bridge::inspect(manifest, duplicated, predicates, input, 9, 72, 16, false).status == 9);
    var bad_pred: host_bridge::Predicate[>..] = [];
    bad_pred.append(predicates);
    bad_pred[0].left.field = 3; // Bool cannot be treated as a U32 term
    assert(host_bridge::inspect(manifest, fields, bad_pred, input, 9, 72, 16, false).status == 9);
    var impossible_work = manifest; impossible_work.work_bytes = 1073741825;
    assert(host_bridge::inspect(impossible_work, fields, predicates, input, 9, 72, 16, false).status == 9);
    var huge_elements: host_bridge::Field[>..] = [];
    huge_elements.append(fields);
    huge_elements[1].max_count = 4294967295;
    assert(host_bridge::inspect(manifest, huge_elements, predicates, input, 9, 72, 16, false).status == 9);
    assert(host_bridge::predicate_holds(3, 4294967295, 0));
    assert(!host_bridge::predicate_holds(3, 4294967295, 1));
    assert(host_bridge::predicate_holds(4, 0, 0));
    assert(!host_bridge::predicate_holds(4, 0, 1));
    assert(host_bridge::predicate_holds(5, 0, 4294967295));
    assert(!host_bridge::predicate_holds(5, 4294967295, 2));

    // Exact zero-sized Unit geometry admits maximum logical count without a
    // huge array or an element-by-element loop. Offset remains aligned and
    // outside the fixed descriptor area.
    let unit_manifest = host_bridge::Manifest {
        export_id: 2, ingress_bytes: 40, egress_bytes: 40, output_kind: 0,
        output_capacity: 0, result_max_count: 4294967295, work_bytes: 0,
        required_domain_mask: 1, output_items_are_count: true
    };
    let unit_fields: host_bridge::Field[] = [host_bridge::Field { role: 1, kind: 0, max_count: 4294967295, domain_binder: 1 }];
    let no_predicates: host_bridge::Predicate[] = [];
    var unit_input: u8[>..] = [];
    for i in 40 { unit_input.push(0); }
    put32(unit_input, 0, 0x4b310001); put32(unit_input, 4, 2); put32(unit_input, 12, 8);
    put32(unit_input, 32, 4294967295); put32(unit_input, 36, 8);
    let unit = host_bridge::inspect(unit_manifest, unit_fields, no_predicates, unit_input, 2, 40, 8, false);
    assert(unit.status == 0 && unit.worst_work == 0);
    let huge_unit = host_bridge::output(unit_manifest, unit_fields, no_predicates, 4294967295, 8);
    assert(huge_unit.status == 0 && huge_unit.required_bytes == 8 && huge_unit.item_count == 4294967295);

    // Unit's alignment is one, including the exclusive end of an odd-length
    // payload. A non-Unit data offset must still be four-byte aligned.
    unit_input.push(0);
    put32(unit_input, 12, 9); put32(unit_input, 36, 9);
    var odd_unit = unit_manifest; odd_unit.ingress_bytes = 41;
    assert(host_bridge::inspect(odd_unit, unit_fields, no_predicates, unit_input, 2, 41, 8, false).status == 0);
    unit_input[40] = 1; // gap between descriptor and Unit's empty data
    assert(host_bridge::inspect(odd_unit, unit_fields, no_predicates, unit_input, 2, 41, 8, false).status == 1);
    unit_input[40] = 0;
    put32(unit_input, 36, 10); // beyond even an empty range's payload end
    assert(host_bridge::inspect(odd_unit, unit_fields, no_predicates, unit_input, 2, 41, 8, false).status == 1);
    print("host bridge planner laws passed");
}
