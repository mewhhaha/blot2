// Bounded diagnostic text records dispatch decisions without rerunning inference.
namespace blot_reuse_dispatch_explanation;
import check.types;
import parse.ast;
import support.error;
import support.option;
import support.json;
type Error = blot_error::Error;
type Text = blot_support::Option<const u8[:]>;
let max_candidates: i64 = 4;
let max_text: i64 = 256;
let max_steps: i64 = 8;
let max_bytes: i64 = 2048;
enum Side { left, builtin, right, destination, receiver, implementation }
enum Outcome { head_mismatch, requires_evidence, incompatible_type, incompatible_effect, selected, overlap, limit, unknown_operand, no_member, incompatible, unsupported_scalar, result_mismatch }
enum ContextKind { left_operand, right_operand }
struct Origin { name: Text, path: Text, span: blot_support::Option<blot_parse_ast::Span> }
struct Step { member: Text, ty: Text, outcome: Outcome }
struct Context { kind: ContextKind, path: Text, span: blot_parse_ast::Span }
struct Candidate { side: Side, origin: blot_support::Option<Origin>, operand: Text, outcome: Outcome }
struct Explanation {
    operation: Text, member: Text, candidates: Candidate[:] = [], steps: Step[:] = [],
    contexts: Context[:] = [], truncated: bool = false,
}
reusable[] var text_runs: u8[>..] = [];
reusable[] var candidate_runs: Candidate[>..] = [];
reusable[] var step_runs: Step[>..] = [];
reusable[] var context_runs: Context[>..] = [];
fn copyText(value: const u8[:]) -> const u8[:] {
    if value.len == 0 { return []; } let out = text_runs.alloc_slice(value.len);
    for byte, index in value { out[index] = byte; } return out;
}
fn freeText(value: Text) {
    if !value.present || value.value.len == 0 { return; }
    let first: const u8& = value.value[0]; let at = text_runs.index_of(first);
    text_runs.free_slice(text_runs[at..at + value.value.len]);
}
fn cloneText(value: Text) -> Text { if value.present { return blot_support::some(copyText(value.value)); } return blot_support::none<const u8[:]>(); }
fn deinit(self: Origin&) { freeText(self.name); freeText(self.path); self.name.present = false; self.path.present = false; }
fn clone(self: Origin) -> Origin { return Origin { cloneText(self.name), cloneText(self.path), self.span }; }
fn deinit(self: Step&) { freeText(self.member); freeText(self.ty); self.member.present = false; self.ty.present = false; }
fn deinit(self: Context&) { freeText(self.path); self.path.present = false; }
fn deinit(self: Candidate&) { freeText(self.operand); if self.origin.present { self.origin.value.deinit(); } self.operand.present = false; self.origin.present = false; }
fn freeCandidates(items: const Candidate[:]) {
    if items.len == 0 { return; } let first: const Candidate& = items[0]; let at = candidate_runs.index_of(first); candidate_runs.free_slice(candidate_runs[at..at + items.len]);
}
fn freeSteps(items: const Step[:]) {
    if items.len == 0 { return; } let first: const Step& = items[0]; let at = step_runs.index_of(first); step_runs.free_slice(step_runs[at..at + items.len]);
}
fn freeContexts(items: const Context[:]) {
    if items.len == 0 { return; } let first: const Context& = items[0]; let at = context_runs.index_of(first); context_runs.free_slice(context_runs[at..at + items.len]);
}
fn copyContexts(items: const Context[:]) -> Context[:] {
    if items.len == 0 { return []; } let out = context_runs.alloc_slice(items.len); for value, index in items { out[index] = value; } return out;
}
fn deinit(self: Explanation&) {
    for &candidate in self.candidates { candidate.deinit(); } for &step in self.steps { step.deinit(); } for &context in self.contexts { context.deinit(); }
    freeCandidates(self.candidates); freeSteps(self.steps); freeContexts(self.contexts); freeText(self.operation); freeText(self.member);
    self = Explanation {};
}
fn clone(self: Explanation) -> Explanation, Error {
    var result = Explanation { operation: cloneText(self.operation), member: cloneText(self.member), truncated: self.truncated };
    if self.candidates.len != 0 {
        let out = candidate_runs.alloc_slice(self.candidates.len);
        for old, index in self.candidates {
            out[index] = Candidate { side: old.side, operand: cloneText(old.operand), outcome: old.outcome };
            if old.origin.present { out[index].origin = blot_support::some(old.origin.value.clone()); }
        }
        result.candidates = out;
    }
    if self.steps.len != 0 {
        let out = step_runs.alloc_slice(self.steps.len);
        for old, index in self.steps { out[index] = Step { cloneText(old.member), cloneText(old.ty), old.outcome }; } result.steps = out;
    }
    if self.contexts.len != 0 {
        let out = context_runs.alloc_slice(self.contexts.len);
        for old, index in self.contexts { out[index] = Context { old.kind, cloneText(old.path), old.span }; } result.contexts = out;
    }
    return result, Error.none;
}
fn jsonStringify(self: Candidate, writer: blot_json::Writer&) -> Error {
    writer.beginObject(); writer.field("side", self.side);
    if self.origin.present { writer.field("origin", self.origin.value); }
    writer.field("operand", self.operand); writer.field("outcome", self.outcome); writer.endObject(); return writer.failure;
}
fn jsonStringify(self: Explanation, writer: blot_json::Writer&) -> Error {
    writer.beginObject(); writer.field("operation", self.operation); writer.field("member", self.member); writer.field("candidates", self.candidates);
    if self.steps.len != 0 { writer.field("steps", self.steps); } if self.contexts.len != 0 { writer.field("contexts", self.contexts); }
    writer.field("truncated", self.truncated); writer.endObject(); return writer.failure;
}
fn removeText(value: Text&) -> bool { if !value.present { return false; } freeText(value); value.present = false; return true; }
fn fit(self: Explanation&) -> Error {
    var needs_bound = self.steps.len != 0 || self.contexts.len != 0;
    for candidate in self.candidates { if candidate.side == Side.implementation { needs_bound = true; } }
    if !needs_bound { return Error.none; }
    loop {
        var bytes: u8[>..<] = []; let error = blot_json::toBytes(self, bytes);
        if error != Error.none { return error; } if bytes.len <= max_bytes { return Error.none; }
        self.truncated = true; var removed = false;
        for &step in self.steps { if removeText(step.ty) || removeText(step.member) { removed = true; break; } }
        if removed { continue; }
        for &context in self.contexts { if removeText(context.path) { removed = true; break; } }
        if removed { continue; }
        for &candidate in self.candidates {
            if removeText(candidate.operand) { removed = true; break; }
            if candidate.origin.present {
                if removeText(candidate.origin.value.path) || removeText(candidate.origin.value.name) { removed = true; break; }
            }
        }
        if !removed { return Error.none; }
    }
}
struct Builder {
    candidates: Candidate[4] = [Candidate { side: Side.left, outcome: Outcome.no_member }; 4],
    len: i64 = 0, steps: Step[8] = [Step { outcome: Outcome.selected }; 8], step_len: i64 = 0, truncated: bool = false,
}
fn deinit(self: Builder&) {
    for index in self.len { self.candidates[index].deinit(); }
    for index in self.step_len { self.steps[index].deinit(); }
    self.len = 0; self.step_len = 0;
}
fn add(self: Builder&, side: Side, operand: Text, outcome: Outcome) {
    if self.len == max_candidates { freeText(operand); self.truncated = true; return; }
    self.candidates[self.len] = Candidate { side: side, operand: operand, outcome: outcome }; self.len++;
}
fn ownText(self: Builder&, value: const u8[:]) -> const u8[:], Error {
    if value.len > max_text { self.truncated = true; } return copyText(value[..boundary(value, max_text)]), Error.none;
}
fn makeOrigin(self: Builder&, name: const u8[:], path: Text, span: blot_support::Option<blot_parse_ast::Span>) -> Origin, Error {
    let owned, error = self.ownText(name); if error != Error.none { return Origin {}, error; }
    var result = Origin { name: blot_support::some(owned), span: span };
    if path.present {
        let owned, error = self.ownText(path.value); if error != Error.none { result.deinit(); return Origin {}, error; } result.path = blot_support::some(owned);
    }
    return result, Error.none;
}
fn addOrigin(self: Builder&, operand: Text, outcome: Outcome, value: Origin) {
    if self.len == max_candidates { freeText(operand); var origin = value; origin.deinit(); self.truncated = true; return; }
    self.candidates[self.len] = Candidate { Side.implementation, blot_support::some(value), operand, outcome }; self.len++;
}
fn addStep(self: Builder&, member: Text, ty: Text, outcome: Outcome) -> Error {
    var value = Step { ty: ty, outcome: outcome };
    if self.step_len == max_steps { value.deinit(); self.truncated = true; return Error.none; }
    if member.present {
        let text, error = self.ownText(member.value); if error != Error.none { value.deinit(); return error; } value.member = blot_support::some(text);
    }
    self.steps[self.step_len] = value; self.step_len++; return Error.none;
}
fn own(self: Builder&, bytes: u8[>..<]&) -> const u8[:], Error {
    if bytes.len > max_text { bytes.resize(boundary(bytes, max_text)); self.truncated = true; }
    let result = copyText(bytes); bytes.clear(); return result, Error.none;
}
fn finish(self: Builder&, operation: Text, member: Text) -> Explanation, Error {
    var result = Explanation { truncated: self.truncated };
    if self.len != 0 { let out = candidate_runs.alloc_slice(self.len); for index in self.len { out[index] = self.candidates[index]; } result.candidates = out; }
    if self.step_len != 0 { let out = step_runs.alloc_slice(self.step_len); for index in self.step_len { out[index] = self.steps[index]; } result.steps = out; }
    self.len = 0; self.step_len = 0;
    if operation.present { result.operation = blot_support::some(copyText(operation.value[..boundary(operation.value, max_text)])); }
    if member.present { if member.value.len > max_text { self.truncated = true; } result.member = blot_support::some(copyText(member.value[..boundary(member.value, max_text)])); }
    let error = result.fit(); if error != Error.none { result.deinit(); return Explanation {}, error; } return result, Error.none;
}
fn boundary(text: const u8[:], limit: i64) -> i64 {
    if text.len <= limit { return text.len; } var end = limit;
    while end > 0 && (text[end] & 0xc0) == 0x80 { end--; } return end;
}

