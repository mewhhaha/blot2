// Storage operations remain explicit through Core and ownership planning.
namespace blot_check_storage_ops;
import support.error;
import support.option;
import support.structural_adapters;

import support.structural;
import std;
enum Op { ref, at, link, view, load, length, read, push, pop, truncate, copy, share, with_capacity, reserve, extend, push_front, pop_front, insert, remove, reverse, split, concat, slice, repeat, ramp, from_frozen }
fn lookup(name: const u8[:]) -> blot_support::Option<Op> {
    if !starts_with(name, "@storage.") { return blot_support::Option<Op> { false, Op.ref , ..}; }
    let tail = name[9..];
    if tail == "ref" { return blot_support::Option<Op> { true, Op.ref , ..}; }
    if tail == "at" { return blot_support::Option<Op> { true, Op.at , ..}; }
    if tail == "link" { return blot_support::Option<Op> { true, Op.link , ..}; }
    if tail == "view" { return blot_support::Option<Op> { true, Op.view , ..}; }
    if tail == "load" { return blot_support::Option<Op> { true, Op.load , ..}; }
    if tail == "length" { return blot_support::Option<Op> { true, Op.length , ..}; }
    if tail == "read" { return blot_support::Option<Op> { true, Op.read , ..}; }
    if tail == "push" { return blot_support::Option<Op> { true, Op.push , ..}; }
    if tail == "pop" { return blot_support::Option<Op> { true, Op.pop , ..}; }
    if tail == "truncate" { return blot_support::Option<Op> { true, Op.truncate , ..}; }
    if tail == "copy" { return blot_support::Option<Op> { true, Op.copy , ..}; }
    if tail == "share" { return blot_support::Option<Op> { true, Op.share , ..}; }
    if tail == "with_capacity" { return blot_support::Option<Op> { true, Op.with_capacity , ..}; }
    if tail == "reserve" { return blot_support::Option<Op> { true, Op.reserve , ..}; }
    if tail == "extend" { return blot_support::Option<Op> { true, Op.extend , ..}; }
    if tail == "push_front" { return blot_support::Option<Op> { true, Op.push_front , ..}; }
    if tail == "pop_front" { return blot_support::Option<Op> { true, Op.pop_front , ..}; }
    if tail == "insert" { return blot_support::Option<Op> { true, Op.insert , ..}; }
    if tail == "remove" { return blot_support::Option<Op> { true, Op.remove , ..}; }
    if tail == "reverse" { return blot_support::Option<Op> { true, Op.reverse , ..}; }
    if tail == "split" { return blot_support::Option<Op> { true, Op.split , ..}; }
    if tail == "concat" { return blot_support::Option<Op> { true, Op.concat , ..}; }
    if tail == "slice" { return blot_support::Option<Op> { true, Op.slice , ..}; }
    if tail == "repeat" { return blot_support::Option<Op> { true, Op.repeat , ..}; }
    if tail == "ramp" { return blot_support::Option<Op> { true, Op.ramp , ..}; }
    if tail == "from_frozen" { return blot_support::Option<Op> { true, Op.from_frozen , ..}; }
    return blot_support::Option<Op> { false, Op.ref , ..};
}
fn arity(op: Op) -> u32 {
    match op {
        ref, load, length, pop, copy, share, with_capacity, pop_front, reverse, from_frozen => { return 1; },
        at, link, read, push, truncate, reserve, extend, push_front, remove, split, concat, repeat => { return 2; },
        view, insert, slice, ramp => { return 3; },
    }
}
fn writes(op: Op) -> bool {
    match op { push, pop, truncate, share, reserve, extend, push_front, pop_front, insert, remove => { return true; }, _ => { return false; }, }
}

fn opCode(value: Op) -> u32 {
    match value {
        ref => { return 0; },
        at => { return 1; },
        link => { return 2; },
        view => { return 3; },
        load => { return 4; },
        length => { return 5; },
        read => { return 6; },
        push => { return 7; },
        pop => { return 8; },
        truncate => { return 9; },
        reserve => { return 10; },
        copy => { return 11; },
        extend => { return 12; },
        share => { return 13; },
        with_capacity => { return 14; },
        push_front => { return 15; },
        pop_front => { return 16; },
        insert => { return 17; },
        remove => { return 18; },
        reverse => { return 19; },
        split => { return 20; },
        concat => { return 21; },
        slice => { return 22; },
        repeat => { return 23; },
        ramp => { return 24; },
        from_frozen => { return 25; },
    }
}
fn opFromCode(code: u32) -> Op, blot_error::Error {
    match code {
        0 => { return Op.ref, blot_error::Error.none; },
        1 => { return Op.at, blot_error::Error.none; },
        2 => { return Op.link, blot_error::Error.none; },
        3 => { return Op.view, blot_error::Error.none; },
        4 => { return Op.load, blot_error::Error.none; },
        5 => { return Op.length, blot_error::Error.none; },
        6 => { return Op.read, blot_error::Error.none; },
        7 => { return Op.push, blot_error::Error.none; },
        8 => { return Op.pop, blot_error::Error.none; },
        9 => { return Op.truncate, blot_error::Error.none; },
        10 => { return Op.reserve, blot_error::Error.none; },
        11 => { return Op.copy, blot_error::Error.none; },
        12 => { return Op.extend, blot_error::Error.none; },
        13 => { return Op.share, blot_error::Error.none; },
        14 => { return Op.with_capacity, blot_error::Error.none; },
        15 => { return Op.push_front, blot_error::Error.none; },
        16 => { return Op.pop_front, blot_error::Error.none; },
        17 => { return Op.insert, blot_error::Error.none; },
        18 => { return Op.remove, blot_error::Error.none; },
        19 => { return Op.reverse, blot_error::Error.none; },
        20 => { return Op.split, blot_error::Error.none; },
        21 => { return Op.concat, blot_error::Error.none; },
        22 => { return Op.slice, blot_error::Error.none; },
        23 => { return Op.repeat, blot_error::Error.none; },
        24 => { return Op.ramp, blot_error::Error.none; },
        25 => { return Op.from_frozen, blot_error::Error.none; },
        _ => { return Op.ref, blot_error::Error.invalid_artifact; },
    }
}

fn blot_structural::equal(left: blot_check_storage_ops::Op, right: blot_check_storage_ops::Op) -> bool { return left == right; }
fn blot_check_storage_ops::blotStructuralHash<S>(value: blot_check_storage_ops::Op,sink: S&) { blot_structural::hash(sink, blot_check_storage_ops::opCode(value) as! u32); }
