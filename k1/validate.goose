// Validation of the narrow, transient scalar fixture. This is not a decoder
// for portable artifacts or the full K1 independent Core validator.
namespace validate;
import work;
import scalar_core;

fn letter(c: u8) -> bool {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}
fn digit(c: u8) -> bool { return c >= '0' && c <= '9'; }

fn name_valid(name: u8[:]) -> bool {
    if name.len == 0 || !letter(name[0]) { return false; }
    for c, i in name {
        if i > 0 && !letter(c) && !digit(c) { return false; }
    }
    return name != "_" && name != "import" && name != "as" && name != "pub" &&
        name != "let" && name != "static" && name != "local" && name != "type" &&
        name != "fn" && name != "in" && name != "do" && name != "return" &&
        name != "break" && name != "continue" && name != "next" && name != "stop" &&
        name != "seal" && name != "abort" && name != "if" && name != "else" &&
        name != "case" && name != "for" && name != "carry" && name != "invariant" &&
        name != "forall" && name != "exists" && name != "where" &&
        name != "requires" && name != "ensures" && name != "on_true" &&
        name != "on_false" && name != "resources" && name != "region" &&
        name != "owned" && name != "pack" && name != "open" && name != "space" &&
        name != "dest" && name != "env" && name != "builder" && name != "view" &&
        name != "index" && name != "array" && name != "U32" && name != "F32" &&
        name != "Unit" && name != "Bool" && name != "RegionOwner" && name != "Space" &&
        name != "Dest" && name != "EnvDest" && name != "Builder" && name != "View" &&
        name != "Index" && name != "Fn" && name != "Owned" && name != "Result" &&
        name != "Many" && name != "Once" && name != "Append" && name != "Resize" &&
        name != "Type" && name != "Region" && name != "Nat" && name != "Domain" &&
        name != "Plain" && name != "Share";
}

// Reject malformed UTF-8 throughout the source, including comments.
fn valid_utf8(source: u8[:]) -> bool {
    var i: i64 = 0;
    while i < source.len {
        let a = source[i];
        if a < 128 { i += 1; continue; }
        if a >= 194 && a <= 223 {
            if i + 1 >= source.len { return false; }
            let b = source[i + 1];
            if b < 128 || b > 191 { return false; }
            i += 2; continue;
        }
        if a >= 224 && a <= 239 {
            if i + 2 >= source.len { return false; }
            let b = source[i + 1];
            let c = source[i + 2];
            if b < 128 || b > 191 || c < 128 || c > 191 { return false; }
            if a == 224 && b < 160 { return false; }
            if a == 237 && b > 159 { return false; }
            i += 3; continue;
        }
        if a >= 240 && a <= 244 {
            if i + 3 >= source.len { return false; }
            let b = source[i + 1];
            let c = source[i + 2];
            let d = source[i + 3];
            if b < 128 || b > 191 || c < 128 || c > 191 || d < 128 || d > 191 { return false; }
            if a == 240 && b < 144 { return false; }
            if a == 244 && b > 143 { return false; }
            i += 4; continue;
        }
        return false;
    }
    return true;
}

