// Lexical resizable scratch owners live outside every inference cycle.
namespace squid_check_check;
import check.check_scheme_import;
import check.parameter_patterns;
import check.scheme_dependencies;
import check.solver_worklist;
import check.source_sort;
import check.types;
import parse.ast;
import parse.symbols;
import phase_profile;
import reuse.completion_names;
import reuse.hole_diagnostics;
import reuse.principal_interface;
import support.error;
import support.option;

import .check;
import .check_owners;
import support.native;
import std;
import dictionary;
fn checkEngine(tree:const squid_parse_ast::Tree&,pool:squid_parse_symbols::Pool&,imports:const ImportedBinding[:],headers:const SourceHeader[:],catalogs:const ImportedCatalog[:],source_catalogs:const SourceCatalog[:],unit:u32,allow_imports:bool,options:ModuleOptions,source_validation:bool,execution:PrivateExecution,exhaustion:BudgetExhaustion&)->Checked,squid_error::Error {
resetWithState();
var owner_import_arena=ImportArena{records:[]};
var owner_import_callees:u32[>..<]=[];
var owner_import_variables:u32[>..<]=[];
var owner_order_entries:OrderEntry[>..<]=[];
var owner_name_bytes:u8[>..<]=[];
var owner_diagnostic_bytes:u8[>..<]=[];
var owner_expected_bytes:u8[>..<]=[];
var owner_actual_bytes:u8[>..<]=[];
var owner_header_diagnostics:Diagnostic[>..]=[];
var owner_active_aliases:dictionary<u32,bool> = dictionary<u32,bool>{};
var owner_holes:Engine_holes[>..<]=[];
var owner_computations:Computation[>..<]=[];
var owner_reflections:Reflection[>..<]=[];
var owner_storage_frames:Engine_storage_frames[>..<]=[];
var owner_effect_runners:EffectRunner[>..<]=[];
var owner_provider_blocks:ProviderBlock[>..<]=[];
var owner_body_closed_rows:ClosedRow[>..<]=[];
var owner_covered_requirements:CoveredRequirement[>..<]=[];
var owner_closed_row_keys:dictionary<ClosedRow,bool> = dictionary<ClosedRow,bool>{};
var owner_row_sources:dictionary<u32,squid_parse_ast::Id> = dictionary<u32,squid_parse_ast::Id>{};
var owner_effect_families:EffectFamily[>..]=[];
var owner_effect_templates:EffectTemplate[>..]=[];
var owner_operation_uses:OperationUse[>..<]=[];
var owner_bindings:Binding[>..]=[];
var owner_imported_values:dictionary<ExternalTarget,u32> = dictionary<ExternalTarget,u32>{};
var owner_imported_globals:dictionary<squid_parse_symbols::Symbol,ExternalTarget> = dictionary<squid_parse_symbols::Symbol,ExternalTarget>{};
var owner_imported_qualified:dictionary<Qualified,ExternalTarget> = dictionary<Qualified,ExternalTarget>{};
var owner_merges:Merge[>..<]=[];
var owner_obligations:squid_check_types::Obligation[>..<]=[];
var owner_pending:PendingObligation[>..<]=[];
var owner_pending_ranges:PendingRange[>..<]=[];
var owner_callee_memo:dictionary<const u8[:],CalleeOutcome> = dictionary<const u8[:],CalleeOutcome>{};
var owner_qualifications:Qualification[>..<]=[];
var owner_qualification_uses:QualificationUse[>..<]=[];
var owner_forwarded_requirements:dictionary<ForwardedRequirement,bool> = dictionary<ForwardedRequirement,bool>{};
var owner_staged_global_diagnostics:dictionary<BindingId,Diagnostic[:]> = dictionary<BindingId,Diagnostic[:]>{};
var owner_selected_globals:SelectedGlobal[>..<]=[];
var owner_declared_obligations:squid_check_types::Obligation[>..<]=[];
var owner_predicate_origins:squid_parse_ast::Span[>..<]=[];
var owner_computed_variables:squid_check_types::Id[>..<]=[];
var owner_computed_rows:u32[>..<]=[];
var owner_diagnostics:Diagnostic[>..<]=[];
var owner_global_states:dictionary<BindingId,Global> = dictionary<BindingId,Global>{};
var owner_active:BindingId[>..<]=[];
var owner_env:Entry[>..<]=[];
var owner_function_exit_lambdas:squid_parse_ast::Id[>..<]=[];
var owner_nominals:Nominal[>..]=[];
var owner_contracts:Contract[>..]=[];
var owner_contract_predicates:squid_check_types::Obligation[>..]=[];
var owner_contract_members:ContractMember[>..]=[];
var owner_implementations:Implementation[>..]=[];
var owner_implementation_predicates:squid_check_types::Obligation[>..]=[];
var owner_implementation_members:ImplementationMember[>..]=[];
var owner_member_templates:squid_reuse_principal_interface::MemberTemplate[>..<]=[];
var owner_implementation_bindings:dictionary<BindingId,u32> = dictionary<BindingId,u32>{};
var owner_implementation_member_sources:dictionary<u32,squid_parse_ast::Id> = dictionary<u32,squid_parse_ast::Id>{};
var owner_implementation_member_states:dictionary<u32,Engine_implementation_member_states_state> = dictionary<u32,Engine_implementation_member_states_state>{};
var owner_active_evidence:Engine_active_evidence[>..<]=[];
var owner_implementation_order:u32[>..<]=[];
var owner_provisional_equations:Engine_provisional_equations[>..<]=[];
var owner_member_sources:dictionary<u32,squid_parse_ast::Id> = dictionary<u32,squid_parse_ast::Id>{};
var owner_member_states:dictionary<u32,Engine_member_states_state> = dictionary<u32,Engine_member_states_state>{};
var owner_contract_states:dictionary<u32,Engine_contract_states_state> = dictionary<u32,Engine_contract_states_state>{};
var owner_constructors:Constructor[>..]=[];
var owner_imported_constructor_heights:u8[>..]=[];
var owner_computation_annotations:squid_check_types::Id[>..<]=[];
var owner_projection_catalog:Projection[>..<]=[];
var owner_loop_carries:LoopCarry[>..<]=[];
var owner_loop_exits:LoopExit[>..<]=[];
var owner_statement_arms:StatementArm[>..<]=[];
var owner_loop_stack:LoopFrame[>..<]=[];
var owner_cases:squid_parse_ast::Id[>..<]=[];
var owner_associated:Associated[>..<]=[];
var owner_associated_pending:ExternalTarget[>..<]=[];
var owner_zig_orders:u32[>..]=[];
var catalog_effect_family_names:dictionary<Qualified,u32> = dictionary<Qualified,u32>{};
var catalog_effect_family_identities:dictionary<Identity,u32> = dictionary<Identity,u32>{};
var catalog_effect_members:dictionary<EffectMember,u32> = dictionary<EffectMember,u32>{};
var catalog_effect_operation_names:dictionary<Qualified,u32> = dictionary<Qualified,u32>{};
var catalog_effect_template_identities:dictionary<Identity,u32> = dictionary<Identity,u32>{};
var catalog_qualified_symbols:dictionary<squid_parse_symbols::Symbol,QualifiedResolution> = dictionary<squid_parse_symbols::Symbol,QualifiedResolution>{};
var catalog_contract_names:dictionary<Qualified,u32> = dictionary<Qualified,u32>{};
var catalog_implementation_names:dictionary<Qualified,u32> = dictionary<Qualified,u32>{};
var catalog_contract_identities:dictionary<Identity,u32> = dictionary<Identity,u32>{};
var producer_nominal_indices:dictionary<Identity,u32> = dictionary<Identity,u32>{};
var catalog_nominal_identities:dictionary<Identity,u32> = dictionary<Identity,u32>{};
var catalog_constructor_identities:dictionary<Identity,u32> = dictionary<Identity,u32>{};
var catalog_nominal_names:dictionary<Qualified,u32> = dictionary<Qualified,u32>{};
var catalog_constructor_names:dictionary<Qualified,u32> = dictionary<Qualified,u32>{};
var catalog_associated_ops:dictionary<AssociatedKey,u32> = dictionary<AssociatedKey,u32>{};
var catalog_associated_members:dictionary<AssociatedMember,u32> = dictionary<AssociatedMember,u32>{};
var catalog_qualified:dictionary<Qualified,BindingId> = dictionary<Qualified,BindingId>{};
var catalog_external_targets:dictionary<ExternalTarget,BindingId> = dictionary<ExternalTarget,BindingId>{};
var catalog_globals:dictionary<squid_parse_symbols::Symbol,BindingId> = dictionary<squid_parse_symbols::Symbol,BindingId>{};
var imports_private_scopes:squid_check_check_scheme_import::WordMap=squid_check_check_scheme_import::WordMap{..};
var imports_mapping:squid_check_check_scheme_import::WordMap=squid_check_check_scheme_import::WordMap{..};
var imports_row_variables:squid_check_check_scheme_import::WordMap=squid_check_check_scheme_import::WordMap{..};
var imports_rows:squid_check_check_scheme_import::WordMap=squid_check_check_scheme_import::WordMap{..};
var imports_labels:squid_check_check_scheme_import::WordMap=squid_check_check_scheme_import::WordMap{..};
let initialized_types,error=squid_check_types::initWithOptions(squid_check_types::Options{closed_graphs:true, ..});if error!=squid_error::Error.none {return default<Checked>(),error;}var types=initialized_types;
let patterns,error=squid_check_parameter_patterns::initPooled();if error!=squid_error::Error.none {types.deinit();return default<Checked>(),error;}
let queue,error=squid_check_solver_worklist::initPooled();if error!=squid_error::Error.none {types.deinit();var patterns=patterns;patterns.deinit();return default<Checked>(),error;}
let watches,error=squid_check_solver_worklist::initPooled();if error!=squid_error::Error.none {types.deinit();var patterns=patterns;patterns.deinit();var queue=queue;queue.deinit();return default<Checked>(),error;}
var dependency_entries:squid_check_scheme_dependencies::Entry[>..<]=[];
var slice_provider_block_ids:u32[>..]=[];slice_provider_block_ids.resize(tree.nodes.len,default<u32>());
var slice_effect_runner_ids:u32[>..]=[];slice_effect_runner_ids.resize(tree.nodes.len,default<u32>());
var slice_operation_refs:u32[>..]=[];slice_operation_refs.resize(tree.nodes.len,default<u32>());
var slice_lambda_closed_rows:squid_check_types::List[>..]=[];slice_lambda_closed_rows.resize(tree.nodes.len,default<squid_check_types::List>());
var slice_dispatch_signatures:squid_check_types::Id[>..]=[];slice_dispatch_signatures.resize(tree.nodes.len,default<squid_check_types::Id>());
var slice_expr_types:squid_check_types::Id[>..]=[];slice_expr_types.resize(tree.nodes.len,default<squid_check_types::Id>());
var slice_resolved:BindingId[>..]=[];slice_resolved.resize(tree.nodes.len,default<BindingId>());
var slice_constructor_resolved:u32[>..]=[];slice_constructor_resolved.resize(tree.nodes.len,default<u32>());
var slice_projections:u32[>..]=[];slice_projections.resize(tree.nodes.len,0xffffffff);
var slice_projection_resolved:u32[>..]=[];slice_projection_resolved.resize(tree.nodes.len,default<u32>());
var slice_access_paths:squid_check_types::List[>..]=[];slice_access_paths.resize(tree.nodes.len,default<squid_check_types::List>());
var slice_access_nodes:squid_check_types::List[>..]=[];slice_access_nodes.resize(tree.nodes.len,default<squid_check_types::List>());
var slice_access_types:squid_check_types::List[>..]=[];slice_access_types.resize(tree.nodes.len,default<squid_check_types::List>());
var slice_rebindings:Rebinding[>..]=[];slice_rebindings.resize(tree.nodes.len,default<Rebinding>());
var slice_loop_ranges:squid_check_types::List[>..]=[];slice_loop_ranges.resize(tree.nodes.len,default<squid_check_types::List>());
var slice_iterator_bodies:squid_parse_ast::Id[>..]=[];slice_iterator_bodies.resize(tree.nodes.len,default<squid_parse_ast::Id>());
var tag_origins:TagOrigin[>..]=[]; let ast_walk_1_count=tree.nodes.items.len;for id in 0..ast_walk_1_count {let node=tree.nodes.items[id];if node.tag==squid_parse_ast::tag_attribute {tag_origins.push(TagOrigin{tree.span(node.a),id as u32, ..});}}
let __field_order_72_import_callees: u32[>..<]& .= owner_import_callees; let __field_order_73_import_variables: u32[>..<]& .= owner_import_variables; let __field_order_74_order_entries: squid_check_check::OrderEntry[>..<]& .= owner_order_entries; let __field_order_75_name_bytes: u8[>..<]& .= owner_name_bytes; let __field_order_76_diagnostic_bytes: u8[>..<]& .= owner_diagnostic_bytes; let __field_order_77_expected_bytes: u8[>..<]& .= owner_expected_bytes; let __field_order_78_actual_bytes: u8[>..<]& .= owner_actual_bytes; let __field_order_79_header_diagnostics: squid_check_check::Diagnostic[>..]& .= owner_header_diagnostics; let __field_order_83_active_aliases: dictionary<u32,bool>& .= owner_active_aliases; let __field_order_84_holes: squid_check_check::Engine_holes[>..<]& .= owner_holes; let __field_order_86_computations: squid_check_check::Computation[>..<]& .= owner_computations; let __field_order_90_reflections: squid_check_check::Reflection[>..<]& .= owner_reflections; let __field_order_95_storage_frames: squid_check_check::Engine_storage_frames[>..<]& .= owner_storage_frames; let __field_order_96_effect_runners: squid_check_check::EffectRunner[>..<]& .= owner_effect_runners; let __field_order_97_provider_blocks: squid_check_check::ProviderBlock[>..<]& .= owner_provider_blocks; let __field_order_98_body_closed_rows: squid_check_check::ClosedRow[>..<]& .= owner_body_closed_rows; let __field_order_99_covered_requirements: squid_check_check::CoveredRequirement[>..<]& .= owner_covered_requirements; let __field_order_105_closed_row_keys: dictionary<squid_check_check::ClosedRow,bool>& .= owner_closed_row_keys; let __field_order_106_row_sources: dictionary<u32,squid_parse_ast::Id>& .= owner_row_sources; let __field_order_107_effect_families: squid_check_check::EffectFamily[>..]& .= owner_effect_families; let __field_order_108_effect_templates: squid_check_check::EffectTemplate[>..]& .= owner_effect_templates; let __field_order_109_operation_uses: squid_check_check::OperationUse[>..<]& .= owner_operation_uses; let __field_order_110_bindings: squid_check_check::Binding[>..]& .= owner_bindings; let __field_order_111_imported_values: dictionary<squid_check_check::ExternalTarget,u32>& .= owner_imported_values; let __field_order_112_imported_globals: dictionary<squid_parse_symbols::Symbol,squid_check_check::ExternalTarget>& .= owner_imported_globals; let __field_order_113_imported_qualified: dictionary<squid_check_check::Qualified,squid_check_check::ExternalTarget>& .= owner_imported_qualified; let __field_order_114_merges: squid_check_check::Merge[>..<]& .= owner_merges; let __field_order_115_obligations: squid_check_types::Obligation[>..<]& .= owner_obligations; let __field_order_116_pending: squid_check_check::PendingObligation[>..<]& .= owner_pending; let __field_order_117_callee_memo: dictionary<const u8[:],squid_check_check::CalleeOutcome>& .= owner_callee_memo; let __field_order_118_qualifications: squid_check_check::Qualification[>..<]& .= owner_qualifications; let __field_order_119_qualification_uses: squid_check_check::QualificationUse[>..<]& .= owner_qualification_uses; let __field_order_120_forwarded_requirements: dictionary<squid_check_check::ForwardedRequirement,bool>& .= owner_forwarded_requirements; let __field_order_121_staged_global_diagnostics: dictionary<squid_check_check::BindingId,squid_check_check::Diagnostic[:]>& .= owner_staged_global_diagnostics; let __field_order_122_selected_globals: squid_check_check::SelectedGlobal[>..<]& .= owner_selected_globals; let __field_order_123_declared_obligations: squid_check_types::Obligation[>..<]& .= owner_declared_obligations; let __field_order_124_predicate_origins: squid_parse_ast::Span[>..<]& .= owner_predicate_origins; let __field_order_125_computed_variables: squid_check_types::Id[>..<]& .= owner_computed_variables; let __field_order_126_computed_rows: u32[>..<]& .= owner_computed_rows; let __field_order_127_diagnostics: squid_check_check::Diagnostic[>..<]& .= owner_diagnostics; let __field_order_128_global_states: dictionary<squid_check_check::BindingId,squid_check_check::Global>& .= owner_global_states; let __field_order_129_active: squid_check_check::BindingId[>..<]& .= owner_active; let __field_order_130_env: squid_check_check::Entry[>..<]& .= owner_env; let __field_order_131_function_exit_lambdas: squid_parse_ast::Id[>..<]& .= owner_function_exit_lambdas; let __field_order_132_nominals: squid_check_check::Nominal[>..]& .= owner_nominals; let __field_order_133_contracts: squid_check_check::Contract[>..]& .= owner_contracts; let __field_order_134_contract_predicates: squid_check_types::Obligation[>..]& .= owner_contract_predicates; let __field_order_135_contract_members: squid_check_check::ContractMember[>..]& .= owner_contract_members; let __field_order_136_implementations: squid_check_check::Implementation[>..]& .= owner_implementations; let __field_order_137_implementation_predicates: squid_check_types::Obligation[>..]& .= owner_implementation_predicates; let __field_order_138_implementation_members: squid_check_check::ImplementationMember[>..]& .= owner_implementation_members; let __field_order_139_member_templates: squid_reuse_principal_interface::MemberTemplate[>..<]& .= owner_member_templates; let __field_order_144_implementation_bindings: dictionary<squid_check_check::BindingId,u32>& .= owner_implementation_bindings; let __field_order_145_implementation_member_sources: dictionary<u32,squid_parse_ast::Id>& .= owner_implementation_member_sources; let __field_order_146_implementation_member_states: dictionary<u32,squid_check_check::Engine_implementation_member_states_state>& .= owner_implementation_member_states; let __field_order_147_active_evidence: squid_check_check::Engine_active_evidence[>..<]& .= owner_active_evidence; let __field_order_148_implementation_order: u32[>..<]& .= owner_implementation_order; let __field_order_149_provisional_equations: squid_check_check::Engine_provisional_equations[>..<]& .= owner_provisional_equations; let __field_order_150_member_sources: dictionary<u32,squid_parse_ast::Id>& .= owner_member_sources; let __field_order_151_member_states: dictionary<u32,squid_check_check::Engine_member_states_state>& .= owner_member_states; let __field_order_152_contract_states: dictionary<u32,squid_check_check::Engine_contract_states_state>& .= owner_contract_states; let __field_order_153_constructors: squid_check_check::Constructor[>..]& .= owner_constructors; let __field_order_154_computation_annotations: squid_check_types::Id[>..<]& .= owner_computation_annotations; let __field_order_155_projection_catalog: squid_check_check::Projection[>..<]& .= owner_projection_catalog; let __field_order_161_loop_carries: squid_check_check::LoopCarry[>..<]& .= owner_loop_carries; let __field_order_162_loop_exits: squid_check_check::LoopExit[>..<]& .= owner_loop_exits; let __field_order_163_statement_arms: squid_check_check::StatementArm[>..<]& .= owner_statement_arms; let __field_order_164_loop_stack: squid_check_check::LoopFrame[>..<]& .= owner_loop_stack; let __field_order_165_cases: squid_parse_ast::Id[>..<]& .= owner_cases; let __field_order_166_associated: squid_check_check::Associated[>..<]& .= owner_associated; let __field_order_166b_associated_pending: squid_check_check::ExternalTarget[>..<]& .= owner_associated_pending; let __field_order_166c_zig_orders: u32[>..]& .= owner_zig_orders; let __field_order_167_catalogs: squid_check_check::CatalogIndex = CatalogIndex{effect_family_names:catalog_effect_family_names,effect_family_identities:catalog_effect_family_identities,effect_members:catalog_effect_members,effect_operation_names:catalog_effect_operation_names,effect_template_identities:catalog_effect_template_identities,qualified_symbols:catalog_qualified_symbols,contract_names:catalog_contract_names,implementation_names:catalog_implementation_names,contract_identities:catalog_contract_identities,nominal_identities:catalog_nominal_identities,producer_nominal_indices:producer_nominal_indices,constructor_identities:catalog_constructor_identities,nominal_names:catalog_nominal_names,constructor_names:catalog_constructor_names,associated_ops:catalog_associated_ops,associated_members:catalog_associated_members,qualified:catalog_qualified,external_targets:catalog_external_targets,globals:catalog_globals, ..}; let __field_order_168_import_tables: squid_check_check_scheme_import::Tables = squid_check_check_scheme_import::Tables{private_scopes:imports_private_scopes,mapping:imports_mapping,row_variables:imports_row_variables,rows:imports_rows,labels:imports_labels, ..}; let __field_order_171_tree: const squid_parse_ast::Tree& .= tree; let __field_order_172_pool: squid_parse_symbols::Pool& .= pool; let __field_order_173_types: squid_check_types::Store = types; let __field_order_174_parameter_patterns: squid_check_parameter_patterns::Store = patterns; let __field_order_176_pending_queue: squid_check_solver_worklist::Queue = queue; var dependency_cache=squid_check_scheme_dependencies::init(dependency_entries,watches); let __field_order_177_scheme_dependencies: squid_check_scheme_dependencies::Cache& .= dependency_cache; let __field_order_183_editor_marker: squid_support::Option<squid_check_check::EditorMarker> = options.editor; let __field_order_184_budget_exhaustion: squid_check_check::BudgetExhaustion? .= exhaustion; let __field_order_185_execution: squid_check_check::PrivateExecution = execution; let __field_order_186_inference_limit: i64 = inferenceBudget(options); let __field_order_188_self_name: squid_parse_symbols::Symbol = 0; let __field_order_189_unit: u32 = unit; let __field_order_190_builtin_catalog: bool = options.builtin_catalog; let __field_order_190b_is_std: bool = options.is_std; let __field_order_191_purity_origins: squid_check_check::ModuleOrigins = options.purity_origins; let __field_order_192_source_validation: bool = source_validation; let __field_order_193_prelude_unit: u32 = options.prelude_unit; let __field_order_194_producer_capabilities: squid_support::Option<squid_check_check::ProducerCapabilities> = options.producer_capabilities; let __field_order_195_producer_storage: squid_support::Option<squid_check_check::ProducerStorage> = options.producer_storage; let __field_order_197_provider_block_ids: u32[:] = slice_provider_block_ids; let __field_order_198_effect_runner_ids: u32[:] = slice_effect_runner_ids; let __field_order_199_operation_refs: u32[:] = slice_operation_refs; let __field_order_200_lambda_closed_rows: squid_check_types::List[:] = slice_lambda_closed_rows; let __field_order_201_dispatch_signatures: squid_check_types::Id[:] = slice_dispatch_signatures; let __field_order_202_expr_types: squid_check_types::Id[:] = slice_expr_types; let __field_order_203_resolved: squid_check_check::BindingId[:] = slice_resolved; let __field_order_204_constructor_resolved: u32[:] = slice_constructor_resolved; let __field_order_205_projections: u32[:] = slice_projections; let __field_order_206_projection_resolved: u32[:] = slice_projection_resolved; let __field_order_207_access_paths: squid_check_types::List[:] = slice_access_paths; let __field_order_208_access_nodes: squid_check_types::List[:] = slice_access_nodes; let __field_order_209_access_types: squid_check_types::List[:] = slice_access_types; let __field_order_210_rebindings: squid_check_check::Rebinding[:] = slice_rebindings; let __field_order_211_loop_ranges: squid_check_types::List[:] = slice_loop_ranges; let __field_order_212_iterator_bodies: squid_parse_ast::Id[:] = slice_iterator_bodies; let __field_order_217_tag_origins: squid_check_check::TagOrigin[:] = tag_origins; var engine=Engine{ import_callees: __field_order_72_import_callees, import_variables: __field_order_73_import_variables, import_tables: __field_order_168_import_tables, order_entries: __field_order_74_order_entries, name_bytes: __field_order_75_name_bytes, diagnostic_bytes: __field_order_76_diagnostic_bytes, expected_bytes: __field_order_77_expected_bytes, actual_bytes: __field_order_78_actual_bytes, header_diagnostics: __field_order_79_header_diagnostics, catalogs: __field_order_167_catalogs, editor_marker: __field_order_183_editor_marker, active_aliases: __field_order_83_active_aliases, holes: __field_order_84_holes, execution: __field_order_185_execution, inference_limit: __field_order_186_inference_limit, budget_exhaustion: __field_order_184_budget_exhaustion, computations: __field_order_86_computations, reflections: __field_order_90_reflections, tag_origins: __field_order_217_tag_origins, storage_frames: __field_order_95_storage_frames, effect_runners: __field_order_96_effect_runners, effect_runner_ids: __field_order_198_effect_runner_ids, provider_blocks: __field_order_97_provider_blocks, provider_block_ids: __field_order_197_provider_block_ids, body_closed_rows: __field_order_98_body_closed_rows, covered_requirements: __field_order_99_covered_requirements, closed_row_keys: __field_order_105_closed_row_keys, row_sources: __field_order_106_row_sources, purity_origins: __field_order_191_purity_origins, lambda_closed_rows: __field_order_200_lambda_closed_rows, dispatch_signatures: __field_order_201_dispatch_signatures, effect_families: __field_order_107_effect_families, effect_templates: __field_order_108_effect_templates, operation_uses: __field_order_109_operation_uses, operation_refs: __field_order_199_operation_refs, tree: __field_order_171_tree, pool: __field_order_172_pool, types: __field_order_173_types, parameter_patterns: __field_order_174_parameter_patterns, expr_types: __field_order_202_expr_types, resolved: __field_order_203_resolved, bindings: __field_order_110_bindings, imported_values: __field_order_111_imported_values, import_arena: owner_import_arena, imported_globals: __field_order_112_imported_globals, imported_qualified: __field_order_113_imported_qualified, merges: __field_order_114_merges, obligations: __field_order_115_obligations, pending: __field_order_116_pending, pending_ranges:owner_pending_ranges, pending_queue: __field_order_176_pending_queue, scheme_dependencies: __field_order_177_scheme_dependencies, callee_memo: __field_order_117_callee_memo, qualifications: __field_order_118_qualifications, qualification_uses: __field_order_119_qualification_uses, forwarded_requirements: __field_order_120_forwarded_requirements, staged_global_diagnostics: __field_order_121_staged_global_diagnostics, selected_globals: __field_order_122_selected_globals, declared_obligations: __field_order_123_declared_obligations, predicate_origins: __field_order_124_predicate_origins, computed_variables: __field_order_125_computed_variables, computed_rows: __field_order_126_computed_rows, diagnostics: __field_order_127_diagnostics, global_states: __field_order_128_global_states, active: __field_order_129_active, env: __field_order_130_env, function_exit_lambdas: __field_order_131_function_exit_lambdas, self_name: __field_order_188_self_name, unit: __field_order_189_unit, builtin_catalog: __field_order_190_builtin_catalog, is_std: __field_order_190b_is_std, source_validation: __field_order_192_source_validation, producer_capabilities: __field_order_194_producer_capabilities, producer_storage: __field_order_195_producer_storage, prelude_unit: __field_order_193_prelude_unit, nominals: __field_order_132_nominals, contracts: __field_order_133_contracts, contract_predicates: __field_order_134_contract_predicates, contract_members: __field_order_135_contract_members, implementations: __field_order_136_implementations, implementation_predicates: __field_order_137_implementation_predicates, implementation_members: __field_order_138_implementation_members, member_templates: __field_order_139_member_templates, implementation_bindings: __field_order_144_implementation_bindings, implementation_member_sources: __field_order_145_implementation_member_sources, implementation_member_states: __field_order_146_implementation_member_states, active_evidence: __field_order_147_active_evidence, implementation_order: __field_order_148_implementation_order, provisional_equations: __field_order_149_provisional_equations, member_sources: __field_order_150_member_sources, member_states: __field_order_151_member_states, contract_states: __field_order_152_contract_states, constructors: __field_order_153_constructors, imported_constructor_heights: owner_imported_constructor_heights, computation_annotations: __field_order_154_computation_annotations, constructor_resolved: __field_order_204_constructor_resolved, projections: __field_order_205_projections, access_paths: __field_order_207_access_paths, access_nodes: __field_order_208_access_nodes, access_types: __field_order_209_access_types, projection_resolved: __field_order_206_projection_resolved, projection_catalog: __field_order_155_projection_catalog, rebindings: __field_order_210_rebindings, loop_carries: __field_order_161_loop_carries, iterator_bodies: __field_order_212_iterator_bodies, loop_ranges: __field_order_211_loop_ranges, loop_exits: __field_order_162_loop_exits, statement_arms: __field_order_163_statement_arms, loop_stack: __field_order_164_loop_stack, cases: __field_order_165_cases, associated: __field_order_166_associated, associated_pending: __field_order_166b_associated_pending, zig_orders: __field_order_166c_zig_orders, .. };
initializeEngineAccounting(engine,options);let checked,error=checkEngineBody(engine,imports,headers,catalogs,source_catalogs,allow_imports,options,source_validation,exhaustion);deinitEngine(engine);return checked,error;
}
fn publishChecked(engine:Engine&)->Checked,squid_error::Error {let pending=engine.publishPendingAssociated();if pending!=squid_error::Error.none {return default<Checked>(),pending;}let owner,error=newCheckedOwner();if error!=squid_error::Error.none {return default<Checked>(),error;}engine.completed_projection_steps=engine.types.projection_steps;engine.completed_projection_limit=engine.types.projection_limit;engine.completed_projection_exhausted=engine.types.projection_exhausted;var result=Checked{ owner:owner, types:squid_check_types::checkedView(engine.types), parameter_patterns:squid_check_parameter_patterns::checkedView(engine.parameter_patterns), body_elaborations:engine.body_elaborations, counters:engine.counters, unit:engine.unit, .. };engine.types=squid_check_types::Store{..};engine.parameter_patterns=squid_check_parameter_patterns::Store{..};if !engine.source_validation {result.imported_schemes=engine.catalogs.external_targets.count;}result.counters.inference_steps=(engine.inference_transitions+result.types.projection_steps) as u64;result.counters.associated_steps=result.types.projection_steps as u64;
result.function_exit_lambdas=ownChecked_function_exit_lambdas(owner,engine.function_exit_lambdas);
result.iterator_bodies=ownChecked_iterator_bodies(owner,engine.iterator_bodies);
result.computations=ownChecked_computations(owner,engine.computations);
result.reflections=ownChecked_reflections(owner,engine.reflections);
result.tag_origins=ownChecked_tag_origins(owner,engine.tag_origins);
result.effect_runners=ownChecked_effect_runners(owner,engine.effect_runners);
result.effect_runner_ids=ownChecked_effect_runner_ids(owner,engine.effect_runner_ids);
result.provider_blocks=ownChecked_provider_blocks(owner,engine.provider_blocks);
result.provider_block_ids=ownChecked_provider_block_ids(owner,engine.provider_block_ids);
result.body_closed_rows=ownChecked_body_closed_rows(owner,engine.body_closed_rows);
result.lambda_closed_rows=ownChecked_lambda_closed_rows(owner,engine.lambda_closed_rows);
result.dispatch_signatures=ownChecked_dispatch_signatures(owner,engine.dispatch_signatures);
result.covered_requirements=ownChecked_covered_requirements(owner,engine.covered_requirements);
result.effect_families=ownChecked_effect_families(owner,engine.effect_families);
result.effect_templates=ownChecked_effect_templates(owner,engine.effect_templates);
result.operation_uses=ownChecked_operation_uses(owner,engine.operation_uses);
result.operation_refs=ownChecked_operation_refs(owner,engine.operation_refs);
result.expr_types=ownChecked_expr_types(owner,engine.expr_types);
result.resolved=ownChecked_resolved(owner,engine.resolved);
result.bindings=ownChecked_bindings(owner,engine.bindings);
result.merges=ownChecked_merges(owner,engine.merges);
result.obligations=ownChecked_obligations(owner,engine.obligations);
let diagnostics,diagnostic_error=cloneDiagnostics(owner,engine.diagnostics);if diagnostic_error!=squid_error::Error.none {result.deinit();return default<Checked>(),diagnostic_error;}result.diagnostics=diagnostics;
result.associated=ownChecked_associated(owner,engine.associated);
result.nominals=ownChecked_nominals(owner,engine.nominals);
result.contracts=ownChecked_contracts(owner,engine.contracts);
result.contract_predicates=ownChecked_contract_predicates(owner,engine.contract_predicates);
result.contract_members=ownChecked_contract_members(owner,engine.contract_members);
result.implementations=ownChecked_implementations(owner,engine.implementations);
result.implementation_predicates=ownChecked_implementation_predicates(owner,engine.implementation_predicates);
result.implementation_members=ownChecked_implementation_members(owner,engine.implementation_members);
result.member_templates=ownChecked_member_templates(owner,engine.member_templates);
result.constructors=ownChecked_constructors(owner,engine.constructors);
result.constructor_resolved=ownChecked_constructor_resolved(owner,engine.constructor_resolved);
result.projections=ownChecked_projections(owner,engine.projections);
result.access_paths=ownChecked_access_paths(owner,engine.access_paths);
result.access_nodes=ownChecked_access_nodes(owner,engine.access_nodes);
result.access_types=ownChecked_access_types(owner,engine.access_types);
result.projection_resolved=ownChecked_projection_resolved(owner,engine.projection_resolved);
result.projection_catalog=ownChecked_projection_catalog(owner,engine.projection_catalog);
result.rebindings=ownChecked_rebindings(owner,engine.rebindings);
result.loop_carries=ownChecked_loop_carries(owner,engine.loop_carries);
result.loop_ranges=ownChecked_loop_ranges(owner,engine.loop_ranges);
result.loop_exits=ownChecked_loop_exits(owner,engine.loop_exits);
result.statement_arms=ownChecked_statement_arms(owner,engine.statement_arms);
if engine.editor_capture.present {let capture=engine.editor_capture.value;let owned=ownEditorCapture(owner,capture);result.editor=squid_support::Option<EditorCapture>{true,owned};squid_reuse_completion_names::release(capture.names);}engine.editor_capture=squid_support::none<EditorCapture>();return result,squid_error::Error.none;}
fn ownEditorCapture(owner:CheckedOwner,value:EditorCapture)->EditorCapture {
 var result=EditorCapture{names:ownChecked_editor_names(owner,value.names),kind:value.kind,node:value.node,scope:value.scope,visible:value.visible,visible_names:value.visible_names,scope_names:value.scope_names,type_scope:value.type_scope,truncated:value.truncated,owner:value.owner,receiver:value.receiver,namespace_:value.namespace_,..};
 if value.context.present {result.context=squid_support::Option<squid_reuse_hole_diagnostics::Snapshot>{true,squid_reuse_hole_diagnostics::canonicalOwned(value.context.value)};}return result;
}
fn initializeEngineAccounting(engine:Engine&,options:ModuleOptions) {engine.types.projection_limit=inferenceBudget(options);let remaining .= options.associated_remaining;if remaining {engine.types.projection_limit=min(engine.types.projection_limit,remaining);}}
fn checkEngineBody(engine:Engine&,imports:const ImportedBinding[:],headers:const SourceHeader[:],catalogs:const ImportedCatalog[:],source_catalogs:const SourceCatalog[:],allow_imports:bool,options:ModuleOptions,source_validation:bool,exhaustion:BudgetExhaustion&)->Checked,squid_error::Error {
 engine.effect_families.push(EffectFamily{identity:Identity{0,0, ..},name:0, ..});engine.effect_templates.push(EffectTemplate{identity:Identity{0,0, ..},family:0,name:0,parameter:0,result:0, ..});engine.nominals.push(Nominal{identity:Identity{0,0, ..},name:0,parameters:squid_check_types::List{..},variables:squid_check_types::List{..}, ..});engine.constructors.push(Constructor{identity:Identity{0,0, ..},nominal:0,tag:0,name:0, ..});engine.projection_catalog.push(Projection{nominal:Identity{0,0, ..},field:0,variants:squid_check_types::List{..}, ..});let self_name,present=engine.pool.lookup("self");if present {engine.self_name=self_name;}
 var binding_capacity=imports.len+headers.len+1;let ast_walk_2_count=engine.tree.nodes.items.len;for ast_walk_2_index in 0..ast_walk_2_count {let node=engine.tree.nodes.items[ast_walk_2_index];if node.tag==squid_parse_ast::tag_value_decl || node.tag==squid_parse_ast::tag_entry_process_decl {binding_capacity+=1;}else if node.tag==squid_parse_ast::tag_entry_kernel_decl {binding_capacity+=2;}else if !source_validation && (node.tag==squid_parse_ast::tag_parameter || node.tag==squid_parse_ast::tag_pattern_name) {binding_capacity+=1;}}let ignored,error=engine.addBinding(Binding{name:0,declaration:0,owner:0,kind:squid_reuse_principal_interface::Kind.local,ty:0, ..});if error!=squid_error::Error.none {return default<Checked>(),error;}let ast_walk_3_count=engine.tree.diagnostics.items.len;for ast_walk_3_index in 0..ast_walk_3_count {let diagnostic=engine.tree.diagnostics.items[ast_walk_3_index];engine.diagnostics.push(Diagnostic{code:Code.syntax,span:squid_parse_ast::Span{diagnostic.start,diagnostic.end, ..},node:0, ..});}
 let checked,error=checkEngineSemantic(engine,imports,headers,catalogs,source_catalogs,allow_imports,options,source_validation);var steps=engine.completed_projection_steps;var limit=engine.completed_projection_limit;var exhausted=engine.completed_projection_exhausted;if engine.types.lease!=0 {steps=engine.types.projection_steps;limit=engine.types.projection_limit;exhausted=engine.types.projection_exhausted;}let remaining .= options.associated_remaining;if remaining {remaining-=min(remaining,steps);}if exhausted {engine.exhaustBudget();exhaustion.associated=true;exhaustion.associated_limit=limit;}return checked,error;
}
fn checkEngineSemantic(engine:Engine&,imports:const ImportedBinding[:],headers:const SourceHeader[:],catalogs:const ImportedCatalog[:],source_catalogs:const SourceCatalog[:],allow_imports:bool,options:ModuleOptions,source_validation:bool)->Checked,squid_error::Error {let error=engine.collectModuleHeaders(imports,headers,catalogs,source_catalogs,allow_imports);if error!=squid_error::Error.none {return default<Checked>(),error;}let retained .= options.retained_core;
if retained {
 let error=engine.seedRetainedGlobals(retained,options.skip_root);
 if error!=squid_error::Error.none {return default<Checked>(),error;}
}
let error=engine.validateModuleBodies(options.skip_root);
if error!=squid_error::Error.none {return default<Checked>(),error;}
if retained && !engine.acceptRetainedGlobals(retained,options.skip_root) {return default<Checked>(),squid_error::Error.invalid_artifact;}
let value,error=publishChecked(engine);if error!=squid_error::Error.none {return default<Checked>(),error;}var checked=value;if !source_validation && engine.initializer_rejected {let result,error=rejectedSource(checked.diagnostics);checked.deinit();if error!=squid_error::Error.none {return default<Checked>(),error;}var rejected=result;rejected.initializer_rejected=true;rejected.unit=engine.unit;return rejected,squid_error::Error.none;}
engine.frontend_work.modules=1;engine.frontend_work.type_nodes=checked.types.nodes.len as u64;engine.frontend_work.dependency_hits=engine.scheme_dependencies.hits;engine.frontend_work.dependency_recomputations=engine.scheme_dependencies.recomputations;engine.frontend_work.normalization=checked.types.normalization;for binding in checked.bindings {if binding.kind==squid_reuse_principal_interface::Kind.external && binding.read {engine.frontend_work.imported_read+=1;}}squid_phase_profile::recordChecking(engine.frontend_work);return checked,squid_error::Error.none;
}
fn deinitEngine(engine:Engine&) {
 engine.import_tables.private_scopes.deinit();engine.import_tables.mapping.deinit();engine.import_tables.row_variables.deinit();engine.import_tables.rows.deinit();engine.import_tables.labels.deinit();
 engine.imported_values.clear();
 deinitDiagnosticPayloads(engine.diagnostics);for slot in engine.staged_global_diagnostics.slots {if slot.tag!=0 {deinitDiagnosticPayloads(slot.val);if slot.val.len!=0 {component_diagnostics.free_slice(slot.val);}}}for slot in engine.callee_memo.slots {if slot.tag!=0 {freeDiagnosticText(slot.key);if slot.val.types.len!=0 {equation_type_ids.free_slice(slot.val.types);}if slot.val.rows.len!=0 {equation_type_ids.free_slice(slot.val.rows);}}}engine.type_env.deinit();engine.row_env.deinit();if engine.editor_capture.present {squid_reuse_completion_names::release(engine.editor_capture.value.names);if engine.editor_capture.value.context.present {engine.editor_capture.value.context.value.deinit();}}engine.parameter_patterns.deinit();engine.types.deinit();engine.pending_queue.deinit();engine.scheme_dependencies.deinit();deinitDiagnosticPayloads(engine.header_diagnostics);
}

