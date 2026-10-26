// One required pipeline for fresh CLI builds and retained session revisions.
import .model;
import .loader;
import .frontend;
import .retained;
import .plan;
import .fingerprint;
import .manifest;
import .wasm;
import .validate;
import .optimize;
import os;
import json;
struct BuildConfig { input: const u8[:], root: const u8[:], selected: const u8[:], bridge_config: const u8[:], cancel_file: const u8[:], opt_mode: const u8[:], emit: bool, telemetry: bool = false, trace: bool = false }
struct BuildStats {
    load_ns: i64, complete_ns: i64, plan_ns: i64, validate_ns: i64, optimize_ns: i64, lower_ns: i64, total_ns: i64,
    bodies: u64, declarations: u64, static_bodies: u64, semantic_visits: u64, validation_visits: u64,
    proof_visits: u64, validation_proof_visits: u64, proof_terms: u64, proof_edges: u64,
    static_steps: u64, static_bytes: u64, interface_instantiations: u64,
    semantic_instances: u64, executable_instances: u64, adapter_count: u64,
    rewrite_visits: u64, rewrite_applications: u64, rewrite_declines: u64, generated_bytes: u64,
    completed_modules: u64, created_regions: u64, active_regions: u32, downstream_regions: u64, reuse: ReuseStats
}
// Append fields to an already open JSON object. Inventory counts describe the
// checked candidate; work counts describe this invocation, excluding reuse.
fn append_build_work(out: u8[>..]&, s: BuildStats) {
    format(out, ",\"created_regions\":", s.created_regions,
        ",\"general_inference_regions_created\":0,\"general_inference_nodes\":0",
        ",\"proof_terms\":", s.proof_terms, ",\"proof_edges\":", s.proof_edges,
        ",\"proof_visits\":", s.proof_visits, ",\"validation_proof_visits\":", s.validation_proof_visits,
        ",\"static_steps\":", s.static_steps, ",\"static_bytes\":", s.static_bytes,
        ",\"interface_instantiations\":", s.interface_instantiations,
        ",\"semantic_instances\":", s.semantic_instances, ",\"executable_instances\":", s.executable_instances,
        ",\"adapter_count\":", s.adapter_count, ",\"rewrite_visits\":", s.rewrite_visits,
        ",\"rewrite_applications\":", s.rewrite_applications, ",\"rewrite_declines\":", s.rewrite_declines,
        ",\"generated_bytes\":", s.generated_bytes, ",\"cache_admission_visits\":", s.reuse.admission_visits,
        ",\"dependency_visits\":", s.reuse.dependency_visits,
        ",\"dependency_invalidations\":", s.reuse.dependency_invalidations,
        ",\"cache_lookups\":", s.reuse.lookups, ",\"cache_hits\":", s.reuse.hits,
        ",\"cache_misses\":", s.reuse.misses);
}
fn trace_phase(config: BuildConfig, phase: const u8[:], module: const u8[:]) {
    if !config.trace { return; } var line: u8[>..] = []; line.append("{\"phase\":"); json::format_string(line, phase);
    line.append(",\"module\":"); json::format_string(line, module); line.append("}\n"); write_stderr(line);
}
fn emit_wasm_candidate(c: Core, out: u8[>..]&, diagnostics: Diagnostic[>..]&, telemetry: bool) -> bool {
    var manifest: u8[>..] = [];
    if telemetry {
        if !manifest_json_telemetry(c, manifest) { return loader_error(diagnostics, 4011, 0); }
        return wasm_emit_manifest_telemetry(c, out, manifest, diagnostics);
    }
    if !manifest_json(c, manifest) { return loader_error(diagnostics, 4011, 0); }
    return wasm_emit_manifest(c, out, manifest, diagnostics);
}
fn optimized_wasm(c: Core, mode: const u8[:], out: u8[>..]&, diagnostics: Diagnostic[>..]&, stats: optimize::Stats&, optimize_ns: i64&, telemetry: bool) -> bool {
    if mode == "off" { return emit_wasm_candidate(c, out, diagnostics, telemetry); }
    var success = false;
    with_core() { candidate =>
        let start = clock_ns();
        let admitted = optimize::optimize(c, optimize::Limits {}, candidate, stats, diagnostics);
        optimize_ns = clock_ns() - start;
        if admitted { success = emit_wasm_candidate(core_view(candidate), out, diagnostics, telemetry); }
        else if stats.declines > 0 && diagnostics.len == 0 { success = emit_wasm_candidate(c, out, diagnostics, telemetry); }
        else { if diagnostics.len == 0 { loader_error(diagnostics, 4015, 0); } success = false; }
    };
    return success;
}
fn compile_candidate(prior: Core, config: BuildConfig, b: CoreBuilder, wasm_bytes: u8[>..]&, stats: BuildStats&, diagnostics: Diagnostic[>..]&) -> bool {
    let start = clock_ns(); var order: u32[>..] = [];
    fn cancelled() -> bool { return config.cancel_file.len != 0 && file_exists(config.cancel_file); }
    if cancelled() { return loader_error(diagnostics, 4009, 0); }
    trace_phase(config, "loading", "");
    if !load_package(config.input, config.root, b, order, diagnostics) { return false; }
    let loaded = clock_ns(); stats.load_ns = loaded - start;
    trace_phase(config, "completion", "");
    for module_id in order {
        if cancelled() { return loader_error(diagnostics, 4009, 0); }
        let m = b.modules[module_id]; var work = Work { .. }; let source = b.bytes[m.source.start..m.source.start + m.source.count];
        let accepted = if prior.receipts.len > 1 {
            complete_retained_module(prior, source, name_bytes(core_view(b), m.path), b, work, stats.reuse, diagnostics)
        } else { frontend_complete(source, name_bytes(core_view(b), m.path), b, work, diagnostics) };
        stats.semantic_visits += work.visits;
        stats.proof_visits += work.proof_visits; stats.static_steps += work.static_steps;
        stats.static_bytes += work.static_bytes; stats.interface_instantiations += work.interface_instantiations;
        if !accepted { return false; }
        stats.completed_modules++; trace_phase(config, "module-complete", name_bytes(core_view(b), m.path));
    }
    if cancelled() { return loader_error(diagnostics, 4009, 0); }
    let completed = clock_ns(); stats.complete_ns = completed - loaded; stats.declarations = b.phase.completed; stats.bodies = (b.functions.len - 1) as u64 - stats.reuse.bodies; for f in b.functions { if f.evaluator_only { stats.static_bodies++; } }
    trace_phase(config, "planning", "");
    if config.bridge_config.len != 0 && !configure_bridge(config.bridge_config, b, diagnostics) { return false; }
    if !build_plans(b, config.selected, diagnostics) || !finish_bridge_plans(b, diagnostics) || !canonical_schemas(b, diagnostics) || !fingerprint_interfaces(b, diagnostics) { return false; }
    if !seal_completion(b) { return loader_error(diagnostics, 4008, 0); }
    if cancelled() { return loader_error(diagnostics, 4009, 0); }
    let planned = clock_ns(); stats.plan_ns = planned - completed; var validation_work = Work { .. };
    trace_phase(config, "validation", "");
    if !validator::validate_core(core_view(b), validator::FRESH, validation_work, diagnostics) { return false; }
    stats.validation_visits = validation_work.visits; stats.validation_proof_visits = validation_work.proof_visits;
    let validated = clock_ns(); stats.validate_ns = validated - planned; var opt_stats = optimize::Stats {};
    trace_phase(config, "lowering", "");
    if config.emit && !optimized_wasm(core_view(b), config.opt_mode, wasm_bytes, diagnostics, opt_stats, stats.optimize_ns, config.telemetry) { return false; }
    if b.phase.active != 0 || b.phase.created != b.phase.sealed_created { return loader_error(diagnostics, 4008, 0); }
    stats.active_regions = b.phase.active; stats.downstream_regions = b.phase.created - b.phase.sealed_created;
    stats.created_regions = b.phase.created;
    stats.proof_terms = (b.terms.len - 1) as u64; stats.proof_edges = (b.facts.len + b.evidence.len - 2) as u64;
    stats.semantic_instances = (b.functions.len - 1) as u64;
    stats.executable_instances = if config.emit { stats.semantic_instances - stats.static_bodies } else { 0 as u64 };
    stats.adapter_count = (b.callable_adapters.len - 1) as u64;
    stats.rewrite_visits = opt_stats.visits; stats.rewrite_applications = opt_stats.applications; stats.rewrite_declines = opt_stats.declines;
    stats.generated_bytes = wasm_bytes.len as u64;
    stats.lower_ns = clock_ns() - validated - stats.optimize_ns; stats.total_ns = clock_ns() - start; return true;
}