// This recognizer intentionally does not call the frontend. It checks that
// the proposed scalar operations actually correspond to the original source.
struct Token { tag: i64, start: i64, end: i64 }
fn scan(source: u8[:], from: i64) -> Token {
    var p = from;
    while p < source.len {
        let c = source[p];
        if c == ' ' { p += 1; continue; }
        if c == '\r' && p + 1 < source.len && source[p + 1] == '\n' { p += 1; continue; }
        if c == '/' && p + 1 < source.len && source[p + 1] == '/' {
            p += 2;
            while p < source.len && source[p] != '\n' { p += 1; }
            continue;
        }
        break;
    }
    let start = p;
    if p == source.len { return Token { 0, p, p }; }
    let c = source[p];
    if c == '\n' { return Token { 1, p, p + 1 }; }
    if letter(c) {
        p += 1;
        while p < source.len && (letter(source[p]) || digit(source[p])) { p += 1; }
        return Token { 2, start, p };
    }
    if digit(c) {
        p += 1;
        while p < source.len && digit(source[p]) { p += 1; }
        return Token { 3, start, p };
    }
    if c == ':' { return Token { 4, p, p + 1 }; }
    if c == '=' {
        if p + 1 < source.len && source[p + 1] == '>' { return Token { 7, p, p + 2 }; }
        return Token { 5, p, p + 1 };
    }
    if c == '-' && p + 1 < source.len && source[p + 1] == '>' { return Token { 6, p, p + 2 }; }
    if c == '&' {
        if p + 1 < source.len && source[p + 1] == '&' { return Token { 8, p, p + 2 }; }
        return Token { 10, p, p + 1 };
    }
    if c == '<' {
        if p + 1 < source.len && (source[p + 1] == '<' || source[p + 1] == '=') { return Token { 8, p, p + 2 }; }
        return Token { 11, p, p + 1 };
    }
    return Token { 8, p, p + 1 };
}
// Optional shared work is enabled only by scalar_v2_with_work. The
// original validator stays available for isolated artifacts and compatibility.
struct VisitLimit {
    enabled: bool = false, hit: bool = false, cause: u32 = 0,
    source_phase: u32 = 2, core_phase: u32 = 5
}
fn visit(meter: work::Meter&, limit: VisitLimit&, phase: u32, event: u32) -> bool {
    if !limit.enabled { return true; }
    if limit.hit { return false; }
    let receipt = work::charge(meter, phase, event);
    if receipt.status != 0 { limit.hit = true; limit.cause = receipt.status; return false; }
    return true;
}
fn charged_scan(source: u8[:], from: i64, meter: work::Meter&, limit: VisitLimit&) -> Token {
    if limit.hit { return Token { 12, from, from }; }
    let token = scan(source, from);
    if token.tag == 0 || token.tag == 1 { return token; }
    if !visit(meter, limit, limit.source_phase, 1) { return Token { 12, token.start, token.start }; }
    return token;
}

fn word(source: u8[:], token: Token, expected: u8[:]) -> bool {
    return token.tag == 2 && source[token.start..token.end] == expected;
}
fn suite(source: u8[:], from: i64, indent: i64) -> Token {
    var t = scan(source, from);
    if t.tag != 1 { return Token { 8, t.start, t.end }; }
    t = scan(source, t.end);
    while t.tag == 1 { t = scan(source, t.end); }
    if t.tag == 0 { return Token { 8, t.start, t.end }; }
    var start = t.start;
    while start > 0 && source[start - 1] != '\n' { start -= 1; }
    if t.start - start != indent { return Token { 8, start, t.start }; }
    return t;
}
fn suite_v2_work(source: u8[:], from: i64, indent: i64,
                 meter: work::Meter&, limit: VisitLimit&) -> Token {
    var t = charged_scan(source, from, meter, limit);
    if t.tag != 1 { return Token { 8, t.start, t.end }; }
    if !visit(meter, limit, limit.source_phase, 1) { return Token { 12, t.start, t.start }; }
    t = charged_scan(source, t.end, meter, limit);
    while t.tag == 1 { t = charged_scan(source, t.end, meter, limit); }
    if t.tag == 0 { return Token { 8, t.start, t.end }; }
    var line = t.start;
    while line > 0 && source[line - 1] != '\n' { line -= 1; }
    if t.start - line != indent { return Token { 8, line, t.start }; }
    return t;
}

