// Experimental pure M12 geometry/validation planner for scalar-only wire
// payload schemas. This is NOT a checked K1 manifest, authority constructor,
// host wrapper, guest execution, or byte-copy implementation. Caller must
// independently establish callable identity, effect/resource contracts,
// region/domain provenance, fixed manifest hashes and schema eligibility.
// No input byte or numeric binder value is itself storage/domain authority.
namespace host_bridge;
import layout;

// kind: 0 Unit, 1 U32, 2 F32, 3 Bool. role: 0 fixed scalar, 1 View.
// Every View declares a distinct nonzero domain binder. Nat binder 0 means
// no mapped Nat; 1..32 names a checked Nat binder. View max_count is mandatory.
struct Field { role: u32 = 0, kind: u32 = 0, max_count: u32 = 0, nat_binder: u32 = 0, domain_binder: u32 = 0 }
// Term kinds: 0 literal; 1 U32 fixed field; 2 input View length; 3 output C.
struct Term { kind: u32 = 0, field: u32 = 0, literal: u32 = 0 }
// Predicate kinds: 0 Eq, 1 Lt, 2 Le, 3 AddFits, 4 SubFits, 5 MulFits.
struct Predicate { kind: u32 = 0, left: Term = Term {}, right: Term = Term {} }
struct Manifest {
    export_id: u32 = 0,
    ingress_bytes: u32 = 0, egress_bytes: u32 = 0,
    expected_items: u32 = 0,
    output_kind: u32 = 0, output_capacity: u32 = 0, result_max_count: u32 = 0,
    output_nat_binder: u32 = 0, required_nat_mask: u32 = 0, required_domain_mask: u32 = 0,
    work_bytes: u32 = 0, output_items_are_count: bool = false
}
struct InputPlan {
    // Wire statuses: 0 accepted, 1 InvalidInput, 4 Busy. 9 is internal
    // compile-time ineligible, NEVER a status to write into a wire header.
    status: i64 = 9, fixed_bytes: u32 = 0, payload_bytes: u32 = 0, worst_work: u32 = 0
}
struct OutputPlan {
    // 0 Ok, 2 OutputTooSmall, 9 internal invalid/unqualified model input.
    status: i64 = 9, payload_bytes: u32 = 0, required_bytes: u32 = 0,
    item_count: u32 = 0, data_offset: u32 = 0
}
fn stride(kind: u32) -> u32 { if kind == 0 { return 0; } return 4; }
fn binder_bit(binder: u32) -> u32 { return 1 as u32 << (binder - 1); }
fn term_valid(term: Term, fields: Field[:]) -> bool {
    if term.kind > 3 { return false; }
    if term.kind == 0 { return term.field == 0; }
    if term.literal != 0 { return false; }
    if term.kind == 3 { return term.field == 0; }
    if term.field >= fields.len { return false; }
    let field = fields[term.field];
    if term.kind == 1 { return field.role == 0 && field.kind == 1; }
    return field.role == 1;
}

