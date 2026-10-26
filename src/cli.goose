import std;
import os;
import .model;
import .loader;
import .plan;
import .frontend;
import .validate;
import .artifact;
import .wasm;
import .manifest;
import .tooling;
import .optimize;
import .fingerprint;
import .driver;

fn diagnostic_name(code: u32) -> const u8[:] {
    if code >= 1000 && code < 2000 { return frontend_diagnostic_name(code); }
    if code >= 2000 && code < 3000 { return validator::validator_diagnostic_name(code); }
    if code >= 3000 && code < 4000 { return "k1_lowering_error"; }
    return integration_diagnostic_name(code);
}
fn show_diagnostics(c: Core, diagnostics: const Diagnostic[:]) {
    for d in diagnostics {
        var text: u8[>..] = [];
        if id_ok(d.origin, c.origins.len) {
            let o = c.origins[d.origin];
            if id_ok(o.module, c.modules.len) && span_ok(c.modules[o.module].source, c.bytes.len) && id_ok(c.modules[o.module].path, c.names.len) && span_ok(c.names[c.modules[o.module].path].bytes, c.bytes.len) {
                let m = c.modules[o.module];
                var line: u32 = 1; var col: u32 = 1;
                let source = c.bytes[m.source.start..m.source.start + m.source.count];
                for ch in source[..min(o.start as i64, source.len)] {
                    if ch == '\n' { line++; col = 1; } else { col++; }
                }
                format(text, name_bytes(c, m.path), ":", line, ":", col, ": ");
            }
        }
        format(text, diagnostic_name(d.code));
        if d.code >= 1000 && d.code < 2000 && id_ok(d.detail, c.names.len) { format(text, ": ", name_bytes(c, d.detail)); }
        else { format(text, " (", d.code, ", detail ", d.detail, ", related ", d.related, ")"); }
        text.push('\n');
        write_stderr(text);
    }
}
fn usage() {
    print("Blot K1 (Goose rewrite, development)");
    print("blot check FILE [--language=k1] [--package-root=DIR] [--timings]");
    print("blot build FILE -o FILE.wasm [--export=NAME] [--emit-core=FILE.bk1]");
    print("blot rebuild FILE.bk1 -o FILE.wasm  # independently validate and lower Core");
    print("blot inspect FILE.bk1 [--language=k1]");
    print("blot format FILE [-o FILE]");
    print("blot migrate FILE");
    print("blot complete PREFIX");
    print("blot serve  # newline-delimited JSON build requests on stdin");
    print("blot --version");
}
fn request_structure_bounded(line: const u8[:]) -> bool {
    var depth: u32 = 0; var quoted = false; var escaped = false; var structures: u32 = 0;
    for byte in line {
        if quoted { if escaped { escaped = false; } else if byte == '\\' { escaped = true; } else if byte == '"' { quoted = false; } continue; }
        if byte == '"' { quoted = true; }
        else if byte == '{' || byte == '[' { depth++; structures++; if depth > 32 || structures > 256 { return false; } }
        else if byte == '}' || byte == ']' { if depth == 0 { return false; } depth--; }
    }
    return !quoted && depth == 0;
}
fn serve_main() {
    // Two bounded revision buffers: candidate allocation happens before output
    // publication; committing is a nonallocating active-index change.
    var cache_a: u8[>..<] = []; var cache_b: u8[>..<] = []; var active: u32 = 0; var revision: u32 = 0;
    while true {
        if active == 0 { cache_b.resize(0); } else { cache_a.resize(0); }
        var line: u8[>..] = []; let line_status = read_line_bounded(65536, line); if line_status == 0 { return; }
        if line_status != 1 || !request_structure_bounded(line) { print("{\"ok\":false,\"error\":\"invalid_request\"}"); flush_stdout(); continue; }
        var nodes: json::Node[>..] = []; var decoded: u8[>..] = [];
        let root, error = json::parse(line, nodes, decoded);
        if !root || line.len > 65536 || nodes.len > 256 { print("{\"ok\":false,\"error\":\"invalid_request\"}"); flush_stdout(); continue; }
        let input, input_ok = json::as_string(json::member(root, "input"));
        let output, output_ok = json::as_string(json::member(root, "output"));
        let package_root, root_ok = json::as_string(json::member(root, "package_root"));
        let selected, selected_ok = json::as_string(json::member(root, "export"));
        let bridge, bridge_ok = json::as_string(json::member(root, "bridge_config"));
        let mode, mode_ok = json::as_string(json::member(root, "opt"));
        let cancel, cancel_ok = json::as_string(json::member(root, "cancel_file"));
        let telemetry, telemetry_ok = json::as_bool(json::member(root, "telemetry"));
        let trace, trace_ok = json::as_bool(json::member(root, "trace"));
        if !input_ok || !output_ok || input.len == 0 || output.len == 0 || mode_ok && mode != "off" && mode != "fast" && mode != "release" {
            print("{\"ok\":false,\"error\":\"invalid_request\"}"); flush_stdout(); continue;
        }
        let config = BuildConfig { input: input, root: if root_ok { package_root } else { "." }, selected: if selected_ok { selected } else { "" }, bridge_config: if bridge_ok { bridge } else { "" }, cancel_file: if cancel_ok { cancel } else { "" }, opt_mode: if mode_ok { mode } else { "off" }, emit: true, telemetry: telemetry_ok && telemetry, trace: trace_ok && trace };
        var success = false; var stats = BuildStats { .. }; var cached = false;
        var cache_admit_ns: i64 = 0; var cache_encode_ns: i64 = 0; var publication_ns: i64 = 0;
        let cache_start = clock_ns();
        // Only the session's immutable buffer may retain source-admission
        // authority. Corrupt optional storage declines to fresh completion.
        with_retained_revision(if active == 0 { cache_a[..] } else { cache_b[..] }, RETAINED_CURRENT_PROCESS, stats.reuse) { prior =>
            cache_admit_ns = clock_ns() - cache_start;
            with_core() { candidate =>
                var diagnostics: Diagnostic[>..] = []; var wasm_bytes: u8[>..] = []; var encoded: u8[>..] = [];
                if !compile_candidate(prior, config, candidate, wasm_bytes, stats, diagnostics) { show_diagnostics(core_view(candidate), diagnostics); return from with_core; }
                let encode_start = clock_ns();
                cached = candidate.receipts.len - 1 <= 16384 && artifact::artifact_encode(core_view(candidate), encoded) && encoded.len <= 134217728;
                if active == 0 { if cached { cache_b.append(encoded); } }
                else { if cached { cache_a.append(encoded); } }
                cache_encode_ns = clock_ns() - encode_start;
                if cancel_ok && file_exists(cancel) { loader_error(diagnostics, 4009, 0); show_diagnostics(core_view(candidate), diagnostics); return from with_core; }
                let publication_start = clock_ns(); let published = write_file_atomic(output, wasm_bytes); publication_ns = clock_ns() - publication_start;
                if !published { loader_error(diagnostics, 4000, 0); show_diagnostics(core_view(candidate), diagnostics); return from with_core; }
                active = 1 - active; revision++; success = true;
            };
        };
        var response: u8[>..] = [];
        format(response, "{\"ok\":", if success { "true" } else { "false" }, ",\"revision\":", revision, ",\"cached\":", if cached { "true" } else { "false" }, ",\"completed_bodies\":", stats.bodies, ",\"reused_bodies\":", stats.reuse.bodies, ",\"cache_declines\":", stats.reuse.declines, ",\"complete_ns\":", stats.complete_ns, ",\"total_ns\":", stats.total_ns, ",\"cache_admit_ns\":", cache_admit_ns, ",\"cache_encode_ns\":", cache_encode_ns, ",\"publication_ns\":", publication_ns, ",\"load_ns\":", stats.load_ns, ",\"plan_ns\":", stats.plan_ns, ",\"validate_ns\":", stats.validate_ns, ",\"lower_ns\":", stats.lower_ns, ",\"semantic_visits\":", stats.semantic_visits, ",\"validation_visits\":", stats.validation_visits, ",\"completed_modules\":", stats.completed_modules, ",\"active_regions\":", stats.active_regions, ",\"downstream_regions\":", stats.downstream_regions, ",\"retained_bytes\":", if active == 0 { cache_a.len } else { cache_b.len });
        append_build_work(response, stats); response.append("}\n");
        write_stdout(response); flush_stdout();
    }
}