// Rehydrate principals into this inference store. Core IDs are never used as
// mutable checker IDs, including the local targets of shared obligations.
fn retainedTypeSource(core:const squid_check_core::Module&)->squid_check_frozen_types::Source {
 let effects=core.types.effects;
 return squid_check_frozen_types::Source.frozen{
  value:squid_check_frozen_types::Graph{nodes:core.types.nodes,extra:core.types.extra,
   rows:effects.rows,labels:effects.labels,operations:core.types.operations,row_variable_count:effects.variable_count},..};
}

fn seedRetainedGlobals(self_:Engine&,core:const squid_check_core::Module&,skip_root:const bool[:])->squid_error::Error {
 if self_.diagnostics.len!=0 {return squid_error::Error.invalid_artifact;}
 var edited:bool[>..<]=[];
 edited.resize(self_.bindings.len,false);
 for root,index in self_.tree.roots.items {if !skip_root[index] {edited[self_.resolved[root]]=true;}}
 for binding,index in self_.bindings {
  if binding.kind!=squid_reuse_principal_interface::Kind.global {continue;}
  if index>=core.bindings.len {return squid_error::Error.invalid_artifact;}
  let old=core.bindings[index];
  if old.kind!=binding.kind || old.private!=binding.private || old.body_id==0 || old.body_id>=core.bodies.len ||
     core.bodies[old.body_id].binding!=index ||
     !self_.sameRetainedGlobalName(core,index as u32,binding) {return squid_error::Error.invalid_artifact;}
 }
 for before,index in core.bindings {
  if before.kind==squid_reuse_principal_interface::Kind.global &&
     (index>=self_.bindings.len || self_.bindings[index].kind!=before.kind) {return squid_error::Error.invalid_artifact;}
 }
 var copier=squid_check_check_scheme_import::init(retainedTypeSource(core),self_.types,self_.import_tables);
 copier.fresh_variables=true;
 copier.fresh_rows=true;
 let error=seedRetainedSchemes(self_,core,edited[..],copier);
 copier.reset();
 return error;
}

