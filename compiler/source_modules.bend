import Base
import ./model.bend as M
import ./monomorph.bend as Mono
import ./effect_families.bend as Families
import ./cst.bend as C
import ./lower.bend as Lower
import ./source_types.bend as Types
import ./index.bend as Index
import ./operators.bend as O
import ./inference_batch.bend as B
import ./checked_core.bend as Core

type Linked is Data:
  Linked{module: M.Module, scopes: Map<&2, Lower.Context>}

type Imported is Data:
  Imported{scope: Lower.Context, namespaces: Set()}

def namespace_present(namespaces: Set(), name: String) -> Bool:
  Maybe.is_some(&2, Unit, Index.find(Unit, namespaces, name))

def occupied_alias(global: Maybe<&2, Lower.Global>, header: Maybe<&2, Types.Header>) -> Bool:
  match global header:
    case None{} None{}:
      False{}
    case _ _:
      True{}

def unique_namespace(duplicate: Bool, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Unit>:
  match duplicate:
    case False{}:
      Done{Unit{}}
    case True{}:
      Fail{C.diagnostic(node, "duplicate_name", "an import namespace cannot share its name with another namespace or local binding")}

def import_global(found: Maybe<&2, Lower.Global>, alias: String, scope: Lower.Context, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Lower.Context>:
  match found:
    case None{}:
      Done{scope}
    case Some{Lower.Global{source, core, kind}}:
      Lower.add_global(scope, alias, core, kind, node)

def import_family_members(members: List<&2, M.TypeId>, +source: String, +alias: String, +globals: Map<&2, Lower.Global>, scope: Lower.Context, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, Lower.Context>:
  match members:
    case Nil{}:
      Done{scope}
    case M.TypeId{module_name, +declaration} <> rest:
      do Result<&2, &2, M.Diagnostic, Lower.Context>:
        +member_alias : String = alias ++ String.drop(declaration, String.length(source))
        next : Lower.Context <- import_global(Lower.lookup_global(globals, declaration), member_alias, scope, node)
        import_family_members(rest, source, alias, globals, next, node)

def import_family(found: Maybe<&2, Lower.Global>, +globals: Map<&2, Lower.Global>, +source: String, +alias: String, scope: Lower.Context, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, Lower.Context>:
  match found:
    case Some{Lower.Global{original, core, Lower.EffectFamilyName{members, parameters}}}:
      import_family_members(members, source, alias, globals, scope, node)
    case _:
      Done{scope}

def import_header(found: Maybe<&2, Types.Header>, +alias: String, +scope: Lower.Context, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Lower.Context>:
  match found:
    case None{}:
      Done{scope}
    case Some{Types.Header{source, identity, parameters}}:
      Lower.Context{globals, headers, fixities, locals, label, annotation_variables} = scope
      Lower.add_header(Types.lookup_header(headers, alias), scope, Types.Header{alias, identity, parameters}, node)

def namespace_globals(globals: Map<&2, Lower.Global>, +prefix: String, scope: Lower.Context, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, Lower.Context>:
  match globals:
    case MTip{}:
      Done{scope}
    case MLeaf{key, Lower.Global{source, core, kind}}:
      Lower.add_global(scope, prefix ++ source, core, kind, node)
    case MNode{position, left, right}:
      do Result<&2, &2, M.Diagnostic, Lower.Context>:
        next : Lower.Context <- namespace_globals(left, prefix, scope, node)
        namespace_globals(right, prefix, next, node)

def namespace_headers(headers: Map<&2, Types.Header>, +prefix: String, scope: Lower.Context, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, Lower.Context>:
  match headers:
    case MTip{}:
      Done{scope}
    case MLeaf{key, Types.Header{+source, identity, parameters}}:
      import_header(Some{Types.Header{source, identity, parameters}}, prefix ++ source, scope, node)
    case MNode{position, left, right}:
      do Result<&2, &2, M.Diagnostic, Lower.Context>:
        next : Lower.Context <- namespace_headers(left, prefix, scope, node)
        namespace_headers(right, prefix, next, node)

def import_alias(nodes: List<&2, C.Cst>, fallback: String) -> Result<&2, &2, M.Diagnostic, String>:
  match nodes:
    case Nil{}:
      Done{fallback}
    case marker <> alias <> Nil{}:
      Done{C.text_of(alias)}
    case node <> tail:
      Fail{C.diagnostic(node, "internal_cst", "invalid source import alias")}

def exported_name(global: Maybe<&2, Lower.Global>, header: Maybe<&2, Types.Header>, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Unit>:
  match global header:
    case None{} None{}:
      Fail{C.diagnostic(node, "unknown_export", "imported module does not export this name")}
    case _ _:
      Done{Unit{}}

def named_imports(nodes: List<&2, C.Cst>, +globals: Map<&2, Lower.Global>, +headers: Map<&2, Types.Header>, +namespaces: Set(), scope: Lower.Context) -> Result<&2, &2, M.Diagnostic, Lower.Context>:
  match nodes:
    case Nil{}:
      Done{scope}
    case +node <> tail:
      do Result<&2, &2, M.Diagnostic, Lower.Context>:
        name_node : C.Cst <- C.one(C.field_values(node, "name"))
        +name : String <- Done{C.text_of(name_node)}
        +alias : String <- import_alias(C.field_values(node, "alias"), name)
        +global : Maybe<&2, Lower.Global> <- Done{Lower.lookup_global(globals, name)}
        +header : Maybe<&2, Types.Header> <- Done{Types.lookup_header(headers, name)}
        valid : Unit <- exported_name(global, header, node)
        available : Unit <- unique_namespace(namespace_present(namespaces, alias), node)
        with_global : Lower.Context <- import_global(global, alias, scope, node)
        with_members : Lower.Context <- import_family(global, globals, name, alias, with_global, node)
        next : Lower.Context <- import_header(header, alias, with_members, node)
        named_imports(tail, globals, headers, namespaces, next)

def import_binding(namespace: Bool, +node: C.Cst, exported: Lower.Context, +scope: Lower.Context, +namespaces: Set()) -> Result<&2, &2, M.Diagnostic, Imported>:
  match namespace exported:
    case True{} Lower.Context{globals, headers, fixities, locals, label, annotation_variables}:
      Lower.Context{own_globals, own_headers, own_fixities, own_locals, own_label, own_annotation_variables} = scope
      do Result<&2, &2, M.Diagnostic, Imported>:
        alias : C.Cst <- C.one(C.field_values(node, "name"))
        +name : String <- Done{C.text_of(alias)}
        available : Unit <- unique_namespace(Bool.or(namespace_present(namespaces, name), occupied_alias(Lower.lookup_global(own_globals, name), Types.lookup_header(own_headers, name))), node)
        +prefix : String <- Done{name ++ "."}
        with_globals : Lower.Context <- namespace_globals(globals, prefix, scope, node)
        next : Lower.Context <- namespace_headers(headers, prefix, with_globals, node)
        Done{Imported{next, Set.add(namespaces, name)}}
    case False{} Lower.Context{globals, headers, fixities, locals, label, annotation_variables}:
      do Result<&2, &2, M.Diagnostic, Imported>:
        next : Lower.Context <- named_imports(C.field_values(node, "bindings"), globals, headers, namespaces, scope)
        Done{Imported{next, namespaces}}

def require_module(found: Maybe<&2, Lower.Context>, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Lower.Context>:
  match found:
    case Some{scope}:
      Done{scope}
    case None{}:
      Fail{C.diagnostic(node, "unresolved_import", "source module dependency is missing or out of order")}

def imported_scope_work(nodes: List<&2, C.Cst>, +modules: Map<&2, Lower.Context>, imported: Imported) -> Result<&2, &2, M.Diagnostic, Lower.Context>:
  match nodes:
    case Nil{}:
      Imported{scope, namespaces} = imported
      Done{scope}
    case +node <> tail:
      Imported{scope, namespaces} = imported
      do Result<&2, &2, M.Diagnostic, Lower.Context>:
        exported : Lower.Context <- require_module(Index.find(Lower.Context, modules, C.text_of(node)), node)
        +binding : C.Cst <- C.one(C.field_values(node, "binding"))
        next : Imported <- import_binding(M.name_equal(C.kind_of(binding), "namespace_import"), binding, exported, scope, namespaces)
        imported_scope_work(tail, modules, next)

def imported_scope(nodes: List<&2, C.Cst>, modules: Map<&2, Lower.Context>, scope: Lower.Context) -> Result<&2, &2, M.Diagnostic, Lower.Context>:
  imported_scope_work(nodes, modules, Imported{scope, Set.new()})

# Imported scopes depend on declarations, not lowered bodies. Preserve errors
# as task results so an earlier body failure still precedes a later scope failure.
type ModuleTask is Data:
  ModuleTask{declarations: List<&2, C.Cst>, prefix: String, name: String, entry: Bool, scope: Lower.Context}

type ModulePreparation is Data:
  ModulePreparation{task: ModuleTask, scopes: Map<&2, Lower.Context>}

def prepare_module(+node: C.Cst, +entry: String, prelude_scope: Lower.Context, +scopes: Map<&2, Lower.Context>) -> Result<&2, &2, M.Diagnostic, ModulePreparation>:
  +name = C.text_of(node)
  +is_entry = M.name_equal(name, entry)
  +prefix = Bool.pick(String, is_entry, "", "$module[" ++ name ++ "].")
  do Result<&2, &2, M.Diagnostic, ModulePreparation>:
    +body : C.Cst <- C.one(C.field_values(node, "body"))
    +declarations : List<&2, C.Cst> = C.field_values(body, "declarations")
    +own : Lower.Context <- Lower.collect_names(declarations, prefix, name)
    imported : Lower.Context <- imported_scope(C.field_values(body, "imports"), scopes, own)
    +scope : Lower.Context = Lower.combine_context(imported, prelude_scope)
    fixities : List<&2, O.Fixity> <- Lower.collect_fixities(declarations, scope, False{})
    return ModulePreparation{ModuleTask{declarations, prefix, name, is_entry, Lower.with_fixities(scope, fixities)}, Map.set(&2, Lower.Context, scopes, name, own)}

def module_weight(prepared: Result<&2, &2, M.Diagnostic, ModuleTask>) -> Nat:
  match prepared:
    case Fail{error}:
      1n
    case Done{ModuleTask{declarations, prefix, name, entry, scope}}:
      Lower.declaration_cost(65536n, declarations, 1n)

def prepared_task(prepared: Result<&2, &2, M.Diagnostic, ModulePreparation>) -> Result<&2, &2, M.Diagnostic, ModuleTask>:
  match prepared:
    case Fail{error}:
      Fail{error}
    case Done{ModulePreparation{task, scopes}}:
      Done{task}

def prepared_scopes(prepared: Result<&2, &2, M.Diagnostic, ModulePreparation>) -> Map<&2, Lower.Context>:
  match prepared:
    case Fail{error}:
      Map.new(&2, Lower.Context)
    case Done{ModulePreparation{task, scopes}}:
      scopes

def prepare_modules(nodes: List<&2, C.Cst>, +entry: String, +prelude_scope: Lower.Context, scopes: Map<&2, Lower.Context>) -> List<&2, B.Weighted<Result<&2, &2, M.Diagnostic, ModuleTask>>>:
  match nodes:
    case Nil{}:
      Nil{}
    case node <> tail:
      +prepared = prepare_module(node, entry, prelude_scope, scopes)
      +task = prepared_task(prepared)
      B.Weighted{task, module_weight(task)} <> prepare_modules(tail, entry, prelude_scope, prepared_scopes(prepared))

def lower_module_task(task: ModuleTask, fuel: Nat) -> Result<&2, &2, M.Diagnostic, M.Module>:
  ModuleTask{declarations, prefix, name, entry, scope} = task
  Lower.lower_declarations(declarations, prefix, name, entry, fuel, scope)

def lower_module(prepared: Result<&2, &2, M.Diagnostic, ModuleTask>, fuel: Nat) -> Result<&2, &2, M.Diagnostic, M.Module>:
  do Result<&2, &2, M.Diagnostic, M.Module>:
    task : ModuleTask <- prepared
    lower_module_task(task, fuel)

def collect_modules(modules: List<&2, Result<&2, &2, M.Diagnostic, M.Module>>, previous: M.Module) -> Result<&2, &2, M.Diagnostic, M.Module>:
  match modules:
    case Nil{}:
      Done{previous}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        module : M.Module <- head
        collect_modules(tail, Lower.combine_modules(previous, module))

def link(nodes: List<&2, C.Cst>, entry: String, prelude_scope: Lower.Context, linked: Linked, fuel: Nat) -> Result<&2, &2, M.Diagnostic, M.Module>:
  match nodes linked:
    case Nil{} Linked{previous, scopes}:
      Done{previous}
    case node <> Nil{} Linked{previous, scopes}:
      prepared = prepare_module(node, entry, prelude_scope, scopes)
      do Result<&2, &2, M.Diagnostic, M.Module>:
        module : M.Module <- lower_module(prepared_task(prepared), fuel)
        return Lower.combine_modules(previous, module)
    case nodes Linked{previous, scopes}:
      tasks = prepare_modules(nodes, entry, prelude_scope, scopes)
      outcomes = B.execute(~Result<&2, &2, M.Diagnostic, ModuleTask>, ~Nat, ~Result<&2, &2, M.Diagnostic, M.Module>, ~lower_module, B.plan(Result<&2, &2, M.Diagnostic, ModuleTask>, tasks, 512n), fuel)
      collect_modules(outcomes, previous)

def prepared_project(prepared: Result<&2, &2, M.Diagnostic, Lower.Prelude>, +root: C.Cst, fuel: Nat) -> Result<&2, &2, M.Diagnostic, M.Module>:
  match prepared:
    case Fail{error}:
      Fail{error}
    case Done{Lower.Prelude{module, scope}}:
      link(C.field_values(root, "modules"), C.text_of(root), scope, Linked{module, MTip{}}, fuel)

def source_module(project: Bool, +root: C.Cst, prelude: C.Cst, +fuel: Nat) -> Result<&2, &2, M.Diagnostic, M.Module>:
  match project:
    case False{}:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        +module : M.Module <- Lower.source_module(root, prelude, fuel)
        prepared : M.Module <- Families.prepare(module)
        Mono.prepare(prepared, "main", M.module_operations(module))
    case True{}:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        +module : M.Module <- prepared_project(Lower.prepare_prelude(prelude, fuel), root, fuel)
        prepared : M.Module <- Families.prepare(module)
        Mono.prepare(prepared, C.text_of(root), M.module_operations(module))

# Cold source compilation selects exports from the final checked signatures.
# This avoids a separate all-affected inference pass merely to refresh exports.
def source_module_deferred(project: Bool, +root: C.Cst, prelude: C.Cst, +fuel: Nat) -> Result<&2, &2, M.Diagnostic, M.Module>:
  match project:
    case False{}:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        +module : M.Module <- Lower.source_module(root, prelude, fuel)
        prepared : M.Module <- Families.prepare(module)
        Mono.prepare_deferred(prepared, "main", M.module_operations(module))
    case True{}:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        +module : M.Module <- prepared_project(Lower.prepare_prelude(prelude, fuel), root, fuel)
        prepared : M.Module <- Families.prepare(module)
        Mono.prepare_deferred(prepared, C.text_of(root), M.module_operations(module))

# Retain the solved specialization evidence until the final group check.
def source_module_core(project: Bool, +root: C.Cst, prelude: C.Cst, +fuel: Nat) -> Result<&2, &2, M.Diagnostic, Core.Prepared>:
  match project:
    case False{}:
      do Result<&2, &2, M.Diagnostic, Core.Prepared>:
        +module : M.Module <- Lower.source_module(root, prelude, fuel)
        prepared : M.Module <- Families.prepare(module)
        Mono.prepare_deferred_core(prepared, "main", M.module_operations(module))
    case True{}:
      do Result<&2, &2, M.Diagnostic, Core.Prepared>:
        +module : M.Module <- prepared_project(Lower.prepare_prelude(prelude, fuel), root, fuel)
        prepared : M.Module <- Families.prepare(module)
        Mono.prepare_deferred_core(prepared, C.text_of(root), M.module_operations(module))
