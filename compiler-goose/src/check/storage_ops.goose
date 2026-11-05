// Storage operations remain explicit through Core and ownership planning.
namespace blot_check_storage_ops;
import support.error;
import support.option;
import support.structural_adapters;

import support.structural;
import std;
enum Op { ref, at, link, view, load, write, length, read, push, pop, truncate, freeze, copy, reserve }
fn lookup(name: const u8[:]) -> blot_support::Option<Op> {
    if !starts_with(name, "@storage.") { return blot_support::Option<Op> { false, Op.ref , ..}; }
    let tail = name[9..];
    if tail == "ref" { return blot_support::Option<Op> { true, Op.ref , ..}; }
    if tail == "at" { return blot_support::Option<Op> { true, Op.at , ..}; }
    if tail == "link" { return blot_support::Option<Op> { true, Op.link , ..}; }
    if tail == "view" { return blot_support::Option<Op> { true, Op.view , ..}; }
    if tail == "load" { return blot_support::Option<Op> { true, Op.load , ..}; }
    if tail == "write" { return blot_support::Option<Op> { true, Op.write , ..}; }
    if tail == "length" { return blot_support::Option<Op> { true, Op.length , ..}; }
    if tail == "read" { return blot_support::Option<Op> { true, Op.read , ..}; }
    if tail == "push" { return blot_support::Option<Op> { true, Op.push , ..}; }
    if tail == "pop" { return blot_support::Option<Op> { true, Op.pop , ..}; }
    if tail == "truncate" { return blot_support::Option<Op> { true, Op.truncate , ..}; }
    if tail == "freeze" { return blot_support::Option<Op> { true, Op.freeze , ..}; }
    if tail == "copy" { return blot_support::Option<Op> { true, Op.copy , ..}; }
    if tail == "reserve" { return blot_support::Option<Op> { true, Op.reserve , ..}; }
    return blot_support::Option<Op> { false, Op.ref , ..};
}
fn arity(op: Op) -> u32 {
    match op {
        ref, load, length, pop, freeze, copy => { return 1; },
        at, link, write, read, push, truncate, reserve => { return 2; },
        view => { return 3; },
    }
}
fn writes(op: Op) -> bool {
    match op { write, push, pop, truncate, freeze, reserve => { return true; }, _ => { return false; }, }
}

fn opCode(value: Op) -> u32 {
    match value {
        ref => { return 0; },
        at => { return 1; },
        link => { return 2; },
        view => { return 3; },
        load => { return 4; },
        write => { return 5; },
        length => { return 6; },
        read => { return 7; },
        push => { return 8; },
        pop => { return 9; },
        truncate => { return 10; },
        freeze => { return 11; },
        copy => { return 12; },
        reserve => { return 13; },
    }
}
fn opFromCode(code: u32) -> Op, blot_error::Error {
    match code {
        0 => { return Op.ref, blot_error::Error.none; },
        1 => { return Op.at, blot_error::Error.none; },
        2 => { return Op.link, blot_error::Error.none; },
        3 => { return Op.view, blot_error::Error.none; },
        4 => { return Op.load, blot_error::Error.none; },
        5 => { return Op.write, blot_error::Error.none; },
        6 => { return Op.length, blot_error::Error.none; },
        7 => { return Op.read, blot_error::Error.none; },
        8 => { return Op.push, blot_error::Error.none; },
        9 => { return Op.pop, blot_error::Error.none; },
        10 => { return Op.truncate, blot_error::Error.none; },
        11 => { return Op.freeze, blot_error::Error.none; },
        12 => { return Op.copy, blot_error::Error.none; },
        13 => { return Op.reserve, blot_error::Error.none; },
        _ => { return Op.ref, blot_error::Error.invalid_artifact; },
    }
}

fn blot_structural::equal(left: blot_check_storage_ops::Op, right: blot_check_storage_ops::Op) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_storage_ops::Op) { blot_structural::hash(sink, blot_check_storage_ops::opCode(value) as! u32); }
