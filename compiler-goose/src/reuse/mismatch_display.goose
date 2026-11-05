// Diagnostic spelling observes resolved types; it never asks the solver a question.
namespace blot_reuse_mismatch_display;
import std;
import check.core;
import check.types;
import check.effects;
import backend.runtime_identity;
import support.option;
import support.error;
import support.path;
type Error = blot_error::Error;
struct Context {
    units: const blot_check_core::Module[:], identity: blot_support::Option<blot_backend_runtime_identity::View>,
    entry: u32 = 0, prelude: u32 = 0, source_mode: bool = false,
}
struct Display { store: const blot_check_types::Store&, context: Context, text: u8[>..<]& }
fn origin(context: Context, owner: u32, diagnostic_origin: const u8[:], output: u8[>..<]&) -> bool, Error {
    if !context.identity.present { if diagnostic_origin.len == 0 { return false, blot_error::Error.none; } output.append(diagnostic_origin); return true, blot_error::Error.none; }
    if owner != 0 && owner == context.prelude { output.append("std/prelude"); return true, blot_error::Error.none; }
    if context.source_mode && owner == context.entry { output.append("main"); return true, blot_error::Error.none; }
    let current = context.identity.value; let entry_path = current.owner(context.entry); let owner_path = current.owner(owner);
    if !entry_path.present || !owner_path.present { return false, blot_error::Error.none; }
    let directory = blot_support_path::dirname(entry_path.value); if !directory.present { return false, blot_error::Error.none; }
    let start = output.len; let error = blot_support_path::relative(directory.value, owner_path.value, output);
    if error != blot_error::Error.none { output.resize(start); return false, error; } return output.len != start, blot_error::Error.none;
}
fn number(self_: Display&, value: u32) {
    var buffer: u8[10] = [0; 10]; var index: i64 = 10; var rest = value;
    loop { index--; buffer[index] = ('0' + rest % 10) as u8; rest /= 10; if rest == 0 { break; } }
    self_.text.append(buffer[index..]);
}
fn nominal(self_: Display&, owner: u32, declaration: u32) -> bool, Error {
    var module: const blot_check_core::Module? = null;
    for &candidate, index in self_.context.units { var unit = candidate.unit; if unit == 0 { unit = (index + 1) as u32; } if unit == owner { module .= candidate; break; } }
    if !module { return false, blot_error::Error.none; }
    var found = false; var item = default<blot_check_core::Nominal>();
    for candidate in module.nominals { if candidate.identity.decl == declaration && (candidate.identity.unit == 0 || candidate.identity.unit == owner) { item = candidate; found = true; break; } }
    if !found { return false, blot_error::Error.none; }
    let name = module.name(item.diagnostic_name); if name.len == 0 { return false, blot_error::Error.none; }
    let present, error = origin(self_.context, owner, module.name(item.diagnostic_origin), self_.text);
    if error != blot_error::Error.none || !present { return false, error; }
    self_.text.append("::"); self_.text.append(name); return true, blot_error::Error.none;
}
recursive fn row(self_: Display&, id: u32, depth: u8) -> bool, Error {
    let value = self_.store.row(id); let labels = self_.store.rowLabels(id);
    if labels.len == 0 && value.tail == blot_check_effects::Tail.closed { return true, blot_error::Error.none; }
    self_.text.append(" ! {");
    for label, index in labels {
        if index != 0 { self_.text.append(", "); } let operation = self_.store.operation(label);
        let named, error = self_.nominal(operation.identity.unit, operation.identity.decl); if error != blot_error::Error.none || !named { return false, error; }
        if operation.instance.decl != 0 { self_.text.append(" @scope"); self_.number(operation.instance.unit); self_.text.push(':'); self_.number(operation.instance.decl); }
        for argument in self_.store.operationArguments(label) { self_.text.append(" ("); let shown, failure = self_.ty(argument, depth); if failure != blot_error::Error.none || !shown { return false, failure; } self_.text.push(')'); }
    }
    match value.tail {
        closed => {},
        variable variable => { self_.text.append("| ?e"); self_.number(variable.value); },
        parameter => { return false, blot_error::Error.none; },
        formal formal => { self_.text.append("| "); let shown, error = self_.ty(formal.value, depth); if error != blot_error::Error.none || !shown { return false, error; } },
    }
    self_.text.push('}'); return true, blot_error::Error.none;
}
recursive fn ty(self_: Display&, id: u32, depth: u8) -> bool, Error {
    if depth == 0 { self_.text.append("..."); return true, blot_error::Error.none; } let value = self_.store.node(id);
    match value.tag {
        scoped => { let shown, error = self_.ty(value.a, depth - 1); if error != blot_error::Error.none || !shown { return false, error; } self_.text.append(" @scope"); self_.number(value.b); self_.text.push(':'); self_.number(value.c); },
        unit => { self_.text.append("Unit"); }, boolean => { self_.text.append("Bool"); },
        unsigned32 => { self_.text.append("U32"); }, floating32 => { self_.text.append("F32"); },
        never => { self_.text.append("Never"); }, variable => { self_.text.push('?'); self_.number(value.a); },
        function => {
            self_.text.push('('); let a, first = self_.ty(value.a, depth - 1); if first != blot_error::Error.none || !a { return false, first; }
            self_.text.append(" -> "); let b, second = self_.ty(value.b, depth - 1); if second != blot_error::Error.none || !b { return false, second; }
            let r, third = self_.row(value.c, depth - 1); if third != blot_error::Error.none || !r { return false, third; } self_.text.push(')');
        },
        array, list, cursor => {
            if value.tag == blot_check_types::Tag.cursor { self_.text.append("Cursor ("); } else if value.tag == blot_check_types::Tag.list { self_.text.append("List ("); } else { self_.text.append("Array ("); }
            let shown, error = self_.ty(value.a, depth - 1); if error != blot_error::Error.none || !shown { return false, error; } self_.text.push(')');
        },
        product => {
            self_.text.push('('); for child, index in self_.store.list(blot_check_types::List { value.a, value.b , ..}) { if index != 0 { self_.text.append(", "); } let shown, error = self_.ty(child, depth - 1); if error != blot_error::Error.none || !shown { return false, error; } } self_.text.push(')');
        },
        nominal => {
            let named, error = self_.nominal(value.a, value.b); if error != blot_error::Error.none || !named { return false, error; }
            for argument in self_.store.nominalArguments(value) { self_.text.append(" ("); let shown, failure = self_.ty(argument, depth - 1); if failure != blot_error::Error.none || !shown { return false, failure; } self_.text.push(')'); }
        }, _ => { return false, blot_error::Error.none; },
    }
    return true, blot_error::Error.none;
}
fn render(store: const blot_check_types::Store&, context: Context, actual: u32, expected: u32, output: u8[>..<]&) -> bool, Error {
    let start = output.len; var display = Display { store, context, output , ..}; output.append("cannot unify ");
    let left, first = display.ty(actual, 64); if first != blot_error::Error.none || !left { output.resize(start); return false, first; }
    output.append(" with "); let right, second = display.ty(expected, 64); if second != blot_error::Error.none || !right { output.resize(start); return false, second; }
    return true, blot_error::Error.none;
}