fn sameRetainedGlobalName(self_:const Engine&,core:const squid_check_core::Module&,index:u32,binding:Binding)->bool {
 let name=core.name(core.bodies[core.bindings[index].body_id].declaration_name);
 if name==self_.pool.get(binding.name) {return true;}
 // Template bodies have no source-name entry. Their header was freshly
 // collected, and its contract and member key identify the same binding.
 if name.len!=0 {return false;}
 for template,ordinal in self_.member_templates {
  if template.binding!=index {continue;}
  if ordinal>=core.member_templates.len {return false;}
  let old=core.member_templates[ordinal];
  return old.binding==index && old.contract==template.contract && old.name==template.name;
 }
 return false;
}

fn seedRetainedSchemes(self_:Engine&,core:const squid_check_core::Module&,edited:const bool[:],copier:squid_check_check_scheme_import::Copier&)->squid_error::Error {
 var mapped:u32[>..]=[];
 var visiting:bool[>..]=[];
 mapped.resize(core.bindings.len,0);
 visiting.resize(core.bindings.len,false);
 for before,index in core.bindings {
  if before.kind!=squid_reuse_principal_interface::Kind.global || edited[index] {continue;}
  let error=self_.seedRetainedScheme(core,index as u32,self_.bindings[index].declaration,edited,mapped[..],visiting[..],copier,0);
  if error!=squid_error::Error.none {return error;}
 }
 return squid_error::Error.none;
}

