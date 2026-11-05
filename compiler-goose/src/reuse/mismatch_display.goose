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
    if !context.identity.present { if diagnostic_origin.len == 0 { return false, Error.none; } output.append(diagnostic_origin); return true, Error.none; }
    if owner != 0 && owner == context.prelude { output.append("std/prelude"); return true, Error.none; }
    if context.source_mode && owner == context.entry { output.append("main"); return true, Error.none; }
    let current = context.identity.value; let entry_path = current.owner(context.entry); let owner_path = current.owner(owner);
    if !entry_path.present || !owner_path.present { return false, Error.none; }
    let directory = blot_support_path::dirname(entry_path.value); if !directory.present { return false, Error.none; }
    let start = output.len; let error = blot_support_path::relative(directory.value, owner_path.value, output);
    if error != Error.none { output.resize(start); return false, error; } return output.len != start, Error.none;
}
fn number(self: Display&, value: u32) {
    var buffer: u8[10] = [0; 10]; var index: i64 = 10; var rest = value;
    loop { index--; buffer[index] = ('0' + rest % 10) as u8; rest /= 10; if rest == 0 { break; } }
    self.text.append(buffer[index..]);
}
fn nominal(self: Display&, owner: u32, declaration: u32) -> bool, Error {
    var module: const blot_check_core::Module? = null;
    for &candidate, index in self.context.units { var unit = candidate.unit; if unit == 0 { unit = (index + 1) as u32; } if unit == owner { module .= candidate; break; } }
    if !module { return false, Error.none; }
    var found = false; var item = default<blot_check_core::Nominal>();
    for candidate in module.nominals { if candidate.identity.decl == declaration && (candidate.identity.unit == 0 || candidate.identity.unit == owner) { item = candidate; found = true; break; } }
    if !found { return false, Error.none; }
    let name = module.name(item.diagnostic_name); if name.len == 0 { return false, Error.none; }
    let present, error = origin(self.context, owner, module.name(item.diagnostic_origin), self.text);
    if error != Error.none || !present { return false, error; }
    self.text.append("::"); self.text.append(name); return true, Error.none;
}
recursive fn row(self: Display&, id: u32, depth: u8) -> bool, Error {
    let value = self.store.row(id); let labels = self.store.rowLabels(id);
    if labels.len == 0 && value.tail == blot_check_effects::Tail.closed { return true, Error.none; }
    self.text.append(" ! {");
    for label, index in labels {
        if index != 0 { self.text.append(", "); } let operation = self.store.operation(label);
        let named, error = self.nominal(operation.identity.unit, operation.identity.decl); if error != Error.none || !named { return false, error; }
        if operation.instance.decl != 0 { self.text.append(" @scope"); self.number(operation.instance.unit); self.text.push(':'); self.number(operation.instance.decl); }
        for argument in self.store.operationArguments(label) { self.text.append(" ("); let shown, failure = self.ty(argument, depth); if failure != Error.none || !shown { return false, failure; } self.text.push(')'); }
    }
    match value.tail {
        blot_check_effects::Tail.closed => {},
        blot_check_effects::Tail.variable variable => { self.text.append("| ?e"); self.number(variable.value); },
        blot_check_effects::Tail.parameter => { return false, Error.none; },
        blot_check_effects::Tail.formal formal => { self.text.append("| "); let shown, error = self.ty(formal.value, depth); if error != Error.none || !shown { return false, error; } },
    }
    self.text.push('}'); return true, Error.none;
}
recursive fn ty(self: Display&, id: u32, depth: u8) -> bool, Error {
    if depth == 0 { self.text.append("..."); return true, Error.none; } let value = self.store.node(id);
    match value.tag {
        blot_check_types::Tag.scoped => { let shown, error = self.ty(value.a, depth - 1); if error != Error.none || !shown { return false, error; } self.text.append(" @scope"); self.number(value.b); self.text.push(':'); self.number(value.c); },
        blot_check_types::Tag.unit => { self.text.append("Unit"); }, blot_check_types::Tag.boolean => { self.text.append("Bool"); },
        blot_check_types::Tag.unsigned32 => { self.text.append("U32"); }, blot_check_types::Tag.floating32 => { self.text.append("F32"); },
        blot_check_types::Tag.never => { self.text.append("Never"); }, blot_check_types::Tag.variable => { self.text.push('?'); self.number(value.a); },
        blot_check_types::Tag.function => {
            self.text.push('('); let a, first = self.ty(value.a, depth - 1); if first != Error.none || !a { return false, first; }
            self.text.append(" -> "); let b, second = self.ty(value.b, depth - 1); if second != Error.none || !b { return false, second; }
            let r, third = self.row(value.c, depth - 1); if third != Error.none || !r { return false, third; } self.text.push(')');
        },
        blot_check_types::Tag.array, blot_check_types::Tag.list, blot_check_types::Tag.cursor => {
            if value.tag == blot_check_types::Tag.cursor { self.text.append("Cursor ("); } else if value.tag == blot_check_types::Tag.list { self.text.append("List ("); } else { self.text.append("Array ("); }
            let shown, error = self.ty(value.a, depth - 1); if error != Error.none || !shown { return false, error; } self.text.push(')');
        },
        blot_check_types::Tag.product => {
            self.text.push('('); for child, index in self.store.list(blot_check_types::List { value.a, value.b , ..}) { if index != 0 { self.text.append(", "); } let shown, error = self.ty(child, depth - 1); if error != Error.none || !shown { return false, error; } } self.text.push(')');
        },
        blot_check_types::Tag.nominal => {
            let named, error = self.nominal(value.a, value.b); if error != Error.none || !named { return false, error; }
            for argument in self.store.nominalArguments(value) { self.text.append(" ("); let shown, failure = self.ty(argument, depth - 1); if failure != Error.none || !shown { return false, failure; } self.text.push(')'); }
        }, _ => { return false, Error.none; },
    }
    return true, Error.none;
}
fn render(store: const blot_check_types::Store&, context: Context, actual: u32, expected: u32, output: u8[>..<]&) -> bool, Error {
    let start = output.len; var display = Display { store, context, output , ..}; output.append("cannot unify ");
    let left, first = display.ty(actual, 64); if first != Error.none || !left { output.resize(start); return false, first; }
    output.append(" with "); let right, second = display.ty(expected, 64); if second != Error.none || !right { output.resize(start); return false, second; }
    return true, Error.none;
}
