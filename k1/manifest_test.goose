import manifest;

fn roles() -> manifest::Geometry {
    var g = manifest::Geometry {};
    for i in 9 { g.regions[i].tag = (i + 1) as u32; }
    return g;
}
fn fixture() -> manifest::Geometry {
    var g = roles();
    g.initial_pages = 275; g.maximum_pages = 275; g.owner_slots = 256;
    g.regions[2] = manifest::Region { tag: 3, start: 0, length: 16 };
    g.regions[3] = manifest::Region { tag: 4, start: 16, length: 8192 };
    g.regions[4] = manifest::Region { tag: 5, start: 8208, length: 512 };
    g.regions[5] = manifest::Region { tag: 6, start: 8720, length: 1048576 };
    g.regions[6] = manifest::Region { tag: 7, start: 1057296, length: 65536 };
    g.regions[7] = manifest::Region { tag: 8, start: 1122832, length: 65536 };
    g.regions[8] = manifest::Region { tag: 9, start: 1191936, length: 16777216 };
    g.padding_count = 2;
    g.padding[0] = manifest::Region { start: 1188368, length: 3568 };
    g.padding[1] = manifest::Region { start: 17969152, length: 53248 };
    return g;
}
fn small(granules: u32) -> manifest::Geometry {
    var g = roles();
    let raw = granules / 8 + (if granules % 8 != 0 { 1 } else { 0 });
    let bitmap = ((raw + 3) / 4) * 4;
    g.owner_slots = 1;
    g.regions[2] = manifest::Region { tag: 3, length: 16 };
    g.regions[3] = manifest::Region { tag: 4, start: 16, length: 32 };
    if bitmap != 0 { g.regions[4] = manifest::Region { tag: 5, start: 48, length: bitmap }; }
    g.regions[6] = manifest::Region { tag: 7, start: 48 + bitmap, length: 32 };
    g.regions[7] = manifest::Region { tag: 8, start: 80 + bitmap, length: 32 };
    let windows_end = 112 + bitmap;
    if granules == 0 {
        g.initial_pages = 1; g.maximum_pages = 1;
        g.padding_count = 1;
        g.padding[0] = manifest::Region { start: windows_end, length: 65536 - windows_end };
    } else {
        let pool_end = 4096 + granules * 4096;
        g.regions[8] = manifest::Region { tag: 9, start: 4096, length: granules * 4096 };
        g.initial_pages = pool_end / 65536 + (if pool_end % 65536 != 0 { 1 } else { 0 });
        g.maximum_pages = g.initial_pages;
        g.padding_count = 1;
        g.padding[0] = manifest::Region { start: windows_end, length: 4096 - windows_end };
        if pool_end != g.initial_pages * 65536 {
            g.padding_count = 2;
            g.padding[1] = manifest::Region { start: pool_end, length: g.initial_pages * 65536 - pool_end };
        }
    }
    return g;
}
fn one_gib() -> manifest::Geometry {
    var g = roles();
    g.initial_pages = 16384; g.maximum_pages = 16384; g.owner_slots = 1;
    g.regions[2] = manifest::Region { tag: 3, length: 16 };
    g.regions[3] = manifest::Region { tag: 4, start: 16, length: 32 };
    g.regions[4] = manifest::Region { tag: 5, start: 48, length: 32768 };
    g.regions[6] = manifest::Region { tag: 7, start: 32816, length: 32 };
    g.regions[7] = manifest::Region { tag: 8, start: 32848, length: 32 };
    g.regions[8] = manifest::Region { tag: 9, start: 40960, length: 1073700864 };
    g.padding_count = 1;
    g.padding[0] = manifest::Region { start: 32880, length: 8080 };
    return g;
}
fn zero_pool(owners: u32, frame_bytes: u32) -> manifest::Geometry {
    var g = roles();
    g.owner_slots = owners;
    g.regions[2] = manifest::Region { tag: 3, length: 16 };
    var end: u32 = 16;
    if owners != 0 {
        g.regions[3] = manifest::Region { tag: 4, start: end, length: owners * 32 };
        end += owners * 32;
    }
    if frame_bytes != 0 {
        g.regions[5] = manifest::Region { tag: 6, start: end, length: frame_bytes };
        end += frame_bytes;
    }
    g.regions[6] = manifest::Region { tag: 7, start: end, length: 32 }; end += 32;
    g.regions[7] = manifest::Region { tag: 8, start: end, length: 32 }; end += 32;
    g.initial_pages = end / 65536 + (if end % 65536 != 0 { 1 } else { 0 });
    g.maximum_pages = g.initial_pages;
    if end != g.initial_pages * 65536 {
        g.padding_count = 1;
        g.padding[0] = manifest::Region { start: end, length: g.initial_pages * 65536 - end };
    }
    return g;
}
fn main() {
    var expected = fixture();
    assert(manifest::validate(expected) == 0);
    var largest = one_gib();
    assert(manifest::validate(largest) == 0);
    var huge_owners = zero_pool(4096, 0);
    assert(manifest::validate(huge_owners) == 0);
    var huge_frame = zero_pool(0, 16777216);
    assert(manifest::validate(huge_frame) == 0);
    for count in [0, 1, 7, 8, 9, 31, 32, 33] {
        var test = small(count as u32);
        assert(manifest::validate(test) == 0);
    }
    var bad = fixture(); bad.page_bytes = 65535; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.owner_entry_bytes = 31; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.root_capsule_bytes = 255; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.granule_bytes = 2048; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.initial_pages = 0; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.maximum_pages = 276; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.initial_pages = 16385; bad.maximum_pages = 16385; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.owner_slots = 4097; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.padding_count = 11; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.regions[8].tag = 4; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.regions[0].start = 4; assert(manifest::validate(bad) == 1); // noncanonical empty
    bad = fixture(); bad.regions[3].length -= 4; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.regions[4].length -= 4; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.regions[5].length = 16777217; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.regions[6].length = 31; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.regions[7].start += 1; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.regions[8].start += 4; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.regions[8].length -= 1; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.regions[2].start = 4294967295; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.regions[2].length = 4294967295; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.padding[0].start += 1; assert(manifest::validate(bad) == 1); // gap
    bad = fixture(); bad.padding[0].start -= 1; bad.padding[0].length += 1; assert(manifest::validate(bad) == 1); // overlap
    bad = fixture(); bad.padding[0].tag = 1; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.padding[0].length = 0; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.padding[1].start = 4294967295; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.padding[2].length = 1; assert(manifest::validate(bad) == 1); // unused slot must be zero
    bad = fixture(); bad.padding_count = 1; assert(manifest::validate(bad) == 1);
    bad = fixture(); bad.padding[1] = bad.padding[0]; assert(manifest::validate(bad) == 1); // duplicate span
    bad = fixture(); bad.regions[6].start = bad.regions[7].start; assert(manifest::validate(bad) == 1);
    bad = largest; bad.regions[8].length += 1; assert(manifest::validate(bad) == 1); // past 1 GiB
    bad = fixture(); bad.initial_pages += 1; bad.maximum_pages += 1; bad.padding[1].length += 65536;
    assert(manifest::validate(bad) == 1); // exact partition but oversized page count
    bad = fixture(); bad.padding_count = 3; bad.padding[1].length = 1;
    bad.padding[2] = manifest::Region { start: 17969153, length: 53247 };
    assert(manifest::validate(bad) == 1); // adjacent padding records must merge
    print("manifest geometry laws passed");
}
