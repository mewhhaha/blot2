// Experimental K1 fixture driver. Public check/build remain unavailable;
// private fixture commands accept only their documented narrow subsets.
import std;
import os;
import catalog;
import work;
import scalar_scheduled;
import public_frontend;
import public_snapshot;
import flow_decl;
import flow_decl_check;
import flow_decl_wasm;
import module_frontend;
import module_wasm;
import add_frontend;
import add_source;
import add_parser;
import add_scoped;
import control_frontend;
import control_validate;
import control_wasm;

extern fn k1_read_bounded(path: const u8[:], out: u8[>..]&) -> i64;

fn fail(message: u8[:]) {
    write_stderr(str("blot-k1: ", message, "\n"));
    exit(1);
}

// Private scalar accounting is partial: these statuses do not certify the
// full K1 work policy or authorize cache/public artifact admission.
fn fail_scalar_work(status: i64) {
    if status == 2 { fail("k1_semantic_limit"); }
    if status == 3 { fail("k1_core_limit"); }
    if status == 4 { fail("internal scalar work accounting failure"); }
    fail("invalid scalar representation");
}

// Private control-flow experiment. The argument to the emitted callable is a
// typed Bool and must already be canonical (0/1). This is not a host ingress
// validator, completed K1 artifact, public export or runtime certificate.
fn control_fixture(source: u8[:], trace: bool) {
    let candidate = control_frontend::parse(source);
    if candidate.status != 0 {
        var detail: u8[>..] = [];
        format(detail, "source error ", candidate.status);
        let category = catalog::source_diagnostic(candidate.status);
        if category.len > 0 { format(detail, " (", category, ")"); }
        format(detail, " at bytes ", candidate.start, "..", candidate.end, "\n");
        write_stderr(detail); exit(1);
    }
    if trace { write_stderr("control fixture: parsed source\n"); }
    if !control_validate::verify(source, candidate.program) {
        fail("internal control source/Core validation failure");
    }
    if trace { write_stderr("control fixture: validated source and control targets\n"); }
    // The encoder independently rechecks source/Core correspondence before
    // creating bytes. Test-only trap probes are not reachable via this path.
    let bytes = control_wasm::emit(source, candidate.program);
    if bytes.len == 0 { fail("internal control emission failure"); }
    if trace { write_stderr("control fixture: emitted Wasm module\n"); }
    let hex = "0123456789abcdef";
    var encoded: u8[>..] = [];
    for b in bytes { encoded.push(hex[b / 16]); encoded.push(hex[b % 16]); }
    encoded.push('\n'); write_stdout(encoded);
}

// Private v3 experiment: independently recheck source and Core before
// producing test-only module bytes. No public K1 admission is implied.
fn module_fixture(source: u8[:], trace: bool) {
    var module, status = module_frontend::parse(source);
    if status != 0 {
        var detail: u8[>..] = [];
        format(detail, "source error ", status);
        var category: u8[>..] = [];
        if status == 8 { category.append("k1_recursive_call"); }
        else if status == 9 { category.append("k1_resource_bound"); }
        else { category.append(catalog::source_diagnostic(status)); }
        if category.len > 0 { format(detail, " (", category, ")"); }
        format(detail, "\n"); write_stderr(detail); exit(1);
    }
    if trace { write_stderr("module fixture: parsed source\n"); }
    if module.source[..] != source {
        fail("internal module source validation failure");
    }
    if trace { write_stderr("module fixture: validated source\n"); }
    // Parse has already checked the fresh module. This constructor grants no
    // authority: verify_core independently rechecks source and Core before
    // any emission, including when the candidate is malformed.
    var completed = module_frontend::build_unvalidated_core(module);
    if module_frontend::verify_core(module, completed) != 0 {
        fail("internal module Core validation failure");
    }
    if trace { write_stderr("module fixture: validated Core\n"); }
    let bytes = wasm_v3::emit_module(completed);
    if bytes.len == 0 { fail("internal module emission failure"); }
    if trace { write_stderr("module fixture: emitted Wasm module\n"); }
    let hex = "0123456789abcdef";
    var encoded: u8[>..] = [];
    for b in bytes { encoded.push(hex[b / 16]); encoded.push(hex[b % 16]); }
    encoded.push('\n'); write_stdout(encoded);
}

