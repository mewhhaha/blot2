// Central geometry constructor for the private scalar Wasm fixture. These
// checked values describe only that fixture's selected profile; they do not
// authenticate a manifest, implement a host bridge, or certify K1 output.
namespace fixture_geometry;
import layout;
import manifest;
import work;

// Returns an empty Geometry and false if any arithmetic or local-profile
// validation fails. Zero-sized static and dictionary regions use the
// manifest model's canonical {tag,0,0} representation.
fn build() -> manifest::Geometry, bool {
    var unused = work::Meter {};
    let geometry, status = build_inner(unused, 7, false);
    return geometry, status == 0;
}

// The metered form follows the same construction path as build. Each geometry
// node/edge and checked layout calculation is charged before it is performed,
// then the independently validated map is traversed with the same meter.
// This is local fixture accounting, not a complete C09 compiler receipt.
// 0 success, 1 invalid geometry/arithmetic, 3 semantic limit, 4 accounting.
fn build_with_work(meter: work::Meter&, phase: u32) -> manifest::Geometry, i64 {
    return build_inner(meter, phase, true);
}
fn build_inner(meter: work::Meter&, phase: u32, metered: bool) -> manifest::Geometry, i64 {
    let initial_status = manifest::visit(meter, phase, metered);
    if initial_status != 0 { return manifest::Geometry {}, initial_status; }
    var g = manifest::Geometry {};
    for i in 9 {
        let status = manifest::visit(meter, phase, metered);
        if status != 0 { return manifest::Geometry {}, status; }
        g.regions[i].tag = (i + 1) as u32;
    }
    g.owner_slots = 256;
    let page_bytes: u32 = 65536;
    let granule_bytes: u32 = 4096;
    let pool_bytes: u32 = 16777216;
    let frame_bytes: u32 = 1048576;
    let window_bytes: u32 = 65536;
    let control_bytes: u32 = 16;
    let owner_status = manifest::visit(meter, phase, metered);
    if owner_status != 0 { return manifest::Geometry {}, owner_status; }
    let owner_bytes, owner_ok = layout::checked_mul(g.owner_slots, g.owner_entry_bytes);
    if !owner_ok { return manifest::Geometry {}, 1; }
    let granules_status = manifest::visit(meter, phase, metered);
    if granules_status != 0 { return manifest::Geometry {}, granules_status; }
    let granules = pool_bytes / granule_bytes;
    let raw_bitmap_status = manifest::visit(meter, phase, metered);
    if raw_bitmap_status != 0 { return manifest::Geometry {}, raw_bitmap_status; }
    var raw_bitmap = granules / 8;
    if granules % 8 != 0 { raw_bitmap += 1; }
    let bitmap_status = manifest::visit(meter, phase, metered);
    if bitmap_status != 0 { return manifest::Geometry {}, bitmap_status; }
    let bitmap_bytes, bitmap_ok = layout::checked_align(raw_bitmap, 4);
    if !bitmap_ok { return manifest::Geometry {}, 1; }
    let control_status = manifest::visit(meter, phase, metered);
    if control_status != 0 { return manifest::Geometry {}, control_status; }
    g.regions[2] = manifest::Region { tag: 3, start: 0, length: control_bytes };
    var cursor = control_bytes;
    let owner_region_status = manifest::visit(meter, phase, metered);
    if owner_region_status != 0 { return manifest::Geometry {}, owner_region_status; }
    g.regions[3] = manifest::Region { tag: 4, start: cursor, length: owner_bytes };
    let owners_end_status = manifest::visit(meter, phase, metered);
    if owners_end_status != 0 { return manifest::Geometry {}, owners_end_status; }
    let owners_end, owners_ok = layout::checked_add(cursor, owner_bytes);
    if !owners_ok { return manifest::Geometry {}, 1; }
    cursor = owners_end;
    let bitmap_region_status = manifest::visit(meter, phase, metered);
    if bitmap_region_status != 0 { return manifest::Geometry {}, bitmap_region_status; }
    g.regions[4] = manifest::Region { tag: 5, start: cursor, length: bitmap_bytes };
    let bitmap_end_status = manifest::visit(meter, phase, metered);
    if bitmap_end_status != 0 { return manifest::Geometry {}, bitmap_end_status; }
    let bitmap_end, bitmap_end_ok = layout::checked_add(cursor, bitmap_bytes);
    if !bitmap_end_ok { return manifest::Geometry {}, 1; }
    cursor = bitmap_end;
    let frame_region_status = manifest::visit(meter, phase, metered);
    if frame_region_status != 0 { return manifest::Geometry {}, frame_region_status; }
    g.regions[5] = manifest::Region { tag: 6, start: cursor, length: frame_bytes };
    let frame_end_status = manifest::visit(meter, phase, metered);
    if frame_end_status != 0 { return manifest::Geometry {}, frame_end_status; }
    let frame_end, frame_ok = layout::checked_add(cursor, frame_bytes);
    if !frame_ok { return manifest::Geometry {}, 1; }
    cursor = frame_end;
    let ingress_region_status = manifest::visit(meter, phase, metered);
    if ingress_region_status != 0 { return manifest::Geometry {}, ingress_region_status; }
    g.regions[6] = manifest::Region { tag: 7, start: cursor, length: window_bytes };
    let ingress_end_status = manifest::visit(meter, phase, metered);
    if ingress_end_status != 0 { return manifest::Geometry {}, ingress_end_status; }
    let ingress_end, ingress_ok = layout::checked_add(cursor, window_bytes);
    if !ingress_ok { return manifest::Geometry {}, 1; }
    cursor = ingress_end;
    let egress_region_status = manifest::visit(meter, phase, metered);
    if egress_region_status != 0 { return manifest::Geometry {}, egress_region_status; }
    g.regions[7] = manifest::Region { tag: 8, start: cursor, length: window_bytes };
    let egress_end_status = manifest::visit(meter, phase, metered);
    if egress_end_status != 0 { return manifest::Geometry {}, egress_end_status; }
    let egress_end, egress_ok = layout::checked_add(cursor, window_bytes);
    if !egress_ok { return manifest::Geometry {}, 1; }
    cursor = egress_end;
    let pool_align_status = manifest::visit(meter, phase, metered);
    if pool_align_status != 0 { return manifest::Geometry {}, pool_align_status; }
    let pool_start, align_ok = layout::checked_align(cursor, granule_bytes);
    if !align_ok { return manifest::Geometry {}, 1; }
    if pool_start > cursor {
        let padding_status = manifest::visit(meter, phase, metered);
        if padding_status != 0 { return manifest::Geometry {}, padding_status; }
        g.padding[g.padding_count] = manifest::Region { start: cursor, length: pool_start - cursor };
        g.padding_count += 1;
    }
    let pool_region_status = manifest::visit(meter, phase, metered);
    if pool_region_status != 0 { return manifest::Geometry {}, pool_region_status; }
    g.regions[8] = manifest::Region { tag: 9, start: pool_start, length: pool_bytes };
    let pool_end_status = manifest::visit(meter, phase, metered);
    if pool_end_status != 0 { return manifest::Geometry {}, pool_end_status; }
    let pool_end, pool_ok = layout::checked_add(pool_start, pool_bytes);
    if !pool_ok { return manifest::Geometry {}, 1; }
    let page_status = manifest::visit(meter, phase, metered);
    if page_status != 0 { return manifest::Geometry {}, page_status; }
    let memory_end, page_ok = layout::checked_align(pool_end, page_bytes);
    if !page_ok || memory_end > 1073741824 { return manifest::Geometry {}, 1; }
    if memory_end > pool_end {
        let padding_status = manifest::visit(meter, phase, metered);
        if padding_status != 0 { return manifest::Geometry {}, padding_status; }
        g.padding[g.padding_count] = manifest::Region { start: pool_end, length: memory_end - pool_end };
        g.padding_count += 1;
    }
    let final_status = manifest::visit(meter, phase, metered);
    if final_status != 0 { return manifest::Geometry {}, final_status; }
    g.initial_pages = memory_end / page_bytes;
    g.maximum_pages = g.initial_pages;
    let validation_status = if metered { manifest::validate_with_work(g, meter, phase) } else { manifest::validate(g) };
    if validation_status != 0 { return manifest::Geometry {}, validation_status; }
    return g, 0;
}
