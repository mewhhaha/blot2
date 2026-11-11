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
fn init(values: blot_check_numeric_proof_terms::Store, tables: Tables) -> Builder { return initParts(values.terms,values.index,values.limits,values.visits,values.account,values.owner_id,tables); }
fn initParts(terms:blot_check_numeric_proof_terms::Term[>..]&,index:blot_check_numeric_proof_terms::TermIndex&,limits:blot_check_numeric_proof_terms::Limits,visits:i64,account:i64?,owner_id:u64,tables:Tables)->Builder {return Builder{values:blot_check_numeric_proof_terms::Store{terms:terms,index:index,limits:limits,visits:visits,account:account,owner_id:owner_id},debits:tables.debits,sources:tables.sources,introductions:tables.introductions,expressions:tables.expressions,parameters:tables.parameters,uses:tables.uses};}
fn deinit(self_: Builder&) { self_.values.deinit(); self_.debits.clear(); ::clear(self_.sources); self_.introductions.clear(); ::clear(self_.expressions); self_.parameters.clear(); self_.uses.clear(); }
fn introduce(self_: Builder&, value: Introduction) -> Error {
    let error = self_.values.charge(1); if error != blot_error::Error.none { return error; } let error = self_.values.view().proposition(value.proposition); if error != blot_error::Error.none { return error; }
    if self_.introductions.len >= self_.values.limits.terms { return blot_error::Error.proof_analysis_limit; }
    { let optional_binding_31 .= ::get(self_.expressions,value.source); if optional_binding_31 { let slot .= optional_binding_31; if !blot_structural::equal(self_.introductions[slot], value) { return blot_error::Error.invalid_proof_operand; } return blot_error::Error.none;  } }
    ::insert(self_.expressions,value.source,self_.introductions.len as u32); self_.introductions.push(value); return blot_error::Error.none;
}
fn parameter(self_: Builder&, value: Parameter) -> Error {
    let error = self_.values.charge(1); if error != blot_error::Error.none { return error; } let error = self_.values.view().proposition(value.proposition); if error != blot_error::Error.none { return error; }
    if self_.parameters.len >= self_.values.limits.terms { return blot_error::Error.proof_analysis_limit; } self_.parameters.push(value); return blot_error::Error.none;
}
fn use(self_: Builder&, value: Use) -> Error {
    let error = self_.values.charge(1); if error != blot_error::Error.none { return error; } let error = self_.values.view().proposition(value.proposition); if error != blot_error::Error.none { return error; }
    if self_.uses.len >= self_.values.limits.terms { return blot_error::Error.proof_analysis_limit; } self_.uses.push(value); return blot_error::Error.none;
}
fn alias(self_: Builder&, binding: u32, source: u32) -> Error { let error = self_.values.charge(1); if error != blot_error::Error.none { return error; } if !::contains(self_.sources,binding) && self_.sources.count >= self_.values.limits.terms { return blot_error::Error.proof_analysis_limit; } ::insert(self_.sources,binding,source); return blot_error::Error.none; }
fn frontier(self_: const Builder&, headers: i64) -> Frontier { return Frontier { headers as u32, self_.values.index.count as u32, self_.introductions.len as u32, self_.parameters.len as u32, self_.uses.len as u32, self_.sources.count as u32, self_.expressions.count as u32 , ..}; }
fn take(self_: Builder&, destination: OwnedTables&) -> Owned, Error {
    let debits = destination.debits.len; let operands = destination.operands.len; let introductions = destination.introductions.len; let parameters = destination.parameters.len; let uses = destination.uses.len;
    destination.debits.append(self_.debits[..]); destination.operands.append(blot_check_numeric_proof_terms::activeTerms(self_.values.terms,self_.values.index.count)); destination.introductions.append(self_.introductions[..]); destination.parameters.append(self_.parameters[..]); destination.uses.append(self_.uses[..]);
    self_.debits.clear(); ::clear(self_.values.index); self_.introductions.clear(); self_.parameters.clear(); self_.uses.clear();
    return Owned { destination.debits[debits..], destination.operands[operands..], destination.introductions[introductions..], destination.parameters[parameters..], destination.uses[uses..] , ..}, blot_error::Error.none;
}
