// Source-backed, owned public scalar interface candidate. This is not a
// CheckedInterface artifact, public admission, package resolver, hash or ABI.
namespace public_interface;
import public_frontend;
import lexer;
import validate;
import catalog;

// Semantic fields only: ABI realization, optimization policy, source origins
// and any digest are deliberately not represented by this candidate.
struct Interface {
    schema: i64 = 0,
    edition: u8[] = [], semantic_policy: u8[] = [],
    package_identity: u8[] = [], module_path: u8[] = [], declaration: u8[] = [],
    visibility: i64 = 0, parameter_type: i64 = 0, result_type: i64 = 0,
    parameter_count: i64 = 0, call_mode: i64 = 0, lifetime: i64 = 0,
    effect_bits: i64 = 0, binder_count: i64 = 0, capture_count: i64 = 0,
    precondition_count: i64 = 0, postcondition_count: i64 = 0,
    on_true_count: i64 = 0, on_false_count: i64 = 0,
    dictionary_count: i64 = 0, layout_premise_count: i64 = 0, data_identity_count: i64 = 0,
    declared_depth: u32 = 0, declared_frame: u32 = 0,
    actual_depth: u32 = 0, actual_frame: u32 = 0
}
struct Result { status: i64 = 1, interface: Interface = Interface {} }

// Package identity is an opaque caller-resolved UTF-8 identifier. Syntax
// checking here cannot establish its namespace, provenance or authority.
fn package_valid(identity: u8[:]) -> bool {
    if identity.len == 0 || identity.len > 16777216 || lexer::invalid_utf8(identity) >= 0 { return false; }
    for b in identity { if b == 0 { return false; } }
    return true;
}
// Exact logical module path, no normalization or filesystem resolution here.
fn module_valid(path: u8[:]) -> bool {
    if path.len == 0 || path.len > 16777216 || lexer::invalid_utf8(path) >= 0 || path[0] == '/' { return false; }
    if path.len >= 2 && ((path[0] >= 'a' && path[0] <= 'z') || (path[0] >= 'A' && path[0] <= 'Z')) && path[1] == ':' { return false; }
    var component: i64 = 0;
    for b, i in path {
        if b == 0 || b == '\\' { return false; }
        if b == '/' {
            if i == component || path[component..i] == "." || path[component..i] == ".." { return false; }
            component = i + 1;
        }
    }
    if component == path.len || path[component..] == "." || path[component..] == ".." { return false; }
    return true;
}
fn identity_valid(package: u8[:], module: u8[:], declaration: u8[:]) -> bool {
    if !package_valid(package) || !module_valid(module) || declaration.len == 0 ||
       declaration.len > 16777216 || !validate::name_valid(declaration) { return false; }
    // Bound total owned producer bytes with subtraction, before allocating.
    if module.len > 16777216 - package.len { return false; }
    if declaration.len > 16777216 - package.len - module.len { return false; }
    return true;
}

// expected package/module/declaration are trusted request inputs, never read
// from a self-asserted artifact. The package resolver remains a separate
// prerequisite and this check does not confer package authority.
fn build(source: u8[:], candidate: public_frontend::Candidate, package: u8[:],
         module: u8[:], declaration: u8[:]) -> Result {
    if !identity_valid(package, module, declaration) || !public_frontend::verify(source, candidate) { return Result {}; }
    if source[candidate.core.name_start..candidate.core.name_end] != declaration { return Result {}; }
    return Result { status: 0, interface: Interface {
        schema: 1, edition: catalog::edition(), semantic_policy: catalog::semantic_policy(),
        package_identity: package, module_path: module, declaration: declaration,
        visibility: 1, parameter_type: 1, result_type: candidate.core.result_type,
        parameter_count: 1, call_mode: 1, lifetime: 1,
        declared_depth: candidate.declared_depth, declared_frame: candidate.declared_frame,
        actual_depth: 1, actual_frame: 0
    } };
}

// Re-recognize the original source, compare the caller-supplied producer tuple
// and all semantic fields, and reject altered declared bounds or visibility.
// No interface bit or previous build/validation stamp is treated as authority.
fn check(source: u8[:], candidate: public_frontend::Candidate, package: u8[:],
         module: u8[:], declaration: u8[:], interface: Interface&) -> i64 {
    if !identity_valid(package, module, declaration) || !public_frontend::verify(source, candidate) { return 1; }
    if source[candidate.core.name_start..candidate.core.name_end] != declaration { return 1; }
    if interface.schema != 1 || interface.edition[..] != catalog::edition() ||
       interface.semantic_policy[..] != catalog::semantic_policy() ||
       interface.package_identity[..] != package || interface.module_path[..] != module ||
       interface.declaration[..] != declaration || interface.visibility != 1 ||
       interface.parameter_type != 1 || interface.result_type != candidate.core.result_type ||
       interface.parameter_count != 1 || interface.call_mode != 1 || interface.lifetime != 1 ||
       interface.effect_bits != 0 || interface.binder_count != 0 || interface.capture_count != 0 ||
       interface.precondition_count != 0 || interface.postcondition_count != 0 ||
       interface.on_true_count != 0 || interface.on_false_count != 0 ||
       interface.dictionary_count != 0 || interface.layout_premise_count != 0 ||
       interface.data_identity_count != 0 ||
       interface.declared_depth != candidate.declared_depth || interface.declared_frame != candidate.declared_frame ||
       interface.actual_depth != 1 || interface.actual_frame != 0 ||
       interface.actual_depth > interface.declared_depth || interface.actual_frame > interface.declared_frame { return 1; }
    return 0;
}
