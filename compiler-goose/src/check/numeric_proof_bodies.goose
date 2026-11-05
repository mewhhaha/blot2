// Exact source introductions, operands and bounded body metadata.
namespace blot_check_numeric_proof_bodies;
import check.numeric_proof_terms;
import support.error;
import support.structural_adapters;

import support.structural;
type Error = blot_error::Error;
struct Introduction { source: u32, owner: u32, arguments: u32[2], proposition: blot_check_numeric_proof_terms::Proposition }
struct Parameter { binding: u32, contract: u32, proposition: blot_check_numeric_proof_terms::Proposition }
struct Use { source: u32, callee: u32, witness: u32, proposition: blot_check_numeric_proof_terms::Proposition }
struct Frontier { headers: u32, terms: u32, introductions: u32, parameters: u32, uses: u32, aliases: u32, expressions: u32 }
struct Debit { binding: u32, visits: u32, frontier: Frontier, output: Frontier }
struct Owned {
    debits: const Debit[:] = default<const Debit[:]>(), operands: const blot_check_numeric_proof_terms::Term[:] = default<const blot_check_numeric_proof_terms::Term[:]>(), introductions: const Introduction[:] = default<const Introduction[:]>(), parameters: const Parameter[:] = default<const Parameter[:]>(), uses: const Use[:] = default<const Use[:]>(),
}
fn deinit(self_: Owned&) { self_ = Owned {..}; }
struct Tables {
    debits: Debit[>..<]&, sources: dictionary<u32,u32>&, introductions: Introduction[>..<]&, expressions: dictionary<u32,u32>&, parameters: Parameter[>..<]&, uses: Use[>..<]&,
}
struct OwnedTables { debits: Debit[>..]&, operands: blot_check_numeric_proof_terms::Term[>..]&, introductions: Introduction[>..]&, parameters: Parameter[>..]&, uses: Use[>..]& }
struct Builder {
    values: blot_check_numeric_proof_terms::Store,
    debits: Debit[>..<]&, sources: dictionary<u32,u32>&, introductions: Introduction[>..<]&, expressions: dictionary<u32,u32>&, parameters: Parameter[>..<]&, uses: Use[>..<]&,
}
fn init(values: blot_check_numeric_proof_terms::Store, tables: Tables) -> Builder { return Builder { values, tables.debits, tables.sources, tables.introductions, tables.expressions, tables.parameters, tables.uses , ..}; }
fn deinit(self_: Builder&) { self_.values.deinit(); self_.debits.clear(); self_.sources.clear(); self_.introductions.clear(); self_.expressions.clear(); self_.parameters.clear(); self_.uses.clear(); }
fn introduce(self_: Builder&, value: Introduction) -> Error {
    let error = self_.values.charge(1); if error != blot_error::Error.none { return error; } let error = self_.values.view().proposition(value.proposition); if error != blot_error::Error.none { return error; }
    if self_.introductions.len >= self_.values.limits.terms { return blot_error::Error.proof_analysis_limit; }
    { let optional_binding_31 .= self_.expressions[value.source]; if optional_binding_31 { let slot .= optional_binding_31; if !blot_structural::equal(self_.introductions[slot], value) { return blot_error::Error.invalid_proof_operand; } return blot_error::Error.none;  } }
    self_.expressions[value.source] = self_.introductions.len as u32; self_.introductions += value; return blot_error::Error.none;
}
fn parameter(self_: Builder&, value: Parameter) -> Error {
    let error = self_.values.charge(1); if error != blot_error::Error.none { return error; } let error = self_.values.view().proposition(value.proposition); if error != blot_error::Error.none { return error; }
    if self_.parameters.len >= self_.values.limits.terms { return blot_error::Error.proof_analysis_limit; } self_.parameters += value; return blot_error::Error.none;
}
fn use(self_: Builder&, value: Use) -> Error {
    let error = self_.values.charge(1); if error != blot_error::Error.none { return error; } let error = self_.values.view().proposition(value.proposition); if error != blot_error::Error.none { return error; }
    if self_.uses.len >= self_.values.limits.terms { return blot_error::Error.proof_analysis_limit; } self_.uses += value; return blot_error::Error.none;
}
fn alias(self_: Builder&, binding: u32, source: u32) -> Error { let error = self_.values.charge(1); if error != blot_error::Error.none { return error; } if !self_.sources.contains(binding) && self_.sources.len >= self_.values.limits.terms { return blot_error::Error.proof_analysis_limit; } self_.sources[binding] = source; return blot_error::Error.none; }
fn frontier(self_: const Builder&, headers: i64) -> Frontier { return Frontier { headers as u32, self_.values.terms.len as u32, self_.introductions.len as u32, self_.parameters.len as u32, self_.uses.len as u32, self_.sources.len as u32, self_.expressions.len as u32 , ..}; }
fn take(self_: Builder&, destination: OwnedTables) -> Owned, Error {
    let debits = destination.debits.len; let operands = destination.operands.len; let introductions = destination.introductions.len; let parameters = destination.parameters.len; let uses = destination.uses.len;
    destination.debits += self_.debits[..]; destination.operands += self_.values.terms[..]; destination.introductions += self_.introductions[..]; destination.parameters += self_.parameters[..]; destination.uses += self_.uses[..];
    self_.debits.clear(); self_.values.terms.clear(); self_.introductions.clear(); self_.parameters.clear(); self_.uses.clear();
    return Owned { destination.debits[debits..], destination.operands[operands..], destination.introductions[introductions..], destination.parameters[parameters..], destination.uses[uses..] , ..}, blot_error::Error.none;
}
