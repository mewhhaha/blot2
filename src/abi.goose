import .model;
import .runtime;
import .hash;
fn memory_geometry_bytes(map: runtime::MemoryMap, out: u8[>..]&) {
    for word in [map.static_base, map.static_bytes, map.control, map.owners, map.owner_slots,
        map.bitmap, map.bitmap_bytes, map.frame, map.frame_bytes, map.ingress, map.ingress_bytes,
        map.egress, map.egress_bytes, map.pool, map.pool_bytes, map.granules, map.end, map.pages] {
        for i in 4 { out.push((word >> (8 * i)) as! u8); }
    }
}
fn memory_geometry_hash(map: runtime::MemoryMap) -> k1hash::Digest {
    var bytes:u8[>..] = []; memory_geometry_bytes(map, bytes); return k1hash::blake3(bytes);
}
