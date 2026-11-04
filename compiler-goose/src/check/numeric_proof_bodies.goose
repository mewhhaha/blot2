// Exact source introductions, operands and bounded body metadata.
namespace blot_check_numeric_proof_bodies;
import support.error;
import support.structural;
import .numeric_proof_terms;
type Error = blot_error::Error;
struct Introduction { source: u32, owner: u32, arguments: u32[2], proposition: blot_check_numeric_proof_terms::Proposition }
struct Parameter { binding: u32, contract: u32, proposition: blot_check_numeric_proof_terms::Proposition }
struct Use { source: u32, callee: u32, witness: u32, proposition: blot_check_numeric_proof_terms::Proposition }
struct Frontier { headers: u32, terms: u32, introductions: u32, parameters: u32, uses: u32, aliases: u32, expressions: u32 }
struct Debit { binding: u32, visits: u32, frontier: Frontier, output: Frontier }
struct Owned {
    debits: const Debit[:] = [], operands: const blot_check_numeric_proof_terms::Term[:] = [], introductions: const Introduction[:] = [], parameters: const Parameter[:] = [], uses: const Use[:] = [],
}
fn deinit(self: Owned&) { self = Owned {}; }
struct Tables {
    debits: Debit[>..<]&, sources: dictionary<u32,u32>&, introductions: Introduction[>..<]&, expressions: dictionary<u32,u32>&, parameters: Parameter[>..<]&, uses: Use[>..<]&,
}
struct OwnedTables { debits: Debit[>..]&, operands: blot_check_numeric_proof_terms::Term[>..]&, introductions: Introduction[>..]&, parameters: Parameter[>..]&, uses: Use[>..]& }
struct Builder {
    values: blot_check_numeric_proof_terms::Store,
    debits: Debit[>..<]&, sources: dictionary<u32,u32>&, introductions: Introduction[>..<]&, expressions: dictionary<u32,u32>&, parameters: Parameter[>..<]&, uses: Use[>..<]&,
}
fn init(values: blot_check_numeric_proof_terms::Store, tables: Tables) -> Builder { return Builder { values, tables.debits, tables.sources, tables.introductions, tables.expressions, tables.parameters, tables.uses }; }
fn deinit(self: Builder&) { self.values.deinit(); self.debits.clear(); self.sources.clear(); self.introductions.clear(); self.expressions.clear(); self.parameters.clear(); self.uses.clear(); }
fn introduce(self: Builder&, value: Introduction) -> Error {
    let error = self.values.charge(1); if error != Error.none { return error; } let error = self.values.view().proposition(value.proposition); if error != Error.none { return error; }
    if self.introductions.len >= self.values.limits.terms { return Error.proof_analysis_limit; }
    if let slot = self.expressions[value.source] { if !blot_structural::equal(self.introductions[slot], value) { return Error.invalid_proof_operand; } return Error.none; }
    self.expressions[value.source] = self.introductions.len as u32; self.introductions += value; return Error.none;
}
fn parameter(self: Builder&, value: Parameter) -> Error {
    let error = self.values.charge(1); if error != Error.none { return error; } let error = self.values.view().proposition(value.proposition); if error != Error.none { return error; }
    if self.parameters.len >= self.values.limits.terms { return Error.proof_analysis_limit; } self.parameters += value; return Error.none;
}
fn use(self: Builder&, value: Use) -> Error {
    let error = self.values.charge(1); if error != Error.none { return error; } let error = self.values.view().proposition(value.proposition); if error != Error.none { return error; }
    if self.uses.len >= self.values.limits.terms { return Error.proof_analysis_limit; } self.uses += value; return Error.none;
}
fn alias(self: Builder&, binding: u32, source: u32) -> Error { let error = self.values.charge(1); if error != Error.none { return error; } if !self.sources.contains(binding) && self.sources.len >= self.values.limits.terms { return Error.proof_analysis_limit; } self.sources[binding] = source; return Error.none; }
fn frontier(self: const Builder&, headers: i64) -> Frontier { return Frontier { headers as u32, self.values.terms.len as u32, self.introductions.len as u32, self.parameters.len as u32, self.uses.len as u32, self.sources.len as u32, self.expressions.len as u32 }; }
fn take(self: Builder&, destination: OwnedTables) -> Owned, Error {
    let debits = destination.debits.len; let operands = destination.operands.len; let introductions = destination.introductions.len; let parameters = destination.parameters.len; let uses = destination.uses.len;
    destination.debits += self.debits[:]; destination.operands += self.values.terms[:]; destination.introductions += self.introductions[:]; destination.parameters += self.parameters[:]; destination.uses += self.uses[:];
    self.debits.clear(); self.values.terms.clear(); self.introductions.clear(); self.parameters.clear(); self.uses.clear();
    return Owned { destination.debits[debits..], destination.operands[operands..], destination.introductions[introductions..], destination.parameters[parameters..], destination.uses[uses..] }, Error.none;
}
