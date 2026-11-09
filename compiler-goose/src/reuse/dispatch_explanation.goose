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
    operation: Text, member: Text, candidates: Candidate[:] = default<Candidate[:]>(), steps: Step[:] = default<Step[:]>(),
    contexts: Context[:] = default<Context[:]>(), truncated: bool = false,
}
reusable[] var text_runs: u8[>..] = [];
reusable[] var candidate_runs: Candidate[>..] = [];
reusable[] var step_runs: Step[>..] = [];
reusable[] var context_runs: Context[>..] = [];
fn copyText(value: const u8[:]) -> const u8[:] {
    if value.len == 0 { return default<const u8[:]>(); } let out = text_runs.alloc_slice(value.len);
    for byte, index in value { out[index] = byte; } return out;
}
fn freeText(value: Text) {
    if !value.present || value.value.len == 0 { return; }
    text_runs.free_slice(value.value);
}
fn cloneText(value: Text) -> Text { if value.present { return blot_support::some<const u8[:]>(copyText(value.value)); } return blot_support::none<const u8[:]>(); }
fn deinit(self_: Origin&) { freeText(self_.name); freeText(self_.path); self_.name.present = false; self_.path.present = false; }
fn clone(self_: Origin) -> Origin { return canonicalOrigin(Origin { cloneText(self_.name), cloneText(self_.path), self_.span , ..}); }
fn deinit(self_: Step&) { freeText(self_.member); freeText(self_.ty); self_.member.present = false; self_.ty.present = false; }
fn deinit(self_: Context&) { freeText(self_.path); self_.path.present = false; }
fn deinit(self_: Candidate&) { freeText(self_.operand); if self_.origin.present { self_.origin.value.deinit(); } self_.operand.present = false; self_.origin.present = false; }
fn freeCandidates(items: const Candidate[:]) {
    if items.len == 0 { return; } candidate_runs.free_slice(items);
}
fn freeSteps(items: const Step[:]) {
    if items.len == 0 { return; } step_runs.free_slice(items);
}
fn freeContexts(items: const Context[:]) {
    if items.len == 0 { return; } context_runs.free_slice(items);
}
fn copyContexts(items: const Context[:]) -> Context[:] {
    if items.len == 0 { return default<Context[:]>(); } let out = context_runs.alloc_slice(items.len); for value, index in items { out[index] = canonicalContext(value); } return out;
}
fn deinit(self_: Explanation&) {
    for &candidate in self_.candidates { candidate.deinit(); } for &step in self_.steps { step.deinit(); } for &context in self_.contexts { context.deinit(); }
    freeCandidates(self_.candidates); freeSteps(self_.steps); freeContexts(self_.contexts); freeText(self_.operation); freeText(self_.member);
    self_ = Explanation {..};
}
fn clone(self_: Explanation) -> Explanation, Error {
    var result = Explanation { operation: cloneText(self_.operation), member: cloneText(self_.member), truncated: self_.truncated , ..};
    if self_.candidates.len != 0 {
        let out = candidate_runs.alloc_slice(self_.candidates.len);
        for old, index in self_.candidates {
            out[index] = canonicalCandidate(Candidate { side: old.side, operand: cloneText(old.operand), outcome: old.outcome , ..});
            if old.origin.present { out[index].origin = blot_support::some(canonicalOrigin(old.origin.value.clone())); }
        }
        result.candidates = out;
    }
    if self_.steps.len != 0 {
        let out = step_runs.alloc_slice(self_.steps.len);
        for old, index in self_.steps { out[index] = canonicalStep(Step { cloneText(old.member), cloneText(old.ty), old.outcome , ..}); } result.steps = out;
    }
    if self_.contexts.len != 0 {
        let out = context_runs.alloc_slice(self_.contexts.len);
        for old, index in self_.contexts { out[index] = canonicalContext(Context { old.kind, cloneText(old.path), old.span , ..}); } result.contexts = out;
    }
    return result, blot_error::Error.none;
}
fn jsonStringify(self_: Candidate, writer: blot_json::Writer&) -> Error {
    writer.beginObject(); writer.field("side", self_.side);
    if self_.origin.present { writer.field("origin", self_.origin.value); }
    writer.field("operand", self_.operand); writer.field("outcome", self_.outcome); writer.endObject(); return writer.failure;
}
fn jsonStringify(self_: Explanation, writer: blot_json::Writer&) -> Error {
    writer.beginObject(); writer.field("operation", self_.operation); writer.field("member", self_.member); writer.field("candidates", self_.candidates);
    if self_.steps.len != 0 { writer.field("steps", self_.steps); } if self_.contexts.len != 0 { writer.field("contexts", self_.contexts); }
    writer.field("truncated", self_.truncated); writer.endObject(); return writer.failure;
}
fn removeText(value: Text&) -> bool { if !value.present { return false; } freeText(value); value.present = false; return true; }
fn fit(self_: Explanation&) -> Error {
    var needs_bound = self_.steps.len != 0 || self_.contexts.len != 0;
    for candidate in self_.candidates { if candidate.side == Side.implementation { needs_bound = true; } }
    if !needs_bound { return blot_error::Error.none; }
    loop {
        var bytes: u8[>..] = []; let error = blot_json::toBytes(self_, bytes);
        if error != blot_error::Error.none { return error; } if bytes.len <= max_bytes { return blot_error::Error.none; }
        self_.truncated = true; var removed = false;
        for &step in self_.steps { if removeText(step.ty) || removeText(step.member) { removed = true; break; } }
        if removed { continue; }
        for &context in self_.contexts { if removeText(context.path) { removed = true; break; } }
        if removed { continue; }
        for &candidate in self_.candidates {
            if removeText(candidate.operand) { removed = true; break; }
            if candidate.origin.present {
                if removeText(candidate.origin.value.path) || removeText(candidate.origin.value.name) { removed = true; break; }
            }
        }
        if !removed { return blot_error::Error.none; }
    }
}
struct Builder {
    candidates: Candidate[4] = [Candidate { side: Side.left, outcome: Outcome.no_member , ..}; 4],
    len: i64 = 0, steps: Step[8] = [Step { outcome: Outcome.selected , ..}; 8], step_len: i64 = 0, truncated: bool = false,
}
fn deinit(self_: Builder&) {
    for index in self_.len { self_.candidates[index].deinit(); }
    for index in self_.step_len { self_.steps[index].deinit(); }
    self_.len = 0; self_.step_len = 0;
}
fn add(self_: Builder&, side: Side, operand: Text, outcome: Outcome) {
    if self_.len == max_candidates { freeText(operand); self_.truncated = true; return; }
    self_.candidates[self_.len] = canonicalCandidate(Candidate { side: side, operand: operand, outcome: outcome , ..}); self_.len++;
}
fn ownText(self_: Builder&, value: const u8[:]) -> const u8[:], Error {
    if value.len > max_text { self_.truncated = true; } return copyText(value[..boundary(value, max_text)]), blot_error::Error.none;
}
fn makeOrigin(self_: Builder&, name: const u8[:], path: Text, span: blot_support::Option<blot_parse_ast::Span>) -> Origin, Error {
    let owned, error = self_.ownText(name); if error != blot_error::Error.none { return Origin {..}, error; }
    var result = Origin { name: blot_support::some<const u8[:]>(owned), span: span , ..};
    if path.present {
        let owned, error = self_.ownText(path.value); if error != blot_error::Error.none { result.deinit(); return Origin {..}, error; } result.path = blot_support::some<const u8[:]>(owned);
    }
    return result, blot_error::Error.none;
}
fn addOrigin(self_: Builder&, operand: Text, outcome: Outcome, value: Origin) {
    if self_.len == max_candidates { freeText(operand); var origin = value; origin.deinit(); self_.truncated = true; return; }
    self_.candidates[self_.len] = canonicalCandidate(Candidate { Side.implementation, blot_support::some(value), operand, outcome , ..}); self_.len++;
}
fn addStep(self_: Builder&, member: Text, ty: Text, outcome: Outcome) -> Error {
    var value = Step { ty: ty, outcome: outcome , ..};
    if self_.step_len == max_steps { value.deinit(); self_.truncated = true; return blot_error::Error.none; }
    if member.present {
        let text, error = self_.ownText(member.value); if error != blot_error::Error.none { value.deinit(); return error; } value.member = blot_support::some<const u8[:]>(text);
    }
    self_.steps[self_.step_len] = canonicalStep(value); self_.step_len++; return blot_error::Error.none;
}
fn own(self_: Builder&, bytes: u8[>..<]&) -> const u8[:], Error {
    if bytes.len > max_text { bytes.resize(boundary(bytes, max_text)); self_.truncated = true; }
    let result = copyText(bytes); bytes.clear(); return result, blot_error::Error.none;
}
fn finish(self_: Builder&, operation: Text, member: Text) -> Explanation, Error {
    var result = Explanation { truncated: self_.truncated , ..};
    if self_.len != 0 {
        let out = candidate_runs.alloc_slice(self_.len);
        for index in self_.len {
            let old = self_.candidates[index];
            out[index] = canonicalCandidate(Candidate { side: old.side, operand: cloneText(old.operand), outcome: old.outcome , ..});
            if old.origin.present { out[index].origin = blot_support::some(canonicalOrigin(old.origin.value.clone())); }
        }
        result.candidates = out;
    }
    if self_.step_len != 0 {
        let out = step_runs.alloc_slice(self_.step_len);
        for index in self_.step_len { let old = self_.steps[index]; out[index] = canonicalStep(Step { cloneText(old.member), cloneText(old.ty), old.outcome , ..}); }
        result.steps = out;
    }
    if operation.present { result.operation = blot_support::some<const u8[:]>(copyText(operation.value[..boundary(operation.value, max_text)])); }
    if member.present { if member.value.len > max_text { self_.truncated = true; } result.member = blot_support::some<const u8[:]>(copyText(member.value[..boundary(member.value, max_text)])); }
    // Publication snapshots own their text; arguments may still name Builder text.
    self_.deinit();
    let error = result.fit(); if error != blot_error::Error.none { result.deinit(); return Explanation {..}, error; } return result, blot_error::Error.none;
}
fn boundary(text: const u8[:], limit: i64) -> i64 {
    if text.len <= limit { return text.len; } var end = limit;
    while end > 0 && (text[end] & 0xc0) == 0x80 { end--; } return end;
}

