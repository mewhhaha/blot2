// Initial standalone K1 compiler driver. Only the documented scalar slice is
// admitted; all other K1 programs are rejected before any output is written.
import std;
import os;
import frontend;
import parser;
import validate;
import core;
import scalar_core;
import scalar_plan;
import wasm;
import catalog;
import module_frontend;
import module_wasm;
import add_frontend;
import add_source;
import add_parser;
import add_proof;
import add_core;
import add_wasm;

extern fn k1_read_bounded(path: const u8[:], out: u8[>..]&) -> i64;

fn fail(message: u8[:]) {
    write_stderr(str("blot-k1: ", message, "\n"));
    exit(1);
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
    if module.source[..] != source || module_frontend::verify(module) != 0 {
        fail("internal module source validation failure");
    }
    if trace { write_stderr("module fixture: validated source\n"); }
    var completed = module_frontend::to_core(module);
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

fn fail_add_work(work: add_proof::Work) {
    var message: u8[>..] = [];
    if work.limit == 3 { message.append("k1_semantic_limit"); }
    else { message.append("k1_proof_limit"); }
    let measured = if work.limit_quantity == 1 { work.terms }
        else if work.limit_quantity == 2 { work.edges }
        else if work.limit_quantity == 3 { work.proof_visits }
        else { work.semantic_visits };
    format(message, " (quantity ", work.limit_quantity, ", measured ", measured, ")");
    fail(message);
}

// Separate private v4 experiment. The fixed owner/scope and in-memory Work
// are local to this invocation, not cross-compile provenance or a cache key.
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
    var work = add_proof::Work {};
    let proof = add_proof::build(add_core::subject(), work);
    if proof.status != 0 {
        if proof.status == 2 || proof.status == 3 { fail_add_work(work); }
        fail("internal checked-add proof construction failure");
    }
    let checked = add_core::make_core(parsed.core, proof.proof);
    let core_status = add_core::validate_core(source, checked, work);
    if core_status != 0 {
        if core_status == 2 || core_status == 3 { fail_add_work(work); }
        fail("internal checked-add Core validation failure");
    }
    if trace { write_stderr("add fixture: validated Core and evidence\n"); }
    let plan = add_core::make_plan(checked);
    let bytes = add_wasm::emit(source, plan, work);
    if bytes.len == 0 {
        if work.limit == 2 || work.limit == 3 { fail_add_work(work); }
        fail("internal checked-add plan or emission failure");
    }
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
    if (argv.len != 3 && argv.len != 4) || (argv[1] != "fixture" && argv[1] != "module-fixture" && argv[1] != "add-fixture") || (argv.len == 4 && argv[3] != "--trace") {
        fail("usage: blot-k1 fixture|module-fixture|add-fixture ENTRY [--trace] (experimental internal fixture)");
    }
    var source: u8[>..] = [];
    let read_status = k1_read_bounded(argv[2], source);
    if read_status == 2 { fail("source exceeds the 16 MiB limit"); }
    if read_status != 0 { fail("cannot read source file"); }
    let trace = argv.len == 4;
    if argv[1] == "module-fixture" { module_fixture(source, trace); return; }
    if argv[1] == "add-fixture" { add_fixture(source, trace); return; }
    let parsed = frontend::parse_scalar(source);
    if parsed.status != 0 {
        var detail: u8[>..] = [];
        format(detail, "source error ", parsed.status);
        let diagnostic = catalog::source_diagnostic(parsed.status);
        if diagnostic.len > 0 { format(detail, " (", diagnostic, ")"); }
        format(detail, " at bytes ", parsed.start, "..", parsed.end, "\n");
        write_stderr(detail);
        exit(1);
    }
    if trace { write_stderr("fixture: parsed scalar source\n"); }
    // A fresh source-to-Core validator establishes correspondence. The
    // transient record has no portable artifact or cached authority.
    var typed = scalar_core::build(parsed.result_type, parsed.binary_op, parsed.kind,
                                   parsed.literal, parsed.right_kind, parsed.right_literal);
    typed.name_start = parsed.name_start; typed.name_end = parsed.name_end;
    typed.parameter_start = parsed.parameter_start; typed.parameter_end = parsed.parameter_end;
    typed.left_start = parsed.start; typed.left_end = parsed.end;
    typed.operator_start = parsed.operator_start; typed.operator_end = parsed.operator_end;
    typed.right_start = parsed.right_start; typed.right_end = parsed.right_end;
    if validate::scalar_v2(source, typed, catalog::edition(), catalog::semantic_policy(),
                           catalog::optimization_policy(), catalog::wasm_abi()) != 0 {
        fail("invalid scalar representation");
    }
    if trace { write_stderr("fixture: validated scalar structure\n"); }
    // This additional experimental parser/arena check is not public admission.
    // A disagreement after independent source checking is a compiler error.
    var tree, tree_status = parser::parse(source);
    if tree_status != 0 || tree.source[..] != source[..] || !parser::verify(tree) {
        fail("internal scalar syntax mismatch");
    }
    if trace { write_stderr("fixture: validated owned scalar syntax\n"); }
    // The earlier plan model covers unary scalar functions only.
    if parsed.binary_op == 0 {
        let function = core::make_function(parsed.kind + 1, parsed.literal);
        if core::validate_function(function) != 0 { fail("invalid checked scalar function"); }
        if trace { write_stderr("fixture: validated in-memory scalar function\n"); }
        let plan = core::make_plan(function);
        if core::validate_plan(plan) != 0 { fail("invalid scalar lowering plan"); }
        if trace { write_stderr("fixture: validated in-memory lowering plan\n"); }
    }
    let typed_plan = scalar_plan::make(typed);
    if !scalar_plan::validate(typed_plan) { fail("invalid typed scalar lowering plan"); }
    if trace { write_stderr("fixture: validated typed scalar lowering plan\n"); }
    {
        let bytes = wasm::emit_scalar_v2(source[typed_plan.core.name_start..typed_plan.core.name_end], typed_plan);
        if bytes.len == 0 { fail("cannot emit scalar module"); }
        if trace { write_stderr("fixture: emitted Wasm module\n"); }
        // Hex keeps the fixture transport byte-exact across platforms. The
        // driver never opens an output path or replaces an existing file.
        let hex = "0123456789abcdef";
        var encoded: u8[>..] = [];
        for b in bytes {
            encoded.push(hex[b / 16]);
            encoded.push(hex[b % 16]);
        }
        encoded.push('\n');
        write_stdout(encoded);
    }
}
