// Private finite-resource model with at most one selected callee per function.
// No source authority, host engine-stack guarantee or general artifact contract.
namespace closure_resources;
// callee is one-based, zero for leaf; indirect marks the selected call edge.
struct Fn { own: u32 = 0, frame: u32 = 0, depth: u32 = 0, callee: u32 = 0, indirect: bool = false }
// 0 valid, 1 malformed, 2 recursive named cycle, 3 resource/indirect cycle.
fn validate(fs: Fn[:]) -> u32 {
    if fs.len == 0 || fs.len > 128 { return 1; }
    for f in fs {
        if f.depth == 0 || f.depth > 128 || f.callee > fs.len ||
           (f.callee == 0 && f.indirect) { return 1; }
    }
    // Bound every walk by node count; distinguish any callback-hidden cycle.
    for start in fs.len {
        var seen: bool[128] = [false; 128];
        var index = start;
        while true {
            if seen[index] {
                // Classify edges in the cycle itself, not an incoming path.
                let first = index;
                var cursor = index;
                var callback = false;
                loop {
                    let edge = fs[cursor];
                    callback = callback || edge.indirect;
                    cursor = edge.callee - 1;
                    if cursor == first { break; }
                }
                return if callback { 3 } else { 2 };
            }
            seen[index] = true;
            let f = fs[index];
            if f.callee == 0 { break; }
            index = f.callee - 1;
        }
    }
    for f in fs {
        if f.callee == 0 {
            if f.own > f.frame { return 3; }
        } else {
            let g = fs[f.callee - 1];
            if (g.depth as u64) + 1 > f.depth || (f.own as u64) + g.frame > f.frame { return 3; }
        }
    }
    return 0;
}
// Widening must retain a finite depth and may never shrink either guarantee.
fn widens(old_depth: u32, old_frame: u32, new_depth: u32, new_frame: u32) -> bool {
    return old_depth >= 1 && old_depth <= 128 && new_depth <= 128 &&
        new_depth >= old_depth && new_frame >= old_frame;
}