// Returns (fixed wire bytes, worst aligned placement bytes, eligible). The
// model intentionally accepts at most 64 fields/predicates and only scalar
// Plain schemas. Other correct K1 schemas are deferred, not semantically bad.
fn schema(manifest: Manifest, fields: Field[:], predicates: Predicate[:]) -> u32, u32, bool {
    if fields.len > 64 || predicates.len > 64 || manifest.output_kind > 3 ||
       manifest.ingress_bytes < 32 || manifest.egress_bytes < 32 ||
       manifest.ingress_bytes > 1073741824 || manifest.egress_bytes > 1073741824 ||
       manifest.work_bytes > 1073741824 || manifest.output_nat_binder > 32 { return 0, 0, false; }
    var fixed: u32 = 0;
    var work: u32 = 0;
    var nat_mask: u32 = 0;
    var domain_mask: u32 = 0;
    for field in fields {
        if field.kind > 3 || field.role > 1 || field.nat_binder > 32 || field.domain_binder > 32 { return 0, 0, false; }
        if field.role == 0 {
            if field.max_count != 0 || field.nat_binder != 0 || field.domain_binder != 0 { return 0, 0, false; }
            let next, ok = layout::checked_add(fixed, stride(field.kind));
            if !ok { return 0, 0, false; }
            fixed = next;
        } else {
            if field.domain_binder == 0 { return 0, 0, false; }
            let domain = binder_bit(field.domain_binder);
            if (domain_mask & domain) != 0 { return 0, 0, false; }
            domain_mask |= domain;
            if field.nat_binder != 0 { nat_mask |= binder_bit(field.nat_binder); }
            let next, ok = layout::checked_add(fixed, 8);
            if !ok { return 0, 0, false; }
            fixed = next;
            let size, size_ok = layout::checked_mul(field.max_count, stride(field.kind));
            if !size_ok { return 0, 0, false; }
            if size != 0 {
                let aligned, align_ok = layout::checked_align(work, 4);
                if !align_ok { return 0, 0, false; }
                let advanced, add_ok = layout::checked_add(aligned, size);
                if !add_ok { return 0, 0, false; }
                work = advanced;
            }
        }
    }
    if manifest.output_nat_binder != 0 { nat_mask |= binder_bit(manifest.output_nat_binder); }
    if nat_mask != manifest.required_nat_mask || domain_mask != manifest.required_domain_mask { return 0, 0, false; }
    let output_size, output_ok = layout::checked_mul(manifest.output_capacity, stride(manifest.output_kind));
    if !output_ok { return 0, 0, false; }
    if output_size != 0 {
        let aligned, align_ok = layout::checked_align(work, 4);
        if !align_ok { return 0, 0, false; }
        let advanced, add_ok = layout::checked_add(aligned, output_size);
        if !add_ok { return 0, 0, false; }
        work = advanced;
    }
    if work > manifest.work_bytes { return 0, 0, false; }
    // M12's exact required_bytes is U32 and includes the eight-byte descriptor.
    let max_result, max_ok = layout::checked_mul(manifest.result_max_count, stride(manifest.output_kind));
    if !max_ok { return 0, 0, false; }
    let _, total_ok = layout::checked_add(max_result, 8);
    if !total_ok { return 0, 0, false; }
    for p in predicates {
        if p.kind > 5 || !term_valid(p.left, fields) || !term_valid(p.right, fields) { return 0, 0, false; }
    }
    return fixed, work, true;
}

// Only called after all four bytes are proven present.
fn word(bytes: u8[:], p: i64) -> u32 {
    return bytes[p] | (bytes[p + 1] as u32 << 8) |
        (bytes[p + 2] as u32 << 16) | (bytes[p + 3] as u32 << 24);
}
fn valid_bool(bytes: u8[:], p: i64) -> bool {
    return bytes[p] <= 1 && bytes[p + 1] == 0 && bytes[p + 2] == 0 && bytes[p + 3] == 0;
}
fn term_value(t: Term, values: u32[:], lengths: u32[:], capacity: u32) -> u32 {
    if t.kind == 0 { return t.literal; }
    if t.kind == 1 { return values[t.field]; }
    if t.kind == 2 { return lengths[t.field]; }
    return capacity;
}
fn predicate_holds(kind: u32, a: u32, b: u32) -> bool {
    if kind == 0 { return a == b; }
    if kind == 1 { return a < b; }
    if kind == 2 { return a <= b; }
    if kind == 3 { return b <= 4294967295 - a; }
    if kind == 4 { return a >= b; }
    return a == 0 || b <= 4294967295 / a;
}

