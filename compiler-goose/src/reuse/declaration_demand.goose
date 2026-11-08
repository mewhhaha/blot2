// Optional source reachability owns AST identities, never checked schemes.
namespace blot_reuse_declaration_demand;
import std;
import dictionary;
import parse.ast;
import reuse.project;
import reuse.global_references;
import support.error;
import support.option;
type Error=blot_error::Error;
type Project=blot_reuse_project::Project;
type UnitId=u32;
type Id=blot_parse_ast::Id;
struct Stats {total:i64=0,reached:i64=0,fallback_units:i64=0,transitions:i64=0}
struct Unit {declarations:const Id[:]=default<const Id[:]>(),total:i64=0}
struct Plan {units:const Unit[:]=default<const Unit[:]>(),stats:Stats=Stats {..}}
reusable[] var plan_units:Unit[>..]=[];
reusable[] var plan_roots:Id[>..]=[];
fn releaseRoots(values:const Id[:]) {if values.len==0 {return;}plan_roots.free_slice(values);}
fn deinit(self_:Plan&) {for unit in self_.units {releaseRoots(unit.declarations);}if self_.units.len!=0 {plan_units.free_slice(self_.units);}self_=Plan {..};}
fn wants(self_:const Plan&,unit:UnitId,declaration:Id)->bool {
 if unit==0||unit>self_.units.len {return true;}let roots=self_.units[unit-1].declarations;var low:i64=0;var high=roots.len;
 while low<high {let middle=low+(high-low)/2;if roots[middle]<declaration {low=middle+1;}else {high=middle;}}return low<roots.len&&roots[low]==declaration;
}
struct Key {unit:UnitId,name:u32}
fn hash(key:Key)->u64 {return (key.unit as u64)<<32|key.name as u64;}
struct Name {value:u32=0,namespace_:UnitId=0,public:bool=false,ambiguous:bool=false}
struct Declaration {unit:UnitId,node:Id,owner:Id,seed:bool}
struct Builder {source:const Project&,declarations:Declaration[>..<]&,names:dictionary<Key,Name>&,exports:dictionary<Key,Name>&,selected:bool[>..<]&,fallback:bool[>..<]&,work:u32[>..<]&,current:UnitId=0,stats:Stats=Stats {..}}
fn put(self_:Builder&,key:Key,name:Name)->Error {
 let old=self_.names.get(key);if old {if old.value==0&&old.namespace_==0&&name.value==0&&name.namespace_==0 {return blot_error::Error.none;}old.ambiguous=true;}else {self_.names.insert(key,name);}return blot_error::Error.none;
}
fn dotted(text:const u8[:])->i64 {for byte,index in text {if byte=='.' {return index;}}return -1;}
fn value(self_:Builder&,unit:UnitId,root:Id,method:Id)->Error {
 let tree .= self_.source.unit(unit).tree;let declaration=tree.value_decl(root);let associated=dotted(self_.source.symbols.get(declaration.name))>=0;var owner=root;if method!=0 {owner=method;}
 self_.declarations.push(Declaration {unit,root,owner,method!=0||associated||declaration.exported, ..});
 if method==0 {{ let propagated_error = self_.put(Key {unit,declaration.name, ..},Name {value:self_.declarations.len as u32,public:self_.source.symbols.get(declaration.modifier)!="private"&&!blot_parse_ast::declaration_traits(tree,root).private, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }}return blot_error::Error.none;
}
fn collect(self_:Builder&)->Error {
 for &unit,index in self_.source.units.items {
  let id=(index+1) as UnitId;
  for root in unit.tree.roots.items {
   let node=unit.tree.node(root);
   match node.tag {
    blot_parse_ast::tag_value_decl=>{{ let propagated_error = self_.value(id,root,0); if propagated_error != blot_error::Error.none { return propagated_error; } }},
    blot_parse_ast::tag_implementation_decl=>{{ let propagated_error = self_.put(Key {id,node.a, ..},Name {public:!blot_parse_ast::declaration_traits(unit.tree,root).private, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }for member in unit.tree.list(unit.tree.implementation(root).members) {if unit.tree.node(member).tag==blot_parse_ast::tag_value_decl {{ let propagated_error = self_.value(id,member,root); if propagated_error != blot_error::Error.none { return propagated_error; } }}}},
    blot_parse_ast::tag_data_decl=>{let traits=blot_parse_ast::declaration_traits(unit.tree,root);{ let propagated_error = self_.put(Key {id,node.a, ..},Name {public:!traits.private, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }for constructor in unit.tree.children(node.b) {{ let propagated_error = self_.put(Key {id,unit.tree.node(constructor).a, ..},Name {public:!traits.private&&!traits.is_opaque, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }}},
    blot_parse_ast::tag_type_alias_decl,blot_parse_ast::tag_contract_decl,blot_parse_ast::tag_effect_decl,blot_parse_ast::tag_effect_type_decl=>{{ let propagated_error = self_.put(Key {id,node.a, ..},Name {public:!blot_parse_ast::declaration_traits(unit.tree,root).private, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }},
    _=>{},
   }
  }
 }
 return blot_error::Error.none;
}
recursive fn exported(self_:Builder&,unit:UnitId,name:u32,depth:i64)->blot_support::Option<Name> {
 if unit==0||unit>self_.source.units.len||depth>=64 {return blot_support::none<Name>();}let key=Key {unit,name, ..};
 {let found=self_.exports.get(key);if found {return blot_support::some(copy(found));}}
 {let found=self_.names.get(key);if found {if found.public {return blot_support::some(copy(found));}}}
 let tree .= self_.source.unit(unit).tree;
 for imported in self_.source.unitImports(unit) {
  if tree.node(imported.declaration.node).tag!=blot_parse_ast::tag_export_decl {continue;}if imported.namespace_!=0 {return blot_support::none<Name>();}
  for binding in tree.list(imported.bindings) {let alias=tree.import_binding(binding);if alias.alias==name {return self_.exported(imported.target,alias.name,depth+1);}}
 }
 return blot_support::none<Name>();
}
fn importNames(self_:Builder&)->Error {
 for &unit,index in self_.source.units.items {
  let id=(index+1) as UnitId;
  for imported in self_.source.unitImports(id) {
   if imported.declaration.node==0 {{ let propagated_error = self_.whole(id); if propagated_error != blot_error::Error.none { return propagated_error; } }continue;}
   let forwarding=unit.tree.node(imported.declaration.node).tag==blot_parse_ast::tag_export_decl;
   if imported.namespace_!=0 {{ let propagated_error = self_.put(Key {id,imported.namespace_, ..},Name {namespace_:imported.target, ..}); if propagated_error != blot_error::Error.none { return propagated_error; } }if forwarding {{ let propagated_error = self_.whole(id); if propagated_error != blot_error::Error.none { return propagated_error; } }}continue;}
   let binding_count=unit.tree.list(imported.bindings).len;for binding_ordinal in 0..binding_count {let binding=unit.tree.list(imported.bindings)[binding_ordinal];
    let alias=unit.tree.import_binding(binding);let found=self_.exported(imported.target,alias.name,0);var target=Name {..};
    if found.present {target=found.value;}else {{ let propagated_error = self_.whole(imported.target); if propagated_error != blot_error::Error.none { return propagated_error; } }}target.public=forwarding;{ let propagated_error = self_.put(Key {id,alias.alias, ..},target); if propagated_error != blot_error::Error.none { return propagated_error; } }
    if forwarding {let old=self_.exports.get(Key {id,alias.alias, ..});if old {old.ambiguous=true;}else {self_.exports.insert(Key {id,alias.alias, ..},target);}}
   }
  }
 }
 return blot_error::Error.none;
}
fn reach(self_:Builder&,value:u32)->Error {if self_.selected[value-1] {return blot_error::Error.none;}self_.selected[value-1]=true;self_.work.push(value);return blot_error::Error.none;}
recursive fn whole(self_:Builder&,unit:UnitId)->Error {
 if unit==0||unit>self_.fallback.len||self_.fallback[unit-1] {return blot_error::Error.none;}self_.fallback[unit-1]=true;self_.stats.fallback_units++;
 for declaration,index in self_.declarations {if declaration.unit==unit {{ let propagated_error = self_.reach((index+1) as u32); if propagated_error != blot_error::Error.none { return propagated_error; } }}}
 for imported in self_.source.unitImports(unit) {{ let propagated_error = self_.whole(imported.target); if propagated_error != blot_error::Error.none { return propagated_error; } }}if self_.source.unit(unit).implicit_prelude {{ let propagated_error = self_.whole(self_.source.prelude_unit); if propagated_error != blot_error::Error.none { return propagated_error; } }}return blot_error::Error.none;
}
fn exportedPath(self_:Builder&,unit:UnitId,spelling:const u8[:])->blot_support::Option<Name> {
 {let name,exists=self_.source.symbols.lookup(spelling);if exists {let found=self_.exported(unit,name,0);if found.present {return found;}}}
 for character,index in spelling {if character!='.' {continue;}let prefix,exists=self_.source.symbols.lookup(spelling[..index]);if exists {let found=self_.exported(unit,prefix,0);if found.present {return found;}}}return blot_support::none<Name>();
}
fn visible(self_:Builder&,unit:UnitId,name:u32)->blot_support::Option<Name> {
 {let found=self_.names.get(Key {unit,name, ..});if found {return blot_support::some(copy(found));}}
 let spelling=self_.source.symbols.get(name);let dot=dotted(spelling);
 if dot>=0 {
  let head,exists=self_.source.symbols.lookup(spelling[..dot]);if exists {
   let base=self_.names.get(Key {unit,head, ..});if base {let value=copy(base);if value.namespace_==0 {return blot_support::some(value);}return self_.exportedPath(value.namespace_,spelling[dot+1..]);}
  }
 }
 if self_.source.unit(unit).implicit_prelude {let found=self_.exported(self_.source.prelude_unit,name,0);if found.present {return found;}}
 let builtins:const u8[:][19]=["U32","F32","Bool","Unit","Never","Array","List","Cursor","GrowArray","ResizeArray","Ref","View","Link","Demand","Computation","EffectSet","EffectDescriptor","Code","Descriptor"];
 for builtin in builtins {if spelling==builtin {return blot_support::some(Name {..});}}return blot_support::none<Name>();
}
fn contains(values:const u32[:],name:u32)->bool {for value in values {if value==name {return true;}}return false;}
fn shadowed(self_:const Builder&,locals:const u32[:],name:u32)->bool {
 if contains(locals,name) {return true;}let spelling=self_.source.symbols.get(name);let dot=dotted(spelling);if dot>=0 {let head,exists=self_.source.symbols.lookup(spelling[..dot]);if exists {return contains(locals,head);}}return false;
}
recursive fn operator(self_:Builder&,unit:UnitId,name:u32)->blot_support::Option<blot_parse_ast::Fixity> {
 for root in self_.source.unit(unit).tree.roots.items {if self_.source.unit(unit).tree.node(root).tag==blot_parse_ast::tag_fixity_decl {let fixity=self_.source.unit(unit).tree.fixity(root);if fixity.operator==name {return blot_support::some(fixity);}}}
 if self_.source.unit(unit).implicit_prelude {return self_.operator(self_.source.prelude_unit,name);}return blot_support::none<blot_parse_ast::Fixity>();
}
recursive fn operatorUnit(self_:Builder&,unit:UnitId,name:u32)->blot_support::Option<UnitId> {
 for root in self_.source.unit(unit).tree.roots.items {if self_.source.unit(unit).tree.node(root).tag==blot_parse_ast::tag_fixity_decl&&self_.source.unit(unit).tree.fixity(root).operator==name {return blot_support::some(unit);}}
 if self_.source.unit(unit).implicit_prelude {return self_.operatorUnit(self_.source.prelude_unit,name);}return blot_support::none<UnitId>();
}
fn resolved(value:u32)->blot_support::Option<u32>,Error {return blot_support::some(value),blot_error::Error.none;}
fn unresolved()->blot_support::Option<u32>,Error {return blot_support::none<u32>(),blot_error::Error.none;}
fn resolve(self_:Builder&,kind:blot_reuse_global_references::Kind,name:u32,member:u32,locals:const u32[:])->blot_support::Option<u32>,Error {
 var found=blot_support::none<Name>();
 match kind {
  name=>{if self_.shadowed(locals,name) {return unresolved();}found=self_.visible(self_.current,name);},
  qualified=>{
   if self_.shadowed(locals,name) {return unresolved();}let base=self_.visible(self_.current,name);if !base.present {return unresolved();}
   if base.value.namespace_!=0 {found=self_.exportedPath(base.value.namespace_,self_.source.symbols.get(member));if !found.present {let error=self_.whole(base.value.namespace_);if error!=blot_error::Error.none {return blot_support::none<u32>(),error;}}}
   else if base.value.value==0&&!base.value.ambiguous {return resolved(0);}else {return unresolved();}
  },
  operator=>{
   let spelling=self_.source.symbols.get(name);if spelling=="and"||spelling=="or" {return resolved(0);}let fixity=self_.operator(self_.current,name);
   if fixity.present {
    if fixity.value.named&&self_.shadowed(locals,fixity.value.target) {return unresolved();}
    if fixity.value.named {found=self_.visible(self_.current,fixity.value.target);}else {let owner=self_.operatorUnit(self_.current,name);if owner.present {found=self_.visible(owner.value,fixity.value.target);}}
   }else {
    var symbolic=spelling.len==0;if spelling.len!=0 {let byte=spelling[0];symbolic=!((byte>='A'&&byte<='Z')||(byte>='a'&&byte<='z')||byte=='_');}
    if symbolic {let error=self_.whole(self_.current);if error!=blot_error::Error.none {return blot_support::none<u32>(),error;}return resolved(0);}if self_.shadowed(locals,name) {return unresolved();}found=self_.visible(self_.current,name);
   }
  },
 }
 if !found.present||found.value.ambiguous {let error=self_.whole(self_.current);if error!=blot_error::Error.none {return blot_support::none<u32>(),error;}return resolved(0);}
 if found.value.namespace_!=0 {let error=self_.whole(found.value.namespace_);if error!=blot_error::Error.none {return blot_support::none<u32>(),error;}return resolved(0);}return resolved(found.value.value);
}
fn prepare(loaded:const Project&)->blot_support::Option<Plan>,Error {
 if loaded.compiled_modules.len!=0||loaded.diagnostics.len!=0 {return blot_support::none<Plan>(),blot_error::Error.none;}
 var declarations:Declaration[>..<]=[];var names:dictionary<Key,Name> =dictionary<Key,Name> {};var exports:dictionary<Key,Name> =dictionary<Key,Name> {};var selected:bool[>..<]=[];var fallback:bool[>..<]=[];var work:u32[>..<]=[];
 var builder=Builder {loaded,declarations,names,exports,selected,fallback,work, ..};let error=prepareBuilder(builder);if error!=blot_error::Error.none {return blot_support::none<Plan>(),error;}
 let units=plan_units.alloc_slice(loaded.units.len);for &unit in units {unit=Unit {..};}
 for declaration in declarations {units[declaration.unit-1].total++;}
 for &unit,index in units {
  var count:i64=0;for declaration,ordinal in declarations {if declaration.unit==index+1&&selected[ordinal] {count++;}}
  let roots=plan_roots.alloc_slice(count);var at:i64=0;for declaration,ordinal in declarations {if declaration.unit==index+1&&selected[ordinal] {roots[at]=declaration.node;at++;}}
  // Integer ordering is total; tie order cannot affect the membership manifest.
  sort(roots);unit.declarations=roots;
 }
 builder.stats.total=declarations.len;builder.stats.reached=work.len;return blot_support::some(Plan {units,builder.stats, ..}),blot_error::Error.none;
}
fn prepareBuilder(builder:Builder&)->Error {
 { let propagated_error = builder.collect(); if propagated_error != blot_error::Error.none { return propagated_error; } }builder.selected.resize(builder.declarations.len,false);builder.fallback.resize(builder.source.units.len,false);{ let propagated_error = builder.importNames(); if propagated_error != blot_error::Error.none { return propagated_error; } }
 for declaration,index in builder.declarations {if declaration.seed {{ let propagated_error = builder.reach((index+1) as u32); if propagated_error != blot_error::Error.none { return propagated_error; } }}}
 for &unit,index in builder.source.units.items {
  let id=(index+1) as UnitId;
  for root in unit.tree.roots.items {
   if unit.tree.node(root).tag!=blot_parse_ast::tag_fixity_decl {continue;}let target=unit.tree.fixity(root).target;let found=builder.visible(id,target);
   if found.present {if found.value.ambiguous||found.value.value==0 {{ let propagated_error = builder.whole(id); if propagated_error != blot_error::Error.none { return propagated_error; } }}else {{ let propagated_error = builder.reach(found.value.value); if propagated_error != blot_error::Error.none { return propagated_error; } }}}else {{ let propagated_error = builder.whole(id); if propagated_error != blot_error::Error.none { return propagated_error; } }}
  }
 }
 var next:i64=0;
 while next<builder.work.len {
  let declaration=builder.declarations[builder.work[next]-1];next++;let tree .= builder.source.unit(declaration.unit).tree;
  let span,present=blot_parse_ast::declaration_nodes(tree,declaration.owner);
  if present {for node in tree.nodes.items[span.start..span.start+span.len] {if node.tag==blot_parse_ast::tag_package_pack||node.tag==blot_parse_ast::tag_package_unpack {{ let propagated_error = builder.whole(declaration.unit); if propagated_error != blot_error::Error.none { return propagated_error; } }break;}}}else {{ let propagated_error = builder.whole(declaration.unit); if propagated_error != blot_error::Error.none { return propagated_error; } }}
  builder.current=declaration.unit;let self_name,self_exists=builder.source.symbols.lookup("self");var self_symbol:u32=0;if self_exists {self_symbol=self_name;}
  let found,error=blot_reuse_global_references::discover(tree,declaration.node,builder,self_symbol,builder.stats.transitions,4000000);
  if error==blot_error::Error.type_limit {{ let propagated_error = builder.whole(declaration.unit); if propagated_error != blot_error::Error.none { return propagated_error; } }continue;}if error!=blot_error::Error.none {return error;}
  var failure=blot_error::Error.none;for reference in found {if reference.binding!=0 {failure=builder.reach(reference.binding);if failure!=blot_error::Error.none {break;}}}blot_reuse_global_references::release(found);if failure!=blot_error::Error.none {return failure;}
 }
 return blot_error::Error.none;
}
