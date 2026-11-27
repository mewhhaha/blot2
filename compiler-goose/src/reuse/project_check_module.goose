// Import catalogs, aliases and source diagnostics preserve dependency order.
namespace squid_reuse_project_check;
import .project_check;
fn require(condition:bool)->Error {if !condition {return squid_error::Error.invalid_artifact;}return squid_error::Error.none;}
fn appendCatalog(self_:Engine&,catalogs:squid_check_check::ImportedCatalog[>..]&,source_catalogs:squid_check_check::SourceCatalog[>..]&,producer:CatalogModule,name:u32,namespace_:u32,kind:squid_check_check::ImportedCatalog_kind,index:u32,origin:u32)->Error {
 match producer.owner {
 typed payload=>{catalogs.push(squid_check_check::ImportedCatalog{ producer:squid_support::Option<squid_check_check::LiveProducer>{true,squid_check_check::liveProducer(payload.value)}, namespace_:namespace_, name:name, kind:kind, index:index, origin:origin, .. });},
 source payload=>{              let __field_order_568_producer: squid_check_check::DeclarationCatalog = squid_check_check::declarationCatalog(payload.value); let __field_order_569_declarations: const squid_check_check::SourceDeclaration[:] = payload.value.declarations; let __field_order_570_name: squid_parse_symbols::Symbol = name; let __field_order_571_namespace_: squid_parse_symbols::Symbol = namespace_; let __field_order_572_kind: squid_check_check::ImportedCatalog_kind = kind; let __field_order_573_index: u32 = index; let __field_order_574_origin: squid_parse_ast::Id = origin; source_catalogs.push(squid_check_check::SourceCatalog{ producer: __field_order_568_producer, declarations: __field_order_569_declarations, namespace_: __field_order_571_namespace_, name: __field_order_570_name, kind: __field_order_572_kind, index: __field_order_573_index, origin: __field_order_574_origin, .. });},
 frozen payload=>{       if self_.source_validation {       let __field_order_575_producer: squid_check_check::DeclarationCatalog = producer.catalog(); let __field_order_576_declarations: const squid_check_check::SourceDeclaration[:] = self_.compiled_catalogs[payload.value.unit-1].declarations; let __field_order_577_name: squid_parse_symbols::Symbol = name; let __field_order_578_namespace_: squid_parse_symbols::Symbol = namespace_; let __field_order_579_kind: squid_check_check::ImportedCatalog_kind = kind; let __field_order_580_index: u32 = index; let __field_order_581_origin: squid_parse_ast::Id = origin; source_catalogs.push(squid_check_check::SourceCatalog{ producer: __field_order_575_producer, declarations: __field_order_576_declarations, namespace_: __field_order_578_namespace_, name: __field_order_577_name, kind: __field_order_579_kind, index: __field_order_580_index, origin: __field_order_581_origin, .. });}else {catalogs.push(squid_check_check::ImportedCatalog{ frozen:squid_support::Option<squid_check_check::FrozenProducer>{true,squid_check_check::frozenProducer(payload.value,producer.summaries)}, namespace_:namespace_, name:name, kind:kind, index:index, origin:origin, .. });}},
 inactive=>{return squid_error::Error.invalid_artifact;},
 }return squid_error::Error.none;
}
fn importExport(self_:Engine&,imports:squid_check_check::ImportedBinding[>..]&,headers:squid_check_check::SourceHeader[>..]&,catalogs:squid_check_check::ImportedCatalog[>..]&,source_catalogs:squid_check_check::SourceCatalog[>..]&,producer:CatalogModule,exported:Export,name:u32,namespace_:u32,origin:u32)->Error {
 if exported.kind==squid_reuse_frozen_dependency::ExportKind.value {var local_name=name;var member:u32=0;if namespace_!=0 {local_name=0;member=name;}if self_.source_validation {var imported=self_.headerImport(exported.target,origin);imported.name=local_name;imported.namespace_=namespace_;imported.member=member;headers.push(imported);}else {let value,error=self_.valueImport(exported.target,origin);if error!=squid_error::Error.none {return error;}var imported=value;imported.name=local_name;imported.namespace_=namespace_;imported.member=member;imports.push(imported);}return squid_error::Error.none;}
 var kind=squid_check_check::ImportedCatalog_kind.nominal;match exported.kind {nominal=>{},constructor=>{kind=squid_check_check::ImportedCatalog_kind.constructor;},effect_family=>{kind=squid_check_check::ImportedCatalog_kind.effect_family;},contract=>{kind=squid_check_check::ImportedCatalog_kind.contract;},implementation=>{kind=squid_check_check::ImportedCatalog_kind.implementation;},value=>{abort("value import uses the binding path");}}
 return self_.appendCatalog(catalogs,source_catalogs,producer,name,namespace_,kind,exported.catalog,origin);
}
fn appendDiagnostics(self_:Engine&,unit:u32,diagnostics:const squid_check_check::Diagnostic[:])->Error {
 for source in diagnostics {var origin=unit;if source.origin_unit!=0 {origin=source.origin_unit;}var item=Diagnostic{unit:origin,span:source.span,code:Code.semantic,semantic:squid_support::some(source.code),type_application:source.type_application,symbol:source.symbol,implicit_type_witness:source.implicit_type_witness,source_terminator:source.source_terminator,numeric_literal:source.numeric_literal,contexts:source.contexts,context_len:source.context_len, ..};
 if source.purity.present {var witness=source.purity.value;if witness.operation_name.present {witness.operation_name=squid_support::some<const u8[:]>(copyOwned(witness.operation_name.value));}item.purity=squid_support::Option<squid_check_check::PurityWitness>{true,witness};}
 if source.detail.present {item.detail=squid_support::some<const u8[:]>(copyOwned(source.detail.value));}
 if source.hole.present {let hole,error=source.hole.value.clone();if error!=squid_error::Error.none {item.deinit();return error;}item.hole=squid_support::Option<squid_reuse_hole_diagnostics::Snapshot>{true,hole};}
 if source.explanation.present {let explanation,error=source.explanation.value.clone();if error!=squid_error::Error.none {item.deinit();return error;}item.explanation=squid_support::Option<squid_reuse_dispatch_explanation::Explanation>{true,explanation};}
 let error=self_.diagnostics.push(item);if error!=squid_error::Error.none {item.deinit();return error;}
 }return squid_error::Error.none;
}
fn moduleExports<D>(self_:Engine&,unit:u32,catalog:squid_check_check::DeclarationCatalog,declarations:const D[:],diagnostics:const squid_check_check::Diagnostic[:],forwarded:const Export[:])->Export[:],Error {
 var exports:Export[>..<]=[];for binding,index in declarations {if binding.kind!=squid_reuse_principal_interface::Kind.global || binding.private {continue;}exports.push(Export{name:binding.name,target:ExternalTarget{unit,index as u32, ..}, ..});}
 for nominal,index in catalog.nominals {if index!=0 && nominal.identity.unit==unit && !nominal.private {exports.push(Export{nominal.name,ExternalTarget{unit,0, ..},squid_reuse_frozen_dependency::ExportKind.nominal,index as u32, ..});}}
 for constructor,index in catalog.constructors {if index!=0 && constructor.identity.unit==unit && !constructor.private {exports.push(Export{constructor.name,ExternalTarget{unit,0, ..},squid_reuse_frozen_dependency::ExportKind.constructor,index as u32, ..});}}
 for family,index in catalog.effect_families {if index!=0 && family.identity.unit==unit && !family.private {exports.push(Export{family.name,ExternalTarget{unit,0, ..},squid_reuse_frozen_dependency::ExportKind.effect_family,index as u32, ..});}}
 for contract,index in catalog.contracts {if contract.identity.unit==unit && !contract.private {exports.push(Export{contract.name,ExternalTarget{unit,0, ..},squid_reuse_frozen_dependency::ExportKind.contract,index as u32, ..});}}
 for implementation,index in catalog.implementations {if implementation.identity.unit==unit && !implementation.private {exports.push(Export{implementation.name,ExternalTarget{unit,0, ..},squid_reuse_frozen_dependency::ExportKind.implementation,index as u32, ..});}}
 exports.append(forwarded);let error=self_.appendDiagnostics(unit,diagnostics);if error!=squid_error::Error.none {return default<Export[:]>(),error;}return copyOwned(exports[..]),squid_error::Error.none;
}
fn checkModule(self_:Engine&,unit:u32)->Error {let source=self_.source.unit(unit);squid_phase_profile::traceModule(unit,self_.source.symbols.get(source.filename),source.source.len);let region=squid_phase_profile::region("check.module",unit,0,source.source.len as u32);let error=checkModuleBody(self_,unit);region.exit();return error;}
fn checkModuleBody(self_:Engine&,unit:u32,options_core:const squid_check_core::Module?=null,skip_root:const bool[:]=default<const bool[:]>(),selective:squid_check_check::Checked?=null)->Error {
 let before=self_.diagnostics.items.len;let source=self_.source.unit(unit);let tree:const squid_parse_ast::Tree& =source.tree;
 var occupied=dictionary<u32,bool>{};var forwarded:Export[>..<]=[];var imports:squid_check_check::ImportedBinding[>..]=[];var headers:squid_check_check::SourceHeader[>..]=[];var catalogs:squid_check_check::ImportedCatalog[>..]=[];var source_catalogs:squid_check_check::SourceCatalog[>..]=[];
 for root in tree.roots.items {let node=tree.node(root);if node.tag==squid_parse_ast::tag_value_decl || node.tag==squid_parse_ast::tag_entry_kernel_decl || node.tag==squid_parse_ast::tag_entry_process_decl || node.tag==squid_parse_ast::tag_data_decl || node.tag==squid_parse_ast::tag_type_alias_decl || node.tag==squid_parse_ast::tag_contract_decl || node.tag==squid_parse_ast::tag_implementation_decl || node.tag==squid_parse_ast::tag_effect_type_decl || node.tag==squid_parse_ast::tag_effect_decl {occupied.insert(node.a,true);}if node.tag==squid_parse_ast::tag_data_decl {let constructor_count=tree.children(node.b).len;for index in 0..constructor_count {let constructor=tree.children(node.b)[index];let name=tree.node(constructor).a;occupied.insert(name,true);}}
 if ((node.tag==squid_parse_ast::tag_value_decl && tree.value_decl(root).exported) || node.tag==squid_parse_ast::tag_entry_kernel_decl || node.tag==squid_parse_ast::tag_entry_process_decl) && unit!=self_.source.entry {{ let propagated_error = self_.diagnostic(unit,tree.span(root),Code.entry_module); if propagated_error != squid_error::Error.none { return propagated_error; } }}}
 for imported in self_.source.unitImports(unit) {
 let info=tree.import_decl(imported.declaration.node);let forwarding=tree.node(imported.declaration.node).tag==squid_parse_ast::tag_export_decl;
 if info.namespace_!=0 {let present=occupied.contains(info.namespace_);if !present {occupied.insert(info.namespace_,true);}if present {{ let propagated_error = self_.diagnostic(unit,info.namespace_span,Code.duplicate_name); if propagated_error != squid_error::Error.none { return propagated_error; } }continue;}}
 let found=self_.catalogModule(imported.target);if !found.present || !found.value.valid {{ let propagated_error = self_.diagnostic(unit,imported.span,Code.dependency_failed); if propagated_error != squid_error::Error.none { return propagated_error; } }continue;}let producer=found.value;
 { let propagated_error = self_.appendCatalog(catalogs,source_catalogs,producer,0,0,squid_check_check::ImportedCatalog_kind.catalog,0,imported.declaration.node); if propagated_error != squid_error::Error.none { return propagated_error; } }
 if info.namespace_!=0 {for exported in producer.exports {var original=producer;if exported.kind!=squid_reuse_frozen_dependency::ExportKind.value && exported.target.unit!=0 && exported.target.unit!=imported.target {let current=self_.catalogModule(exported.target.unit);if !current.present {return squid_error::Error.invalid_artifact;}original=current.value;}{ let propagated_error = self_.importExport(imports,headers,catalogs,source_catalogs,original,exported,exported.name,info.namespace_,imported.declaration.node); if propagated_error != squid_error::Error.none { return propagated_error; } }}}
 else {let binding_count=tree.list(info.bindings).len;
 var export_heads=dictionary<u32,i64>{};var export_next:i64[>..]=[];
 let indexed_exports=!forwarding && binding_count>=4 && producer.exports.len>=16;
 if indexed_exports {
  export_next.resize(producer.exports.len,-1);
  var ei=producer.exports.len;
  while ei>0 {
   ei-=1;
   let ename=producer.exports[ei].name;
   let prev .= export_heads.get(ename);
   if prev {export_next[ei]=prev;}
   export_heads.insert(ename,ei);
  }
 }
 for binding_ordinal in 0..binding_count {let binding=tree.list(info.bindings)[binding_ordinal];let alias=tree.import_binding(binding);let present=occupied.contains(alias.alias);if !present {occupied.insert(alias.alias,true);}if present {{ let propagated_error = self_.diagnostic(unit,tree.span(binding),Code.duplicate_name); if propagated_error != squid_error::Error.none { return propagated_error; } }continue;}var found=false;
 if indexed_exports {
  let head .= export_heads.get(alias.name);
  if head {
   var ei:i64=head;
   while ei>=0 {
    let exported=producer.exports[ei];
    found=true;var original=producer;if exported.kind!=squid_reuse_frozen_dependency::ExportKind.value && exported.target.unit!=0 && exported.target.unit!=imported.target {let current=self_.catalogModule(exported.target.unit);if !current.present {return squid_error::Error.invalid_artifact;}original=current.value;}
    { let propagated_error = self_.importExport(imports,headers,catalogs,source_catalogs,original,exported,alias.alias,0,binding); if propagated_error != squid_error::Error.none { return propagated_error; } }
    ei=export_next[ei];
   }
  }
 } else {
  for exported in producer.exports {if forwarding {if self_.resolution_remaining==0 {{ let propagated_error = self_.diagnostic(unit,tree.span(binding),Code.resolution_budget); if propagated_error != squid_error::Error.none { return propagated_error; } }break;}self_.resolution_remaining-=1;}if exported.name!=alias.name {continue;}found=true;var original=producer;if exported.kind!=squid_reuse_frozen_dependency::ExportKind.value && exported.target.unit!=0 && exported.target.unit!=imported.target {let current=self_.catalogModule(exported.target.unit);if !current.present {return squid_error::Error.invalid_artifact;}original=current.value;}
  { let propagated_error = self_.importExport(imports,headers,catalogs,source_catalogs,original,exported,alias.alias,0,binding); if propagated_error != squid_error::Error.none { return propagated_error; } }if forwarding {var public=exported;public.name=alias.alias;forwarded.push(public);}}
 }
 if !found {{ let propagated_error = self_.diagnostic(unit,tree.span(binding),Code.unknown_export); if propagated_error != squid_error::Error.none { return propagated_error; } }continue;}
 }}
 }
 if source.implicit_prelude {
 let prelude=self_.source.prelude_unit;let found=self_.catalogModule(prelude);if !found.present || !found.value.valid {{ let propagated_error = self_.diagnostic(unit,Span{0,0, ..},Code.dependency_failed); if propagated_error != squid_error::Error.none { return propagated_error; } }}
 else {let producer=found.value;{ let propagated_error = self_.appendCatalog(catalogs,source_catalogs,producer,0,0,squid_check_check::ImportedCatalog_kind.catalog,0,0); if propagated_error != squid_error::Error.none { return propagated_error; } }for exported in producer.exports {if occupied.contains(exported.name) {continue;}{ let propagated_error = self_.importExport(imports,headers,catalogs,source_catalogs,producer,exported,exported.name,0,0); if propagated_error != squid_error::Error.none { return propagated_error; } }}
 }}
 if self_.prepare_names {return squid_check_check::prepareGeneratedNames(self_.source.symbols,tree,catalogs[..]);}
 let context=BodyNameContext{self_, ..};                  let __field_order_582_associated_remaining: i64? .= self_.associated_remaining; let __field_order_583_purity_origins: squid_check_check::ModuleOrigins = moduleOrigins(self_.source); let __field_order_584_builtin_catalog: bool = unit==self_.source.prelude_unit; let __field_order_585_prelude_unit: u32 = self_.source.prelude_unit; let __field_order_589_producer_capabilities: squid_support::Option<squid_check_check::ProducerCapabilities> = squid_support::Option<squid_check_check::ProducerCapabilities>{true,squid_check_check::ProducerCapabilities{context:context,interface:true, ..}}; let __field_order_590_producer_storage: squid_support::Option<squid_check_check::ProducerStorage> = squid_support::Option<squid_check_check::ProducerStorage>{true,squid_check_check::ProducerStorage{context:context, ..}}; var options=squid_check_check::ModuleOptions{ purity_origins: __field_order_583_purity_origins, builtin_catalog: __field_order_584_builtin_catalog, is_std: unit==self_.source.prelude_unit || source.is_std, prelude_unit: __field_order_585_prelude_unit, associated_remaining: __field_order_582_associated_remaining, producer_capabilities: __field_order_589_producer_capabilities, producer_storage: __field_order_590_producer_storage, .. };
 match self_.editor {none=>{},query payload=>{options.max_inference_transitions=squid_support::some(payload.value.budget.remaining);if payload.value.unit==unit {options.editor=squid_support::some(payload.value.marker);}}}
 if self_.source_validation {
 let value,error=squid_check_check::validateModuleSource(tree,self_.source.symbols,headers[..],source_catalogs[..],unit,options);{ let propagated_error = error; if propagated_error != squid_error::Error.none { return propagated_error; } }var validation=value;
 if squid_check_check::hasNumericFailure(tree) && validation.diagnostics.len==0 {validation.deinit();return squid_error::Error.numeric_validation_incomplete;}
 let exports,error=self_.moduleExports(unit,squid_check_check::declarationCatalog(validation),validation.declarations,validation.diagnostics,forwarded[..]);if error!=squid_error::Error.none {validation.deinit();return error;}self_.source_modules[unit-1]=squid_support::Option<SourceModule>{true,SourceModule{validation,exports,self_.diagnostics.items.len==before, ..}};return squid_error::Error.none;
 }
 options.retained_core .= options_core;
 options.skip_root=skip_root;
 let value,error=squid_check_check::checkModuleWithPrivateExecution(tree,self_.source.symbols,imports[..],catalogs[..],unit,options,self_.execution);{ let propagated_error = error; if propagated_error != squid_error::Error.none { return propagated_error; } }var checked=value;
 let output .= selective;
 if output {
  if checked.diagnostics.len!=0 || checked.initializer_rejected {checked.deinit();return squid_error::Error.invalid_artifact;}
  output=checked;
  return squid_error::Error.none;
 }
 accountEditorBudget(self_.editor,checked.counters.inference_steps as i64,checked.initializer_rejected,checked.diagnostics);
 if checked.initializer_rejected {let error=self_.appendDiagnostics(unit,checked.diagnostics);checked.deinit();return error;}
 let exports,error=self_.moduleExports(unit,squid_check_check::declarationCatalog(checked),checked.bindings,checked.diagnostics,forwarded[..]);if error!=squid_error::Error.none {checked.deinit();return error;}
 publishModule(self_.result,unit,Module{checked,exports,self_.diagnostics.items.len==before, ..});self_.result.body_elaborations+=checked.body_elaborations;self_.result.imported_schemes+=checked.imported_schemes;self_.result.normalization.merge(checked.types.normalization);return squid_error::Error.none;
}

// The invocation borrows the caller's shared budget; no writeback or owned prefix is needed.
fn accountEditorBudget(editor:Editor,steps:i64,initializer_rejected:bool,diagnostics:const squid_check_check::Diagnostic[:]) {
 match editor {query payload=>{let budget .= payload.value.budget;let ignored=budget.spend(steps);if initializer_rejected {budget.exhausted=true;}for issue in diagnostics {if issue.code==squid_check_check::Code.inference_budget {budget.remaining=0;budget.exhausted=true;}}},none=>{}}
}