fn corresponds(source: u8[:], start: i64, end: i64, name_start: i64,
               name_end: i64, kind: i64) -> bool {
    var t = scan(source, 0);
    while t.tag == 1 { t = scan(source, t.end); }
    if !word(source, t, "let") { return false; }
    var line = t.start;
    while line > 0 && source[line - 1] != '\n' { line -= 1; }
    if line != t.start { return false; }
    t = scan(source, t.end);
    if t.tag != 2 || t.start != name_start || t.end != name_end ||
       !name_valid(source[t.start..t.end]) { return false; }
    t = scan(source, t.end);
    if t.tag != 4 { return false; }
    t = scan(source, t.end);
    if !word(source, t, "U32") { return false; }
    t = scan(source, t.end);
    if t.tag != 6 { return false; }
    t = scan(source, t.end);
    if !word(source, t, "U32") { return false; }
    t = scan(source, t.end);
    if t.tag != 5 { return false; }
    t = scan(source, t.end);
    if !word(source, t, "fn") { return false; }
    t = scan(source, t.end);
    if t.tag != 2 || !name_valid(source[t.start..t.end]) { return false; }
    let parameter_start = t.start;
    let parameter_end = t.end;
    t = scan(source, t.end);
    if t.tag != 7 { return false; }
    t = scan(source, t.end);
    var body_indent: i64 = 0;
    if word(source, t, "do") {
        t = scan(source, t.end);
        if t.tag != 4 { return false; }
        t = suite(source, t.end, 2);
        if t.tag == 8 { return false; }
        body_indent = 2;
    }
    if !word(source, t, "return") { return false; }
    t = scan(source, t.end);
    if word(source, t, "do") {
        t = scan(source, t.end);
        if t.tag != 4 { return false; }
        t = suite(source, t.end, body_indent + 2);
        if t.tag == 8 || (!word(source, t, "break") && !word(source, t, "return")) { return false; }
        t = scan(source, t.end);
    }
    if t.start != start || t.end != end { return false; }
    if kind == 0 {
        if t.tag != 2 || source[t.start..t.end] != source[parameter_start..parameter_end] { return false; }
    } else if kind == 1 {
        if t.tag != 3 { return false; }
    } else { return false; }
    t = scan(source, t.end);
    while t.tag == 1 { t = scan(source, t.end); }
    return t.tag == 0;
}

// Return 0 for a structurally valid fixture, 1 for invalid structure, and 2
// for incompatible version identifiers. All offsets are checked before slices.
// This independently rechecks this narrow source-to-fixture correspondence.
// Untrusted serialized artifacts and general Core require further validation.
fn scalar(source: u8[:], start: i64, end: i64, name_start: i64, name_end: i64,
          kind: i64, literal: u32, edition: u8[:], sem_policy: u8[:],
          opt_policy: u8[:], abi: u8[:]) -> i64 {
    if edition != "k1" || sem_policy != "K1-SEM-POLICY-1" ||
       opt_policy != "K1-OPT-POLICY-1" || abi != "K1-WASM32-ABI1" { return 2; }
    if source.len > 16777216 || start < 0 || end <= start || end > source.len ||
       name_start < 0 || name_end <= name_start || name_end > source.len { return 1; }
    if !valid_utf8(source) { return 1; }
    if !name_valid(source[name_start..name_end]) { return 1; }
    if !corresponds(source, start, end, name_start, name_end, kind) { return 1; }
    let operand = source[start..end];
    if kind == 0 {
        if literal != 0 || !name_valid(operand) { return 1; }
    } else if kind == 1 {
        var value: u64 = 0;
        for c in operand {
            if !digit(c) { return 1; }
            let digit_value = (c - '0') as u64;
            if value > (4294967295 - digit_value) / 10 { return 1; }
            value = value * 10 + digit_value;
        }
        if value != literal { return 1; }
    } else { return 1; }
    return 0;
}

// SC02 validation uses the recognizer above, independently of the frontend and
// Core builder. All indexes below are bounded before touching the Core array.
struct Atom { ok: bool = false, id: i64 = 0, next: i64 = 0 }
fn zero_value(value: scalar_core::ScalarValue) -> bool {
    return value.producer == 0 && value.type_id == 0 && value.op_id == 0 &&
        value.literal == 0 && value.left_id == 0 && value.right_id == 0;
}
fn core_atom(source: u8[:], t: Token, parameter_start: i64, parameter_end: i64,
             core: scalar_core::ScalarCore, value_count: i64, next: i64, meter: work::Meter&, limit: VisitLimit&) -> Atom {
    if t.tag == 2 {
        if source[t.start..t.end] != source[parameter_start..parameter_end] { return Atom {}; }
        return Atom { ok: true, id: 0, next: next };
    }
    if t.tag != 3 || next >= value_count || next >= 4 { return Atom {}; }
    var number: u64 = 0;
    for i in t.start..t.end {
        let digit_value = (source[i] - '0') as u64;
        if number > (4294967295 - digit_value) / 10 { return Atom {}; }
        number = number * 10 + digit_value;
    }
    if !visit(meter, limit, limit.core_phase, 4) { return Atom {}; }
    let value = core.values[next];
    if value.producer != 2 || value.type_id != 1 || value.op_id != 0 ||
       value.literal != number || value.left_id != 0 || value.right_id != 0 { return Atom {}; }
    return Atom { ok: true, id: next, next: next + 1 };
}

