// Isolated resolver cache benchmark. Each line is thread CPU nanoseconds.
// Run as a Goose main beside the compiler source modules.
import check.types;
import support.native;

fn fill(map:blot_check_types::Map_projection_resolutions&,count:i64) {
    for i in count {
        let key=blot_check_types::ProjectionResolution{(i+1) as u32,0,1,..};
        assert(map.insert(key,(i+1) as u32));
    }
}
fn run(dense:i64,sparse:i64,rounds:i64) -> u64 {
    var map=blot_check_types::Map_projection_resolutions{..};
    let start=blot_native::thread_cpu_ns();
    for round in rounds {
        fill(map,dense);map.clear();
        for epoch in sparse {fill(map,3);map.clear();}
    }
    let end=blot_native::thread_cpu_ns();
    map.deinit();
    return end-start;
}
fn main() {
    print(run(4096,512,16));
    print(run(4096,0,64));
    print(run(4096,1,64));
}
