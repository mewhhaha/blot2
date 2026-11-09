namespace blot_eval_implementation_predicates;
import check.core;
import check.effects;
import check.types;
import eval.type_evidence;
import reuse.dispatch_explanation;

fn failureOutcome(kind: blot_check_types::ObligationKind) -> blot_reuse_dispatch_explanation::Outcome {
 if kind==blot_check_types::ObligationKind.contract { return blot_reuse_dispatch_explanation::Outcome.requires_evidence; }
 if kind==blot_check_types::ObligationKind.effect_operation||kind==blot_check_types::ObligationKind.effect_rep||kind==blot_check_types::ObligationKind.effect_handler { return blot_reuse_dispatch_explanation::Outcome.incompatible_effect; } return blot_reuse_dispatch_explanation::Outcome.incompatible_type;
}
fn primitiveResult(evidence: blot_eval_type_evidence::Store,operator: blot_check_types::Operator,left: u32,right: u32) -> u32,bool {
 if operator==blot_check_types::Operator.none||left!=right { return 0,false; } let tag=evidence.node(left).tag;
 if tag!=blot_eval_type_evidence::Tag.unsigned32&&tag!=blot_eval_type_evidence::Tag.floating32&&tag!=blot_eval_type_evidence::Tag.boolean { return 0,false; }
 let equality=operator==blot_check_types::Operator.equal||operator==blot_check_types::Operator.not_equal;
 let comparison=equality||operator==blot_check_types::Operator.less||operator==blot_check_types::Operator.less_equal||operator==blot_check_types::Operator.greater||operator==blot_check_types::Operator.greater_equal;
 let integer=operator==blot_check_types::Operator.rem||operator==blot_check_types::Operator.bit_and||operator==blot_check_types::Operator.bit_or||operator==blot_check_types::Operator.bit_xor||operator==blot_check_types::Operator.shift_left||operator==blot_check_types::Operator.shift_right;
 if (tag==blot_eval_type_evidence::Tag.boolean&&!equality)||(tag==blot_eval_type_evidence::Tag.floating32&&integer) { return 0,false; } if comparison { return 2,true; } return left,true;
}
fn currentRow(source: const blot_check_core::Types&,id: u32) -> blot_check_effects::Row { return source.row(id); }
fn currentRow(source: const blot_check_types::Store&,id: u32) -> blot_check_effects::Row {
 var row=source.row(id); var at=row.cursor; var depth=0;
 while row.labels.len==0&&depth<256 {
  var variable: u32=0; var is_variable=false; match row.tail { variable v=>{ variable=v.value; is_variable=true; },_=>{}, }
  if !is_variable { break; } let write,present=source.effects.replacementAt(variable,at); if !present { break; } row=source.row(write.replacement); at=write.position+1; depth++;
 }
 return row;
}
fn inferredCarrier<S>(source: const S&,predicate: blot_check_types::Obligation,rows: blot_check_types::List) -> bool {
 if predicate.kind!=blot_check_types::ObligationKind.dispatch&&predicate.kind!=blot_check_types::ObligationKind.receiver&&predicate.kind!=blot_check_types::ObligationKind.update { return false; }
 if predicate.signature==0 { return false; } let node=source.node(predicate.signature); if node.tag!=blot_check_types::Tag.function||node.a!=1||node.b!=1 { return false; }
 let row=currentRow(source,node.c); if row.labels.len!=0 { return false; } var variable: u32=0;
 match row.tail { variable v=>{ variable=v.value; },_=>{ return false; }, }
 for parameter in source.list(rows) { let declared=currentRow(source,parameter); match declared.tail { variable v=>{ if variable==v.value { return false; } },_=>{}, } } return true;
}