fn scalar_v2_impl(source: u8[:], core: scalar_core::ScalarCore, edition: u8[:],
             sem_policy: u8[:], opt_policy: u8[:], abi: u8[:],
             meter: work::Meter&, limit: VisitLimit&) -> i64 {
    if edition != "k1" || sem_policy != "K1-SEM-POLICY-1" ||
       opt_policy != "K1-OPT-POLICY-1" || abi != "K1-WASM32-ABI1" { return 2; }
    if source.len > 16777216 || !valid_utf8(source) { return 1; }
    if !visit(meter, limit, limit.core_phase, 4) { return 1; }
    // Snapshot all scalar header fields during this visit. Result ID is an
    // edge and is deliberately read only after its separate charge below.
    let value_count = core.value_count;
    let result_type = core.result_type;
    let name_start = core.name_start; let name_end = core.name_end;
    let declared_parameter_start = core.parameter_start; let declared_parameter_end = core.parameter_end;
    let left_start = core.left_start; let left_end = core.left_end;
    let operator_start = core.operator_start; let operator_end = core.operator_end;
    let right_start = core.right_start; let right_end = core.right_end;
    if value_count < 1 || value_count > 4 { return 1; }
    if !visit(meter, limit, limit.core_phase, 4) { return 1; }
    if core.terminator != 1 { return 1; }
    // Unused fixed slots are bounded representation fields, not Core nodes;
    // inspect them while visiting the owning header.
    for i in value_count..4 { if !zero_value(core.values[i]) { return 1; } }
    if !visit(meter, limit, limit.core_phase, 4) { return 1; }
    let parameter = core.values[0];
    if parameter.producer != 1 || parameter.type_id != 1 || parameter.op_id != 0 ||
       parameter.literal != 0 || parameter.left_id != 0 || parameter.right_id != 0 { return 1; }
    var t = charged_scan(source, 0, meter, limit);
    while t.tag == 1 { t = charged_scan(source, t.end, meter, limit); }
    if !word(source, t, "let") { return 1; }
    var line = t.start;
    while line > 0 && source[line - 1] != '\n' { line -= 1; }
    if line != t.start { return 1; }
    t = charged_scan(source, t.end, meter, limit);
    if t.tag != 2 || t.start != name_start || t.end != name_end ||
       !name_valid(source[t.start..t.end]) { return 1; }
    t = charged_scan(source, t.end, meter, limit);
    if t.tag != 4 { return 1; }
    t = charged_scan(source, t.end, meter, limit);
    if !word(source, t, "U32") { return 1; }
    t = charged_scan(source, t.end, meter, limit);
    if t.tag != 6 { return 1; }
    t = charged_scan(source, t.end, meter, limit);
    if result_type == 1 {
        if !word(source, t, "U32") { return 1; }
    } else if result_type == 2 {
        if !word(source, t, "Bool") { return 1; }
    } else { return 1; }
    t = charged_scan(source, t.end, meter, limit);
    if t.tag != 5 { return 1; }
    t = charged_scan(source, t.end, meter, limit);
    if !word(source, t, "fn") { return 1; }
    t = charged_scan(source, t.end, meter, limit);
    if t.tag != 2 || t.start != declared_parameter_start || t.end != declared_parameter_end ||
       !name_valid(source[t.start..t.end]) { return 1; }
    let parameter_start = t.start;
    let parameter_end = t.end;
    t = charged_scan(source, t.end, meter, limit);
    if t.tag != 7 { return 1; }
    t = charged_scan(source, t.end, meter, limit);
    var body_indent: i64 = 0;
    if word(source, t, "do") {
        t = charged_scan(source, t.end, meter, limit);
        if t.tag != 4 { return 1; }
        t = suite_v2_work(source, t.end, 2, meter, limit);
        if t.tag == 8 { return 1; }
        body_indent = 2;
    }
    if !word(source, t, "return") { return 1; }
    t = charged_scan(source, t.end, meter, limit);
    if word(source, t, "do") {
        t = charged_scan(source, t.end, meter, limit);
        if t.tag != 4 { return 1; }
        t = suite_v2_work(source, t.end, body_indent + 2, meter, limit);
        if t.tag == 8 || (!word(source, t, "break") && !word(source, t, "return")) { return 1; }
        t = charged_scan(source, t.end, meter, limit);
    }
    if t.start != left_start || t.end != left_end { return 1; }
    let left = core_atom(source, t, parameter_start, parameter_end, core, value_count, 1, meter, limit);
    if !left.ok { return 1; }
    t = charged_scan(source, t.end, meter, limit);
    if t.tag == 10 || t.tag == 11 {
        let op = if t.tag == 10 { 1 } else { 2 };
        if t.start != operator_start || t.end != operator_end ||
           (op == 1 && result_type != 1) || (op == 2 && result_type != 2) { return 1; }
        t = charged_scan(source, t.end, meter, limit);
        if t.start != right_start || t.end != right_end { return 1; }
        let right = core_atom(source, t, parameter_start, parameter_end, core, value_count, left.next, meter, limit);
        if !right.ok || right.next >= value_count || right.next >= 4 { return 1; }
        if !visit(meter, limit, limit.core_phase, 4) { return 1; }
        let op_value = core.values[right.next];
        if op_value.producer != 3 || op_value.type_id != result_type || op_value.op_id != op ||
           op_value.literal != 0 { return 1; }
        // Charge each actual Core value edge immediately before inspecting it.
        if !visit(meter, limit, limit.core_phase, 5) || op_value.left_id != left.id { return 1; }
        if !visit(meter, limit, limit.core_phase, 5) || op_value.right_id != right.id { return 1; }
        if !visit(meter, limit, limit.core_phase, 5) { return 1; }
        let result_id = core.result_id;
        if result_id != right.next || value_count != right.next + 1 { return 1; }
        t = charged_scan(source, t.end, meter, limit);
    } else {
        if result_type != 1 { return 1; }
        if !visit(meter, limit, limit.core_phase, 5) { return 1; }
        let result_id = core.result_id;
        if result_id != left.id || value_count != left.next ||
           operator_start != 0 || operator_end != 0 || right_start != 0 || right_end != 0 { return 1; }
    }
    while t.tag == 1 { t = charged_scan(source, t.end, meter, limit); }
    if t.tag != 0 { return 1; }
    return 0;
}

