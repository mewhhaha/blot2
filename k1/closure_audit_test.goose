// Independent fixture checks. The source/contract records remain private and
// do not establish a general K1 closure, lifetime, or artifact contract.
import closure_core;
import closure_parse;
import closure_validate;
import closure_wasm;
import closure_resources;

fn advance(fs: closure_resources::Fn[:], i: i64) -> i64 {
    if i < 0 { return -1; }
    let callee = fs[i].callee;
    return if callee == 0 { -1 } else { callee - 1 };
}
// Independent Floyd cycle walk, followed by a separate resource comparison.
// The tested inputs have valid indices and finite depth; malformed cases are
// covered by the main closure tests.
fn oracle(fs: closure_resources::Fn[:]) -> u32 {
    for start in fs.len {
        var slow = advance(fs,start);
        var fast = advance(fs,advance(fs,start));
        while slow >= 0 && fast >= 0 && slow != fast {
            slow = advance(fs,slow); fast = advance(fs,advance(fs,fast));
        }
        if slow < 0 || fast < 0 { continue; }
        var entry = start;
        while entry != slow { entry = advance(fs,entry); slow = advance(fs,slow); }
        var cursor = entry; var indirect = false;
        loop {
            indirect = indirect || fs[cursor].indirect;
            cursor = advance(fs,cursor);
            if cursor == entry { break; }
        }
        return if indirect { 3 } else { 2 };
    }
    for f in fs {
        if f.callee == 0 { if f.own > f.frame { return 3; } }
        else {
            let child = fs[f.callee - 1];
            if (child.depth as u64) + 1 > f.depth || (f.own as u64) + child.frame > f.frame { return 3; }
        }
    }
    return 0;
}
fn random(seed: u32&) -> u32 { seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5; return seed; }
fn main() {
    let source = "let f: (U32,U32)->U32 = fn (c,a) => do:\n  let g = fn x => return x & c\n  return g(a)\n";
    var original, status = closure_parse::parse(source);
    assert(status == 0 && closure_validate::verify(source,original));
    // Change the stored source and authoritative comparison input together so
    // the rejection comes from lexical binding checks, not a byte mismatch.
    let spans = [original.capture_use, original.inner_use, original.binding_use,
                 original.argument_use, original.capture, original.argument,
                 original.binding, original.parameter];
    for span in spans {
        for replacement in ['c','a','g','x','f','?'] {
            if source[span.start] == replacement { continue; }
            var forged = copy(original); var changed: u8[>..] = []; changed.append(source);
            changed[span.start] = replacement as u8; forged.source[span.start] = replacement as u8;
            assert(!closure_validate::verify(changed,forged));
            assert(closure_wasm::emit(changed,forged).len == 0);
        }
    }
    var seed: u32 = 0x8aa5c913;
    for trial in 1200 {
        let n = 1 + random(seed) % 16;
        var fs: closure_resources::Fn[>..] = [];
        for i in n {
            let callee = random(seed) % (n + 1);
            let depth = 1 + random(seed) % 128;
            let own = if random(seed) % 12 == 0 { 4294967295 } else { random(seed) % 32 };
            let frame = if random(seed) % 12 == 0 { 4294967295 } else { random(seed) % 64 };
            let indirect = callee != 0 && random(seed) % 2 == 0;
            fs.push(closure_resources::Fn { own: own, frame: frame, depth: depth, callee: callee, indirect: indirect });
        }
        assert(closure_resources::validate(fs) == oracle(fs));
    }
    print("independent closure binding and resource oracle passed");
}