fn operatorSymbol(operator: blot_check_types::Operator) -> Text {
    match operator {
        blot_check_types::Operator.add => { return blot_support::some<const u8[:]>("+"); },
        blot_check_types::Operator.sub => { return blot_support::some<const u8[:]>("-"); },
        blot_check_types::Operator.mul => { return blot_support::some<const u8[:]>("*"); },
        blot_check_types::Operator.div => { return blot_support::some<const u8[:]>("/"); },
        blot_check_types::Operator.rem => { return blot_support::some<const u8[:]>("%"); },
        blot_check_types::Operator.equal => { return blot_support::some<const u8[:]>("=="); },
        blot_check_types::Operator.not_equal => { return blot_support::some<const u8[:]>("!="); },
        blot_check_types::Operator.less => { return blot_support::some<const u8[:]>("<"); },
        blot_check_types::Operator.less_equal => { return blot_support::some<const u8[:]>("<="); },
        blot_check_types::Operator.greater => { return blot_support::some<const u8[:]>(">"); },
        blot_check_types::Operator.greater_equal => { return blot_support::some<const u8[:]>(">="); },
        blot_check_types::Operator.bit_and => { return blot_support::some<const u8[:]>("&"); },
        blot_check_types::Operator.bit_or => { return blot_support::some<const u8[:]>("|"); },
        blot_check_types::Operator.bit_xor => { return blot_support::some<const u8[:]>("^"); },
        blot_check_types::Operator.shift_left => { return blot_support::some<const u8[:]>("<<"); },
        blot_check_types::Operator.shift_right => { return blot_support::some<const u8[:]>(">>"); },
        blot_check_types::Operator.none => { return blot_support::none<const u8[:]>(); },
    }
}

