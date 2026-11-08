// Only entry syntax is parsed; admitted dependency interfaces stay immutable.
namespace blot_reuse_dependency_project_consumer;
import std;
import dictionary;
import parse.lexer;
import parse.token;
import parse.parser;
import parse.symbols;
import parse.ast;
import parse.syntax_diagnostics;
import check.check;
import check.types;
import check.core;
import check.core_builder;
import check.frozen_types;
import check.numeric_proof_headers;
import reuse.project;
import reuse.project_check;
import reuse.frozen_dependency;
import reuse.principal_interface;
import reuse.dependency_consumer;
import reuse.dependency_payload;
import reuse.purity_diagnostics;
import reuse.hole_diagnostics;
import reuse.dispatch_explanation;
import backend.core_backend;
import backend.runtime_identity;
import support.path;
import support.error;
import support.option;
type Error=blot_error::Error;
type Core=blot_check_core::Module;
type Frozen=blot_reuse_frozen_dependency::FrozenDependency;
type Module=blot_reuse_frozen_dependency::Module;
type Target=blot_reuse_principal_interface::ExternalTarget;
type Owner=blot_reuse_dependency_payload::Owner;
type OwnedCore=blot_reuse_dependency_payload::Owned<Core>;
type Result=blot_reuse_dependency_consumer::Result;
type Stats=blot_reuse_dependency_consumer::Stats;
type Diagnostic=blot_reuse_dependency_consumer::Diagnostic;
type Workspace=blot_backend_core_backend::CompileWorkspace;
type Options=blot_reuse_project::Options;
type Pool=blot_parse_symbols::Pool;
type Tree=blot_parse_ast::Tree;
type Span=blot_parse_ast::Span;
type Binding=blot_check_check::ImportedBinding;
type Catalog=blot_check_check::ImportedCatalog;
type Fixity=blot_check_check::ImportedFixity;
type Origin=blot_check_check::ModuleOrigin;
struct ResolvedImport {node:u32,owner:u32}
enum Lowered {inactive,ready{ir:OwnedCore,stats:Stats},rejected{value:Result}}
fn deinit(self_:Lowered&) {match self_ {inactive=>{},ready payload=>{payload.ir.deinit();},rejected payload=>{payload.value.deinit();}}self_=Lowered.inactive;}
fn rejected(unit:u32,stage:const u8[:],code:const u8[:],span:Span,message:const u8[:])->Lowered,Error {let issue,error=blot_reuse_dependency_consumer::init(unit,stage,code,span,message);if error!=blot_error::Error.none {return Lowered.inactive,error;}return Lowered.rejected{Result{diagnostic:blot_support::some(issue),..}},blot_error::Error.none;}
fn publishedRejected<T>(unit:u32,stage:const u8[:],source:const u8[:],publication:blot_parse_syntax_diagnostics::Publication,details:T)->Lowered,Error {let issue,error=blot_reuse_dependency_consumer::publishedDiagnostic(unit,stage,source,publication,details);if error!=blot_error::Error.none {return Lowered.inactive,error;}return Lowered.rejected{Result{diagnostic:blot_support::some(issue),..}},blot_error::Error.none;}
fn projectRejected(unit:u32,code:blot_reuse_project_check::Code,span:Span)->Lowered,Error {let issue=blot_reuse_project_check::Diagnostic{ unit:unit, span:span, code:code, .. };return rejected(unit,"project-check",issue.codeName(),span,issue.message());}
fn loadRejected(unit:u32,code:blot_reuse_project::Code,span:Span)->Lowered,Error {let issue=blot_reuse_project::Diagnostic{ unit:unit, span:span, code:code, .. };return rejected(unit,"load",issue.codeName(),span,issue.message());}
fn target(bundle:const Frozen&,owner:u32,raw:Target)->Target,Error {var unit=raw.unit;if unit==0 {unit=owner;}if unit==0 || unit>bundle.modules.len || raw.binding==0 || raw.binding>=bundle.modules[unit-1].interface.bindings.len {return Target{0,0},blot_error::Error.invalid_artifact;}return Target{unit,raw.binding},blot_error::Error.none;}
fn importedValue(bundle:const Frozen&,owner:u32,raw:Target,origin:u32)->Binding,Error {
    let resolved,error=target(bundle,owner,raw);if error!=blot_error::Error.none {return default<Binding>(),error;}let producer:const blot_reuse_principal_interface::Interface& =bundle.modules[resolved.unit-1].interface;let definition=producer.bindings[resolved.binding];
    let __field_order_607_producer_binding: blot_check_check::BindingId = resolved.binding; let __field_order_608_proof_contract: const blot_check_numeric_proof_headers::Owned? .= blot_check_numeric_proof_headers::find(producer.proof_contracts,resolved.binding); let __field_order_609_types: blot_check_frozen_types::Source = blot_check_frozen_types::Source.frozen{producer.graph}; let __field_order_610_scheme: blot_check_types::Scheme = definition.scheme; let __field_order_611_obligations: const blot_check_types::Obligation[:] = producer.obligations; let __field_order_612_capability_flow: blot_check_check::CapabilityFlow = definition.capability_flow; let __field_order_613_capability_parameters: blot_check_capability_flow::Parameters = definition.capability_parameters; let __field_order_614_named_function: bool = definition.named_function; let __field_order_615_callees: blot_check_check::Callees = blot_check_check::Callees.frozen{producer}; return Binding{ target:resolved, interface:blot_check_check::SchemeInterface{ producer_binding: __field_order_607_producer_binding, proof_contract: __field_order_608_proof_contract, capability_flow: __field_order_612_capability_flow, capability_parameters: __field_order_613_capability_parameters, named_function: __field_order_614_named_function, types: __field_order_609_types, scheme: __field_order_610_scheme, obligations: __field_order_611_obligations, callees: __field_order_615_callees, .. }, origin:origin, .. },blot_error::Error.none;
}
fn importExport(bundle:const Frozen&,imports:Binding[>..<]&,catalogs:Catalog[>..<]&,owner:u32,exported:blot_reuse_frozen_dependency::Export,name:u32,namespace_id:u32,origin:u32)->Error {
    if exported.kind==blot_reuse_frozen_dependency::ExportKind.value {var value,error=importedValue(bundle,owner,exported.target,origin);if error!=blot_error::Error.none {return error;}value.name=name;value.namespace_=namespace_id;value.member=0;if namespace_id!=0 {value.name=0;value.member=name;}imports.push(value);}
    else {var producer=owner;if exported.target.unit!=0 {producer=exported.target.unit;}if producer==0 || producer>bundle.modules.len {return blot_error::Error.invalid_artifact;}let __alias_field_56_frozen: const blot_reuse_principal_interface::Interface? .= bundle.modules[producer-1].interface; let __alias_field_57_name: blot_parse_symbols::Symbol = name; let __alias_field_58_namespace_: blot_parse_symbols::Symbol = namespace_id; let __alias_field_59_origin: blot_parse_ast::Id = origin; let __alias_field_60_index: u32 = exported.catalog; let __alias_field_61_kind: blot_check_check::ImportedCatalog_kind = blot_reuse_dependency_consumer::exportKind(exported.kind); catalogs.push(Catalog{ frozen: __alias_field_56_frozen, namespace_: __alias_field_58_namespace_, name: __alias_field_57_name, kind: __alias_field_61_kind, index: __alias_field_60_index, origin: __alias_field_59_origin, .. });}return blot_error::Error.none;
}
fn exactClosure(bundle:const Frozen&,roots:const ResolvedImport[:],prelude:u32)->Error {var seen:bool[>..<]=[];seen.resize(bundle.modules.len,false);var stack:u32[>..<]=[];if prelude!=0 {stack.push(prelude);}for root in roots {stack.push(root.owner);}while stack.len!=0 {let unit=stack[stack.len-1];stack.resize(stack.len-1);if unit==0 || unit>bundle.modules.len {return blot_error::Error.invalid_artifact;}if seen[unit-1] {continue;}seen[unit-1]=true;stack.append(bundle.modules[unit-1].imports);}for reached in seen {if !reached {return blot_error::Error.dependency_set_changed;}}return blot_error::Error.none;}

