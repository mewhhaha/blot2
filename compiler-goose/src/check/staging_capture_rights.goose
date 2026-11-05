// Future-local captures require complete executable lifetime edges.
namespace blot_check_staging_capture_rights;
type ModuleRef = blot_check_frozen_core_validation::ModuleRef;
import .frozen_core_validation;
import support.error;
import support.option;
import .core;
import .types;
import .capability_lifetimes;
import .usage_core;
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
fn require(value: bool) -> Error { if !value { return Error.invalid_artifact; } return Error.none; }
fn Checker::deinit(self: Checker&) { for entry in self.reports { blot_check_capability_lifetimes::deinit(entry.report); } self.reports.clear(); }
fn Checker::step(self: Checker&) -> Error { if self.remaining == 0 { return Error.invalid_artifact; } self.remaining -= 1; return Error.none; }
fn Checker::report(self: Checker&, root: u32) -> const Report?, Error {
    for entry in self.reports { let err = self.step(); if err != Error.none { return null, err; } if entry.scope == root { return entry.report, Error.none; } }
    if !self.allocating { return null, Error.invalid_artifact; }
    var result, err = blot_check_capability_lifetimes::analyzeScope(self.module, self.units, root, self.remaining);
    if err != Error.none { if err != Error.out_of_memory { err = Error.invalid_artifact; } return null, err; }
    if !result.complete { blot_check_capability_lifetimes::deinit(result); return null, Error.invalid_artifact; }
    self.reports.append(Entry { root, result }); return self.reports[self.reports.len - 1].report, Error.none;
}
fn Checker::confined(self: Checker&, image: const Report&, value: u32, scopes: const u32[:]) -> Error {
    if !self.allocating { return Error.invalid_artifact; } var work: u32[>..<]; var seen: dictionary<u32,bool>;
    work.append(value);
    while work.len != 0 {
        let current = work[work.len - 1]; work.resize(work.len - 1);
        var err = self.step(); if err != Error.none { return err; } if current >= image.nodes.len { return Error.invalid_artifact; }
        if seen.contains(current) { continue; } seen.insert(current, true); let node = image.nodes[current];
        if node.kind == blot_check_capability_lifetimes::Kind.unknown || node.kind == blot_check_capability_lifetimes::Kind.external { return Error.invalid_artifact; }
        if node.kind == blot_check_capability_lifetimes::Kind.capability {
            if node.owner >= image.nodes.len { return Error.invalid_artifact; } let owner = image.nodes[node.owner];
            if owner.kind != blot_check_capability_lifetimes::Kind.scope || owner.site.unit != self.module.unit { return Error.invalid_artifact; }
            var found = false; for scope in scopes { if scope == owner.site.node { found = true; break; } } if !found { return Error.invalid_artifact; }
        }
        var next = node.first_edge;
        while next.present { err = self.step(); if err != Error.none { return err; } let index = next.value; if index >= image.edges.len { return Error.invalid_artifact; } let edge = image.edges[index]; if edge.from != current { return Error.invalid_artifact; } work.append(edge.to); next = edge.next; }
        if node.contents != 0 { work.append(node.contents); }
    } return Error.none;
}
fn Checker::loanCapture(self: Checker&, closure: u32, binding: u32, loans: const u32[:]) -> bool, Error {
    let borrowed = self.module.types.node(self.module.bindings[binding].ty);
    if borrowed.tag != blot_check_types::Tag.usage || (borrowed.b != blot_check_types::usageCode(blot_check_types::UsageKind.borrow) && borrowed.b != blot_check_types::usageCode(blot_check_types::UsageKind.borrow_mut)) || borrowed.c == 0 { return false, Error.none; }
    let region = self.module.types.node(borrowed.c); if region.tag != blot_check_types::Tag.bound || region.a != 0 || region.b != 2 || region.c != binding { return false, Error.none; }
    for site in loans { let err = self.step(); if err != Error.none { return false, err; } let node = self.module.node(site); var callback_id: u32 = 0; if node.tag == blot_check_core::Tag.usage_borrow { callback_id = node.b; } if node.tag == blot_check_core::Tag.resource_scope { callback_id = node.c; }
        if callback_id == 0 || self.module.node(callback_id).tag != blot_check_core::Tag.closure { return false, Error.invalid_artifact; } let callback = self.module.closure(callback_id);
        if callback.parameter.binding != binding || callback.parameter.ty != self.module.bindings[binding].ty { continue; }
        return blot_check_usage_core::physicallyCaptures(self.module, self.module.closures[self.module.node(closure).a].body, binding, self.remaining);
    } return false, Error.none;
}
fn Checker::requireLoanCaptures(self: Checker&, closure: u32, loans: const u32[:]) -> Error {
    let callback = self.module.closures[self.module.node(closure).a]; let captures = self.module.extra[callback.captures.start..callback.captures.start + callback.captures.len];
    for site in loans { let err = self.step(); if err != Error.none { return err; } let node = self.module.node(site); var owner_id = node.b; if node.tag == blot_check_core::Tag.resource_scope { owner_id = node.c; } let owner = self.module.closure(owner_id); let binding = owner.parameter.binding; if binding == callback.parameter.binding { continue; }
        let physically, err = blot_check_usage_core::physicallyCaptures(self.module, callback.body, binding, self.remaining); if err != Error.none { return err; }
        if physically { var found = false; for capture in captures { if capture == binding { found = true; break; } } if !found { return Error.invalid_artifact; } }
    } return Error.none;
}
fn Checker::capture(self: Checker&, closure: u32, binding: u32, scopes: const u32[:], loans: const u32[:]) -> Error {
    let loan, err = self.loanCapture(closure, binding, loans); if err != Error.none { return err; } if loan { return Error.none; } if scopes.len == 0 { return Error.invalid_artifact; }
    let catalog = self.module.node(closure).a; var found = false;
    // report may grow its table; acquire the borrow after the operation completes.
    let report_value, report_error = self.report(scopes[0]); if report_error != Error.none { return report_error; } let report .= report_value;
    for node, value in report.nodes { let err = self.step(); if err != Error.none { return err; }
        if node.site.unit != self.module.unit || node.site.node != closure || !node.closure.present || node.closure.value != catalog { continue; } var captured = false; var next = node.first_edge;
        while next.present { let err = self.step(); if err != Error.none { return err; } let index = next.value; if index >= report.edges.len { return Error.invalid_artifact; } let edge = report.edges[index]; if edge.from != value { return Error.invalid_artifact; } next = edge.next; if edge.kind != blot_check_capability_lifetimes::EdgeKind.capture || edge.field != binding { continue; }
            let err = self.confined(report, edge.to, scopes); if err != Error.none { return err; } captured = true;
        } if !captured { return Error.invalid_artifact; } found = true;
    } return require(found);
}
