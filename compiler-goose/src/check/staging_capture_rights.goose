// Future-local captures require complete executable lifetime edges.
namespace blot_check_staging_capture_rights;
import parse.ast;
import check.capability_lifetimes;
import check.core;
import check.frozen_core_scopes;
import check.types;
import check.usage_core;
import support.error;

type ModuleRef = blot_check_frozen_core_validation::ModuleRef;
import .frozen_core_validation;
import support.option;
type Error = blot_error::Error;
type Module = blot_check_core::Module;
type Report = blot_check_capability_lifetimes::Report;
struct Entry { scope: u32, report: Report }
struct Checker {
    allocating: bool,
    module: const Module&,
    units: const ModuleRef[:],
    remaining: i64&,
    reports: Entry[>..<]&
}
fn require(value: bool) -> Error { if !value { return blot_error::Error.invalid_artifact; } return blot_error::Error.none; }
fn deinit(self_: Checker&) { for entry in self_.reports { blot_check_capability_lifetimes::deinit(entry.report); } self_.reports.clear(); }
fn step(self_: Checker&) -> Error { if self_.remaining == 0 { return blot_error::Error.invalid_artifact; } self_.remaining -= 1; return blot_error::Error.none; }
fn report(self_: Checker&, root: u32) -> const Report?, Error {
    for &entry in self_.reports { let err = self_.step(); if err != blot_error::Error.none { return null, err; } if entry.scope == root { return entry.report, blot_error::Error.none; } }
    if !self_.allocating { return null, blot_error::Error.invalid_artifact; }
    var result, err = blot_check_capability_lifetimes::analyzeScope(self_.module, self_.units, root, self_.remaining);
    if err != blot_error::Error.none { if err != blot_error::Error.out_of_memory { err = blot_error::Error.invalid_artifact; } return null, err; }
    if !result.complete { blot_check_capability_lifetimes::deinit(result); return null, blot_error::Error.invalid_artifact; }
    self_.reports.push(Entry { root, result , ..}); return self_.reports[self_.reports.len - 1].report, blot_error::Error.none;
}
fn confined(self_: Checker&, image: const Report&, value: u32, scopes: const u32[:]) -> Error {
    if !self_.allocating { return blot_error::Error.invalid_artifact; } var work: u32[>..<]=[]; var seen: dictionary<u32,bool> = dictionary<u32,bool>{};
    work.append(value);
    while work.len != 0 {
        let current = work[work.len - 1]; work.resize(work.len - 1);
        var err = self_.step(); if err != blot_error::Error.none { return err; } if current >= image.nodes.len { return blot_error::Error.invalid_artifact; }
        if seen.contains(current) { continue; } seen.insert(current, true); let node = image.nodes[current];
        if node.kind == blot_check_capability_lifetimes::Kind.unknown || node.kind == blot_check_capability_lifetimes::Kind.external { return blot_error::Error.invalid_artifact; }
        if node.kind == blot_check_capability_lifetimes::Kind.capability {
            if node.owner >= image.nodes.len { return blot_error::Error.invalid_artifact; } let owner = image.nodes[node.owner];
            if owner.kind != blot_check_capability_lifetimes::Kind.scope || owner.site.unit != self_.module.unit { return blot_error::Error.invalid_artifact; }
            var found = false; for scope in scopes { if scope == owner.site.node { found = true; break; } } if !found { return blot_error::Error.invalid_artifact; }
        }
        var next = node.first_edge;
        while next.present { err = self_.step(); if err != blot_error::Error.none { return err; } let index = next.value; if index >= image.edges.len { return blot_error::Error.invalid_artifact; } let edge = image.edges[index]; if edge.from != current { return blot_error::Error.invalid_artifact; } work.append(edge.to); next = edge.next; }
        if node.contents != 0 { work.append(node.contents); }
    } return blot_error::Error.none;
}
fn loanCapture(self_: Checker&, closure: u32, binding: u32, loans: const u32[:]) -> bool, Error {
    let borrowed = self_.module.types.node(self_.module.bindings[binding].ty);
    if borrowed.tag != blot_check_types::Tag.usage || (borrowed.b != blot_check_types::usageCode(blot_parse_ast::usagekind_borrow) && borrowed.b != blot_check_types::usageCode(blot_parse_ast::usagekind_borrow_mut)) || borrowed.c == 0 { return false, blot_error::Error.none; }
    let region = self_.module.types.node(borrowed.c); if region.tag != blot_check_types::Tag.bound || region.a != 0 || region.b != 2 || region.c != binding { return false, blot_error::Error.none; }
    for site in loans { let err = self_.step(); if err != blot_error::Error.none { return false, err; } let node = self_.module.node(site); var callback_id: u32 = 0; if node.tag == blot_check_core::Tag.usage_borrow { callback_id = node.b; } if node.tag == blot_check_core::Tag.resource_scope { callback_id = node.c; }
        if callback_id == 0 || self_.module.node(callback_id).tag != blot_check_core::Tag.closure { return false, blot_error::Error.invalid_artifact; } let callback = self_.module.closure(callback_id);
        if callback.parameter.binding != binding || callback.parameter.ty != self_.module.bindings[binding].ty { continue; }
        return blot_check_usage_core::physicallyCaptures(self_.module, self_.module.closures[self_.module.node(closure).a].body, binding, self_.remaining);
    } return false, blot_error::Error.none;
}
fn requireLoanCaptures(self_: Checker&, closure: u32, loans: const u32[:]) -> Error {
    let callback = self_.module.closures[self_.module.node(closure).a]; let captures = self_.module.extra[callback.captures.start..callback.captures.start + callback.captures.len];
    for site in loans { let err = self_.step(); if err != blot_error::Error.none { return err; } let node = self_.module.node(site); var owner_id = node.b; if node.tag == blot_check_core::Tag.resource_scope { owner_id = node.c; } let owner = self_.module.closure(owner_id); let binding = owner.parameter.binding; if binding == callback.parameter.binding { continue; }
        let physically, err = blot_check_usage_core::physicallyCaptures(self_.module, callback.body, binding, self_.remaining); if err != blot_error::Error.none { return err; }
        if physically { var found = false; for capture in captures { if capture == binding { found = true; break; } } if !found { return blot_error::Error.invalid_artifact; } }
    } return blot_error::Error.none;
}
fn capture(self_: Checker&, closure: u32, binding: u32, scopes: const u32[:], loans: const u32[:]) -> Error {
    let loan, err = self_.loanCapture(closure, binding, loans); if err != blot_error::Error.none { return err; } if loan { return blot_error::Error.none; } if scopes.len == 0 { return blot_error::Error.invalid_artifact; }
    let catalog = self_.module.node(closure).a; var found = false;
    // report may grow its table; acquire the borrow after the operation completes.
    let report_value, report_error = self_.report(scopes[0]); if report_error != blot_error::Error.none { return report_error; } let report .= report_value;
    for node, value in report.nodes { let err = self_.step(); if err != blot_error::Error.none { return err; }
        if node.site.unit != self_.module.unit || node.site.node != closure || !node.closure.present || node.closure.value != catalog { continue; } var captured = false; var next = node.first_edge;
        while next.present { let err = self_.step(); if err != blot_error::Error.none { return err; } let index = next.value; if index >= report.edges.len { return blot_error::Error.invalid_artifact; } let edge = report.edges[index]; if edge.from != value { return blot_error::Error.invalid_artifact; } next = edge.next; if edge.kind != blot_check_capability_lifetimes::EdgeKind.capture || edge.field != binding { continue; }
            let err = self_.confined(report, edge.to, scopes); if err != blot_error::Error.none { return err; } captured = true;
        } if !captured { return blot_error::Error.invalid_artifact; } found = true;
    } return require(found);
}
