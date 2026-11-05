// Semantic row labels and operation arguments never cross owners unmapped.
namespace blot_check_effect_evidence;
import std;
import dictionary;
import support.error;
import support.option;
import support.native;
type Id = u32;
type Label = u32;
type Error = blot_error::Error;
struct List { start: u32 = 0, len: u32 = 0 }
struct Row { start: u32 = 0, len: u32 = 0, formal: u32 = 0 }
struct Operation { identity: blot_check_types::NominalIdentity, arguments: List, instance: blot_check_types::NominalIdentity = blot_check_types::NominalIdentity { 0, 0 } }
struct View { operations: const Operation[:] = [], arguments: const u32[:] = [], rows: const Row[:] = [], labels: const Label[:] = [], owner_id: u64 = 0 }
fn operation(self: View, label: Label) -> Operation { return self.operations[label]; }
fn operationArguments(self: View, label: Label) -> const u32[:] { let span = operation(self, label).arguments; return self.arguments[span.start..span.start + span.len]; }
fn rowLabels(self: View, row: Id) -> const Label[:] { if row == 0 { return self.labels[..0]; } let span = self.rows[row]; return self.labels[span.start..span.start + span.len]; }
struct Snapshot { operations: const Operation[:], arguments: const u32[:], rows: const Row[:], labels: const Label[:], owner_id: u64 }
struct SnapshotTables { operations: Operation[>..]&, arguments: u32[>..]&, rows: Row[>..]&, labels: Label[>..]& }
fn view(self: const Snapshot&) -> View { return View { self.operations, self.arguments, self.rows, self.labels, self.owner_id }; }
fn deinit(self: Snapshot&) { self.operations = []; self.arguments = []; self.rows = []; self.labels = []; self.owner_id = 0; }
struct Tables {
    operations: Operation[>..<]&, arguments: u32[>..<]&, rows: Row[>..<]&, labels: Label[>..<]&,
    operation_next: Label[>..<]&, row_next: Id[>..<]&,
    operation_buckets: dictionary<u64, Label>&, row_buckets: dictionary<u64, Id>&,
}
struct Store {
    operations: Operation[>..<]&, arguments: u32[>..<]&, rows: Row[>..<]&, labels: Label[>..<]&,
    operation_next: Label[>..<]&, row_next: Id[>..<]&,
    operation_buckets: dictionary<u64, Label>&, row_buckets: dictionary<u64, Id>&, owner_id: u64,
}
fn init(t: Tables) -> Store, Error {
    var self = Store { t.operations, t.arguments, t.rows, t.labels, t.operation_next, t.row_next,
        t.operation_buckets, t.row_buckets, blot_native::fresh_owner_id() };
    self.operations.push(Operation { blot_check_types::NominalIdentity { 0, 0 }, List {} });
    self.operation_next.push(0); self.rows.push(Row {}); self.row_next.push(0);
    return self, Error.none;
}
fn deinit(self: Store&) {
    self.operations.clear(); self.arguments.clear(); self.rows.clear(); self.labels.clear(); self.operation_next.clear();
    self.row_next.clear(); self.operation_buckets.clear(); self.row_buckets.clear(); self.owner_id = 0;
}
fn view(self: const Store&) -> View { return View { self.operations, self.arguments, self.rows, self.labels, self.owner_id }; }
fn copyOwned(self: const Store&, target: SnapshotTables) -> Snapshot, Error {
    let op_start = target.operations.len; let arg_start = target.arguments.len;
    let row_start = target.rows.len; let label_start = target.labels.len;
    target.operations.append(self.operations); target.arguments.append(self.arguments);
    target.rows.append(self.rows); target.labels.append(self.labels);
    return Snapshot { target.operations[op_start..], target.arguments[arg_start..], target.rows[row_start..],
        target.labels[label_start..], blot_native::fresh_owner_id() }, Error.none;
}
fn clone(self: const Store&, tables: Tables) -> Store, Error {
    var result = Store { tables.operations, tables.arguments, tables.rows, tables.labels, tables.operation_next,
        tables.row_next, tables.operation_buckets, tables.row_buckets, blot_native::fresh_owner_id() };
    result.operations.append(self.operations); result.arguments.append(self.arguments); result.rows.append(self.rows);
    result.labels.append(self.labels); result.operation_next.append(self.operation_next); result.row_next.append(self.row_next);
    result.operation_buckets.slots.clear(); result.operation_buckets.slots.append(self.operation_buckets.slots); result.operation_buckets.count = self.operation_buckets.count;
    result.row_buckets.slots.clear(); result.row_buckets.slots.append(self.row_buckets.slots); result.row_buckets.count = self.row_buckets.count;
    return result, Error.none;
}
fn internOperation(self: Store&, identity: blot_check_types::NominalIdentity, values: const u32[:]) -> Label, Error {
    return internOperationInstance(self, identity, values, blot_check_types::NominalIdentity { 0, 0 });
}
fn operationFingerprint(identity: blot_check_types::NominalIdentity, values: const u32[:], instance: blot_check_types::NominalIdentity) -> u64 {
    var fingerprint = ::hash_combine(::hash(identity.unit), ::hash(identity.decl));
    if instance.decl != 0 { fingerprint = ::hash_combine(::hash_combine(fingerprint, ::hash(instance.unit)), ::hash(instance.decl)); }
    for value in values { fingerprint = ::hash_combine(fingerprint, ::hash(value)); }
    return fingerprint;
}
fn rowFingerprint(values: const Label[:], formal: u32) -> u64 {
    var fingerprint = ::hash(formal); for value in values { fingerprint = ::hash_combine(fingerprint, ::hash(value)); } return fingerprint;
}
fn internOperationInstance(self: Store&, identity: blot_check_types::NominalIdentity, values: const u32[:], instance: blot_check_types::NominalIdentity) -> Label, Error {
    return internOperationInstanceHashed(self, identity, values, instance, operationFingerprint(identity, values, instance));
}
fn internOperationHashed(self: Store&, identity: blot_check_types::NominalIdentity, values: const u32[:], fingerprint: u64) -> Label, Error {
    return internOperationInstanceHashed(self, identity, values, blot_check_types::NominalIdentity { 0, 0 }, fingerprint);
}
fn internOperationInstanceHashed(self: Store&, identity: blot_check_types::NominalIdentity, values: const u32[:], instance: blot_check_types::NominalIdentity, fingerprint: u64) -> Label, Error {
    if identity.decl == 0 || (identity.unit == 0 && identity.decl == 1 && (instance.unit != 0 || instance.decl != 0)) { return 0, Error.type_mismatch; }
    for value in values { if value == 0 { return 0, Error.type_mismatch; } }
    var candidate: u32 = 0;
    block { let bucket = self.operation_buckets.get(fingerprint); if bucket { candidate = bucket; } }
    while candidate != 0 {
        let op = operation(view(self), candidate);
        if op.instance.unit == instance.unit && op.instance.decl == instance.decl && op.identity.unit == identity.unit && op.identity.decl == identity.decl && operationArguments(view(self), candidate) == values { return candidate, Error.none; }
        candidate = self.operation_next[candidate];
    }
    if self.operations.len >= 0xffffffff || values.len > 0xffffffff || self.arguments.len > 0xffffffff - values.len { return 0, Error.evidence_limit; }
    var owned: u32[>..] = []; owned.append(values);
    var previous: u32 = 0;
    block { let bucket = self.operation_buckets.get(fingerprint); if bucket { previous = bucket; } }
    let label = self.operations.len as u32;
    self.operations.push(Operation { identity, List { self.arguments.len as u32, owned.len as u32 }, instance });
    self.arguments.append(owned); self.operation_next.push(previous); self.operation_buckets.insert(fingerprint, label);
    return label, Error.none;
}
fn internRow(self: Store&, values: const Label[:]) -> Id, Error { return internRowWithFormal(self, values, 0); }
fn internRowWithFormal(self: Store&, values: const Label[:], formal: u32) -> Id, Error {
    if values.len == 0 && formal == 0 { return 0, Error.none; }
    var ordered = true; var previous: Label = 0;
    for label in values {
        if label == 0 || label >= self.operations.len { return 0, Error.type_mismatch; }
        ordered = ordered && previous <= label; previous = label;
    }
    if ordered { let known = findRow(self, values, formal, rowFingerprint(values, formal)); if known.present { return known.value, Error.none; } }
    var owned: Label[>..] = []; owned.append(values); if !ordered { ::sort(owned); }
    return internRowFormalHashed(self, owned, formal, rowFingerprint(owned, formal));
}
fn internRowHashed(self: Store&, values: const Label[:], fingerprint: u64) -> Id, Error { return internRowFormalHashed(self, values, 0, fingerprint); }
fn findRow(self: const Store&, values: const Label[:], formal: u32, fingerprint: u64) -> blot_support::Option<Id> {
    var candidate: Id = 0;
    block { let bucket = self.row_buckets.get(fingerprint); if bucket { candidate = bucket; } }
    while candidate != 0 {
        if self.rows[candidate].formal == formal && rowLabels(view(self), candidate) == values { return blot_support::Option<Id> { true, candidate }; }
        candidate = self.row_next[candidate];
    }
    return blot_support::Option<Id> { false, 0 };
}
fn internRowFormalHashed(self: Store&, values: const Label[:], formal: u32, fingerprint: u64) -> Id, Error {
    let known = findRow(self, values, formal, fingerprint); if known.present { return known.value, Error.none; }
    if self.rows.len >= 0xffffffff || values.len > 0xffffffff || self.labels.len > 0xffffffff - values.len { return 0, Error.evidence_limit; }
    var previous: Id = 0;
    block { let bucket = self.row_buckets.get(fingerprint); if bucket { previous = bucket; } }
    let id = self.rows.len as u32;
    self.rows.push(Row { self.labels.len as u32, values.len as u32, formal }); self.labels.append(values);
    self.row_next.push(previous); self.row_buckets.insert(fingerprint, id);
    return id, Error.none;
}