fn fail_add_work(status: u32, receipt: work::Receipt) {
    var message: u8[>..] = [];
    if status == 3 { message.append("k1_semantic_limit"); }
    else { message.append("k1_proof_limit"); }
    format(message, " (quantity ", receipt.quantity, ", measured ", receipt.measured, ")");
    fail(message);
}

// End-to-end public-declaration experiment with deliberately synthetic
// package, module and ABI identities. This does not resolve filesystem paths,
// establish an ABI or grant public K1 admission.
fn public_fixture(source: u8[:], trace: bool) {
    let parsed = public_frontend::parse(source);
    if parsed.status != 0 {
        var detail: u8[>..] = [];
        format(detail, "source error ", parsed.status);
        let category = catalog::source_diagnostic(parsed.status);
        if category.len > 0 { format(detail, " (", category, ")"); }
        format(detail, "\n"); write_stderr(detail); exit(1);
    }
    if !public_frontend::verify(source, parsed) { fail("internal public fixture source mismatch"); }
    let name = source[parsed.core.name_start..parsed.core.name_end];
    let abi: u8[32] = [7; 32];
    var made = public_snapshot::make(source, "fixture", "main.blot", name, abi);
    if made.status != 0 { fail("internal public fixture snapshot failure"); }
    let bytes = public_snapshot::emit(made.snapshot, "fixture", "main.blot", name, abi);
    if bytes.len == 0 { fail("internal public fixture emission failure"); }
    if trace { write_stderr("public fixture: source-bound snapshot validated and Wasm emitted\n"); }
    let hex = "0123456789abcdef";
    var encoded: u8[>..] = [];
    for b in bytes { encoded.push(hex[b / 16]); encoded.push(hex[b % 16]); }
    encoded.push('\n'); write_stdout(encoded);
}

// Whole-source private Bool -> U32 control-flow fixture. The caller of the
// resulting test export must supply a canonical Bool; no host ABI is defined.
fn flow_fixture(source: u8[:], trace: bool) {
    var result = flow_decl::build(source);
    if result.status != 0 {
        var detail: u8[>..] = [];
        format(detail, "source error ", result.status);
        let category = if result.status == 13 { "k1_unbound_name" }
            else if result.status == 14 { "k1_type_mismatch" }
            else if result.status == 15 { "k1_missing_return" }
            else if result.status == 12 { "k1_unsupported_feature" }
            else { "k1_syntax" };
        format(detail, " (", category, ")\n"); write_stderr(detail); exit(1);
    }
    if !flow_decl_check::verify(result.decl) { fail("internal flow fixture source mismatch"); }
    let bytes = flow_decl_wasm::emit(source, result.decl);
    if bytes.len == 0 { fail("internal flow fixture emission failure"); }
    if trace { write_stderr("flow fixture: source and typed control flow validated; Wasm emitted\n"); }
    let hex = "0123456789abcdef";
    var encoded: u8[>..] = [];
    for b in bytes { encoded.push(hex[b / 16]); encoded.push(hex[b % 16]); }
    encoded.push('\n'); write_stdout(encoded);
}

