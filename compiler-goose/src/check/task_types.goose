// Task families are compiler-owned; scopes carry exact lexical group owners.
namespace blot_check_task_types;
import check.effects;
import check.types;
import parse.ast;
import support.error;
import support.option;
import support.structural_adapters;

import support.structural;
import std;
let group = blot_check_types::NominalIdentity { 0xffffffff, 16 , ..};
let handle = blot_check_types::NominalIdentity { 0xffffffff, 17 , ..};
let view = blot_check_types::NominalIdentity { 0xffffffff, 18 , ..};
fn isIdentity(unit: u32, decl: u32) -> bool { return unit == group.unit && decl >= group.decl && decl <= view.decl; }
fn isGroup(store, id: blot_check_types::Id) -> bool {
    let scope = store.node(id); if scope.tag != blot_check_types::Tag.scoped { return false; }
    let family = store.node(scope.a); return family.tag == blot_check_types::Tag.nominal && family.a == group.unit && family.b == group.decl;
}
fn scopeCallback(store, raw: blot_check_types::Id) -> blot_support::Option<blot_check_types::Node> {
    let usage = store.node(store.head(raw, 0));
    if usage.tag != blot_check_types::Tag.usage || usage.b != blot_parse_ast::usagekind_once || usage.c != 0 { return blot_support::Option<blot_check_types::Node> { false, default<blot_check_types::Node>() , ..}; }
    let quantified = store.node(store.head(usage.a, 0));
    if quantified.tag != blot_check_types::Tag.forall || quantified.c != 1 { return blot_support::Option<blot_check_types::Node> { false, default<blot_check_types::Node>() , ..}; }
    let binder = store.list(blot_check_types::List { quantified.b, quantified.c , ..})[0]; let bound = store.node(binder);
    if bound.tag != blot_check_types::Tag.bound || bound.b != 2 || bound.c != 0 { return blot_support::Option<blot_check_types::Node> { false, default<blot_check_types::Node>() , ..}; }
    let arrow = store.node(store.head(quantified.a, 0));
    if arrow.tag != blot_check_types::Tag.function || !isGroup(store, store.head(arrow.a, 0)) { return blot_support::Option<blot_check_types::Node> { false, default<blot_check_types::Node>() , ..}; }
    let region = store.node(store.head(arrow.a, 0));
    if region.b != 0 || region.c != binder { return blot_support::Option<blot_check_types::Node> { false, default<blot_check_types::Node>() , ..}; }
    var remaining: i64 = 4096;
    if mentionsRegion(store, arrow.b, binder, remaining, 0) || rowMentionsRegion(store, arrow.c, binder, remaining, 0) { return blot_support::Option<blot_check_types::Node> { false, default<blot_check_types::Node>() , ..}; }
    return blot_support::Option<blot_check_types::Node> { true, arrow , ..};
}
recursive fn rowMentionsRegion(store, row: blot_check_effects::Id, binder: blot_check_types::Id, remaining: i64&, depth: i64) -> bool {
    if remaining == 0 || depth >= 128 { return true; } remaining -= 1;
    for label in store.rowLabels(row) {
        let operation = store.operation(label);
        if operation.instance.unit == 0 && operation.instance.decl != 0 && mentionsRegion(store, operation.instance.decl, binder, remaining, depth + 1) { return true; }
        for argument in store.list(operation.arguments) { if mentionsRegion(store, argument, binder, remaining, depth + 1) { return true; } }
    }
    return false;
}
recursive fn mentionsRegion(store, raw: blot_check_types::Id, binder: blot_check_types::Id, remaining: i64&, depth: i64) -> bool {
    if raw == 0 { return false; } if raw == binder || remaining == 0 || depth >= 128 { return true; } remaining -= 1;
    let node = store.node(store.head(raw, 0));
    match node.tag {
        scoped => { return (node.b == 0 && mentionsRegion(store, node.c, binder, remaining, depth + 1)) || mentionsRegion(store, node.a, binder, remaining, depth + 1); },
        function => { return mentionsRegion(store, node.a, binder, remaining, depth + 1) || mentionsRegion(store, node.b, binder, remaining, depth + 1) || rowMentionsRegion(store, node.c, binder, remaining, depth + 1); },
        usage => { return mentionsRegion(store, node.a, binder, remaining, depth + 1) || mentionsRegion(store, node.c, binder, remaining, depth + 1); },
        provider => { return mentionsRegion(store, node.a, binder, remaining, depth + 1) || rowMentionsRegion(store, node.c, binder, remaining, depth + 1); },
        state_provider => { return mentionsRegion(store, node.a, binder, remaining, depth + 1) || mentionsRegion(store, node.b, binder, remaining, depth + 1) || mentionsRegion(store, node.c, binder, remaining, depth + 1); },
        array, list, cursor, resolver, forall, existential => { return mentionsRegion(store, node.a, binder, remaining, depth + 1); },
        product => { for child in store.list(blot_check_types::List { node.a, node.b , ..}) { if mentionsRegion(store, child, binder, remaining, depth + 1) { return true; } } },
        record => { for index in node.b { if mentionsRegion(store, store.recordField(node, index).ty, binder, remaining, depth + 1) { return true; } } },
        nominal, instance_selection, projection => { for child in store.nominalArguments(node) { if mentionsRegion(store, child, binder, remaining, depth + 1) { return true; } } }, _ => {},
    }
    return false;
}
fn isRegion(store, id: blot_check_types::Id) -> bool { let scope = store.node(id); if scope.tag != blot_check_types::Tag.scoped { return false; } let family = store.node(scope.a); return family.tag == blot_check_types::Tag.nominal && family.a == group.unit && (family.b == group.decl || family.b == view.decl); }
fn isHandle(store, id: blot_check_types::Id) -> bool { let wrapper = store.node(store.head(id, 0)); if wrapper.tag != blot_check_types::Tag.usage || wrapper.b != blot_parse_ast::usagekind_unique { return false; } let family = store.node(store.head(wrapper.a, 0)); return family.tag == blot_check_types::Tag.nominal && family.a == handle.unit && family.b == handle.decl; }
fn receiveResult(store: blot_check_types::Store&, raw: blot_check_types::Id, effects: blot_check_effects::Id) -> blot_support::Option<blot_check_types::Id>, blot_error::Error {
    let selected, error = store.resolve(raw, 0); if error != blot_error::Error.none { return blot_support::Option<blot_check_types::Id> { false, 0 , ..}, error; }
    let input = store.node(selected); if input.tag == blot_check_types::Tag.variable || input.tag == blot_check_types::Tag.projection { return blot_support::Option<blot_check_types::Id> { false, 0 , ..}, blot_error::Error.none; }
    var inputs: blot_check_types::Id[16] = [0; 16]; var count: i64 = 1; inputs[0] = raw;
    if input.tag == blot_check_types::Tag.product { if input.b == 0 || input.b > 16 { return blot_support::Option<blot_check_types::Id> { false, 0 , ..}, blot_error::Error.type_mismatch; } count = input.b; for value, i in store.list(blot_check_types::List { input.a, input.b , ..}) { inputs[i] = value; } }
    var results: blot_check_types::Id[16] = [0; 16]; var rows: blot_check_effects::Id[16] = [0; 16];
    for item, index in inputs[..count] {
        let id, error = store.resolve(item, 0); if error != blot_error::Error.none { return blot_support::Option<blot_check_types::Id> { false, 0 , ..}, error; } let wrapper = store.node(id);
        if wrapper.tag == blot_check_types::Tag.variable || wrapper.tag == blot_check_types::Tag.projection { return blot_support::Option<blot_check_types::Id> { false, 0 , ..}, blot_error::Error.none; }
        if !isHandle(store, id) { return blot_support::Option<blot_check_types::Id> { false, 0 , ..}, blot_error::Error.type_mismatch; }
        let arguments = store.nominalArguments(store.node(wrapper.a)); if arguments.len != 2 { return blot_support::Option<blot_check_types::Id> { false, 0 , ..}, blot_error::Error.type_mismatch; }
        let arrow = store.node(arguments[1]); if arrow.tag != blot_check_types::Tag.function || arrow.a != blot_check_types::unit { return blot_support::Option<blot_check_types::Id> { false, 0 , ..}, blot_error::Error.type_mismatch; }
        results[index] = arrow.b; rows[index] = arrow.c;
    }
    for row in rows[..count] {
        let arrow, ae = store.functionWithEffects(blot_check_types::unit, blot_check_types::unit, row); if ae != blot_error::Error.none { return blot_support::Option<blot_check_types::Id> { false, 0 , ..}, ae; }
        let opened, oe = store.openCovariant(arrow); if oe != blot_error::Error.none { return blot_support::Option<blot_check_types::Id> { false, 0 , ..}, oe; }
        let error = store.unifyEffects(store.node(opened).c, effects); if error != blot_error::Error.none { return blot_support::Option<blot_check_types::Id> { false, 0 , ..}, error; }
    }
    if input.tag == blot_check_types::Tag.product { let result, error = store.product(results[..count]); return blot_support::Option<blot_check_types::Id> { error == blot_error::Error.none, result , ..}, error; }
    return blot_support::Option<blot_check_types::Id> { true, results[0] , ..}, blot_error::Error.none;
}
struct View { payload: blot_check_types::Id, scope: blot_check_types::Id, version: blot_check_types::Id }
fn receivers(store, raw: blot_check_types::Id) -> bool {
    if isHandle(store, raw) { return true; } let input = store.node(store.head(raw, 0));
    if input.tag != blot_check_types::Tag.product || input.b == 0 || input.b > 16 { return false; }
    for item in store.list(blot_check_types::List { input.a, input.b , ..}) { if !isHandle(store, item) { return false; } } return true;
}
fn viewInfo(store, raw: blot_check_types::Id) -> blot_support::Option<View> {
    let wrapper = store.node(store.head(raw, 0)); if wrapper.tag != blot_check_types::Tag.usage || wrapper.b != blot_parse_ast::usagekind_unique { return blot_support::Option<View> { false, default<View>() , ..}; }
    let scope = store.node(store.head(wrapper.a, 0)); if scope.tag != blot_check_types::Tag.scoped { return blot_support::Option<View> { false, default<View>() , ..}; }
    let nominal = store.node(store.head(scope.a, 0)); if nominal.tag != blot_check_types::Tag.nominal || nominal.a != view.unit || nominal.b != view.decl { return blot_support::Option<View> { false, default<View>() , ..}; }
    let arguments = store.nominalArguments(nominal);
    if arguments.len != 2 || store.node(arguments[0]).tag != blot_check_types::Tag.array || store.node(arguments[1]).tag != blot_check_types::Tag.instance_version { return blot_support::Option<View> { false, default<View>() , ..}; }
    return blot_support::Option<View> { true, View { arguments[0], wrapper.a, arguments[1] , ..} , ..};
}
enum Op { scope, spawn, join, cancel, split, read, write, collect, receive }
fn lookup(name: const u8[:]) -> blot_support::Option<Op> {
    if name == "@task.scope" { return blot_support::Option<Op> { true, Op.scope , ..}; } if name == "@task.spawn" { return blot_support::Option<Op> { true, Op.spawn , ..}; }
    if name == "@task.join" { return blot_support::Option<Op> { true, Op.join , ..}; } if name == "@task.cancel" { return blot_support::Option<Op> { true, Op.cancel , ..}; }
    if name == "@task.split" { return blot_support::Option<Op> { true, Op.split , ..}; } if name == "@task.read" { return blot_support::Option<Op> { true, Op.read , ..}; }
    if name == "@task.write" { return blot_support::Option<Op> { true, Op.write , ..}; } if name == "@task.collect" { return blot_support::Option<Op> { true, Op.collect , ..}; }
    if name == "@task.receive" { return blot_support::Option<Op> { true, Op.receive , ..}; } return blot_support::Option<Op> { false, Op.scope , ..};
}
fn present(pool) -> bool { for name in ["@task.scope", "@task.spawn", "@task.join", "@task.cancel", "@task.split", "@task.read", "@task.write", "@task.collect", "@task.receive"] { let id, found = pool.lookup(name); if found { return true; } } return false; }
fn arity(op: Op) -> i64 { match op { scope, join, cancel, collect, receive => { return 1; }, spawn, read => { return 2; }, split, write => { return 3; }, } }
fn concurrentHost(store, raw: blot_check_types::Id) -> bool {
    let arrow = store.node(store.head(raw, 0)); if arrow.tag != blot_check_types::Tag.function { return false; }
    let row = store.row(arrow.c); let labels = store.rowLabels(arrow.c);
    if row.tail != blot_check_effects::Tail.closed || labels.len != 1 || labels[0] != blot_check_types::foreign_operation { return false; }
    for ty in [arrow.a, arrow.b] {
        let value = store.node(store.head(ty, 0));
        if value.tag == blot_check_types::Tag.array { let element = store.node(store.head(value.a, 0)); if element.tag != blot_check_types::Tag.unsigned32 && element.tag != blot_check_types::Tag.floating32 { return false; } }
        else if value.tag != blot_check_types::Tag.unit && value.tag != blot_check_types::Tag.unsigned32 && value.tag != blot_check_types::Tag.floating32 && value.tag != blot_check_types::Tag.boolean { return false; }
    }
    return true;
}
recursive fn readLoanData(store, raw: blot_check_types::Id, remaining: i64&, depth: i64) -> bool, blot_error::Error {
    if remaining == 0 || depth >= 128 { return false, blot_error::Error.none; } remaining -= 1;
    let node = store.node(store.head(raw, 0));
    match node.tag {
        unit, boolean, unsigned32, floating32 => { return true, blot_error::Error.none; },
        array, list => { return readLoanData(store, node.a, remaining, depth + 1); },
        product => { for child in store.list(blot_check_types::List { node.a, node.b , ..}) { let accepted, error = readLoanData(store, child, remaining, depth + 1); if error != blot_error::Error.none || !accepted { return accepted, error; } } return true, blot_error::Error.none; },
        record => { for index in node.b { let accepted, error = readLoanData(store, store.recordField(node, index).ty, remaining, depth + 1); if error != blot_error::Error.none || !accepted { return accepted, error; } } return true, blot_error::Error.none; },
        _ => { return false, blot_error::Error.none; },
    }
}
enum CaptureIssue { transfer, capability, host, budget }
fn captureIssue(store, root: blot_check_types::Id, owning: bool, remaining: i64&, depth: i64) -> blot_support::Option<CaptureIssue>, blot_error::Error { return captureIssueWithRows(store, root, owning, remaining, depth, []); }
recursive fn captureIssueWithRows(store, root: blot_check_types::Id, owning: bool, remaining: i64&, depth: i64, closed_rows: const u32[:]) -> blot_support::Option<CaptureIssue>, blot_error::Error {
    if remaining == 0 || depth >= 128 { return blot_support::Option<CaptureIssue> { true, CaptureIssue.budget , ..}, blot_error::Error.none; } remaining -= 1;
    let node = store.node(store.head(root, 0));
    match node.tag {
        variable, bound, rigid, forall, existential => { return blot_support::Option<CaptureIssue> { true, CaptureIssue.transfer , ..}, blot_error::Error.none; },
        scoped => {
            if isGroup(store, store.head(root, 0)) { return blot_support::Option<CaptureIssue> { false, CaptureIssue.transfer , ..}, blot_error::Error.none; }
            let nominal = store.node(node.a);
            if owning && nominal.tag == blot_check_types::Tag.nominal && nominal.a == view.unit && nominal.b == view.decl {
                let arguments = store.nominalArguments(nominal); if arguments.len == 2 && store.node(arguments[0]).tag == blot_check_types::Tag.array { return captureIssueWithRows(store, arguments[0], false, remaining, depth + 1, closed_rows); }
            }
            return blot_support::Option<CaptureIssue> { true, CaptureIssue.capability , ..}, blot_error::Error.none;
        },
        usage => {
            let kind = node.b;
            if kind == blot_parse_ast::usagekind_concurrent { if concurrentHost(store, node.a) { return blot_support::Option<CaptureIssue> { false, CaptureIssue.host , ..}, blot_error::Error.none; } return blot_support::Option<CaptureIssue> { true, CaptureIssue.host , ..}, blot_error::Error.none; }
            if kind == blot_parse_ast::usagekind_borrow { let read, error = readLoanData(store, node.a, remaining, depth + 1); if error != blot_error::Error.none { return blot_support::Option<CaptureIssue> { false, CaptureIssue.capability , ..}, error; } return blot_support::Option<CaptureIssue> { !read, CaptureIssue.capability , ..}, blot_error::Error.none; }
            if kind == blot_parse_ast::usagekind_borrow_mut { return blot_support::Option<CaptureIssue> { true, CaptureIssue.capability , ..}, blot_error::Error.none; }
            return captureIssueWithRows(store, node.a, kind == blot_parse_ast::usagekind_unique || kind == blot_parse_ast::usagekind_once, remaining, depth + 1, closed_rows);
        },
        function => {
            let row = store.row(node.c); if !closed(row, closed_rows) { return blot_support::Option<CaptureIssue> { true, CaptureIssue.host , ..}, blot_error::Error.none; }
            for label in store.rowLabels(node.c) { if label == blot_check_types::foreign_operation { return blot_support::Option<CaptureIssue> { true, CaptureIssue.host , ..}, blot_error::Error.none; } if store.operation(label).instance.decl != 0 { return blot_support::Option<CaptureIssue> { true, CaptureIssue.capability , ..}, blot_error::Error.none; } }
            let issue, error = captureIssueWithRows(store, node.a, false, remaining, depth + 1, closed_rows); if error != blot_error::Error.none || issue.present { return issue, error; }
            return captureIssueWithRows(store, node.b, false, remaining, depth + 1, closed_rows);
        },
        state_provider, provider => { return blot_support::Option<CaptureIssue> { true, CaptureIssue.capability , ..}, blot_error::Error.none; },
        array, list, cursor => { return captureIssueWithRows(store, node.a, owning, remaining, depth + 1, closed_rows); },
        product => { for child in store.list(blot_check_types::List { node.a, node.b , ..}) { let issue, error = captureIssueWithRows(store, child, owning, remaining, depth + 1, closed_rows); if error != blot_error::Error.none || issue.present { return issue, error; } } },
        record => { for index in node.b { let issue, error = captureIssueWithRows(store, store.recordField(node, index).ty, owning, remaining, depth + 1, closed_rows); if error != blot_error::Error.none || issue.present { return issue, error; } } },
        nominal => { for child in store.nominalArguments(node) { let issue, error = captureIssueWithRows(store, child, owning, remaining, depth + 1, closed_rows); if error != blot_error::Error.none || issue.present { return issue, error; } } }, _ => {},
    }
    return blot_support::Option<CaptureIssue> { false, CaptureIssue.transfer , ..}, blot_error::Error.none;
}
fn closed(row: blot_check_effects::Row, rows: const u32[:]) -> bool {
    match row.tail { closed => { return true; }, variable v => { for candidate in rows { if candidate == v.value { return true; } } return false; }, _ => { return false; }, }
}