// Busy wins before inspection. For eligible schema, all header, descriptor,
// element and precondition failures map to InvalidInput. Buffer is borrowed;
// this routine performs no allocation, no state/window writes, no raw-pointer
// construction and no freeze. Input bounds are checked before every read.
fn inspect(manifest: Manifest, fields: Field[:], predicates: Predicate[:], input: u8[:],
           export_id: u32, input_bytes: u32, output_capacity: u32, busy: bool) -> InputPlan {
    if busy { return InputPlan { status: 4 }; }
    let fixed, work, eligible = schema(manifest, fields, predicates);
    if !eligible { return InputPlan { status: 9 }; }
    if export_id != manifest.export_id || input_bytes < 32 || input_bytes > manifest.ingress_bytes ||
       input_bytes > input.len || output_capacity > manifest.egress_bytes - 32 { return InputPlan { status: 1 }; }
    let payload = input_bytes - 32;
    if word(input, 0) != 0x4b310001 || word(input, 4) != export_id || word(input, 8) != 0 ||
       word(input, 12) != payload || word(input, 16) != 0 || word(input, 20) != manifest.expected_items ||
       word(input, 24) != 0 || word(input, 28) != 0 || fixed > payload { return InputPlan { status: 1 }; }
    var values: u32[64] = [0; 64];
    var lengths: u32[64] = [0; 64];
    var range_starts: u32[64] = [0; 64];
    var range_ends: u32[64] = [0; 64];
    var range_count: i64 = 0;
    var nat_values: u32[32] = [0; 32];
    var nat_seen: bool[32] = [false; 32];
    if manifest.output_nat_binder != 0 {
        let index = manifest.output_nat_binder - 1;
        nat_values[index] = manifest.output_capacity; nat_seen[index] = true;
    }
    var cursor: u32 = 0;
    for field, i in fields {
        let p = 32 + cursor as i64;
        if field.role == 0 {
            if field.kind == 3 && !valid_bool(input, p) { return InputPlan { status: 1 }; }
            if field.kind == 1 { values[i] = word(input, p); }
            cursor += stride(field.kind);
        } else {
            let count = word(input, p);
            let offset = word(input, p + 4);
            cursor += 8;
            // Unit's representation has alignment one; every nonempty scalar
            // representation is four-byte aligned (M02).
            if count > field.max_count || (field.kind != 0 && offset % 4 != 0) || offset < fixed || offset > payload { return InputPlan { status: 1 }; }
            let length, ok = layout::checked_mul(count, stride(field.kind));
            if !ok || length > payload - offset { return InputPlan { status: 1 }; }
            if length != 0 {
                range_starts[range_count] = offset;
                range_ends[range_count] = offset + length; // bounded by payload
                range_count += 1;
            }
            lengths[i] = count;
            if field.nat_binder != 0 {
                let n = field.nat_binder - 1;
                if nat_seen[n] && nat_values[n] != count { return InputPlan { status: 1 }; }
                nat_seen[n] = true; nat_values[n] = count;
            }
            if field.kind == 3 {
                for j in count {
                    if !valid_bool(input, 32 + offset as i64 + j as i64 * 4) { return InputPlan { status: 1 }; }
                }
            }
        }
    }
    // All bytes outside the fixed field area and the union of input array
    // ranges are wire padding, including gaps and trailing bytes; M12 requires
    // those bytes to be zero. Overlapping immutable inputs remain legal.
    // Stable insertion sort is bounded by the model's 64-field limit.
    for i in 1..range_count {
        let start = range_starts[i];
        let end = range_ends[i];
        var j = i;
        while j > 0 && range_starts[j - 1] > start {
            range_starts[j] = range_starts[j - 1];
            range_ends[j] = range_ends[j - 1];
            j -= 1;
        }
        range_starts[j] = start;
        range_ends[j] = end;
    }
    var covered = fixed;
    for i in range_count {
        let start = range_starts[i];
        let end = range_ends[i];
        if start > covered {
            for p in covered..start { if input[32 + p] != 0 { return InputPlan { status: 1 }; } }
        }
        if end > covered { covered = end; }
    }
    for p in covered..payload { if input[32 + p] != 0 { return InputPlan { status: 1 }; } }
    for predicate in predicates {
        let a = term_value(predicate.left, values, lengths, manifest.output_capacity);
        let b = term_value(predicate.right, values, lengths, manifest.output_capacity);
        if !predicate_holds(predicate.kind, a, b) { return InputPlan { status: 1 }; }
    }
    return InputPlan { status: 0, fixed_bytes: fixed, payload_bytes: payload, worst_work: work };
}

// Invoke only after the language function has executed once and produced a
// checked result count. The selected `result_max_count` must cover both output
// and any admitted input-alias result; C alone does not bound an aliased view.
// This calculates payload geometry, not data validity or publication.
fn output(manifest: Manifest, fields: Field[:], predicates: Predicate[:], count: u32, available: u32) -> OutputPlan {
    let _, _, eligible = schema(manifest, fields, predicates);
    if !eligible || available > manifest.egress_bytes - 32 || count > manifest.result_max_count { return OutputPlan {}; }
    let data_bytes, ok = layout::checked_mul(count, stride(manifest.output_kind));
    if !ok { return OutputPlan {}; }
    let required, add_ok = layout::checked_add(8, data_bytes);
    if !add_ok { return OutputPlan {}; }
    let items = if manifest.output_items_are_count { count } else { 0 };
    if required > available { return OutputPlan { status: 2, required_bytes: required, item_count: items }; }
    return OutputPlan { status: 0, payload_bytes: required, required_bytes: required, item_count: items, data_offset: 8 };
}
