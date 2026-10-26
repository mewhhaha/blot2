import std;
import src.model;
fn test_model() {
    with_core() { b =>
        let id = add_name(b, "hello");
        assert(id == 1 && add_name(b, "hello") == id);
        assert(name_bytes(core_view(b), id) == "hello");
        assert(begin_completion(b));
        assert(!seal_completion(b));
        assert(end_completion(b) && seal_completion(b));
        assert(!begin_completion(b));
        assert(!span_ok(Span { 4294967295, 1 }, 10));
    };
    print("model: passed");
}