recursive fn seedRetainedScheme(self_:Engine&,core:const squid_check_core::Module&,index:u32,origin:u32,edited:const bool[:],mapped:u32[:],visiting:bool[:],copier:squid_check_check_scheme_import::Copier&,depth:i64)->squid_error::Error {
 if index==0 || index>=mapped.len || depth>=256 || visiting[index] {return squid_error::Error.invalid_artifact;}
 if mapped[index]!=0 {return squid_error::Error.none;}
 let old=core.bindings[index];
 let global=old.kind==squid_reuse_principal_interface::Kind.global;
 if global {
  if edited[index] {return squid_error::Error.invalid_artifact;}
  if self_.bindings[index].scheme.root!=0 {
   mapped[index]=index;
   return squid_error::Error.none;
  }
 } else if old.kind!=squid_reuse_principal_interface::Kind.external || old.target.unit==0 {
  return squid_error::Error.invalid_artifact;
 }
 visiting[index]=true;
 let range=old.scheme.obligations;
 for goal in core.obligations[range.start..range.start+range.len] {
  if goal.kind!=squid_check_types::ObligationKind.callee_use {continue;}
  let error=self_.seedRetainedScheme(core,goal.identity.decl,origin,edited,mapped,visiting,copier,depth+1);
  if error!=squid_error::Error.none {return error;}
 }
 let ty,error=copier.copy(old.ty,0);
 if error!=squid_error::Error.none {return error;}
 let root,error=copier.copy(old.scheme.root,0);
 if error!=squid_error::Error.none {return error;}
 if root==0 {return squid_error::Error.invalid_artifact;}
 let variables,error=copier.copyTypeList(old.scheme.variables);
 if error!=squid_error::Error.none {return error;}
 let rows,error=copier.relocatedRows(core.types.list(old.scheme.row_variables));
 if error!=squid_error::Error.none {return error;}
 let closed,error=copier.relocatedRows(core.types.list(old.scheme.closed_rows));
 if error!=squid_error::Error.none {return error;}
 let generative,error=copier.copyGenerative(old.scheme.generative);
 if error!=squid_error::Error.none {return error;}
 let start=self_.obligations.len as u32;
 for goal in core.obligations[range.start..range.start+range.len] {
  let ty,error=copier.copy(goal.ty,0);
  if error!=squid_error::Error.none {return error;}
  let result,error=copier.copy(goal.result,0);
  if error!=squid_error::Error.none {return error;}
  let other,error=copier.copy(goal.other,0);
  if error!=squid_error::Error.none {return error;}
  let signature,error=copier.copy(goal.signature,0);
  if error!=squid_error::Error.none {return error;}
  var identity=goal.identity;
  if goal.kind==squid_check_types::ObligationKind.callee_use {identity.decl=mapped[identity.decl];}
  self_.obligations.push(squid_check_types::Obligation{ty:ty,kind:goal.kind,source:origin,
   name:goal.name,result:result,other:other,signature:signature,operator:goal.operator,identity:identity,
   explicit:goal.explicit,qualification_span:goal.qualification_span,qualification_unit:goal.qualification_unit,..});
 }
 let principal=squid_check_types::Scheme{root:root,variables:variables,row_variables:rows,closed_rows:closed,
  generative:generative,obligations:squid_check_types::List{start,range.len,..},..};
 var summary,error=self_.summarizeFrom(principal,self_.obligations[..]);
 if error!=squid_error::Error.none {return error;}
 summary.has_explicit=old.has_explicit;
 if global {
  self_.bindings[index].scheme=principal;
  self_.bindings[index].ty=ty;
  self_.bindings[index].summary=summary;
  self_.bindings[index].capability_parameters=old.capability_parameters;
  self_.global_states.insert(index,Global{state:State.complete,..});
  mapped[index]=index;
 } else {
  // A private transitive callee may be present only as frozen evidence in
  // the old Core. Keep it reachable through the obligation, without adding
  // it to name lookup or replacing an ordinary import in the edited body.
  let target=ExternalTarget{old.target.unit,old.target.binding,..};
  let binding,error=self_.addBinding(Binding{name:0,declaration:origin,owner:origin,kind:old.kind,
   ty:ty,scheme:principal,summary:summary,capability_parameters:old.capability_parameters,
   external:squid_support::some(target),..});
  if error!=squid_error::Error.none {return error;}
  mapped[index]=binding;
 }
 visiting[index]=false;
 return squid_error::Error.none;
}