fn operatorSymbol(operator: blot_check_types::Operator) -> Text {
    match operator {
        add => { return blot_support::some<const u8[:]>("+"); },
        sub => { return blot_support::some<const u8[:]>("-"); },
        mul => { return blot_support::some<const u8[:]>("*"); },
        div => { return blot_support::some<const u8[:]>("/"); },
        rem => { return blot_support::some<const u8[:]>("%"); },
        equal => { return blot_support::some<const u8[:]>("=="); },
        not_equal => { return blot_support::some<const u8[:]>("!="); },
        less => { return blot_support::some<const u8[:]>("<"); },
        less_equal => { return blot_support::some<const u8[:]>("<="); },
        greater => { return blot_support::some<const u8[:]>(">"); },
        greater_equal => { return blot_support::some<const u8[:]>(">="); },
        bit_and => { return blot_support::some<const u8[:]>("&"); },
        bit_or => { return blot_support::some<const u8[:]>("|"); },
        bit_xor => { return blot_support::some<const u8[:]>("^"); },
        shift_left => { return blot_support::some<const u8[:]>("<<"); },
        shift_right => { return blot_support::some<const u8[:]>(">>"); },
        none => { return blot_support::none<const u8[:]>(); },
    }
}

fn operatorMember(operator: blot_check_types::Operator) -> Text {
    match operator {
        add => { return blot_support::some<const u8[:]>("add"); },
        sub => { return blot_support::some<const u8[:]>("sub"); },
        mul => { return blot_support::some<const u8[:]>("mul"); },
        div => { return blot_support::some<const u8[:]>("div"); },
        rem => { return blot_support::some<const u8[:]>("rem"); },
        equal => { return blot_support::some<const u8[:]>("eq"); },
        not_equal => { return blot_support::some<const u8[:]>("ne"); },
        less => { return blot_support::some<const u8[:]>("lt"); },
        less_equal => { return blot_support::some<const u8[:]>("le"); },
        greater => { return blot_support::some<const u8[:]>("gt"); },
        greater_equal => { return blot_support::some<const u8[:]>("ge"); },
        bit_and => { return blot_support::some<const u8[:]>("bit_and"); },
        bit_or => { return blot_support::some<const u8[:]>("bit_or"); },
        bit_xor => { return blot_support::some<const u8[:]>("bit_xor"); },
        shift_left => { return blot_support::some<const u8[:]>("shl"); },
        shift_right => { return blot_support::some<const u8[:]>("shr"); },
        none => { return blot_support::none<const u8[:]>(); },
    }
}