fn opCode(value: Op) -> u32 {
    match value {
        scope => { return 0; },
        spawn => { return 1; },
        join => { return 2; },
        cancel => { return 3; },
        split => { return 4; },
        read => { return 5; },
        write => { return 6; },
        collect => { return 7; },
        receive => { return 8; },
    }
}
fn opFromCode(code: u32) -> Op, blot_error::Error {
    match code {
        0 => { return Op.scope, blot_error::Error.none; },
        1 => { return Op.spawn, blot_error::Error.none; },
        2 => { return Op.join, blot_error::Error.none; },
        3 => { return Op.cancel, blot_error::Error.none; },
        4 => { return Op.split, blot_error::Error.none; },
        5 => { return Op.read, blot_error::Error.none; },
        6 => { return Op.write, blot_error::Error.none; },
        7 => { return Op.collect, blot_error::Error.none; },
        8 => { return Op.receive, blot_error::Error.none; },
        _ => { return Op.scope, blot_error::Error.invalid_artifact; },
    }
}
fn blot_structural::equal(left: blot_check_task_types::Op, right: blot_check_task_types::Op) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_task_types::Op) { blot_structural::hash(sink, blot_check_task_types::opCode(value) as! u32); }
fn captureIssueCode(value: CaptureIssue) -> u32 {
    match value {
        transfer => { return 0; },
        capability => { return 1; },
        host => { return 2; },
        budget => { return 3; },
    }
}
fn captureIssueFromCode(code: u32) -> CaptureIssue, blot_error::Error {
    match code {
        0 => { return CaptureIssue.transfer, blot_error::Error.none; },
        1 => { return CaptureIssue.capability, blot_error::Error.none; },
        2 => { return CaptureIssue.host, blot_error::Error.none; },
        3 => { return CaptureIssue.budget, blot_error::Error.none; },
        _ => { return CaptureIssue.transfer, blot_error::Error.invalid_artifact; },
    }
}
fn blot_structural::equal(left: blot_check_task_types::CaptureIssue, right: blot_check_task_types::CaptureIssue) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_task_types::CaptureIssue) { blot_structural::hash(sink, blot_check_task_types::captureIssueCode(value) as! u8); }




