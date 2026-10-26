import public_frontend;
import scalar_core;
import frontend;

fn accepted(source: u8[:], depth: u32, frame: u32) {
    let candidate = public_frontend::parse(source);
    assert(candidate.status == 0 && candidate.declared_depth == depth && candidate.declared_frame == frame);
    assert(public_frontend::verify(source, candidate));
}
fn rejected(source: u8[:], status: i64) {
    let candidate = public_frontend::parse(source);
    assert(candidate.status == status && candidate.core.value_count == 0);
}
fn main() {
    let identity = "pub let id: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x";
    accepted(identity, 1, 0);
    assert(frontend::parse_scalar(identity).status == 2); // v2 remains private-only.
    accepted("pub let f: U32 -> U32 ! {} resources {depth: 128, frame: 4294967295} = fn x => return 0", 128, 4294967295);
    accepted("pub let f: U32 -> Bool ! {} resources {depth: 3, frame: 64} = fn x => return x < 7", 3, 64);
    accepted("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x & 255\n", 1, 0);
    accepted("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return do:\n  break x\n", 1, 0);
    accepted("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return do:\n    return x\n", 1, 0);
    accepted("// heading\r\npub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x // comment\r\n", 1, 0);
    rejected("pub let f = fn x => return x", 1);
    rejected("pub let f: U32 -> U32 = fn x => return x", 8);
    rejected("pub let f: U32 -> U32 ! {} = fn x => return x", 8);
    rejected("pub let f: U32 -> U32 resources {depth: 1, frame: 0} = fn x => return x", 8);
    rejected("pub let f: U32 -> U32 ! {} resources {depth: 0, frame: 0} = fn x => return x", 9);
    rejected("pub let f: U32 -> U32 ! {} resources {depth: 129, frame: 0} = fn x => return x", 9);
    rejected("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 4294967296} = fn x => return x", 1);
    rejected("pub let f: U32 -> U32 ! {} resources {depth: 1} = fn x => return x", 1);
    rejected("pub let f: U32 -> U32 ! {} resources {depth:\n  1, frame: 0} = fn x => return x", 2);
    rejected("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0, frame: 0} = fn x => return x", 1);
    rejected("pub let f: U32 -> U32 ! {host} resources {depth: 1, frame: 0} = fn x => return x", 2);
    rejected("pub let f: U32 -> U32 ! {} requires [] resources {depth: 1, frame: 0} = fn x => return x", 2);
    rejected("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => return x", 7);
    rejected("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return y", 3);
    rejected("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => x", 4);
    rejected("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  break x", 6);
    rejected("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x + 0", 2);
    rejected("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\nlet y: U32 -> U32 = fn x => return x", 2);
    var candidate = public_frontend::parse(identity);
    let original = candidate;
    candidate.pub_start += 1; assert(!public_frontend::verify(identity, candidate)); candidate = original;
    candidate.effect_end += 1; assert(!public_frontend::verify(identity, candidate)); candidate = original;
    candidate.resources_start += 1; assert(!public_frontend::verify(identity, candidate)); candidate = original;
    candidate.depth_start = -1; assert(!public_frontend::verify(identity, candidate)); candidate = original;
    candidate.frame_end = identity.len + 1; assert(!public_frontend::verify(identity, candidate)); candidate = original;
    candidate.declared_depth = 2; assert(!public_frontend::verify(identity, candidate)); candidate = original;
    candidate.declared_frame = 1; assert(!public_frontend::verify(identity, candidate)); candidate = original;
    candidate.core.name_start = -1; assert(!public_frontend::verify(identity, candidate)); candidate = original;
    candidate.core.left_end += 1; assert(!public_frontend::verify(identity, candidate)); candidate = original;
    candidate.core.values[0].type_id = 2; assert(!public_frontend::verify(identity, candidate)); candidate = original;
    assert(!public_frontend::verify("pub let id: U32 -> U32 ! {} resources {depth: 1, frame: 1} = fn x => return x", candidate));
    assert(!public_frontend::verify("pub let id: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return y", candidate));
    assert(public_frontend::projected(identity, -1, 0, 0).len == 0);
    print("public scalar source candidates: passed");
}
