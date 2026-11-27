// Storage operations remain explicit through Core and ownership planning.
namespace squid_check_storage_ops;
import support.error;
import support.option;
import support.structural_adapters;

import support.structural;
import std;
enum Op { ref, at, link, view, load, length, read, push, pop, truncate, copy, share, with_capacity, reserve, extend, push_front, pop_front, insert, remove, reverse, split, concat, slice, repeat, ramp, from_frozen }
fn lookup(name: const u8[:]) -> squid_support::Option<Op> {
    if !starts_with(name, "@storage.") { return squid_support::Option<Op> { false, Op.ref , ..}; }
    let tail = name[9..];
    if tail == "ref" { return squid_support::Option<Op> { true, Op.ref , ..}; }
    if tail == "at" { return squid_support::Option<Op> { true, Op.at , ..}; }
    if tail == "link" { return squid_support::Option<Op> { true, Op.link , ..}; }
    if tail == "view" { return squid_support::Option<Op> { true, Op.view , ..}; }
    if tail == "load" { return squid_support::Option<Op> { true, Op.load , ..}; }
    if tail == "length" { return squid_support::Option<Op> { true, Op.length , ..}; }
    if tail == "read" { return squid_support::Option<Op> { true, Op.read , ..}; }
    if tail == "push" { return squid_support::Option<Op> { true, Op.push , ..}; }
    if tail == "pop" { return squid_support::Option<Op> { true, Op.pop , ..}; }
    if tail == "truncate" { return squid_support::Option<Op> { true, Op.truncate , ..}; }
    if tail == "copy" { return squid_support::Option<Op> { true, Op.copy , ..}; }
    if tail == "share" { return squid_support::Option<Op> { true, Op.share , ..}; }
    if tail == "with_capacity" { return squid_support::Option<Op> { true, Op.with_capacity , ..}; }
    if tail == "reserve" { return squid_support::Option<Op> { true, Op.reserve , ..}; }
    if tail == "extend" { return squid_support::Option<Op> { true, Op.extend , ..}; }
    if tail == "push_front" { return squid_support::Option<Op> { true, Op.push_front , ..}; }
    if tail == "pop_front" { return squid_support::Option<Op> { true, Op.pop_front , ..}; }
    if tail == "insert" { return squid_support::Option<Op> { true, Op.insert , ..}; }
    if tail == "remove" { return squid_support::Option<Op> { true, Op.remove , ..}; }
    if tail == "reverse" { return squid_support::Option<Op> { true, Op.reverse , ..}; }
    if tail == "split" { return squid_support::Option<Op> { true, Op.split , ..}; }
    if tail == "concat" { return squid_support::Option<Op> { true, Op.concat , ..}; }
    if tail == "slice" { return squid_support::Option<Op> { true, Op.slice , ..}; }
    if tail == "repeat" { return squid_support::Option<Op> { true, Op.repeat , ..}; }
    if tail == "ramp" { return squid_support::Option<Op> { true, Op.ramp , ..}; }
    if tail == "from_frozen" { return squid_support::Option<Op> { true, Op.from_frozen , ..}; }
    return squid_support::Option<Op> { false, Op.ref , ..};
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
fn opFromCode(code: u32) -> Op, squid_error::Error {
    match code {
        0 => { return Op.ref, squid_error::Error.none; },
        1 => { return Op.at, squid_error::Error.none; },
        2 => { return Op.link, squid_error::Error.none; },
        3 => { return Op.view, squid_error::Error.none; },
        4 => { return Op.load, squid_error::Error.none; },
        5 => { return Op.length, squid_error::Error.none; },
        6 => { return Op.read, squid_error::Error.none; },
        7 => { return Op.push, squid_error::Error.none; },
        8 => { return Op.pop, squid_error::Error.none; },
        9 => { return Op.truncate, squid_error::Error.none; },
        10 => { return Op.reserve, squid_error::Error.none; },
        11 => { return Op.copy, squid_error::Error.none; },
        12 => { return Op.extend, squid_error::Error.none; },
        13 => { return Op.share, squid_error::Error.none; },
        14 => { return Op.with_capacity, squid_error::Error.none; },
        15 => { return Op.push_front, squid_error::Error.none; },
        16 => { return Op.pop_front, squid_error::Error.none; },
        17 => { return Op.insert, squid_error::Error.none; },
        18 => { return Op.remove, squid_error::Error.none; },
        19 => { return Op.reverse, squid_error::Error.none; },
        20 => { return Op.split, squid_error::Error.none; },
        21 => { return Op.concat, squid_error::Error.none; },
        22 => { return Op.slice, squid_error::Error.none; },
        23 => { return Op.repeat, squid_error::Error.none; },
        24 => { return Op.ramp, squid_error::Error.none; },
        25 => { return Op.from_frozen, squid_error::Error.none; },
        _ => { return Op.ref, squid_error::Error.invalid_artifact; },
    }
}

fn squid_structural::equal(left: squid_check_storage_ops::Op, right: squid_check_storage_ops::Op) -> bool { return left == right; }
fn squid_check_storage_ops::squidStructuralHash<S>(value: squid_check_storage_ops::Op,sink: S&) { squid_structural::hash(sink, squid_check_storage_ops::opCode(value) as! u32); }
