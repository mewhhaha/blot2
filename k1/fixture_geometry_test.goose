import fixture_geometry;
import manifest;

fn main() {
    let geometry, ok = fixture_geometry::build();
    assert(ok);
    assert(manifest::validate(geometry) == 0);
    assert(geometry.initial_pages == 275 && geometry.maximum_pages == 275);
    assert(geometry.owner_slots == 256 && geometry.regions[3].length == 8192);
    assert(geometry.regions[4].start == 8208 && geometry.regions[4].length == 512);
    assert(geometry.regions[5].start == 8720 && geometry.regions[5].length == 1048576);
    assert(geometry.regions[6].start == 1057296 && geometry.regions[6].length == 65536);
    assert(geometry.regions[7].start == 1122832 && geometry.regions[7].length == 65536);
    assert(geometry.padding_count == 2);
    assert(geometry.padding[0].start == 1188368 && geometry.padding[0].length == 3568);
    assert(geometry.regions[8].start == 1191936 && geometry.regions[8].length == 16777216);
    assert(geometry.padding[1].start == 17969152 && geometry.padding[1].length == 53248);
    // The constructor returns independent values; changing a caller's copy
    // cannot alter later plans.
    var tampered = geometry;
    tampered.regions[8].start += 4096;
    assert(manifest::validate(tampered) != 0);
    let fresh, fresh_ok = fixture_geometry::build();
    assert(fresh_ok && manifest::validate(fresh) == 0 && fresh.regions[8].start == 1191936);
    print("fixture geometry construction passed");
}