// 0 valid, 1 invalid, 2 incompatible, 3 semantic limit, 4 accounting error.
// A caller-owned meter covers both source-token and Core-record visits. Other
// fixture components are still unmetered; this is not a complete receipt.
fn scalar_v2_with_work(source: u8[:], core: scalar_core::ScalarCore, edition: u8[:],
                       sem_policy: u8[:], opt_policy: u8[:], abi: u8[:], meter: work::Meter&) -> i64 {
    var limit = VisitLimit { enabled: true };
    let result = scalar_v2_impl(source, core, edition, sem_policy, opt_policy, abi, meter, limit);
    if limit.hit { return if limit.cause == 1 { 3 } else { 4 }; }
    return result;
}
// A repeated validation performed by a later required phase is charged to
// that phase instead of being attributed to the original source check.
fn scalar_v2_with_work_at_phase(source: u8[:], core: scalar_core::ScalarCore, edition: u8[:],
             sem_policy: u8[:], opt_policy: u8[:], abi: u8[:], meter: work::Meter&, phase: u32) -> i64 {
    if phase != 2 && phase != 5 && phase != 6 && phase != 7 { return 4; }
    var limit = VisitLimit { enabled: true, source_phase: phase, core_phase: phase };
    let result = scalar_v2_impl(source, core, edition, sem_policy, opt_policy, abi, meter, limit);
    if limit.hit { return if limit.cause == 1 { 3 } else { 4 }; }
    return result;
}
fn scalar_v2(source: u8[:], core: scalar_core::ScalarCore, edition: u8[:],
             sem_policy: u8[:], opt_policy: u8[:], abi: u8[:]) -> i64 {
    var meter = work::Meter {};
    var limit = VisitLimit {};
    return scalar_v2_impl(source, core, edition, sem_policy, opt_policy, abi, meter, limit);
}
