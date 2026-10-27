import std;
import .model;
import .platform;
import .frontend;

fn integration_diagnostic_name(code: u32) -> const u8[:] {
    if code == 4000 { return "k1_io_error"; }
    if code == 4001 { return "k1_package_escape"; }
    if code == 4002 { return "k1_import_cycle"; }
    if code == 4003 { return "k1_duplicate_import"; }
    if code == 4004 { return "k1_module_limit"; }
    if code == 4005 { return "k1_edition_mismatch"; }
    if code == 4006 { return "k1_invalid_option"; }
    if code == 4007 { return "k1_invalid_export"; }
    if code == 4008 { return "k1_phase_violation"; }
    if code == 4009 { return "k1_cancelled"; }
    if code == 4010 { return "k1_allocation_failure"; }
    if code == 4011 { return "k1_invalid_manifest"; }
    if code == 4012 { return "k1_layout_limit"; }
    if code == 4013 { return "k1_resource_contract"; }
    if code == 4014 { return "k1_formatter_invariant"; }
    if code == 4015 { return "k1_optimizer_invariant"; }
    if code == 4016 { return "k1_interface_fingerprint_limit"; }
    if code == 4020 { return "k1_static_incompatible"; }
    if code == 4021 { return "k1_static_limit"; }
    if code == 4022 { return "k1_static_limit"; }
    if code == 4023 { return "k1_static_limit"; }
    if code == 4024 { return "k1_static_invalid_core"; }
    if code == 4025 { return "k1_semantic_limit"; }
    return "k1_integration_error";
}
fn loader_error(diags: Diagnostic[>..]&, code: u32, origin: u32) -> bool {
    diags.push(Diagnostic { code: code, origin: origin, .. }); return false;
}
fn within_package(root: const u8[:], path: const u8[:]) -> bool {
    if root == "/" { return path.len > 0 && path[0] == '/'; }
    path.len >= root.len && path[..root.len] == root &&
        (path.len == root.len || path[root.len] == '/')
}
fn import_path_valid(path: const u8[:]) -> bool {
    if path.len < 3 || path[..2] != "./" { return false; }
    for c in path { if c == 0 || c == '\\' || c < 32 { return false; } }
    return true;
}
fn parent_end(path: const u8[:]) -> i64 {
    var at = path.len;
    while at > 0 { at--; if path[at] == '/' { return at + 1; } }
    return 0;
}
fn module_at(b: CoreBuilder, path: const u8[:]) -> u32 {
    for m, i in b.modules {
        if i != 0 && name_bytes(core_view(b), m.path) == path { return i as u32; }
    }
    return 0;
}
fn source_origin(b: CoreBuilder, module_id: u32, start: u32, end: u32) -> u32 {
    let id = b.origins.len as u32;
    b.origins.push(Origin { module: module_id, start: start, end: end }); return id;
}
fn read_module(path: const u8[:], b: CoreBuilder, diags: Diagnostic[>..]&) -> u32 {
    if b.modules.len > 4096 { loader_error(diags, 4004, 0); return 0; }
    var source: u8[>..] = [];
    if !read_bounded(path, LIMIT_SOURCE, source) { loader_error(diags, 4000, 0); return 0; }
    let text = Span { start: b.bytes.len as u32, count: source.len as u32 };
    b.bytes.append(source);
    let name = add_name(b, path);
    let id = b.modules.len as u32;
    b.modules.push(Module { name: name, path: name, source: text, .. });
    return id;
}
struct LoadFrame { module_id: u32, next_import: u32, scanned: bool }

// Discovery is iterative and bounded. The output order is dependencies first.
// Nothing outside this candidate Core is modified on an error.
fn load_package(entry: const u8[:], package_root: const u8[:], b: CoreBuilder,
                order: u32[>..]&, diagnostics: Diagnostic[>..]&) -> bool {
    var root: u8[>..] = []; var path: u8[>..] = [];
    if !real_path(package_root, root) || !real_path(entry, path) { return loader_error(diagnostics, 4000, 0); }
    if !within_package(root, path) { return loader_error(diagnostics, 4001, 0); }
    let main_id = read_module(path, b, diagnostics);
    if main_id == 0 { return false; }
    var state: u32[4097] = [0; 4097];
    var stack: LoadFrame[>..<] = [];
    stack.push(LoadFrame { module_id: main_id, next_import: 0, scanned: false });
    state[main_id] = 1;
    var import_edges: u32 = 0;
    while stack.len > 0 {
        let frame = stack[stack.len - 1];
        let module_id = frame.module_id;
        let m = b.modules[module_id];
        if !frame.scanned {
            let source = b.bytes[m.source.start..m.source.start + m.source.count];
            var paths: Span[>..] = []; var aliases: Span[>..] = [];
            var parser_diags: Diagnostic[>..] = [];
            if !frontend_imports(source, paths, aliases, parser_diags) {
                for d in parser_diags {
                    diagnostics.push(Diagnostic { code: d.code,
                        origin: source_origin(b, module_id, d.origin, d.related), detail: d.detail, related: 0 });
                }
                return false;
            }
            if paths.len > 65536 - import_edges { return loader_error(diagnostics, 4004, 0); }
            import_edges += paths.len as u32;
            var imports: u32[>..] = [];
            for ps, i in paths {
                let aspan = aliases[i];
                let alias = source[aspan.start..aspan.start + aspan.count];
                for prev in aliases[..i] {
                    if source[prev.start..prev.start + prev.count] == alias {
                        return loader_error(diagnostics, 4003, source_origin(b, module_id, aspan.start, aspan.start + aspan.count));
                    }
                }
                let relative = source[ps.start..ps.start + ps.count];
                let origin = source_origin(b, module_id, ps.start, ps.start + ps.count);
                if !import_path_valid(relative) { return loader_error(diagnostics, 4001, origin); }
                let importer = name_bytes(core_view(b), m.path);
                var joined = str(importer[..parent_end(importer)], relative);
                var resolved: u8[>..] = [];
                if !real_path(joined, resolved) { return loader_error(diagnostics, 4000, origin); }
                if !within_package(root, resolved) { return loader_error(diagnostics, 4001, origin); }
                var imported = module_at(b, resolved);
                if imported == 0 { imported = read_module(resolved, b, diagnostics); }
                if imported == 0 { return false; }
                imports.push(imported);
            }
            b.modules[module_id].imports = ref_span(b, imports);
            stack[stack.len - 1].scanned = true;
            continue;
        }
        let imports = m.imports;
        if frame.next_import < imports.count {
            let child = b.refs[imports.start + frame.next_import];
            stack[stack.len - 1].next_import++;
            if state[child] == 1 { return loader_error(diagnostics, 4002, 0); }
            if state[child] == 0 {
                state[child] = 1;
                stack.push(LoadFrame { module_id: child, next_import: 0, scanned: false });
            }
        } else {
            state[module_id] = 2;
            order.push(module_id);
            stack.pop();
        }
    }
    return true;
}