fn acceptRetainedGlobals(self_:Engine&,core:const squid_check_core::Module&,skip_root:const bool[:])->bool {
 if self_.diagnostics.len!=0 || self_.initializer_rejected || self_.reflections.len!=0 ||
    self_.holes.len!=0 {return false;}
 // Lowering erases effect-family nominals to plain function or record
 // types. Those shapes cannot certify a source principal once that
 // principal is observed by the edited body.
 let has_effect_families=self_.effect_families.len>1;
 if has_effect_families {
  for binding,i in self_.bindings {
   if binding.kind!=squid_reuse_principal_interface::Kind.global || !binding.read {continue;}
   if !retainedPrincipalExact(core,i as u32) {return false;}
  }
 }
 var copier=squid_check_check_scheme_import::init(retainedTypeSource(core),self_.types,self_.import_tables);
 var count:i64=0;
 var equal=true;
 for root,index in self_.tree.roots.items {
  if skip_root[index] {continue;}
  count++;
  let binding=self_.resolved[root];
  if (has_effect_families && !retainedPrincipalExact(core,binding)) ||
     !self_.sameRetainedPrincipal(core,binding,copier) {equal=false;break;}
  copier.reset();
 }
 copier.reset();
 return equal && self_.body_elaborations==count;
}

fn sameRetainedPrincipal(self_:Engine&,core:const squid_check_core::Module&,index:u32,copier:squid_check_check_scheme_import::Copier&)->bool {
 let before=core.bindings[index];
 let after=self_.bindings[index];
 let old=before.scheme;
 let next=after.scheme;
 if before.capability_parameters!=after.capability_parameters || before.has_explicit!=after.summary.has_explicit ||
    old.variables.len!=next.variables.len || old.row_variables.len!=next.row_variables.len ||
    old.closed_rows.len!=next.closed_rows.len || old.obligations.len!=next.obligations.len ||
    old.generative.len!=next.generative.len {return false;}
 // Compare both roots and evidence under the same renaming of quantifiers.
 let variables=self_.types.list(next.variables);
 for variable,i in core.types.list(old.variables) {
  let fresh=self_.types.head(variables[i],0);
  if core.types.node(variable).tag!=squid_check_types::Tag.variable ||
     self_.types.node(fresh).tag!=squid_check_types::Tag.variable {return false;}
  for prior in variables[..i] {if self_.types.head(prior,0)==fresh {return false;}}
  copier.mapping.insert(variable,fresh);
 }
 if !self_.matchRetainedRows(copier,core.types.list(old.row_variables),self_.types.list(next.row_variables)) ||
    !self_.matchRetainedRows(copier,core.types.list(old.closed_rows),self_.types.list(next.closed_rows)) {return false;}
 let certificates=core.types.list(core.bodies[before.body_id].closed_rows);
 var rows:u32[>..]=[];
 for decision in self_.body_closed_rows {if decision.owner==index {rows.push(decision.variable);}}
 let cert=self_.matchRetainedRows(copier,certificates,rows[..]);
 if !cert || !self_.sameRetainedType(copier,old.root,next.root) {return false;}
 let generative=self_.types.list(next.generative);
 for ty,i in core.types.list(old.generative) {if !self_.sameRetainedType(copier,ty,generative[i]) {return false;}}
 for goal,i in core.obligations[old.obligations.start..old.obligations.start+old.obligations.len] {
  let other=self_.obligations[next.obligations.start+i];
  if goal.kind!=other.kind || goal.name!=other.name || goal.operator!=other.operator ||
     goal.explicit!=other.explicit || goal.qualification_unit!=other.qualification_unit ||
     goal.qualification_span!=other.qualification_span {return false;}
  if goal.kind==squid_check_types::ObligationKind.callee_use {
   let original=core.bindings[goal.identity.decl];
   let current=self_.bindings[other.identity.decl];
   if original.kind!=current.kind {return false;}
   if current.external.present {
    if original.target.unit!=current.external.value.unit || original.target.binding!=current.external.value.binding {return false;}
   } else if goal.identity!=other.identity {return false;}
  } else if goal.identity!=other.identity {return false;}
  if !self_.sameRetainedType(copier,goal.ty,other.ty) ||
     !self_.sameRetainedType(copier,goal.other,other.other) ||
     !self_.sameRetainedType(copier,goal.result,other.result) ||
     !self_.sameRetainedType(copier,goal.signature,other.signature) {return false;}
 }
 return true;
}

