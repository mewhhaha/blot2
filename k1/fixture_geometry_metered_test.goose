import std;
import fixture_geometry;
import manifest;
import work;

fn main() {
    var meter = work::Meter {};
    var g, status = fixture_geometry::build_with_work(meter, 7);
    assert(status == 0 && manifest::validate(g) == 0);
    // Thirty-two construction/layout visits plus 148 independent validation
    // visits. Both the return and validation use the same compiler-owned meter.
    assert(meter.semantic == 180 && meter.phase_semantic[6] == 180);
    var exact = work::Meter { semantic: 1048576 - 180 };
    let value, exact_status = fixture_geometry::build_with_work(exact, 7);
    assert(exact_status == 0 && value.initial_pages == 275 && exact.semantic == 1048576);
    var short = work::Meter { semantic: 1048576 - 179 };
    let rejected, short_status = fixture_geometry::build_with_work(short, 7);
    assert(short_status == 3 && rejected.initial_pages == 0 && short.semantic == 1048576);
    var invalid = work::Meter {};
    let none, bad_phase = fixture_geometry::build_with_work(invalid, 0);
    assert(bad_phase == 4 && none.initial_pages == 0 && invalid.semantic == 0);
    let unmetered, unmetered_ok = fixture_geometry::build();
    assert(unmetered_ok && unmetered.initial_pages == g.initial_pages);
    print("metered fixture geometry construction passed");
}
