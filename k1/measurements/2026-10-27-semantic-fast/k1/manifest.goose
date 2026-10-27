// Experimental pure validator for the proposed fixed-memory geometry model in
// MANIFEST_SCHEMA.md. This takes value records, NOT untrusted encoded bytes;
// it does not decode an artifact or validate ABI hashes, identities, runtime
// roles, initial memory contents, executable provenance or a certificate.
// It must not be used to admit public K1 artifacts or grant pointer authority.
namespace manifest;
import work;

struct Region { tag: u32 = 0, start: u32 = 0, length: u32 = 0 }
struct Geometry {
    page_bytes: u32 = 65536,
    initial_pages: u32 = 0, maximum_pages: u32 = 0,
    owner_slots: u32 = 0, owner_entry_bytes: u32 = 32,
    granule_bytes: u32 = 4096, root_capsule_bytes: u32 = 256,
    // Tags 1..9 in fixed role order; empty roles are {tag,0,0}.
    regions: Region[9] = [Region {}; 9],
    // Canonical ascending-address, nonempty, separated padding; unused slots
    // are all zero. Nine nonempty fixed regions can create at most ten gaps.
    padding_count: u32 = 0, padding: Region[10] = [Region {}; 10]
}

// 0: valid geometry; 1: malformed/out-of-profile. This narrow result does not
// encode k1_invalid_artifact or k1_incompatible_artifact for a public decoder.
fn visit(m: work::Meter&, phase: u32, enabled: bool) -> i64 {
    if !enabled { return 0; }
    let receipt = work::charge(m, phase, 10); // layout/geometry visit
    if receipt.status == 0 { return 0; }
    if receipt.status == 1 { return 3; } // k1_semantic_limit
    return 4; // invalid phase/meter or other instrumentation failure
}