fn matchRetainedRows(self_:Engine&,copier:squid_check_check_scheme_import::Copier&,before:const u32[:],after:const u32[:])->bool {
 if before.len!=after.len {return false;}
 for old,i in before {
  let next=after[i];
  let a=squid_check_types::rowKeyFormal(old);
  let b=squid_check_types::rowKeyFormal(next);
  if a.present || b.present {
   if !a.present || !b.present || !self_.sameRetainedType(copier,a.value,b.value) {return false;}
   continue;
  }
  let row,error=self_.types.effects.row([],squid_check_effects::Tail.variable{value:next,..});
  if error!=squid_error::Error.none {return false;}
  let known .= copier.row_variables.get(old);
  if known {
   if self_.types.effects.node(known).tail!=self_.types.effects.node(row).tail {return false;}
   continue;
  }
  for prior,j in after[..i] {if prior==next && before[j]!=old {return false;}}
  copier.row_variables.insert(old,row);
 }
 return true;
}

fn sameRetainedType(self_:Engine&,copier:squid_check_check_scheme_import::Copier&,old:u32,next:u32)->bool {
 if old==0 || next==0 {return old==next;}
 let copied,error=copier.copy(old,0);
 if error!=squid_error::Error.none {return false;}
 let a,error=self_.types.resolve(copied,0);
 if error!=squid_error::Error.none {return false;}
 let b,error=self_.types.resolve(next,0);
 if error!=squid_error::Error.none {return false;}
 let equal,error=self_.types.equalSymbolic(a,b);
 return error==squid_error::Error.none && equal;
}