// Separate private v4 experiment. Scope handles and the in-memory meter are
// local to this invocation, not cross-compile provenance or a cache key.
fn add_fixture(source: u8[:], trace: bool) {
    let parsed = add_frontend::parse(source);
    if parsed.status != 0 {
        if parsed.status == 11 { fail("internal checked-add source mismatch"); }
        var detail: u8[>..] = [];
        format(detail, "source error ", parsed.status);
        if parsed.status == 10 { format(detail, " (k1_arithmetic_not_established)"); }
        else {
            let category = catalog::source_diagnostic(parsed.status);
            if category.len > 0 { format(detail, " (", category, ")"); }
        }
        format(detail, "\n"); write_stderr(detail); exit(1);
    }
    if trace { write_stderr("add fixture: parsed source\n"); }
    if add_source::validate(source, parsed.core) != 0 { fail("internal checked-add source mismatch"); }
    var tree, tree_status = add_parser::parse(source);
    if tree_status != 0 || tree.source[..] != source || !add_parser::verify(tree, parsed.core) {
        fail("internal checked-add syntax mismatch");
    }
    if trace { write_stderr("add fixture: validated source and syntax\n"); }
    var job = add_scoped::Job {};
    let built = add_scoped::compile(source, job);
    if built.status != 0 {
        if built.status == 2 || built.status == 3 { fail_add_work(built.status, built.receipt); }
        fail("internal checked-add proof, Core or plan validation failure");
    }
    if trace { write_stderr("add fixture: validated Core and evidence\n"); }
    let bytes = built.bytes;
    if bytes.len == 0 { fail("internal checked-add plan or emission failure"); }
    if trace { write_stderr("add fixture: revalidated plan and emitted Wasm module\n"); }
    let hex = "0123456789abcdef";
    var encoded: u8[>..] = [];
    for b in bytes { encoded.push(hex[b / 16]); encoded.push(hex[b % 16]); }
    encoded.push('\n'); write_stdout(encoded);
}

fn main() {
    let argv = args();
    if argv.len >= 2 && (argv[1] == "check" || argv[1] == "build") {
        fail("K1 is not qualified for public compilation; use the legacy edition");
    }
    if (argv.len != 3 && argv.len != 4) || (argv[1] != "fixture" && argv[1] != "module-fixture" && argv[1] != "add-fixture" && argv[1] != "control-fixture" && argv[1] != "public-fixture" && argv[1] != "flow-fixture") || (argv.len == 4 && argv[3] != "--trace") {
        fail("usage: blot-k1 fixture|module-fixture|add-fixture|control-fixture|public-fixture|flow-fixture ENTRY [--trace] (experimental internal fixture)");
    }
    var source: u8[>..] = [];
    let read_status = k1_read_bounded(argv[2], source);
    if read_status == 2 { fail("source exceeds the 16 MiB limit"); }
    if read_status != 0 { fail("cannot read source file"); }
    let trace = argv.len == 4;
    if argv[1] == "flow-fixture" { flow_fixture(source, trace); return; }
    if argv[1] == "public-fixture" { public_fixture(source, trace); return; }
    if argv[1] == "module-fixture" { module_fixture(source, trace); return; }
    if argv[1] == "add-fixture" { add_fixture(source, trace); return; }
    if argv[1] == "control-fixture" { control_fixture(source, trace); return; }
    // One compiler-owned job enforces phase ordering throughout the actual
    // private scalar pipeline. This remains partial K1 work accounting.
    var job = work::ScheduledWork {};
    let built = scalar_scheduled::run(source, job);
    if built.status != 0 {
        if built.source_status != 0 && built.status == 1 {
            var detail: u8[>..] = [];
            format(detail, "source error ", built.source_status);
            let diagnostic = catalog::source_diagnostic(built.source_status);
            if diagnostic.len > 0 { format(detail, " (", diagnostic, ")"); }
            format(detail, " at bytes ", built.source_start, "..", built.source_end, "\n");
            write_stderr(detail);
            exit(1);
        }
        fail_scalar_work(built.status);
    }
    // These summaries describe checks that completed successfully; they are
    // not the required full K1 phase trace or a public admission receipt.
    if trace {
        write_stderr("fixture: parsed scalar source\n");
        write_stderr("fixture: validated owned scalar syntax\n");
        write_stderr("fixture: validated scalar structure\n");
        write_stderr("fixture: completed metered scalar Core\n");
        write_stderr("fixture: validated typed scalar lowering plan\n");
        write_stderr("fixture: validated scalar Wasm structure\n");
        write_stderr("fixture: emitted Wasm module\n");
    }
    let hex = "0123456789abcdef";
    var encoded: u8[>..] = [];
    for b in built.bytes { encoded.push(hex[b / 16]); encoded.push(hex[b % 16]); }
    encoded.push('\n');
    write_stdout(encoded);
}