fn blot_reuse_dispatch_explanation::blotJsonWrite(value: blot_reuse_dispatch_explanation::Candidate,writer: blot_json::Writer&) -> blot_error::Error { if writer.failure == blot_error::Error.none { writer.failure = value.jsonStringify(writer); } return writer.failure; }
fn blot_reuse_dispatch_explanation::blotJsonWrite(value: blot_reuse_dispatch_explanation::Explanation,writer: blot_json::Writer&) -> blot_error::Error { if writer.failure == blot_error::Error.none { writer.failure = value.jsonStringify(writer); } return writer.failure; }
fn blot_reuse_dispatch_explanation::blotJsonWrite(value: blot_reuse_dispatch_explanation::Side,writer: blot_json::Writer&) -> blot_error::Error { return writer.enumValue(value); }
fn blot_reuse_dispatch_explanation::blotJsonWrite(value: blot_reuse_dispatch_explanation::Outcome,writer: blot_json::Writer&) -> blot_error::Error { return writer.enumValue(value); }
fn blot_reuse_dispatch_explanation::blotJsonWrite(value: blot_reuse_dispatch_explanation::ContextKind,writer: blot_json::Writer&) -> blot_error::Error { return writer.enumValue(value); }

// Reification validates existing owned text, and never accepts borrowed display text.
fn canonicalBytes(value:const u8[:])->const u8[:] {if value.len==0 {return default<const u8[:]>();}let owned=text_runs.realloc_slice(value,value.len);assert(blot_support::same_slice_identity(owned,value));return owned;}
fn canonicalText(value:Text)->Text {if !value.present {return blot_support::none<const u8[:]>();}return blot_support::some<const u8[:]>(canonicalBytes(value.value));}
fn canonicalOrigin(value:Origin)->Origin {return Origin{name:canonicalText(value.name),path:canonicalText(value.path),span:value.span,..};}
fn canonicalStep(value:Step)->Step {return Step{member:canonicalText(value.member),ty:canonicalText(value.ty),outcome:value.outcome,..};}
fn canonicalContext(value:Context)->Context {return Context{kind:value.kind,path:canonicalText(value.path),span:value.span,..};}
fn canonicalCandidate(value:Candidate)->Candidate {var origin=blot_support::none<Origin>();if value.origin.present {origin=blot_support::some(canonicalOrigin(value.origin.value));}return Candidate{side:value.side,origin:origin,operand:canonicalText(value.operand),outcome:value.outcome,..};}
fn canonicalOwned(value:Explanation)->Explanation {
 let candidates=candidate_runs.realloc_slice(value.candidates,value.candidates.len);let steps=step_runs.realloc_slice(value.steps,value.steps.len);let contexts=context_runs.realloc_slice(value.contexts,value.contexts.len);
 if candidates.len!=0 {assert(blot_support::same_slice_identity(candidates,value.candidates));}if steps.len!=0 {assert(blot_support::same_slice_identity(steps,value.steps));}if contexts.len!=0 {assert(blot_support::same_slice_identity(contexts,value.contexts));}
 for index in 0..candidates.len {candidates[index]=canonicalCandidate(candidates[index]);}for index in 0..steps.len {steps[index]=canonicalStep(steps[index]);}for index in 0..contexts.len {contexts[index]=canonicalContext(contexts[index]);}
 return Explanation{operation:canonicalText(value.operation),member:canonicalText(value.member),candidates:candidates,steps:steps,contexts:contexts,truncated:value.truncated};
}
