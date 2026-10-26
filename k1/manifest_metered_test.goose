import std;
import fixture_geometry;
import manifest;
import work;

fn main() {
    var geometry, ok = fixture_geometry::build();
    assert(ok);
    // Geometry contains seven occupied roles and two explicit padding ranges.
    // Accounting: root(1), initial regions(9), padding slots(10), repeated
    // role edges(9), nine partition steps each scanning 9+2 records (108),
    // final region/padding visits (11) = 148.
    var meter = work::Meter {};
    assert(manifest::validate_with_work(geometry, meter, 7) == 0);
    assert(meter.semantic == 148 && meter.phase_semantic[6] == 148);
    assert(manifest::validate(geometry) == 0);

    var exact = work::Meter { semantic: 1048576 - 148 };
    assert(manifest::validate_with_work(geometry, exact, 7) == 0);
    assert(exact.semantic == 1048576 && exact.phase_semantic[6] == 148);
    var short = work::Meter { semantic: 1048576 - 147 };
    assert(manifest::validate_with_work(geometry, short, 7) == 3);
    assert(short.semantic == 1048576 && short.phase_semantic[6] == 147);
    // Failed checks do not change the geometry and phase 0 is invalid before
    // any visit can be recorded.
    let original = geometry.regions[6].start;
    var bad_phase = work::Meter {};
    assert(manifest::validate_with_work(geometry, bad_phase, 0) == 4);
    assert(bad_phase.semantic == 0 && geometry.regions[6].start == original);
    var malformed = geometry;
    malformed.regions[6].start = 4294967295;
    var m1 = work::Meter {};
    var m2 = work::Meter {};
    assert(manifest::validate_with_work(malformed, m1, 7) == 1);
    assert(manifest::validate_with_work(malformed, m2, 7) == 1);
    assert(m1.semantic == m2.semantic && m1.semantic > 0 && m1.semantic < 148);
    assert(malformed.regions[6].start == 4294967295);
    assert(manifest::validate(malformed) == 1);
    print("metered geometry validation passed");
}