// The checker may retain the descriptors during recursive inference. Their
// backing headers and origin text belong to reusable global typed runs.
reusable[] var binding_runs:Binding[>..]=[];
reusable[] var catalog_runs:Catalog[>..]=[];
reusable[] var fixity_runs:Fixity[>..]=[];
reusable[] var origin_runs:Origin[>..]=[];
struct Inputs {imports:Binding[:]=default<Binding[:]>(),catalogs:Catalog[:]=default<Catalog[:]>(),fixities:Fixity[:]=default<Fixity[:]>(),origins:Origin[:]=default<Origin[:]>(),owner:Owner=Owner{..}}
fn deinit(self_:Inputs&) {if self_.imports.len!=0 {binding_runs.free_slice(self_.imports);}if self_.catalogs.len!=0 {catalog_runs.free_slice(self_.catalogs);}if self_.fixities.len!=0 {fixity_runs.free_slice(self_.fixities);}if self_.origins.len!=0 {origin_runs.free_slice(self_.origins);}self_.owner.deinit();self_=Inputs{..};}
fn origins(self_:Inputs&)->blot_check_check::ModuleOrigins {return blot_check_check::ModuleOrigins{entries:self_.origins,has_lookup:true,..};}
fn prepareInputs(self_:Inputs&,bundle:const Frozen&,entry_identity:const u8[:],entry:u32,prelude:u32,imports:const Binding[:],catalogs:const Catalog[:],fixities:const Fixity[:])->Error {
    let owner,error=blot_reuse_dependency_payload::init();if error!=blot_error::Error.none {return error;}self_.owner=owner;self_.imports=binding_runs.alloc_slice(imports.len);for item,index in imports {self_.imports[index]=item;}self_.catalogs=catalog_runs.alloc_slice(catalogs.len);for item,index in catalogs {self_.catalogs[index]=item;}self_.fixities=fixity_runs.alloc_slice(fixities.len);for item,index in fixities {self_.fixities[index]=item;}
    let directory=blot_support_path::dirname(entry_identity);if !directory.present {return blot_error::Error.type_limit;}self_.origins=origin_runs.alloc_slice(bundle.modules.len+1);for &item in self_.origins {item=Origin{unit:0,name:default<const u8[:]>(),..};}
    for &item,index in self_.origins {let unit=(index+1) as u32;var path=entry_identity;if unit!=entry {path=bundle.modules[index].identity.normalized_path;}var relative:u8[>..<]=[];if unit==prelude && unit!=0 {relative.append("std/prelude");}else {let error=blot_support_path::relative(directory.value,path,relative);if error!=blot_error::Error.none {return error;}}let name,error=self_.owner.copy(relative[..]);if error!=blot_error::Error.none {return error;}item=Origin{unit:unit,name:name,source_available:unit==entry,..};}return blot_error::Error.none;
}
fn lowerEntry<P>(provider:P&,entry_identity:const u8[:],source:const u8[:],options:Options,pool:Pool&,bundle:const Frozen&)->Lowered,Error {
    if options.input_mode!=blot_reuse_project::InputMode.project {return Lowered.inactive,blot_error::Error.input_mode_unsupported;}if bundle.modules.len>=0xffffffff {return Lowered.inactive,blot_error::Error.invalid_artifact;}let entry=(bundle.modules.len+1) as u32;var prelude:u32=0;
    for module,index in bundle.modules {let unit=(index+1) as u32;if module.core.unit!=unit || module.interface.unit!=unit {return Lowered.inactive,blot_error::Error.invalid_artifact;}if module.identity.normalized_path==entry_identity {return Lowered.inactive,blot_error::Error.dependency_set_changed;}if module.identity.prelude {if prelude!=0 {return Lowered.inactive,blot_error::Error.invalid_artifact;}prelude=unit;}}
    var inherited:blot_parse_parser::InheritedFixity[>..<]=[];if prelude!=0 {for f in bundle.modules[prelude-1].fixities {inherited.push(blot_parse_parser::InheritedFixity{f.operator,f.precedence,f.association,f.named});}}
    var tokens:blot_parse_token::Token[>..<]=[];var comments:blot_parse_token::Token[>..<]=[];var issues:blot_parse_lexer::Diagnostic[>..<]=[];var lexed=blot_parse_lexer::init(tokens,comments,issues);let lex_error=blot_parse_lexer::lex(source,lexed);if lex_error!=blot_error::Error.none {return Lowered.inactive,lex_error;}if issues.len!=0 {return publishedRejected(entry,"parse-project",source,blot_parse_syntax_diagnostics::lexical(tokens[..],issues[0]),issues[..]);}
    var tree,error=blot_parse_ast::initPooled();if error!=blot_error::Error.none {return Lowered.inactive,error;}let parsed=blot_parse_parser::parse_with_fixities(source,tokens[..],pool,tree,inherited[..]);if parsed!=blot_error::Error.none {tree.deinit();return Lowered.inactive,parsed;}
    if tree.diagnostics.len!=0 {let publication,error=blot_parse_syntax_diagnostics::parse(tokens[..],tree.diagnostics.items[0]);if error!=blot_error::Error.none {tree.deinit();return Lowered.inactive,error;}let result,failure=publishedRejected(entry,"parse-project",source,publication,tree.diagnostics.items);tree.deinit();return result,failure;}
    let result,failure=lowerParsed(provider,entry_identity,source,options,pool,bundle,tree,entry,prelude);tree.deinit();return result,failure;
}
fn lowerParsed<P>(provider:P&,entry_identity:const u8[:],source:const u8[:],options:Options,pool:Pool&,bundle:const Frozen&,tree:Tree&,entry:u32,prelude:u32)->Lowered,Error {
    var resolved:ResolvedImport[>..<]=[];for id in tree.roots.items {if tree.node(id).tag!=blot_parse_ast::tag_import_decl {continue;}let info=tree.importDecl(id);var path:u8[>..<]=[];let path_error=provider.resolve(entry_identity,pool.get(info.path),options,path);if path_error==blot_error::Error.invalid_path {return loadRejected(entry,blot_reuse_project::Code.import_path,tree.span(id));}if path_error!=blot_error::Error.none {return Lowered.inactive,path_error;}
        var canonical:u8[>..<]=[];let error=provider.canonical(path,canonical);if error==blot_error::Error.file_not_found {return loadRejected(entry,blot_reuse_project::Code.missing_file,tree.span(id));}if error==blot_error::Error.out_of_memory {return Lowered.inactive,error;}if error!=blot_error::Error.none {return loadRejected(entry,blot_reuse_project::Code.io_error,tree.span(id));}var owner:u32=0;for module,index in bundle.modules {if module.identity.normalized_path==canonical {owner=(index+1) as u32;break;}}if owner==0 {return Lowered.inactive,blot_error::Error.dependency_set_changed;}resolved.push(ResolvedImport{id,owner});
    }let closure_error=exactClosure(bundle,resolved[..],prelude);if closure_error!=blot_error::Error.none {return Lowered.inactive,closure_error;}
    var occupied:dictionary<u32,bool> =dictionary<u32,bool>{};for id in tree.roots.items {let node=tree.node(id);if node.tag==blot_parse_ast::tag_value_decl || node.tag==blot_parse_ast::tag_data_decl || node.tag==blot_parse_ast::tag_effect_decl || node.tag==blot_parse_ast::tag_effect_type_decl {occupied.insert(node.a,true);}if node.tag==blot_parse_ast::tag_data_decl {for constructor in tree.children(node.b) {occupied.insert(tree.node(constructor).a,true);}}}
    var imports:Binding[>..<]=[];var catalogs:Catalog[>..<]=[];var fixities:Fixity[>..<]=[];
    for imported in resolved {let info=tree.importDecl(imported.node);let producer:const Module& =bundle.modules[imported.owner-1];if info.namespace_!=0 {if occupied.contains(info.namespace_) {return projectRejected(entry,blot_reuse_project_check::Code.duplicate_name,info.namespace_span);}occupied.insert(info.namespace_,true);}catalogs.push(Catalog{frozen:producer.interface,kind:blot_check_check::ImportedCatalog_kind.catalog,index:0,origin:imported.node,..});
        if info.namespace_!=0 {for exported in producer.exports {let error=importExport(bundle,imports,catalogs,imported.owner,exported,exported.name,info.namespace_,imported.node);if error!=blot_error::Error.none {return Lowered.inactive,error;}}}
        else {for binding in tree.list(info.bindings) {let alias=tree.importBinding(binding);if occupied.contains(alias.alias) {return projectRejected(entry,blot_reuse_project_check::Code.duplicate_name,tree.span(binding));}occupied.insert(alias.alias,true);var found=false;for exported in producer.exports {if exported.name!=alias.name {continue;}found=true;let error=importExport(bundle,imports,catalogs,imported.owner,exported,alias.alias,0,binding);if error!=blot_error::Error.none {return Lowered.inactive,error;}}if !found {return projectRejected(entry,blot_reuse_project_check::Code.unknown_export,tree.span(binding));}}}
    }
    if prelude!=0 {let producer:const Module& =bundle.modules[prelude-1];catalogs.push(Catalog{frozen:producer.interface,kind:blot_check_check::ImportedCatalog_kind.catalog,index:0,origin:0,..});for exported in producer.exports {if occupied.contains(exported.name) {continue;}let error=importExport(bundle,imports,catalogs,prelude,exported,exported.name,0,0);if error!=blot_error::Error.none {return Lowered.inactive,error;}}for f in producer.fixities {let actual,error=target(bundle,prelude,f.producer);if error!=blot_error::Error.none {return Lowered.inactive,error;}if !f.named {var hidden,error=importedValue(bundle,prelude,actual,0);if error!=blot_error::Error.none {return Lowered.inactive,error;}hidden.expose=false;imports.push(hidden);}var external=blot_support::none<Target>();if !f.named {external=blot_support::some(actual);}fixities.push(Fixity{operator:f.operator,target:f.target,named:f.named,external:external,..});}}
    var inputs=Inputs{..};let error=inputs.prepareInputs(bundle,entry_identity,entry,prelude,imports[..],catalogs[..],fixities[..]);if error!=blot_error::Error.none {inputs.deinit();return Lowered.inactive,error;}let result,failure=checkEntry(source,pool,tree,entry,prelude,inputs);inputs.deinit();return result,failure;
}
struct HoleDetails {hole:blot_reuse_hole_diagnostics::Snapshot}
struct ExplanationDetails {explanation:blot_reuse_dispatch_explanation::Explanation,contexts:const blot_check_check::DiagnosticContext[:]}
struct ContextDetails {contexts:const blot_check_check::DiagnosticContext[:]}
fn checkRejected(source:const u8[:],pool:Pool&,entry:u32,origins:blot_check_check::ModuleOrigins,issue:blot_check_check::Diagnostic)->Lowered,Error {
    let code=blot_reuse_dependency_consumer::codeName(issue.code);let contexts=issue.contexts[..issue.context_len];var publication=blot_parse_syntax_diagnostics::Publication{cause:blot_parse_syntax_diagnostics::native_detail,code:code,span:issue.span,message:issue.message(),..};
    if issue.hole.present {return publishedRejected(entry,"check-project",source,publication,HoleDetails{issue.hole.value});}if issue.explanation.present {return publishedRejected(entry,"check-project",source,publication,ExplanationDetails{issue.explanation.value,contexts});}if contexts.len!=0 {return publishedRejected(entry,"check-project",source,publication,ContextDetails{contexts});}
    if issue.purity.present {let witness=issue.purity.value;var label:const u8[:]=default<const u8[:]>();if !witness.operation_name.present && !witness.foreign {let name,error=origins.name(witness.identity.unit,entry);if error!=blot_error::Error.none {return Lowered.inactive,error;}label=name;}var text:u8[>..<]=[];let error=blot_reuse_purity_diagnostics::format(pool,label,witness,text);if error!=blot_error::Error.none {return Lowered.inactive,error;}publication.message=text[..];return publishedRejected(entry,"check-project",source,publication,[witness][..]);}
    if issue.numeric_literal.present {let detail=issue.numeric_literal.value;publication.actual_token=detail.actual_token;return publishedRejected(entry,"check-project",source,publication,[detail][..]);}if issue.symbol==0 {return rejected(entry,"check-project",code,issue.span,issue.message());}var message:u8[>..<]=[];message.append(issue.message());if code=="unknown_intrinsic" || code=="unknown_record_field" {message.append(" ");}else {message.append(": ");}message.append(pool.get(issue.symbol));return rejected(entry,"check-project",code,issue.span,message[..]);
}
fn checkEntry(source:const u8[:],pool:Pool&,tree:Tree&,entry:u32,prelude:u32,inputs:Inputs&)->Lowered,Error {
    var checked,error=blot_check_check::checkModuleWithOptions(tree,pool,inputs.imports,inputs.catalogs,entry,blot_check_check::ModuleOptions{purity_origins:blot_reuse_dependency_project_consumer::origins(inputs),prelude_unit:prelude,inherited_fixities:inputs.fixities,..});if error!=blot_error::Error.none {return Lowered.inactive,error;}
    if checked.diagnostics.len!=0 {let result,failure=checkRejected(source,pool,entry,blot_reuse_dependency_project_consumer::origins(inputs),checked.diagnostics[0]);checked.deinit();return result,failure;}
    var ir,failure=blot_check_core_builder::lowerWithOrigins(tree,pool,checked,blot_reuse_dependency_project_consumer::origins(inputs));if failure!=blot_error::Error.none {checked.deinit();return Lowered.inactive,failure;}ir.value.unit=entry;if ir.value.diagnostics.len!=0 {let issue=ir.value.diagnostics[0];let result,failure=rejected(entry,"lower",blot_reuse_dependency_consumer::coreCodeName(issue.code),issue.span,issue.message());ir.deinit();checked.deinit();return result,failure;}
    let stats=Stats{syntax_nodes:tree.nodes.len-1,body_elaborations:checked.body_elaborations,body_lowerings:ir.value.body_lowerings,imported_schemes:checked.imported_schemes,normalization:checked.types.normalization,..};checked.deinit();return Lowered.ready{ir,stats},blot_error::Error.none;
}
fn emissionIdentity(owner:Owner&,pool:const Pool&,bundle:const Frozen&,entry_identity:const u8[:],entry:u32)->blot_backend_runtime_identity::View,Error {
    var owners:blot_backend_runtime_identity::Owner[>..<]=[];for module in bundle.modules {owners.push(blot_backend_runtime_identity::Owner{module.core.unit,module.identity.normalized_path});}owners.push(blot_backend_runtime_identity::Owner{entry,entry_identity});var metadata,error=blot_backend_runtime_identity::capture(pool,owners[..],owners.len);if error!=blot_error::Error.none {return default<blot_backend_runtime_identity::View>(),error;}
    let bytes,e1=owner.copy(metadata.bytes);if e1!=blot_error::Error.none {metadata.deinit();return default<blot_backend_runtime_identity::View>(),e1;}let symbols,e2=owner.copy(metadata.symbols);if e2!=blot_error::Error.none {metadata.deinit();return default<blot_backend_runtime_identity::View>(),e2;}let paths,e3=owner.copy(metadata.owners);metadata.deinit();if e3!=blot_error::Error.none {return default<blot_backend_runtime_identity::View>(),e3;}return blot_backend_runtime_identity::View{bytes,symbols,paths},blot_error::Error.none;
}
fn emitLowered(workspace:Workspace&,owner:Owner&,bundle:const Frozen&,ir:OwnedCore&,stats:Stats,names:blot_backend_runtime_identity::View)->Result,Error {
    let units,error=blot_reuse_dependency_payload::alloc<Core>(owner,bundle.modules.len+1);if error!=blot_error::Error.none {return Result{..},error;}var prelude:u32=0;for module,index in bundle.modules {var copy,error=blot_reuse_dependency_payload::clone(module.core);if error!=blot_error::Error.none {return Result{..},error;}units[index]=copy.value;let error=owner.adopt(copy.owner);if error!=blot_error::Error.none {copy.deinit();return Result{..},error;}if module.identity.prelude {prelude=module.core.unit;}}
    units[bundle.modules.len]=ir.value;let adopted=owner.adopt(ir.owner);if adopted!=blot_error::Error.none {return Result{..},adopted;}let input_owners,error=blot_reuse_dependency_payload::alloc<Owner>(owner,units.len);if error!=blot_error::Error.none {return Result{..},error;}for &input in input_owners {input=Owner{..};}
    let staged=blot_backend_core_backend::pinWorkspaceInputs(workspace,units,owner,input_owners,[]);if staged!=blot_error::Error.none {return Result{..},staged;}let compiled,error=blot_backend_core_backend::compileWithOptions(workspace,units,ir.value.unit,blot_backend_core_backend::CompileOptions{identity:blot_support::some(names),diagnostic_prelude_unit:prelude,..});if error!=blot_error::Error.none {return Result{..},error;}var result=Result{compiled:compiled,stats:stats,..};let pinned=blot_backend_core_backend::pinResult(result.compiled,owner,input_owners,[]);if pinned!=blot_error::Error.none {result.deinit();return Result{..},pinned;}return result,blot_error::Error.none;
}
fn compile<P>(provider:P&,workspace:Workspace&,entry_identity:const u8[:],source:const u8[:],options:Options,pool:Pool&,bundle:const Frozen&)->Result,Error {return compileMode(provider,workspace,entry_identity,source,options,pool,bundle,null);}
fn compileOwned<P>(provider:P&,workspace:Workspace&,entry_identity:const u8[:],source:const u8[:],options:Options,pool:Pool&,bundle:blot_reuse_dependency_payload::Owned<Frozen>&)->Result,Error {return compileMode(provider,workspace,entry_identity,source,options,pool,bundle.value,bundle);}
fn compileMode<P>(provider:P&,workspace:Workspace&,entry_identity:const u8[:],source:const u8[:],options:Options,pool:Pool&,bundle:const Frozen&,consume:blot_reuse_dependency_payload::Owned<Frozen>?)->Result,Error {
    var lowered,error=lowerEntry(provider,entry_identity,source,options,pool,bundle);if error!=blot_error::Error.none {return Result{..},error;}match lowered {inactive=>{abort("inactive lowered entry");},rejected payload=>{let result=payload.value;lowered=Lowered.inactive;return result,blot_error::Error.none;},ready payload=>{
        var owner,error=blot_reuse_dependency_payload::init();if error!=blot_error::Error.none {lowered.deinit();return Result{..},error;}let names,error=emissionIdentity(owner,pool,bundle,entry_identity,payload.ir.value.unit);if error!=blot_error::Error.none {owner.deinit();lowered.deinit();return Result{..},error;}
        if consume {if !consume.owner.unique() {owner.deinit();lowered.deinit();return Result{..},blot_error::Error.invalid_artifact;}for &module in consume.value.modules {var trash,error=blot_reuse_dependency_payload::init();if error!=blot_error::Error.none {owner.deinit();lowered.deinit();return Result{..},error;}consume.owner.partitionInto(trash,module.interface);trash.deinit();module.interface=default<blot_reuse_principal_interface::Interface>();}}
        let result,failure=emitLowered(workspace,owner,bundle,payload.ir,payload.stats,names);owner.deinit();lowered.deinit();return result,failure;
    }}
}