// Function arrows introduced by the named lambda are source arrows. Any
// nested function or raw record is ambiguous in the presence of effects.
fn retainedPrincipalExact(core:const squid_check_core::Module&,binding:u32)->bool {
 if binding>=core.bindings.len {return false;}
 let value=core.bindings[binding];
 if value.body_id==0 {return false;}
 let arity=core.bodies[value.body_id].parameters.len;
 if !retainedTypeExact(core,value.scheme.root,arity,0) ||
    !retainedTypeExact(core,value.ty,arity,0) {return false;}
 let range=value.scheme.obligations;
 for goal in core.obligations[range.start..range.start+range.len] {
  if goal.kind==squid_check_types::ObligationKind.callee_use ||
     !retainedTypeExact(core,goal.ty,0,0) || !retainedTypeExact(core,goal.result,0,0) ||
     !retainedTypeExact(core,goal.other,0,0) || !retainedTypeExact(core,goal.signature,0,0) {return false;}
 }
 return true;
}

recursive fn retainedTypeExact(core:const squid_check_core::Module&,ty:u32,arrows:u32,depth:i64)->bool {
 if depth>=64 {return false;}
 let node=core.types.node(ty);
 match node.tag {
  function=>{
   if arrows==0 || core.types.rowLabels(node.c).len!=0 {return false;}
   return retainedTypeExact(core,node.a,0,depth+1) && retainedTypeExact(core,node.b,arrows-1,depth+1);
  },
  nominal,projection,instance_selection=>{
   for arg in core.types.nominalArguments(node) {if !retainedTypeExact(core,arg,0,depth+1) {return false;}}
  },
  product=>{
   for item in core.types.list(squid_check_types::List{node.a,node.b,..}) {
    if !retainedTypeExact(core,item,0,depth+1) {return false;}
   }
  },
  usage=>{return retainedTypeExact(core,node.a,arrows,depth+1) && retainedTypeExact(core,node.c,0,depth+1);},
  array,list,cursor,resolver=>{return retainedTypeExact(core,node.a,0,depth+1);},
  record,provider,state_provider,scoped,forall,existential,rigid,instance_version=>{return false;},
  _=>{},
 }
 return arrows==0;
}
