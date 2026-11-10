// Successful root conversions belong to this exact pair of immutable owners.
namespace blot_backend_layout_bridge;
import .layout;
import .optimizer_buffers;
import eval.type_evidence;
import reuse.code_expectation;
import support.error;
import support.option;
let missing: u32 = 4294967295;
struct Tables { partial: blot_reuse_code_expectation::Store&,to: blot_backend_optimizer_buffers::Words&,from: blot_backend_optimizer_buffers::Words&,row_to: blot_backend_optimizer_buffers::Words&,row_from: blot_backend_optimizer_buffers::Words&,shapes: blot_backend_optimizer_buffers::Words& }
struct Store {
    layouts: blot_backend_layout::Store&? = null,semantic: blot_eval_type_evidence::Store&? = null,partial: blot_reuse_code_expectation::Store&,
    to: blot_backend_optimizer_buffers::Words&,from: blot_backend_optimizer_buffers::Words&,row_to: blot_backend_optimizer_buffers::Words&,row_from: blot_backend_optimizer_buffers::Words&,shapes: blot_backend_optimizer_buffers::Words&,
}
fn init(tables: Tables) -> Store { Store { partial: tables.partial,to: tables.to,from: tables.from,row_to: tables.row_to,row_from: tables.row_from,shapes: tables.shapes } }
fn bind(store: Store&,layouts: blot_backend_layout::Store&,semantic: blot_eval_type_evidence::Store&) -> blot_error::Error {
    deinit(store); let error=store.partial.reset(); if error != blot_error::Error.none { return error; } store.layouts .= layouts; store.semantic .= semantic; return blot_error::Error.none;
}
fn deinit(store: Store&) { store.partial.deinit(); store.to.clear(); store.from.clear(); store.row_to.clear(); store.row_from.clear(); store.shapes.clear(); store.layouts .= null; store.semantic .= null; }
fn lookup(table: const u32[:],id: u32) -> blot_support::Option<u32> { if id >= table.len || table[id] == missing { return blot_support::none<u32>(); } return blot_support::some(table[id]); }
fn publish(table: blot_backend_optimizer_buffers::Words&,id: u32,result: u32) -> blot_error::Error { if id >= table.len { let error=table.resize((id as i64)+1,missing); if error!=blot_error::Error.none {return error;} } table.items[id] = result; return blot_error::Error.none; }
fn toEvidence(store: Store&,id: u32) -> u32,blot_error::Error {
    if id >= 1 && id <= 5 { return id,blot_error::Error.none; } let known = lookup(store.to.items,id); if known.present { return known.value,blot_error::Error.none; }
    let layouts:blot_backend_layout::Store? .= store.layouts;let semantic:blot_eval_type_evidence::Store? .= store.semantic;assert(layouts);assert(semantic); let result,error = layouts.toEvidence(semantic,id); if error != blot_error::Error.none { return 0,error; } let published=publish(store.to,id,result); if published!=blot_error::Error.none {return 0,published;} return result,blot_error::Error.none;
}
fn fromEvidence(store: Store&,id: u32) -> u32,blot_error::Error {
    if id >= 1 && id <= 5 { return id,blot_error::Error.none; } let known = lookup(store.from.items,id); if known.present { return known.value,blot_error::Error.none; }
    let layouts:blot_backend_layout::Store? .= store.layouts;let semantic:blot_eval_type_evidence::Store? .= store.semantic;assert(layouts);assert(semantic); let result,error = layouts.fromEvidence(semantic.view(),id); if error != blot_error::Error.none { return 0,error; }
    // Canonical semantic record order cannot publish a physical inverse.
    let published=publish(store.from,id,result); if published!=blot_error::Error.none {return 0,published;} return result,blot_error::Error.none;
}
fn rowToEvidence(store: Store&,row: u32) -> u32,blot_error::Error {
    if row == 0 { return 0,blot_error::Error.none; } let known = lookup(store.row_to.items,row); if known.present { return known.value,blot_error::Error.none; }
    let layouts:blot_backend_layout::Store? .= store.layouts;let semantic:blot_eval_type_evidence::Store? .= store.semantic;assert(layouts);assert(semantic); let result,error = layouts.rowToEvidence(semantic,row); if error != blot_error::Error.none { return 0,error; } let published=publish(store.row_to,row,result); if published!=blot_error::Error.none {return 0,published;} return result,blot_error::Error.none;
}
fn rowFromEvidence(store: Store&,row: u32) -> u32,blot_error::Error {
    if row == 0 { return 0,blot_error::Error.none; } let known = lookup(store.row_from.items,row); if known.present { return known.value,blot_error::Error.none; }
    let layouts:blot_backend_layout::Store? .= store.layouts;let semantic:blot_eval_type_evidence::Store? .= store.semantic;assert(layouts);assert(semantic); let result,error = layouts.rowFromEvidence(semantic.view(),row); if error != blot_error::Error.none { return 0,error; } let published=publish(store.row_from,row,result); if published!=blot_error::Error.none {return 0,published;} return result,blot_error::Error.none;
}
fn toCodeExpectation(store: Store&,id: u32) -> u32,blot_error::Error {
    if id >= 1 && id <= 5 { return id,blot_error::Error.none; } if id == blot_backend_layout::erased { return 0,blot_error::Error.none; }
    let known = lookup(store.shapes.items,id); if known.present { return known.value,blot_error::Error.none; } let layouts:blot_backend_layout::Store? .= store.layouts;assert(layouts);
    let result,error = layouts.toCodeExpectation(store.partial,id); if error != blot_error::Error.none { return 0,error; } let published=publish(store.shapes,id,result); if published!=blot_error::Error.none {return 0,published;} return result,blot_error::Error.none;
}
fn partialView(store: Store&) -> blot_reuse_code_expectation::View { store.partial.view() }
