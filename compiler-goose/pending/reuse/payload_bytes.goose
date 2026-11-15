// Actual packed C.2 retained payload storage; wire bytes are separate.
namespace blot_reuse_payload_bytes;
import backend.collection_ops;
import backend.opaque_storage;
import check.capability_contracts;
import check.capability_flow;
import check.core;
import check.effects;
import check.frozen_types;
import check.numeric_proof_contracts;
import check.numeric_proof_headers;
import check.numeric_proof_terms;
import check.parameter_patterns;
import check.types;
import parse.ast;
import reuse.principal_interface;
import support.option;
fn bytes(value:bool)->i64 {return 0;}
fn bytes(value:f32)->i64 {return 0;}
fn bytes(value:f64)->i64 {return 0;}
fn bytes(value:i16)->i64 {return 0;}
fn bytes(value:i32)->i64 {return 0;}
fn bytes(value:i64)->i64 {return 0;}
fn bytes(value:i8)->i64 {return 0;}
fn bytes(value:u16)->i64 {return 0;}
fn bytes(value:u32)->i64 {return 0;}
fn bytes(value:u64)->i64 {return 0;}
fn bytes(value:u8)->i64 {return 0;}
fn bytes(values:const u32[:])->i64 {var total=values.len*4;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_numeric_proof_terms::Kind[:])->i64 {var total=values.len*1;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_numeric_proof_terms::Term[:])->i64 {var total=values.len*10;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_numeric_proof_contracts::Requirement[:])->i64 {var total=values.len*13;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_numeric_proof_headers::Named[:])->i64 {var total=values.len*98;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_capability_contracts::Term[:])->i64 {var total=values.len*13;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_capability_contracts::Binding[:])->i64 {var total=values.len*8;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::FieldName[:])->i64 {var total=values.len*12;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::RuntimeName[:])->i64 {var total=values.len*8;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::DeclarationDependencies[:])->i64 {var total=values.len*20;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::BindingRef[:])->i64 {var total=values.len*8;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::DependencyMember[:])->i64 {var total=values.len*5;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::ErasedDeclarationReference[:])->i64 {var total=values.len*12;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::RequestLoopInfo[:])->i64 {var total=values.len*56;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::RequestArm[:])->i64 {var total=values.len*12;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_types::Node[:])->i64 {var total=values.len*16;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_effects::Row[:])->i64 {var total=values.len*17;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_types::Operation[:])->i64 {var total=values.len*24;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_types::QuantifierGoals[:])->i64 {var total=values.len*12;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_types::Obligation[:])->i64 {var total=values.len*48;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::Node[:])->i64 {var total=values.len*18;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_parse_ast::Span[:])->i64 {var total=values.len*8;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::Binding[:])->i64 {var total=values.len*105;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::Body[:])->i64 {var total=values.len*95;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::Parameter[:])->i64 {var total=values.len*17;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::CallInfo[:])->i64 {var total=values.len*12;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::Merge[:])->i64 {var total=values.len*16;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::List[:])->i64 {var total=values.len*8;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const u8[:])->i64 {var total=values.len*1;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::Obligation[:])->i64 {var total=values.len*60;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::Nominal[:])->i64 {var total=values.len*62;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::OperationName[:])->i64 {var total=values.len*48;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::Constructor[:])->i64 {var total=values.len*64;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::Projection[:])->i64 {var total=values.len*32;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::ProjectionVariant[:])->i64 {var total=values.len*8;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::Pattern[:])->i64 {var total=values.len*25;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::PatternRow[:])->i64 {var total=values.len*8;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::MatchArm[:])->i64 {var total=values.len*24;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::MatchInfo[:])->i64 {var total=values.len*17;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::UpdateInfo[:])->i64 {var total=values.len*28;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::UpdateStep[:])->i64 {var total=values.len*17;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::ClosureInfo[:])->i64 {var total=values.len*45;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::Associated[:])->i64 {var total=values.len*21;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::Contract[:])->i64 {var total=values.len*70;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_reuse_principal_interface::ContractMember[:])->i64 {var total=values.len*17;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_reuse_principal_interface::Implementation[:])->i64 {var total=values.len*98;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_reuse_principal_interface::ImplementationMember[:])->i64 {var total=values.len*17;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_reuse_principal_interface::MemberTemplate[:])->i64 {var total=values.len*24;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_reuse_principal_interface::SelectedProof[:])->i64 {var total=values.len*101;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::SelectedUse[:])->i64 {var total=values.len*8;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::DictionarySelection[:])->i64 {var total=values.len*53;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::DictionaryUse[:])->i64 {var total=values.len*28;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::Primitive[:])->i64 {var total=values.len*4;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::LoopInfo[:])->i64 {var total=values.len*26;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::LoopCarry[:])->i64 {var total=values.len*16;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::ResolverInfo[:])->i64 {var total=values.len*29;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::OperationValue[:])->i64 {var total=values.len*40;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::HandleEffects[:])->i64 {var total=values.len*20;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_core::Diagnostic[:])->i64 {var total=values.len*9;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_check_parameter_patterns::Node[:])->i64 {var total=values.len*9;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_reuse_principal_interface::Binding[:])->i64 {var total=values.len*78;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_reuse_principal_interface::Nominal[:])->i64 {var total=values.len*82;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_reuse_principal_interface::Constructor[:])->i64 {var total=values.len*70;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_reuse_principal_interface::EffectFamily[:])->i64 {var total=values.len*54;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_reuse_principal_interface::EffectTemplate[:])->i64 {var total=values.len*24;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_reuse_principal_interface::Associated[:])->i64 {var total=values.len*17;for value in values {total+=bytes(value);}return total;}
fn bytes(values:const blot_reuse_principal_interface::Contract[:])->i64 {var total=values.len*90;for value in values {total+=bytes(value);}return total;}
fn bytes(value:blot_support::Option<blot_check_numeric_proof_terms::Proposition>)->i64 {if !value.present {return 0;}return bytes(value.value);}
fn bytes(value:blot_support::Option<blot_parse_ast::Span>)->i64 {if !value.present {return 0;}return bytes(value.value);}
fn bytes(value:blot_support::Option<blot_reuse_principal_interface::ExternalTarget>)->i64 {if !value.present {return 0;}return bytes(value.value);}
fn bytes(value:const blot_check_core::Module&)->i64 {return bytes(value.has_rank_contracts)+bytes(value.has_usage_contracts)+bytes(value.has_numeric_proofs)+bytes(value.proof_contracts)+bytes(value.capability_contracts)+bytes(value.field_names)+bytes(value.runtime_names)+bytes(value.source_names)+bytes(value.declaration_dependencies)+bytes(value.dependency_references)+bytes(value.dependency_members)+bytes(value.erased_declaration_references)+bytes(value.request_loops)+bytes(value.request_arms)+bytes(value.tag_calls)+bytes(value.unit)+bytes(value.types)+bytes(value.nodes)+bytes(value.spans)+bytes(value.extra)+bytes(value.bindings)+bytes(value.bodies)+bytes(value.parameters)+bytes(value.references)+bytes(value.calls)+bytes(value.merges)+bytes(value.merge_ranges)+bytes(value.names)+bytes(value.obligations)+bytes(value.nominals)+bytes(value.operation_names)+bytes(value.constructors)+bytes(value.projections)+bytes(value.projection_variants)+bytes(value.patterns)+bytes(value.pattern_rows)+bytes(value.match_arms)+bytes(value.matches)+bytes(value.updates)+bytes(value.update_steps)+bytes(value.closures)+bytes(value.associated)+bytes(value.contracts)+bytes(value.contract_members)+bytes(value.implementations)+bytes(value.implementation_members)+bytes(value.member_templates)+bytes(value.selected_proofs)+bytes(value.selected_members)+bytes(value.selected_edges)+bytes(value.selected_uses)+bytes(value.dictionary_selections)+bytes(value.dictionary_uses)+bytes(value.primitives)+bytes(value.loops)+bytes(value.loop_carries)+bytes(value.resolver_ops)+bytes(value.operation_values)+bytes(value.handle_effects)+bytes(value.dispatch_signatures)+bytes(value.diagnostics)+bytes(value.body_lowerings)+value.package_payloads.len*4;}
fn bytes(value:const blot_check_numeric_proof_headers::Named&)->i64 {return bytes(value.binding)+bytes(value.header);}
fn bytes(value:const blot_check_numeric_proof_headers::Owned&)->i64 {return bytes(value.arity)+bytes(value.value_slots)+bytes(value.proof_slots)+bytes(value.values)+bytes(value.operands)+bytes(value.requirements)+bytes(value.result);}
fn bytes(value:blot_check_numeric_proof_terms::Kind)->i64 {match value {unsigned32=>{return 0;},array=>{return 0;},list=>{return 0;}}}
fn bytes(value:const blot_check_numeric_proof_terms::Term&)->i64 {return bytes(value.tag)+bytes(value.kind)+bytes(value.a)+bytes(value.b);}
fn bytes(value:blot_check_numeric_proof_terms::Tag)->i64 {match value {literal=>{return 0;},formal=>{return 0;},capture=>{return 0;},version=>{return 0;},length=>{return 0;},complement=>{return 0;}}}
fn bytes(value:const blot_check_numeric_proof_contracts::Requirement&)->i64 {return bytes(value.before)+bytes(value.proposition);}
fn bytes(value:const blot_check_numeric_proof_terms::Proposition&)->i64 {return bytes(value.relation)+bytes(value.left)+bytes(value.right);}
fn bytes(value:blot_check_numeric_proof_terms::Relation)->i64 {match value {eq=>{return 0;},lt=>{return 0;},le=>{return 0;},add_fits=>{return 0;},sub_fits=>{return 0;},index=>{return 0;}}}
fn bytes(value:const blot_check_capability_contracts::Collection&)->i64 {return bytes(value.nodes)+bytes(value.words)+bytes(value.bindings);}
fn bytes(value:const blot_check_capability_contracts::Term&)->i64 {return bytes(value.tag)+bytes(value.a)+bytes(value.b)+bytes(value.c);}
fn bytes(value:blot_check_capability_contracts::Tag)->i64 {match value {empty=>{return 0;},unknown=>{return 0;},parameter=>{return 0;},authority=>{return 0;},captures=>{return 0;},product=>{return 0;},record=>{return 0;},wrapped=>{return 0;},join=>{return 0;},project=>{return 0;},elements=>{return 0;},argument=>{return 0;},callable=>{return 0;}}}
fn bytes(value:const blot_check_capability_contracts::Binding&)->i64 {return bytes(value.binding)+bytes(value.root);}
fn bytes(value:const blot_check_core::FieldName&)->i64 {return bytes(value.symbol)+bytes(value.spelling);}
fn bytes(value:const blot_check_core::Name&)->i64 {return bytes(value.start)+bytes(value.len);}
fn bytes(value:const blot_check_core::RuntimeName&)->i64 {return bytes(value.binding)+bytes(value.point);}
fn bytes(value:const blot_check_core::DeclarationDependencies&)->i64 {return bytes(value.references)+bytes(value.members)+bytes(value.runtime_metadata);}
fn bytes(value:const blot_check_core::List&)->i64 {return bytes(value.start)+bytes(value.len);}
fn bytes(value:const blot_check_core::BindingRef&)->i64 {return bytes(value.unit)+bytes(value.binding);}
fn bytes(value:const blot_check_core::DependencyMember&)->i64 {return bytes(value.name)+bytes(value.operator);}
fn bytes(value:blot_check_types::Operator)->i64 {match value {none=>{return 0;},add=>{return 0;},sub=>{return 0;},mul=>{return 0;},div=>{return 0;},rem=>{return 0;},equal=>{return 0;},not_equal=>{return 0;},less=>{return 0;},less_equal=>{return 0;},greater=>{return 0;},greater_equal=>{return 0;},bit_and=>{return 0;},bit_or=>{return 0;},bit_xor=>{return 0;},shift_left=>{return 0;},shift_right=>{return 0;}}}
fn bytes(value:const blot_check_core::ErasedDeclarationReference&)->i64 {return bytes(value.node)+bytes(value.target);}
fn bytes(value:const blot_check_core::RequestLoopInfo&)->i64 {return bytes(value.computation)+bytes(value.action_type)+bytes(value.value_type)+bytes(value.result_type)+bytes(value.state_type)+bytes(value.arms)+bytes(value.completion_pattern)+bytes(value.completion_body)+bytes(value.completion_state_bindings)+bytes(value.carries)+bytes(value.return_target);}
fn bytes(value:const blot_check_core::RequestArm&)->i64 {return bytes(value.operation)+bytes(value.callback)+bytes(value.selector);}
fn bytes(value:const blot_check_core::Types&)->i64 {return bytes(value.nodes)+bytes(value.extra)+bytes(value.effects)+bytes(value.operations)+bytes(value.quantifier_goals)+bytes(value.quantifier_obligations);}
fn bytes(value:const blot_check_types::Node&)->i64 {return bytes(value.tag)+bytes(value.closed_height)+bytes(value.closed_generation)+bytes(value.a)+bytes(value.b)+bytes(value.c);}
fn bytes(value:blot_check_types::Tag)->i64 {match value {absent=>{return 0;},unit=>{return 0;},boolean=>{return 0;},unsigned32=>{return 0;},floating32=>{return 0;},never=>{return 0;},variable=>{return 0;},function=>{return 0;},product=>{return 0;},record=>{return 0;},nominal=>{return 0;},array=>{return 0;},list=>{return 0;},cursor=>{return 0;},type_constructor=>{return 0;},resolver=>{return 0;},provider=>{return 0;},state_provider=>{return 0;},projection=>{return 0;},scoped=>{return 0;},instance_selection=>{return 0;},erased_proof=>{return 0;},forall=>{return 0;},existential=>{return 0;},bound=>{return 0;},rigid=>{return 0;},usage=>{return 0;},instance_version=>{return 0;}}}
fn bytes(value:const blot_check_core::EffectRows&)->i64 {return bytes(value.rows)+bytes(value.labels)+bytes(value.variable_count);}
fn bytes(value:const blot_check_effects::Row&)->i64 {return bytes(value.labels)+bytes(value.tail)+bytes(value.cursor);}
fn bytes(value:const blot_check_effects::List&)->i64 {return bytes(value.start)+bytes(value.len);}
fn bytes(value:blot_check_effects::Tail)->i64 {match value {closed=>{return 0;},variable payload=>{return bytes(payload.value);},parameter payload=>{return bytes(payload.value);},formal payload=>{return bytes(payload.value);}}}
fn bytes(value:const blot_check_types::Operation&)->i64 {return bytes(value.identity)+bytes(value.arguments)+bytes(value.instance);}
fn bytes(value:const blot_check_types::NominalIdentity&)->i64 {return bytes(value.unit)+bytes(value.decl);}
fn bytes(value:const blot_check_types::List&)->i64 {return bytes(value.start)+bytes(value.len);}
fn bytes(value:const blot_check_types::QuantifierGoals&)->i64 {return bytes(value.owner)+bytes(value.goals);}
fn bytes(value:const blot_check_types::Obligation&)->i64 {return bytes(value.ty)+bytes(value.kind)+bytes(value.source)+bytes(value.name)+bytes(value.result)+bytes(value.other)+bytes(value.signature)+bytes(value.operator)+bytes(value.identity)+bytes(value.explicit)+bytes(value.qualification_span)+bytes(value.qualification_unit);}
fn bytes(value:blot_check_types::ObligationKind)->i64 {match value {arithmetic=>{return 0;},ordered=>{return 0;},equality=>{return 0;},integer=>{return 0;},field=>{return 0;},writable_field=>{return 0;},dispatch=>{return 0;},result_dispatch=>{return 0;},monad_factory=>{return 0;},resolver_dispatch=>{return 0;},resolver_shape=>{return 0;},effect_operation=>{return 0;},effect_handler=>{return 0;},receiver=>{return 0;},update=>{return 0;},type_rep=>{return 0;},effect_rep=>{return 0;},type_head=>{return 0;},collection=>{return 0;},record_merge=>{return 0;},callee_use=>{return 0;},type_eq=>{return 0;},contract=>{return 0;},task_receive=>{return 0;}}}
fn bytes(value:const blot_parse_ast::Span&)->i64 {return bytes(value.start)+bytes(value.end);}
fn bytes(value:const blot_check_core::Node&)->i64 {return bytes(value.tag)+bytes(value.op)+bytes(value.ty)+bytes(value.a)+bytes(value.b)+bytes(value.c);}
fn bytes(value:blot_check_core::Tag)->i64 {match value {invalid=>{return 0;},constant=>{return 0;},reference=>{return 0;},scalar=>{return 0;},logical=>{return 0;},call=>{return 0;},if_value=>{return 0;},block_=>{return 0;},suite=>{return 0;},bind=>{return 0;},return_=>{return 0;},if_stmt=>{return 0;},product=>{return 0;},record=>{return 0;},construct=>{return 0;},project=>{return 0;},match_=>{return 0;},pattern_bind=>{return 0;},update=>{return 0;},array=>{return 0;},array_op=>{return 0;},closure=>{return 0;},apply=>{return 0;},constructor_function=>{return 0;},associated=>{return 0;},primitive_function=>{return 0;},panic=>{return 0;},loop_=>{return 0;},break_=>{return 0;},type_same=>{return 0;},result_associated=>{return 0;},type_constructor=>{return 0;},resolver_op=>{return 0;},operation_value=>{return 0;},effect_provider=>{return 0;},state_provider=>{return 0;},handle=>{return 0;},effect_reflection=>{return 0;},computation=>{return 0;},request_loop=>{return 0;},request_decision=>{return 0;},record_merge=>{return 0;},contract_method=>{return 0;},effect_scope=>{return 0;},proof_guard=>{return 0;},package_pack=>{return 0;},package_unpack=>{return 0;},staging=>{return 0;},usage_borrow=>{return 0;},usage_read=>{return 0;},resource_scope=>{return 0;},usage_share=>{return 0;},resource_acquire=>{return 0;},resource_release=>{return 0;},task=>{return 0;},storage=>{return 0;}}}
fn bytes(value:blot_check_core::Op)->i64 {match value {none=>{return 0;},add=>{return 0;},sub=>{return 0;},mul=>{return 0;},div=>{return 0;},rem=>{return 0;},equal=>{return 0;},not_equal=>{return 0;},less=>{return 0;},less_equal=>{return 0;},greater=>{return 0;},greater_equal=>{return 0;},bit_and=>{return 0;},bit_or=>{return 0;},bit_xor=>{return 0;},shift_left=>{return 0;},shift_right=>{return 0;},and_=>{return 0;},or_=>{return 0;},neg=>{return 0;},abs=>{return 0;},ceil=>{return 0;},floor=>{return 0;},trunc=>{return 0;},sqrt=>{return 0;},convert_u32_f32=>{return 0;},convert_f32_u32=>{return 0;},shift_right_signed=>{return 0;},min=>{return 0;},max=>{return 0;},bit_not=>{return 0;},bit_andnot=>{return 0;},any_true=>{return 0;},all_true=>{return 0;},select=>{return 0;},shuffle=>{return 0;},swizzle=>{return 0;},broadcast=>{return 0;},bits=>{return 0;},from_bits=>{return 0;},relaxed_madd=>{return 0;},relaxed_nmadd=>{return 0;},convert_i32_f32=>{return 0;},convert_f32_i32=>{return 0;},continue_=>{return 0;}}}
fn bytes(value:const blot_check_core::Binding&)->i64 {return bytes(value.capability_flow)+bytes(value.capability_parameters)+bytes(value.private)+bytes(value.initializer)+bytes(value.kind)+bytes(value.ty)+bytes(value.scheme)+bytes(value.public_variables)+bytes(value.public_rows)+bytes(value.has_explicit)+bytes(value.body_id)+bytes(value.target)+bytes(value.span);}
fn bytes(value:blot_check_capability_flow::Contract)->i64 {match value {unknown=>{return 0;},identity=>{return 0;},invoke_unit=>{return 0;},member_unit=>{return 0;},invoke_with_capability=>{return 0;},member_first_unit=>{return 0;},member_second_unit=>{return 0;},input_shape=>{return 0;},consume_task=>{return 0;},scope_task=>{return 0;},spawn_task=>{return 0;}}}
fn bytes(value:const blot_check_capability_flow::Parameters&)->i64 {return bytes(value.kind)+bytes(value.mask)+bytes(value.inputs)+bytes(value.invocation_arguments)+bytes(value.invocation_count);}
fn bytes(value:blot_check_capability_flow::ParameterResult)->i64 {match value {product=>{return 0;},invoke_unit=>{return 0;},invalid=>{return 0;},member_closure_unit=>{return 0;},captured_unit=>{return 0;},invoke_input=>{return 0;},invoke_inputs=>{return 0;}}}
fn bytes(value:blot_reuse_principal_interface::Kind)->i64 {match value {global=>{return 0;},local=>{return 0;},parameter=>{return 0;},external=>{return 0;}}}
fn bytes(value:const blot_check_types::Scheme&)->i64 {return bytes(value.root)+bytes(value.variables)+bytes(value.row_variables)+bytes(value.closed_rows)+bytes(value.obligations)+bytes(value.generative);}
fn bytes(value:const blot_check_core::Body&)->i64 {return bytes(value.binding)+bytes(value.root)+bytes(value.parameters)+bytes(value.scheme)+bytes(value.closed_rows)+bytes(value.span)+bytes(value.declaration_name)+bytes(value.export_name)+bytes(value.exported)+bytes(value.runtime)+bytes(value.is_function);}
fn bytes(value:const blot_check_core::Parameter&)->i64 {return bytes(value.binding)+bytes(value.ty)+bytes(value.span)+bytes(value.inferred);}
fn bytes(value:const blot_check_core::CallInfo&)->i64 {return bytes(value.target)+bytes(value.callee_type);}
fn bytes(value:const blot_check_core::Merge&)->i64 {return bytes(value.node)+bytes(value.result)+bytes(value.then_binding)+bytes(value.else_binding);}
fn bytes(value:const blot_check_core::Obligation&)->i64 {return bytes(value.ty)+bytes(value.kind)+bytes(value.span)+bytes(value.name)+bytes(value.result)+bytes(value.other)+bytes(value.signature)+bytes(value.operator)+bytes(value.identity)+bytes(value.explicit)+bytes(value.qualification_span)+bytes(value.qualification_unit)+bytes(value.diagnostic_name);}
fn bytes(value:const blot_check_core::Nominal&)->i64 {return bytes(value.affine)+bytes(value.has_usage)+bytes(value.closed_storage)+bytes(value.private)+bytes(value.is_opaque)+bytes(value.storage)+bytes(value.diagnostic_name)+bytes(value.diagnostic_origin)+bytes(value.identity)+bytes(value.parameters)+bytes(value.variables)+bytes(value.constructors);}
fn bytes(value:const blot_backend_opaque_storage::Storage&)->i64 {return bytes(value.kind)+bytes(value.parameter)+bytes(value.selector);}
fn bytes(value:blot_backend_opaque_storage::Kind)->i64 {match value {unknown=>{return 0;},unit=>{return 0;},boolean=>{return 0;},unsigned32=>{return 0;},floating32=>{return 0;},reference=>{return 0;},parameter=>{return 0;}}}
fn bytes(value:const blot_check_core::OperationName&)->i64 {return bytes(value.identity)+bytes(value.diagnostic_name)+bytes(value.diagnostic_origin)+bytes(value.variables)+bytes(value.parameters)+bytes(value.parameter)+bytes(value.result);}
fn bytes(value:const blot_check_core::Constructor&)->i64 {return bytes(value.identity)+bytes(value.nominal)+bytes(value.tag)+bytes(value.scheme)+bytes(value.payload);}
fn bytes(value:const blot_check_core::Projection&)->i64 {return bytes(value.nominal)+bytes(value.field)+bytes(value.source_type)+bytes(value.result_type)+bytes(value.variants)+bytes(value.diagnostic_point);}
fn bytes(value:const blot_check_core::ProjectionVariant&)->i64 {return bytes(value.tag)+bytes(value.field);}
fn bytes(value:const blot_check_core::Pattern&)->i64 {return bytes(value.tag)+bytes(value.ty)+bytes(value.a)+bytes(value.b)+bytes(value.c)+bytes(value.span);}
fn bytes(value:blot_check_core::PatternTag)->i64 {match value {invalid=>{return 0;},wildcard=>{return 0;},bind=>{return 0;},constant=>{return 0;},value=>{return 0;},product=>{return 0;},constructor=>{return 0;},record_payload=>{return 0;}}}
fn bytes(value:const blot_check_core::PatternRow&)->i64 {return bytes(value.patterns);}
fn bytes(value:const blot_check_core::MatchArm&)->i64 {return bytes(value.rows)+bytes(value.guard_)+bytes(value.body)+bytes(value.span);}
fn bytes(value:const blot_check_core::MatchInfo&)->i64 {return bytes(value.inputs)+bytes(value.arms)+bytes(value.statement);}
fn bytes(value:const blot_check_core::UpdateInfo&)->i64 {return bytes(value.root)+bytes(value.path)+bytes(value.value)+bytes(value.self_binding)+bytes(value.selectors);}
fn bytes(value:const blot_check_core::UpdateStep&)->i64 {return bytes(value.kind)+bytes(value.projection)+bytes(value.index)+bytes(value.source_type)+bytes(value.result_type);}
fn bytes(value:blot_check_core::UpdateKind)->i64 {match value {field=>{return 0;},index=>{return 0;}}}
fn bytes(value:const blot_check_core::ClosureInfo&)->i64 {return bytes(value.qualifier)+bytes(value.body)+bytes(value.parameter)+bytes(value.captures)+bytes(value.function_type)+bytes(value.closed_rows);}
fn bytes(value:const blot_check_core::Associated&)->i64 {return bytes(value.identity)+bytes(value.member)+bytes(value.operator)+bytes(value.target);}
fn bytes(value:const blot_check_core::Contract&)->i64 {return bytes(value.private)+bytes(value.identity)+bytes(value.name)+bytes(value.parameters)+bytes(value.variables)+bytes(value.row_variables)+bytes(value.predicates)+bytes(value.members)+bytes(value.requires_implementation)+bytes(value.row_parameter_names)+bytes(value.row_parameters);}
fn bytes(value:const blot_reuse_principal_interface::ContractMember&)->i64 {return bytes(value.contract)+bytes(value.name)+bytes(value.kind)+bytes(value.root);}
fn bytes(value:blot_reuse_principal_interface::ContractMemberKind)->i64 {match value {defined_type=>{return 0;},abstract_type=>{return 0;},value=>{return 0;}}}
fn bytes(value:const blot_reuse_principal_interface::Implementation&)->i64 {return bytes(value.origin_span)+bytes(value.declaration)+bytes(value.private)+bytes(value.identity)+bytes(value.name)+bytes(value.contract)+bytes(value.head)+bytes(value.variables)+bytes(value.parameter_names)+bytes(value.row_variables)+bytes(value.row_parameter_names)+bytes(value.row_parameters)+bytes(value.predicates)+bytes(value.members);}
fn bytes(value:const blot_reuse_principal_interface::ImplementationMember&)->i64 {return bytes(value.name)+bytes(value.kind)+bytes(value.root)+bytes(value.target);}
fn bytes(value:blot_reuse_principal_interface::ImplementationMemberKind)->i64 {match value {type_=>{return 0;},value=>{return 0;}}}
fn bytes(value:const blot_reuse_principal_interface::ExternalTarget&)->i64 {return bytes(value.unit)+bytes(value.binding);}
fn bytes(value:const blot_reuse_principal_interface::MemberTemplate&)->i64 {return bytes(value.binding)+bytes(value.contract)+bytes(value.name)+bytes(value.arguments);}
fn bytes(value:const blot_reuse_principal_interface::SelectedProof&)->i64 {return bytes(value.predicate_target)+bytes(value.context)+bytes(value.kind)+bytes(value.predicate)+bytes(value.implementation)+bytes(value.contract)+bytes(value.arguments)+bytes(value.members)+bytes(value.prerequisites);}
fn bytes(value:blot_reuse_principal_interface::SelectedProofKind)->i64 {match value {implementation=>{return 0;},predicate=>{return 0;}}}
fn bytes(value:const blot_check_core::SelectedUse&)->i64 {return bytes(value.node)+bytes(value.proof);}
fn bytes(value:const blot_check_core::DictionarySelection&)->i64 {return bytes(value.owner)+bytes(value.quantifier)+bytes(value.goal)+bytes(value.proof)+bytes(value.members)+bytes(value.contents);}
fn bytes(value:blot_check_core::DictionaryProof)->i64 {match value {selected payload=>{return bytes(payload.value);},given payload=>{return bytes(payload.value);}}}
fn bytes(value:const blot_check_core::DictionaryGiven&)->i64 {return bytes(value.opening)+bytes(value.introduction)+bytes(value.quantifier)+bytes(value.goal)+bytes(value.arguments);}
fn bytes(value:const blot_check_core::DictionaryUse&)->i64 {return bytes(value.node)+bytes(value.binding)+bytes(value.opening)+bytes(value.introduction)+bytes(value.quantifier)+bytes(value.goal)+bytes(value.member);}
fn bytes(value:const blot_check_core::Primitive&)->i64 {return bytes(value.kind)+bytes(value.op)+bytes(value.array_op)+bytes(value.arity);}
fn bytes(value:blot_check_core::PrimitiveKind)->i64 {match value {scalar=>{return 0;},array=>{return 0;}}}
fn bytes(value:blot_backend_collection_ops::Op)->i64 {match value {length=>{return 0;},get=>{return 0;},set=>{return 0;},fill=>{return 0;},generate=>{return 0;},append=>{return 0;},prepend=>{return 0;},identity=>{return 0;},convert=>{return 0;},cursor=>{return 0;},cursor_has=>{return 0;},cursor_value=>{return 0;},cursor_advance=>{return 0;},concat=>{return 0;},slice=>{return 0;},simd_load=>{return 0;},simd_store=>{return 0;},flatten=>{return 0;}}}
fn bytes(value:const blot_check_core::LoopInfo&)->i64 {return bytes(value.kind)+bytes(value.first)+bytes(value.end)+bytes(value.pattern)+bytes(value.body)+bytes(value.carries)+bytes(value.can_exit);}
fn bytes(value:blot_check_core::LoopKind)->i64 {match value {forever=>{return 0;},range=>{return 0;},array=>{return 0;}}}
fn bytes(value:const blot_check_core::LoopCarry&)->i64 {return bytes(value.incoming)+bytes(value.iteration)+bytes(value.backedge)+bytes(value.outgoing);}
fn bytes(value:const blot_check_core::ResolverInfo&)->i64 {return bytes(value.operation)+bytes(value.resolver)+bytes(value.arguments)+bytes(value.member)+bytes(value.method)+bytes(value.method_type);}
fn bytes(value:blot_check_core::ResolverOperation)->i64 {match value {monad=>{return 0;},pure=>{return 0;},bind=>{return 0;},forward=>{return 0;},iterate=>{return 0;},run=>{return 0;}}}
fn bytes(value:const blot_check_core::OperationValue&)->i64 {return bytes(value.identity)+bytes(value.arguments)+bytes(value.signature)+bytes(value.witness)+bytes(value.witness_result)+bytes(value.instance)+bytes(value.capability);}
fn bytes(value:const blot_check_core::HandleEffects&)->i64 {return bytes(value.node)+bytes(value.first)+bytes(value.second)+bytes(value.extended)+bytes(value.residual);}
fn bytes(value:const blot_check_core::Diagnostic&)->i64 {return bytes(value.code)+bytes(value.span);}
fn bytes(value:blot_check_core::Code)->i64 {match value {unchecked=>{return 0;},unsupported=>{return 0;},unresolved_binding=>{return 0;},invalid_call=>{return 0;},complexity=>{return 0;}}}
fn bytes(value:const blot_reuse_principal_interface::Interface&)->i64 {return bytes(value.has_rank_contracts)+bytes(value.has_usage_contracts)+bytes(value.has_numeric_proofs)+bytes(value.proof_contracts)+bytes(value.capability_contracts)+bytes(value.unit)+bytes(value.graph)+bytes(value.patterns)+bytes(value.bindings)+bytes(value.obligations)+bytes(value.obligation_spans)+bytes(value.nominals)+bytes(value.constructors)+bytes(value.effect_families)+bytes(value.effect_templates)+bytes(value.associated)+bytes(value.contracts)+bytes(value.contract_predicates)+bytes(value.contract_members)+bytes(value.implementations)+bytes(value.implementation_predicates)+bytes(value.implementation_members)+bytes(value.member_templates)+bytes(value.selected_proofs)+bytes(value.selected_members)+bytes(value.selected_edges);}
fn bytes(value:const blot_check_frozen_types::Graph&)->i64 {return bytes(value.nodes)+bytes(value.extra)+bytes(value.rows)+bytes(value.labels)+bytes(value.operations)+bytes(value.row_variable_count)+bytes(value.quantifier_goals)+bytes(value.quantifier_obligations);}
fn bytes(value:const blot_check_frozen_types::PatternGraph&)->i64 {return bytes(value.nodes)+bytes(value.extra);}
fn bytes(value:const blot_check_parameter_patterns::Node&)->i64 {return bytes(value.kind)+bytes(value.a)+bytes(value.b);}
fn bytes(value:blot_check_parameter_patterns::Kind)->i64 {match value {binding=>{return 0;},tuple=>{return 0;},array=>{return 0;},record=>{return 0;}}}
fn bytes(value:const blot_reuse_principal_interface::Binding&)->i64 {return bytes(value.capability_flow)+bytes(value.capability_parameters)+bytes(value.private)+bytes(value.name)+bytes(value.kind)+bytes(value.named_function)+bytes(value.ty)+bytes(value.scheme)+bytes(value.external);}
fn bytes(value:const blot_reuse_principal_interface::Nominal&)->i64 {return bytes(value.affine)+bytes(value.has_usage)+bytes(value.closed_storage)+bytes(value.private)+bytes(value.is_opaque)+bytes(value.storage)+bytes(value.declaration)+bytes(value.identity)+bytes(value.name)+bytes(value.parameters)+bytes(value.variables)+bytes(value.patterns)+bytes(value.parameter_names)+bytes(value.constructors)+bytes(value.alias)+bytes(value.alias_rows);}
fn bytes(value:const blot_reuse_principal_interface::Constructor&)->i64 {return bytes(value.private)+bytes(value.identity)+bytes(value.nominal)+bytes(value.tag)+bytes(value.name)+bytes(value.scheme)+bytes(value.payload)+bytes(value.declared_record);}
fn bytes(value:const blot_reuse_principal_interface::EffectFamily&)->i64 {return bytes(value.private)+bytes(value.identity)+bytes(value.name)+bytes(value.callable)+bytes(value.parameters)+bytes(value.variables)+bytes(value.patterns)+bytes(value.parameter_names)+bytes(value.operations);}
fn bytes(value:const blot_reuse_principal_interface::EffectTemplate&)->i64 {return bytes(value.identity)+bytes(value.family)+bytes(value.name)+bytes(value.parameter)+bytes(value.result);}
fn bytes(value:const blot_reuse_principal_interface::Associated&)->i64 {return bytes(value.identity)+bytes(value.member)+bytes(value.operator)+bytes(value.binding);}
fn bytes(value:const blot_reuse_principal_interface::Contract&)->i64 {return bytes(value.declaration)+bytes(value.private)+bytes(value.identity)+bytes(value.name)+bytes(value.parameters)+bytes(value.variables)+bytes(value.patterns)+bytes(value.parameter_names)+bytes(value.row_variables)+bytes(value.row_parameter_names)+bytes(value.row_parameters)+bytes(value.predicates)+bytes(value.members)+bytes(value.requires_implementation);}
