// Invocation-local witness/handler equations. Certificates close only fresh rows.
namespace blot_eval_implementation_rows;
import dictionary;
import check.types;
import check.core;
import check.effects;
import check.frozen_types;
import reuse.principal_type_graph;
import .type_evidence;
import .closed_evidence_import;
import support.error;
type Error=blot_error::Error;
type Store=blot_check_types::Store;
type K=blot_check_types::ObligationKind;
type Mapping=blot_eval_type_evidence::Mapping;
type RowMapping=blot_eval_type_evidence::RowMapping;
fn convert(error: Error) -> Error { if error==Error.out_of_memory { return error; } if error==Error.type_limit { return Error.evidence_limit; } return Error.type_mismatch; }
fn syncBudget(store: Store&,observed: i64&,remaining: i64&) -> Error { let spent=store.projection_steps-observed; if spent>remaining { return Error.evidence_limit; } remaining-=spent; observed=store.projection_steps; store.projection_limit=store.projection_steps+remaining; return Error.none; }
fn unifyRows(store: Store&,left: u32,right: u32) -> Error { let e=store.chargeProjection(); if e!=Error.none { return convert(e); } for label in store.rowLabels(left) { let error=store.chargeProjection(); if error!=Error.none { return convert(error); } } for label in store.rowLabels(right) { let error=store.chargeProjection(); if error!=Error.none { return convert(error); } } let error=store.unifyEffects(left,right); if error!=Error.none { return convert(error); } return Error.none; }
struct Context<S,R> { evidence: blot_eval_type_evidence::Store&,source: const S&,clauses: const blot_check_core::Obligation[:],certificates: const u32[:],variables: const u32[:],mappings: Mapping[>..<]&,rows: RowMapping[>..<]&,resolver: blot_eval_type_evidence::ProjectionResolver<R>& }
struct CopyContext<S,R> { outer: Context<S,R>&,scratch: Store&,observed: i64& }
fn withSourceCopy<R>(context: CopyContext<Store,R>&) -> Error { let source=blot_check_frozen_types::Source.store {value:context.outer.source}; return blot_reuse_principal_type_graph::withCopy(source,context.scratch,256,1000000,context.outer.resolver.remaining,context.observed,context,solve); }
fn withSourceCopy<R>(context: CopyContext<blot_check_core::Types,R>&) -> Error {
 let s=context.outer.source; let graph=blot_check_frozen_types::Graph {s.nodes,s.extra,s.effects.rows,s.effects.labels,s.operations,s.effects.variable_count,s.quantifier_goals,s.quantifier_obligations}; let source=blot_check_frozen_types::Source.frozen {value:graph};
 return blot_reuse_principal_type_graph::withFrozenCopy(source,context.scratch,256,1000000,context.outer.resolver.remaining,context.observed,context,solve);
}
fn scratch<S,R>(context: Context<S,R>&,store: Store&) -> Error {
 store.resolution_depth_limit=256; store.projection_limit=context.resolver.remaining; store.has_projections=true; var observed: i64=0;
 defer { let spent=store.projection_steps-observed; if spent>context.resolver.remaining { context.resolver.remaining=0; } else { context.resolver.remaining-=spent; } }
 var copy=CopyContext<S,R> {context,store,observed}; return withSourceCopy(copy);
}
fn solve<S,R>(context: CopyContext<S,R>&,copy: blot_reuse_principal_type_graph::Copier&) -> Error {
 let c=context.outer; let store=context.scratch; let evidence=c.evidence;
 var type_memo: dictionary<u32,u32>; var row_memo: dictionary<u32,u32>; var binders: u32[>..<]=[];
 var closed=blot_eval_closed_evidence_import::Importer {source:evidence.view(),destination:store,types:type_memo,rows:row_memo,binders:binders};
 for mapping in c.mappings { let e=store.chargeProjection(); if e!=Error.none { return convert(e); } let actual,error=closed.ty(mapping.evidence,0); if error!=Error.none { return convert(error); } copy.types.insert(mapping.variable,actual); }
 for mapping in c.rows { let e=store.chargeProjection(); if e!=Error.none { return convert(e); } let actual,error=closed.row(mapping.evidence,0); if error!=Error.none { return convert(error); } copy.row_variables.insert(mapping.variable,actual); }
 for clause in c.clauses {
  if clause.kind!=K.type_head { continue; } let copied,error=copy.ty(clause.ty,0); if error!=Error.none { return convert(error); } var root=copied; var depth=0;
  loop { let resolved,e=store.resolve(root,0); if e!=Error.none { return convert(e); } root=resolved; let n=store.node(root); if n.tag!=blot_check_types::Tag.function { break; } if depth>=256 { return Error.evidence_limit; } let err=store.chargeProjection(); if err!=Error.none { return convert(err); } depth++; root=n.b; }
  let equal,e=store.equalClosed(root,root); if e!=Error.none { return convert(e); } if !equal { continue; } let result,err=copy.ty(clause.result,0); if err!=Error.none { return convert(err); } let unified=store.unify(result,root); if unified!=Error.none { return convert(unified); }
 }
 for variable in c.variables {
  let e=store.chargeProjection(); if e!=Error.none { return convert(e); } var known=false;
  for mapping in c.mappings { let err=store.chargeProjection(); if err!=Error.none { return convert(err); } if mapping.variable==variable { known=true; break; } } if known { continue; }
  let copied,error=copy.ty(variable,0); if error!=Error.none { return convert(error); } let resolved,err=store.resolve(copied,0); if err!=Error.none { return convert(err); } let equal,equal_error=store.equalClosed(resolved,resolved); if equal_error!=Error.none { return convert(equal_error); } if !equal { continue; }
  let sync=syncBudget(store,context.observed,c.resolver.remaining); if sync!=Error.none { return sync; } let actual,projection=evidence.projectWithBudget(store,resolved,[],[],c.resolver.remaining); if projection!=Error.none { return projection; } c.mappings.push(Mapping {variable,actual});
 }
 for clause in c.clauses {
  if c.resolver.remaining==0 { return Error.evidence_limit; } c.resolver.remaining--; if clause.kind!=K.effect_handler { continue; }
  let sync=syncBudget(store,context.observed,c.resolver.remaining); if sync!=Error.none { return sync; } let token_id,error=evidence.projectSelected(c.source,clause.ty,c.mappings,c.rows,c.resolver); if error!=Error.none { return error; } let token=evidence.node(token_id); if token.tag!=blot_eval_type_evidence::Tag.nominal { return Error.type_mismatch; }
  closed.source=evidence.view(); let imported,err=closed.ty(token_id,0); if err!=Error.none { return convert(err); } let nominal=store.node(imported); let label,e=store.internOperation(blot_check_types::NominalIdentity {token.a,token.b},store.nominalArguments(nominal)); if e!=Error.none { return convert(e); }
  let extended=c.source.node(c.source.head(clause.signature,0)); let residual=c.source.node(c.source.head(clause.other,0)); if extended.tag!=blot_check_types::Tag.function||residual.tag!=blot_check_types::Tag.function { return Error.type_mismatch; }
  let left,e1=copy.row(extended.c,0); if e1!=Error.none { return convert(e1); } let right,e2=copy.row(residual.c,0); if e2!=Error.none { return convert(e2); } let tail,e3=store.resolveEffects(right,0); if e3!=Error.none { return convert(e3); }
  var labels: u32[>..<]=[label]; labels.append(store.rowLabels(tail)); let row,e4=store.effects.rowAt(labels,store.row(tail).tail,store.row(tail).cursor); if e4!=Error.none { return convert(blot_check_types::effectError(e4)); } let e5=unifyRows(store,left,row); if e5!=Error.none { return e5; }
 }
 for variable in c.certificates {
  let error=store.chargeProjection(); if error!=Error.none { return convert(error); } let copied=copy.row_variables.get(variable); if !copied { continue; }
  let resolved,e=store.resolveEffects(copied,0); if e!=Error.none { return convert(e); } var is_variable=false; match store.row(resolved).tail { variable=>{ is_variable=true; },_=>{}, } if !is_variable { continue; }
  let established,err=store.effects.row(store.rowLabels(resolved),blot_check_effects::Tail.closed); if err!=Error.none { return convert(blot_check_types::effectError(err)); } let unified=unifyRows(store,resolved,established); if unified!=Error.none { return unified; }
 }
 let sync=syncBudget(store,context.observed,c.resolver.remaining); if sync!=Error.none { return sync; }
 var keys: u32[>..]=[]; for slot in copy.row_variables.slots { if slot.tag!=0 { keys.push(slot.key); } }
 for variable in keys {
  let error=store.chargeProjection(); if error!=Error.none { return convert(error); } var known=false;
  for mapping in c.rows { let e=store.chargeProjection(); if e!=Error.none { return convert(e); } if mapping.variable==variable { known=true; break; } } if known { continue; }
  let copied=copy.row_variables.get(variable); if !copied { continue; } let resolved,err=store.resolveEffects(copied,0); if err!=Error.none { return convert(err); } if store.row(resolved).tail!=blot_check_effects::Tail.closed { continue; }
  let carrier,e=store.functionWithEffects(1,1,resolved); if e!=Error.none { return convert(e); } let synchronized=syncBudget(store,context.observed,c.resolver.remaining); if synchronized!=Error.none { return synchronized; }
  let actual,projection=evidence.projectWithBudget(store,carrier,[],[],c.resolver.remaining); if projection!=Error.none { return projection; } c.rows.push(RowMapping {variable,evidence.node(actual).c});
 }
 return syncBudget(store,context.observed,c.resolver.remaining);
}
fn reconstruct<S,R>(evidence: blot_eval_type_evidence::Store&,source: const S&,clauses: const blot_check_core::Obligation[:],certificates: const u32[:],variables: const u32[:],mappings: Mapping[>..<]&,rows: RowMapping[>..<]&,resolver: blot_eval_type_evidence::ProjectionResolver<R>&) -> Error {
 var needed=false; for clause in clauses { if resolver.remaining==0 { return Error.evidence_limit; } resolver.remaining--; if clause.kind==K.effect_handler||clause.kind==K.type_head { needed=true; break; } } if !needed { return Error.none; }
 var context=Context<S,R> {evidence,source,clauses,certificates,variables,mappings,rows,resolver}; return blot_check_types::withStore(context,scratch);
}