// Both entry points run the identical validation traversal. The metered form
// charges each repeated geometry record, role edge and partition-scan visit
// before following it. A partial visit receipt is retained on failure; the
// input geometry is never mutated. This remains a local geometry model, not
// an authenticated manifest or a complete compiler semantic-work receipt.
fn validate(g: Geometry&) -> i64 {
    var unused = work::Meter {};
    return validate_inner(g, unused, 7, false);
}
fn validate_with_work(g: Geometry&, meter: work::Meter&, phase: u32) -> i64 {
    return validate_inner(g, meter, phase, true);
}
fn validate_inner(g: Geometry&, meter: work::Meter&, phase: u32, metered: bool) -> i64 {
    let root_status = visit(meter, phase, metered);
    if root_status != 0 { return root_status; }
    if g.page_bytes != 65536 || g.granule_bytes != 4096 || g.owner_entry_bytes != 32 ||
       g.root_capsule_bytes != 256 || g.initial_pages == 0 ||
       g.initial_pages != g.maximum_pages || g.initial_pages > 16384 ||
       g.owner_slots > 4096 || g.padding_count > 10 { return 1; }
    // The maximum page count above bounds this multiplication to 1 GiB.
    let memory_end = g.initial_pages * 65536;
    var nonpadding_end: u32 = 0;
    for i in 9 {
        let charge_status = visit(meter, phase, metered);
        if charge_status != 0 { return charge_status; }
        let region = g.regions[i];
        if region.tag != i + 1 { return 1; }
        if region.length == 0 {
            if region.start != 0 { return 1; }
            continue;
        }
        if region.start > memory_end || region.length > memory_end - region.start { return 1; }
        let end = region.start + region.length;
        if end > nonpadding_end { nonpadding_end = end; }
    }
    var previous_end: u32 = 0;
    for i in 10 {
        let charge_status = visit(meter, phase, metered);
        if charge_status != 0 { return charge_status; }
        let padding = g.padding[i];
        if i >= g.padding_count {
            if padding.tag != 0 || padding.start != 0 || padding.length != 0 { return 1; }
            continue;
        }
        if padding.tag != 0 || padding.length == 0 || padding.start > memory_end ||
           padding.length > memory_end - padding.start { return 1; }
        if i != 0 && padding.start <= previous_end { return 1; } // sorted, nonoverlapping, merged
        previous_end = padding.start + padding.length;
    }
    // The nine role edges are read again below, so each incurs a second visit.
    for i in 9 {
        let charge_status = visit(meter, phase, metered);
        if charge_status != 0 { return charge_status; }
    }
    let static_data = g.regions[0];
    let dictionaries = g.regions[1];
    let control = g.regions[2];
    let owners = g.regions[3];
    let bitmap = g.regions[4];
    let frame = g.regions[5];
    let ingress = g.regions[6];
    let egress = g.regions[7];
    let pool = g.regions[8];
    // Every nonempty memory role except Unit storage starts on a word boundary.
    if static_data.start % 4 != 0 || dictionaries.start % 4 != 0 ||
       control.start % 4 != 0 || owners.start % 4 != 0 || bitmap.start % 4 != 0 ||
       frame.start % 4 != 0 || ingress.start % 4 != 0 || egress.start % 4 != 0 { return 1; }
    if owners.length != g.owner_slots * 32 || frame.length > 16777216 ||
       ingress.length < 32 || egress.length < 32 || pool.start % 4096 != 0 || pool.length % 4096 != 0 { return 1; }
    // Pool length was bounded by memory_end. Compute ceil(granules/8), then
    // round to a 4-byte word without any U32-overflowing intermediate.
    let granules = pool.length / 4096;
    var raw_bitmap = granules / 8;
    if granules % 8 != 0 { raw_bitmap += 1; }
    let bitmap_bytes = ((raw_bitmap + 3) / 4) * 4;
    if bitmap.length != bitmap_bytes { return 1; }
    // Local manifest profile normalization: use the smallest page count that
    // contains non-padding regions. General M03 maps may intentionally count
    // reserved padding in their final memory-map end and need not use this rule.
    var needed_pages = nonpadding_end / 65536;
    if nonpadding_end % 65536 != 0 { needed_pages += 1; }
    if needed_pages != g.initial_pages { return 1; }

    // Verify full disjoint coverage using bounded exact walk. Each iteration
    // advances by one nonempty interval; no untrusted offset is followed until
    // range and count checks above have succeeded. Duplicate starts, gaps,
    // overlaps, unvisited regions and padding are rejected.
    var seen_regions: bool[9] = [false; 9];
    var seen_padding: bool[10] = [false; 10];
    var cursor: u32 = 0;
    var visits: i64 = 0;
    while cursor < memory_end {
        let charge_status = visit(meter, phase, metered);
        if charge_status != 0 { return charge_status; }
        if visits >= 19 { return 1; }
        var matches: i64 = 0;
        var next: u32 = cursor;
        var region_index: i64 = -1;
        var padding_index: i64 = -1;
        for i in 9 {
            let charge_status = visit(meter, phase, metered);
            if charge_status != 0 { return charge_status; }
            let region = g.regions[i];
            if region.length != 0 && !seen_regions[i] && region.start == cursor {
                matches += 1; next = region.start + region.length; region_index = i;
            }
        }
        for i in g.padding_count {
            let charge_status = visit(meter, phase, metered);
            if charge_status != 0 { return charge_status; }
            let padding = g.padding[i];
            if !seen_padding[i] && padding.start == cursor {
                matches += 1; next = padding.start + padding.length; padding_index = i;
            }
        }
        if matches != 1 || next <= cursor { return 1; }
        if region_index >= 0 { seen_regions[region_index] = true; }
        else { seen_padding[padding_index] = true; }
        cursor = next;
        visits += 1;
    }
    if cursor != memory_end { return 1; }
    for i in 9 {
        let charge_status = visit(meter, phase, metered);
        if charge_status != 0 { return charge_status; }
        let region = g.regions[i];
        if region.length != 0 && !seen_regions[i] { return 1; }
    }
    for i in g.padding_count {
        let charge_status = visit(meter, phase, metered);
        if charge_status != 0 { return charge_status; }
        if !seen_padding[i] { return 1; }
    }
    return 0;
}