fn cli_main() {
    let argv = args();
    if argv.len < 2 || argv[1] == "--help" || argv[1] == "help" { usage(); return; }
    if argv[1] == "--version" {
        print("blot k1-dev goose a108677d300cb0e8bbb842c35a353abe67a20c6c");
        print("K1-SEM-POLICY-1 K1-OPT-POLICY-1 K1-WASM32-ABI1"); return;
    }
    let command = argv[1];
    if command == "serve" { serve_main(); return; }
    if command != "check" && command != "build" && command != "rebuild" && command != "inspect" && command != "format" && command != "migrate" && command != "complete" { write_stderr("k1_invalid_option: unknown command\n"); exit(2); }
    var input: u8[>..] = []; var output: u8[>..] = []; var root: u8[>..] = [];
    var selected: u8[>..] = []; var artifact_path: u8[>..] = []; var cancel_file: u8[>..] = [];
    var bridge_config: u8[>..] = []; var opt_mode: u8[>..] = [];
    var timings = false; var telemetry = false; var trace = false; var next_output = false;
    for arg in argv[2..] {
        if next_output { output.append(arg); next_output = false; continue; }
        if arg == "-o" { next_output = true; continue; }
        if arg == "--timings" { timings = true; continue; }
        if arg == "--telemetry" { telemetry = true; continue; }
        if arg == "--trace" { trace = true; continue; }
        if starts_with(arg, "--language=") {
            if arg != "--language=k1" { write_stderr("k1_edition_mismatch: this branch implements K1 only\n"); exit(2); }
            continue;
        }
        if starts_with(arg, "--opt=") { opt_mode.append(arg[6..]); continue; }
        if starts_with(arg, "--package-root=") { root.append(arg[15..]); continue; }
        if starts_with(arg, "--bridge-config=") { bridge_config.append(arg[16..]); continue; }
        if starts_with(arg, "--export=") { selected.append(arg[9..]); continue; }
        if starts_with(arg, "--emit-core=") { artifact_path.append(arg[12..]); continue; }
        if starts_with(arg, "--cancel-file=") { cancel_file.append(arg[14..]); continue; }
        if starts_with(arg, "-") || input.len != 0 { write_stderr("k1_invalid_option: unexpected argument\n"); exit(2); }
        input.append(arg);
    }
    if input.len == 0 || next_output || ((command == "build" || command == "rebuild") && output.len == 0) {
        write_stderr("k1_invalid_option: provide input and build output\n"); exit(2);
    }
    if command == "complete" { var text: u8[>..] = []; complete_prefix(input, text); write_stdout(text); return; }
    if command == "format" || command == "migrate" {
        var source: u8[>..] = []; var text: u8[>..] = [];
        if !read_bounded(input, LIMIT_SOURCE, source) { write_stderr("k1_io_error\n"); exit(1); }
        if command == "format" {
            var diagnostics: Diagnostic[>..] = [];
            if !format_source(source, text, diagnostics) { write_stderr("k1_syntax: formatter rejected input or a syntax-changing candidate\n"); exit(1); }
        } else {
            var findings: MigrationFinding[>..] = []; migration_findings(source, findings);
            text.append("{\"language\":\"k1\",\"path\":"); json::format_string(text, input);
            text.append(",\"automatic_changes\":0,\"review_required\":true,\"findings\":[");
            for finding, i in findings {
                if i != 0 { text.push(','); }
                format(text, "{\"start\":", finding.start, ",\"end\":", finding.end, ",\"code\":", finding.code, ",\"message\":");
                json::format_string(text, migration_message(finding.code)); text.push('}');
            }
            text.append("]}\n");
        }
        if output.len != 0 { if !write_file_atomic(output, text) { write_stderr("k1_io_error\n"); exit(1); } }
        else { write_stdout(text); }
        return;
    }
    if opt_mode.len == 0 { opt_mode.append("off"); }
    if opt_mode != "off" && opt_mode != "fast" && opt_mode != "release" { write_stderr("k1_invalid_option: --opt=off|fast|release\n"); exit(2); }
    if root.len == 0 { root.append("."); }
    let start = clock_ns();
    with_core() { b =>
        var diagnostics: Diagnostic[>..] = [];
        if command == "inspect" || command == "rebuild" {
            var bytes: u8[>..] = []; var work = Work { .. };
            if command == "rebuild" && (bridge_config.len != 0 || selected.len != 0 || artifact_path.len != 0) { write_stderr("k1_invalid_option: rebuild uses the artifact's checked exports and ABI\n"); exit(2); }
            if cancel_file.len != 0 && file_exists(cancel_file) { write_stderr("k1_cancelled\n"); exit(1); }
            if !read_bounded(input, LIMIT_ARTIFACT, bytes) { loader_error(diagnostics, 4000, 0); }
            else if artifact::artifact_decode(bytes, b, diagnostics) {
                if validator::validate_core(core_view(b), validator::REQUIRED, work, diagnostics) {
                    if command == "rebuild" {
                        var wasm_bytes: u8[>..] = []; var opt_stats = optimize::Stats {}; var optimize_ns: i64 = 0;
                        if !optimized_wasm(core_view(b), opt_mode, wasm_bytes, diagnostics, opt_stats, optimize_ns, telemetry) { show_diagnostics(core_view(b), diagnostics); exit(1); }
                        if cancel_file.len != 0 && file_exists(cancel_file) { write_stderr("k1_cancelled\n"); exit(1); }
                        if !write_file_atomic(output, wasm_bytes) { write_stderr("k1_io_error: Wasm output\n"); exit(1); }
                        return;
                    }
                    print("valid K1 Core: ", b.functions.len - 1, " functions, ", b.ops.len - 1, " operations"); return;
                }
            }
            show_diagnostics(core_view(b), diagnostics); exit(1);
        }
        var wasm_bytes: u8[>..] = []; var core_bytes: u8[>..] = []; var stats = BuildStats { .. };
        let config = BuildConfig { input: input, root: root, selected: selected, bridge_config: bridge_config, cancel_file: cancel_file, opt_mode: opt_mode, emit: command == "build", telemetry: telemetry, trace: trace };
        if !compile_candidate(Core { .. }, config, b, wasm_bytes, stats, diagnostics) { show_diagnostics(core_view(b), diagnostics); exit(1); }
        if artifact_path.len != 0 && !artifact::artifact_encode(core_view(b), core_bytes) { write_stderr("k1_artifact_limit\n"); exit(1); }
        if cancel_file.len != 0 && file_exists(cancel_file) { write_stderr("k1_cancelled\n"); exit(1); }
        // Publication happens only after every required phase has succeeded.
        if artifact_path.len != 0 && command == "build" {
            if !write_output_pair(artifact_path, core_bytes, output, wasm_bytes) { write_stderr("k1_io_error: output transaction\n"); exit(1); }
        } else {
            if artifact_path.len != 0 && !write_file_atomic(artifact_path, core_bytes) { write_stderr("k1_io_error: artifact output\n"); exit(1); }
            if command == "build" && !write_file_atomic(output, wasm_bytes) { write_stderr("k1_io_error: Wasm output\n"); exit(1); }
        }
        if timings {
            var line: u8[>..] = [];
            format(line, "{\"edition\":\"k1\",\"load_ns\":", stats.load_ns,
                ",\"complete_ns\":", stats.complete_ns, ",\"plan_ns\":", stats.plan_ns,
                ",\"validate_ns\":", stats.validate_ns, ",\"lower_ns\":", stats.lower_ns, ",\"optimize_ns\":", stats.optimize_ns,
                ",\"total_ns\":", clock_ns() - start, ",\"completed_bodies\":", stats.bodies, ",\"completed_declarations\":", stats.declarations, ",\"static_bodies\":", stats.static_bodies, ",\"semantic_visits\":", stats.semantic_visits, ",\"validation_visits\":", stats.validation_visits, ",\"completed_modules\":", stats.completed_modules, ",\"active_regions\":", stats.active_regions, ",\"downstream_regions\":", stats.downstream_regions);
            append_build_work(line, stats); line.append("}\n");
            write_stderr(line);
        }
    };
}