fn operatorMember(operator: blot_check_types::Operator) -> Text {
    match operator {
        blot_check_types::Operator.add => { return blot_support::some<const u8[:]>("add"); },
        blot_check_types::Operator.sub => { return blot_support::some<const u8[:]>("sub"); },
        blot_check_types::Operator.mul => { return blot_support::some<const u8[:]>("mul"); },
        blot_check_types::Operator.div => { return blot_support::some<const u8[:]>("div"); },
        blot_check_types::Operator.rem => { return blot_support::some<const u8[:]>("rem"); },
        blot_check_types::Operator.equal => { return blot_support::some<const u8[:]>("eq"); },
        blot_check_types::Operator.not_equal => { return blot_support::some<const u8[:]>("ne"); },
        blot_check_types::Operator.less => { return blot_support::some<const u8[:]>("lt"); },
        blot_check_types::Operator.less_equal => { return blot_support::some<const u8[:]>("le"); },
        blot_check_types::Operator.greater => { return blot_support::some<const u8[:]>("gt"); },
        blot_check_types::Operator.greater_equal => { return blot_support::some<const u8[:]>("ge"); },
        blot_check_types::Operator.bit_and => { return blot_support::some<const u8[:]>("bit_and"); },
        blot_check_types::Operator.bit_or => { return blot_support::some<const u8[:]>("bit_or"); },
        blot_check_types::Operator.bit_xor => { return blot_support::some<const u8[:]>("bit_xor"); },
        blot_check_types::Operator.shift_left => { return blot_support::some<const u8[:]>("shl"); },
        blot_check_types::Operator.shift_right => { return blot_support::some<const u8[:]>("shr"); },
        blot_check_types::Operator.none => { return blot_support::none<const u8[:]>(); },
    }
}

fn blot_json::write(writer: blot_json::Writer&, value: blot_reuse_dispatch_explanation::Candidate) { if writer.failure == blot_error::Error.none { writer.failure = value.jsonStringify(writer); } }
fn blot_json::write(writer: blot_json::Writer&, value: blot_reuse_dispatch_explanation::Explanation) { if writer.failure == blot_error::Error.none { writer.failure = value.jsonStringify(writer); } }
fn blot_json::write(writer: blot_json::Writer&, value: blot_reuse_dispatch_explanation::Side) { writer.enumValue(value); }
fn blot_json::write(writer: blot_json::Writer&, value: blot_reuse_dispatch_explanation::Outcome) { writer.enumValue(value); }
fn blot_json::write(writer: blot_json::Writer&, value: blot_reuse_dispatch_explanation::ContextKind) { writer.enumValue(value); }
