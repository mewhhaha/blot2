// One revision owns its exact namespace, graph images and foreign validation bounds.
namespace blot_reuse_dependency_certificate;
import std;
import check.core;
import check.frozen_core_validation;
import backend.runtime_identity;
import reuse.validation_image;
import reuse.code_artifacts;
import reuse.semantic_query_table;
import support.error;
import support.option;
import support.structural;
type Error = blot_error::Error;
type Image = blot_reuse_validation_image::Image;
type Context = blot_check_frozen_core_validation::Context;
type ModuleRef = blot_check_frozen_core_validation::ModuleRef;
type View = blot_backend_runtime_identity::View;
type Pin = blot_reuse_code_artifacts::ModulePin;
struct ModuleImage { unit: u32, path: const u8[:], token: u64, graph: Image }
struct Dependencies { namespace_: Image, modules: ModuleImage[:] = default<ModuleImage[:]>() }
struct Checked {}
struct Record { key: blot_check_frozen_core_validation::ContextImage, dependencies: Dependencies, value: Checked }
struct Certificate { record: Record, reused_images: i64 = 0 }
struct Stats {
    dependency_validations: i64 = 0, reused_dependency_validations: i64 = 0,
    projection_scans: i64 = 0, projection_visits: i64 = 0, projection_workspace_peak_bytes: i64 = 0,
    retained: blot_reuse_semantic_query_table::Storage = blot_reuse_semantic_query_table::Storage {..}, reused_images: i64 = 0,
}
fn observe<G>(self_: Stats&, gate: const G&) {
    self_.dependency_validations += gate.dependency_validations; self_.reused_dependency_validations += gate.reused_dependency_validations;
    self_.projection_scans += gate.projection_scans; self_.projection_visits += gate.projection_visits; self_.projection_workspace_peak_bytes = max(self_.projection_workspace_peak_bytes, gate.projection_workspace_peak_bytes);
}
let owned_bytes: i64 = 67108864;
// Packed C.2 host footprints; references and lease IDs are never serialized.
let module_image_bytes: i64 = 56; let image_owner_bytes: i64 = 20; let nominal_fact_bytes: i64 = 11;
reusable[] var paths: u8[>..] = [];
reusable[] var module_images: ModuleImage[>..] = [];
fn ownPath(bytes: const u8[:]) -> const u8[:] { if bytes.len == 0 { return default<const u8[:]>(); } let out = paths.alloc_slice(bytes.len); for byte, index in bytes { out[index] = byte; } return out; }
fn releasePath(bytes: const u8[:]) { if bytes.len != 0 { paths.free_slice(bytes); } }
fn deinit(self_: ModuleImage&) { releasePath(self_.path); self_.graph.deinit(); self_.path = default<const u8[:]>(); }
fn deinit(self_: Dependencies&) {
    self_.namespace_.deinit(); let count = self_.modules.len; if count == 0 { return; }
    let first: const ModuleImage& = self_.modules[0]; let at = module_images.index_of(first); assert(at >= 0);
    for &module in self_.modules { module.deinit(); } module_images.free_slice(module_images[at..at + count]); self_.modules = default<ModuleImage[:]>();
}
fn deinit(self_: Certificate&) { self_.record.key.deinit(); self_.record.dependencies.deinit(); }
fn capture(context: Context, pins: const Pin[:], names: View) -> blot_support::Option<Certificate>, Error { return captureWithBudget(context, pins, names, owned_bytes); }
fn captureWithBudget(context: Context, pins: const Pin[:], names: View, budget: i64) -> blot_support::Option<Certificate>, Error { return captureReusingWithBudget(context, pins, names, null, [], budget); }
fn captureReusing(context: Context, pins: const Pin[:], names: View, previous: const Certificate?, reusable_: const bool[:]) -> blot_support::Option<Certificate>, Error { return captureReusingWithBudget(context, pins, names, previous, reusable_, owned_bytes); }
fn reusedImage(previous: const Certificate?, reusable_: const bool[:], ordinal: i64, pin: Pin) -> blot_support::Option<Image> {
    if !previous || ordinal >= reusable_.len || !reusable_[ordinal] || ordinal >= previous.record.dependencies.modules.len { return blot_support::none<Image>(); }
    let module = previous.record.dependencies.modules[ordinal]; if module.unit != pin.unit || module.path != pin.canonical_path || module.token != pin.token || module.graph.bytes.len == 0 { return blot_support::none<Image>(); } return blot_support::some(module.graph);
}
fn captureReusingWithBudget(context: Context, pins: const Pin[:], names: View, previous: const Certificate?, reusable_: const bool[:], budget: i64) -> blot_support::Option<Certificate>, Error {
    let no = blot_support::none<Certificate>(); if pins.len == 0 || pins.len != context.units.len || names.owners.len != pins.len || budget < 0 { return no, blot_error::Error.none; }
    var remaining = budget;
    if pins.len > remaining / module_image_bytes { return no, blot_error::Error.none; } remaining -= pins.len * module_image_bytes;
    if context.units.len > remaining / image_owner_bytes { return no, blot_error::Error.none; } remaining -= context.units.len * image_owner_bytes;
    for ref in context.units { if ref.value.nominals.len > remaining / nominal_fact_bytes { return no, blot_error::Error.none; } remaining -= ref.value.nominals.len * nominal_fact_bytes; }
    let image, captured = blot_check_frozen_core_validation::capture(context, context.units); if captured != blot_error::Error.none { return no, captured; }
    var result = Certificate { record: Record { key: image, dependencies: Dependencies { namespace_: Image {..} , ..}, value: Checked {..} , ..} , ..};
    let namespace_, names_error = blot_reuse_validation_image::capture(names, remaining);
    if names_error != blot_error::Error.none || !namespace_.present { result.deinit(); return no, names_error; } result.record.dependencies.namespace_ = namespace_.value;
    let run = module_images.alloc_slice(pins.len); var initialized: i64 = 0;
    let failure = captureModules(result, context, pins, names, previous, reusable_, remaining, run, initialized);
    if failure != blot_error::Error.none || initialized != pins.len {
        for &module in run[..initialized] { module.deinit(); }
        if run.len != 0 { module_images.free_slice(run); }
        result.deinit(); return no, failure;
    }
    result.record.dependencies.modules = run; return blot_support::some(result), blot_error::Error.none;
}
fn captureModules(result: Certificate&, context: Context, pins: const Pin[:], names: View, previous: const Certificate?, reusable_: const bool[:], remaining: i64&, run: ModuleImage[:], initialized: i64&) -> Error {
    for pin, ordinal in pins {
        let unit .= context.units[ordinal].value; let owner = names.owner((ordinal + 1) as u32);
        if !owner.present || pin.module .!= unit || pin.unit != ordinal + 1 || pin.canonical_path != owner.value || pin.canonical_path.len > remaining { return blot_error::Error.none; }
        remaining -= pin.canonical_path.len; let path = ownPath(pin.canonical_path); var graph = Image {..};
        let shared = reusedImage(previous, reusable_, ordinal, pin);
        if shared.present {
            if shared.value.bytes.len > remaining { releasePath(path); return blot_error::Error.none; } remaining -= shared.value.bytes.len;
            let retained, error = shared.value.retain(); if error != blot_error::Error.none { releasePath(path); return error; } graph = retained; result.reused_images++;
        } else {
            let captured, error = blot_reuse_validation_image::capture(unit, remaining);
            if error != blot_error::Error.none || !captured.present { releasePath(path); return error; } graph = captured.value;
        }
        run[ordinal] = ModuleImage { pin.unit, path, pin.token, graph , ..}; initialized++;
    }
    return blot_error::Error.none;
}
fn storage(self_: const Certificate&) -> blot_reuse_semantic_query_table::Storage {
    let dependencies = self_.record.dependencies;
    var bytes = dependencies.namespace_.bytes.len + dependencies.modules.len * module_image_bytes + self_.record.key.owners.len * image_owner_bytes + self_.record.key.nominal_facts.len * nominal_fact_bytes;
    for module in dependencies.modules { bytes += module.path.len + module.graph.bytes.len; } return blot_reuse_semantic_query_table::Storage { records: 1, payload_bytes: bytes , ..};
}
fn matches(self_: const Certificate&, context: Context, names: View, callers: const ModuleRef[:]) -> bool { return self_.record.dependencies.modules.len == context.units.len && self_.record.key.matches(context, callers) && self_.record.dependencies.namespace_.matches(names); }
fn sameContext(self_: const Certificate&, context: Context, names: View, pins: const Pin[:]) -> bool {
    if self_.record.dependencies.modules.len != pins.len || pins.len != context.units.len || !blot_structural::equal(self_.record.key.symbol_count, context.symbol_count) || !blot_structural::equal(self_.record.key.source_length, context.source_length) || !self_.record.dependencies.namespace_.matches(names) { return false; }
    for pin, ordinal in pins { if pin.module .!= context.units[ordinal].value || !self_.admits(ordinal, pin) { return false; } } return true;
}
fn admits(self_: const Certificate&, unit: i64, pin: Pin) -> bool { if unit < 0 || unit >= self_.record.dependencies.modules.len { return false; } let module = self_.record.dependencies.modules[unit]; return module.unit == pin.unit && module.path == pin.canonical_path && module.token == pin.token && module.graph.matches(pin.module); }
