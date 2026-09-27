import Base
import ./model.bend as M
import ./types.bend as T
import ./index.bend as Index
import ./nat_index.bend as NatIndex
import ./core_compare.bend as CoreCompare

# The source occurrence is deliberately outside Predicate. It locates a use
# and its diagnostic without changing semantic scheme or evidence equality.
type UsePlan is Data:
  UsePlan{site: Nat, subject: String, instantiated_type: M.Ty, predicates: List<&2, M.Predicate>}

# A selected arrow retains its complete curried type. In particular every
# latent row survives partial application; no aggregate invocation row can
# replace this signature.
type Evidence is Data:
  SelectedFunction{name: String, signature: M.Ty}
  SelectedField{owner: M.TypeId, member: String, accessor: String, signature: M.Ty}
  SelectedOperation{identity: M.TypeId, signature: M.Ty}
  RepresentedType{represented: M.Ty}
  RepresentedEffect{row: M.EffectRow}

type EvidenceAnswer is Data:
  EvidenceAnswer{predicate: M.Predicate, evidence: Evidence}

def predicate_types(predicate: M.Predicate) -> List<&2, M.Ty>:
  match predicate:
    case M.AssociatedPredicate{member, templates, left, right, result, invocation}:
      [left, right, result]
    case M.ReceiverPredicate{member, templates, receiver, argument, result, invocation}:
      [receiver, argument, result]
    case M.FieldPredicate{member, receiver, result}:
      [receiver, result]
    case M.UpdatePredicate{member, receiver, assigned, result, invocation}:
      [receiver, assigned, result]
    case M.OperationPredicate{template, arguments, function_type}:
      function_type <> arguments
    case M.TypeRepPredicate{represented}:
      [represented]
    case M.EffectRepPredicate{row}:
      Nil{}

def predicate_rows(predicate: M.Predicate) -> List<&2, M.EffectRow>:
  match predicate:
    case M.AssociatedPredicate{member, templates, left, right, result, invocation}:
      [invocation]
    case M.ReceiverPredicate{member, templates, receiver, argument, result, invocation}:
      [invocation]
    case M.UpdatePredicate{member, receiver, assigned, result, invocation}:
      [invocation]
    case M.EffectRepPredicate{row}:
      [row]
    case _:
      Nil{}

def rows_free(rows: List<&2, M.EffectRow>) -> List<&2, Nat>:
  match rows:
    case Nil{}:
      Nil{}
    case row <> tail:
      T.union(T.row_free(row), rows_free(tail))

def unresolved_rows(rows: List<&2, M.EffectRow>) -> Bool:
  match rows:
    case Nil{}:
      False{}
    case M.EffectRow{operations, M.FreeRow{scope, name}} <> tail:
      True{}
    case head <> tail:
      unresolved_rows(tail)

def require_resolved_source(names: List<&2, M.Ty>, open_row: Bool) -> Result<&2, &2, M.Diagnostic, Unit>:
  match names open_row:
    case Nil{} False{}:
      Done{Unit{}}
    case _ _:
      Fail{M.Diagnostic{"unresolved_annotation", "constraint", "source type or row name reached a semantic predicate before annotation freshening"}}

def free(+predicate: M.Predicate) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
    source_names : List<&2, M.Ty> <- T.annotation_names(65536n, T.ManyTypes{predicate_types(predicate)})
    source : Unit <- require_resolved_source(source_names, unresolved_rows(predicate_rows(predicate)))
    types : List<&2, Nat> <- T.free(M.ProductTy{predicate_types(predicate)})
    return T.union(types, rows_free(predicate_rows(predicate)))

# Evaluate `free` head-first so the earliest invalid predicate keeps its
# diagnostic. Fold the collected groups from the right to retain the former
# right-associated T.union ordering of variable IDs.
def free_list_groups(predicates: List<&2, M.Predicate>, reversed: List<&2, List<&2, Nat>>) -> Result<&2, &2, M.Diagnostic, List<&2, List<&2, Nat>>>:
  match predicates:
    case Nil{}:
      Done{reversed}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, List<&2, Nat>>>:
        own : List<&2, Nat> <- free(head)
        free_list_groups(tail, own <> reversed)

def free_list_union_indexed(reversed: List<&2, List<&2, Nat>>, accumulated: T.VariableUnion) -> T.VariableUnion:
  match reversed:
    case Nil{}:
      accumulated
    case own <> tail:
      free_list_union_indexed(tail, T.union_into(own, accumulated))

# One accumulator spans the entire right fold. It scans small lists and builds
# a membership index once on promotion. Its retained list follows T.union,
# including duplicate IDs already in it.
def free_list_union(reversed: List<&2, List<&2, Nat>>, accumulated: List<&2, Nat>) -> List<&2, Nat>:
  match reversed:
    case Nil{}:
      accumulated
    case own <> tail:
      T.union_values(free_list_union_indexed(own <> tail, T.union_seed(accumulated)))

def free_list(predicates: List<&2, M.Predicate>) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
    groups : List<&2, List<&2, Nat>> <- free_list_groups(predicates, Nil{})
    return free_list_union(groups, Nil{})

type Transform is Data:
  Resolve{substitutions: T.Substitutions}
  Rename{mapping: NatIndex.Index<Nat>, kind: T.VariableKind}
  FreshParameters{mapping: NatIndex.Index<Nat>}
  RelocateFree{suffix: String}
  ReplaceSource{scope: String, name: String, variable: Nat}
  ReplaceVariable{index: Nat, variable: Nat}
  ReplaceParameter{index: Nat, value: M.Ty}

def transform_type(ty: M.Ty, transform: Transform) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match transform:
    case Resolve{substitutions}:
      T.resolve(substitutions, ty)
    case Rename{mapping, kind}:
      do Result<&2, &2, M.Diagnostic, M.Ty>:
        types : List<&2, M.Ty> <- T.rename_work(65536n, T.OneType{ty}, mapping, kind)
        T.first_type(types)
    case FreshParameters{mapping}:
      do Result<&2, &2, M.Diagnostic, M.Ty>:
        types : List<&2, M.Ty> <- T.rewrite(65536n, T.OneType{ty}, T.FreshParameters{mapping})
        T.first_type(types)
    case RelocateFree{suffix}:
      do Result<&2, &2, M.Diagnostic, M.Ty>:
        types : List<&2, M.Ty> <- T.rewrite(65536n, T.OneType{ty}, T.RelocateFree{suffix})
        T.first_type(types)
    case ReplaceSource{scope, name, variable}:
      do Result<&2, &2, M.Diagnostic, M.Ty>:
        types : List<&2, M.Ty> <- T.rewrite(65536n, T.OneType{ty}, T.ReplaceFree{scope, name, M.VariableTy{variable}})
        T.first_type(types)
    case ReplaceVariable{index, variable}:
      T.replace(ty, index, M.VariableTy{variable})
    case ReplaceParameter{index, value}:
      do Result<&2, &2, M.Diagnostic, M.Ty>:
        types : List<&2, M.Ty> <- T.rewrite(65536n, T.OneType{ty}, T.ReplaceParameter{index, value})
        T.first_type(types)

def transform_row(row: M.EffectRow, transform: Transform) -> Result<&2, &2, M.Diagnostic, M.EffectRow>:
  match transform:
    case Resolve{substitutions}:
      Done{T.resolve_row(substitutions, row)}
    case Rename{mapping, kind}:
      Done{T.rename_row_kind(row, mapping, kind)}
    case FreshParameters{mapping}:
      T.rewrite_row(row, T.FreshParameters{mapping})
    case RelocateFree{suffix}:
      T.rewrite_row(row, T.RelocateFree{suffix})
    case ReplaceSource{scope, name, variable}:
      T.rewrite_row(row, T.ReplaceFree{scope, name, M.VariableTy{variable}})
    case ReplaceVariable{index, variable}:
      T.rewrite_row(row, T.ReplaceVariable{index, M.VariableTy{variable}})
    case ReplaceParameter{index, value}:
      T.rewrite_row(row, T.ReplaceParameter{index, value})

def transform_types(types: List<&2, M.Ty>, +transform: Transform) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  match types:
    case Nil{}:
      Done{Nil{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        next : M.Ty <- transform_type(head, transform)
        rest : List<&2, M.Ty> <- transform_types(tail, transform)
        return next <> rest

def transform(predicate: M.Predicate, +change: Transform) -> Result<&2, &2, M.Diagnostic, M.Predicate>:
  match predicate:
    case M.AssociatedPredicate{member, templates, left, right, result, row}:
      do Result<&2, &2, M.Diagnostic, M.Predicate>:
        l : M.Ty <- transform_type(left, change)
        r : M.Ty <- transform_type(right, change)
        out : M.Ty <- transform_type(result, change)
        changed : M.EffectRow <- transform_row(row, change)
        return M.AssociatedPredicate{member, templates, l, r, out, changed}
    case M.ReceiverPredicate{member, templates, receiver, argument, result, row}:
      do Result<&2, &2, M.Diagnostic, M.Predicate>:
        recv : M.Ty <- transform_type(receiver, change)
        arg : M.Ty <- transform_type(argument, change)
        out : M.Ty <- transform_type(result, change)
        changed : M.EffectRow <- transform_row(row, change)
        return M.ReceiverPredicate{member, templates, recv, arg, out, changed}
    case M.FieldPredicate{member, receiver, result}:
      do Result<&2, &2, M.Diagnostic, M.Predicate>:
        recv : M.Ty <- transform_type(receiver, change)
        out : M.Ty <- transform_type(result, change)
        return M.FieldPredicate{member, recv, out}
    case M.UpdatePredicate{member, receiver, assigned, result, row}:
      do Result<&2, &2, M.Diagnostic, M.Predicate>:
        recv : M.Ty <- transform_type(receiver, change)
        value : M.Ty <- transform_type(assigned, change)
        out : M.Ty <- transform_type(result, change)
        changed : M.EffectRow <- transform_row(row, change)
        return M.UpdatePredicate{member, recv, value, out, changed}
    case M.OperationPredicate{template, arguments, function_type}:
      do Result<&2, &2, M.Diagnostic, M.Predicate>:
        args : List<&2, M.Ty> <- transform_types(arguments, change)
        ty : M.Ty <- transform_type(function_type, change)
        return M.OperationPredicate{template, args, ty}
    case M.TypeRepPredicate{represented}:
      do Result<&2, &2, M.Diagnostic, M.Predicate>:
        ty : M.Ty <- transform_type(represented, change)
        return M.TypeRepPredicate{ty}
    case M.EffectRepPredicate{row}:
      do Result<&2, &2, M.Diagnostic, M.Predicate>:
        changed : M.EffectRow <- transform_row(row, change)
        return M.EffectRepPredicate{changed}

# Keep the first failure in source order without building one nested Result
# continuation per predicate. Large imported schemes can have thousands of
# qualified needs after parameters are instantiated.
def transform_list_work(predicates: List<&2, M.Predicate>, +change: Transform, reversed: List<&2, M.Predicate>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
  match predicates:
    case Nil{}:
      Done{List.reverse(&2, M.Predicate, reversed)}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
        first : M.Predicate <- transform(head, change)
        transform_list_work(tail, change, first <> reversed)

def transform_list(predicates: List<&2, M.Predicate>, change: Transform) -> Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
  transform_list_work(predicates, change, Nil{})

def resolve(substitutions: T.Substitutions, predicate: M.Predicate) -> Result<&2, &2, M.Diagnostic, M.Predicate>:
  transform(predicate, Resolve{substitutions})

def resolve_list(substitutions: T.Substitutions, predicates: List<&2, M.Predicate>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
  transform_list(predicates, Resolve{substitutions})

def resolve_use(plan: UsePlan, +substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, UsePlan>:
  UsePlan{site, subject, ty, predicates} = plan
  do Result<&2, &2, M.Diagnostic, UsePlan>:
    resolved : M.Ty <- T.resolve(substitutions, ty)
    needs : List<&2, M.Predicate> <- resolve_list(substitutions, predicates)
    return UsePlan{site, subject, resolved, needs}

def resolve_uses(plans: List<&2, UsePlan>, +substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, UsePlan>>:
  match plans:
    case Nil{}:
      Done{Nil{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, UsePlan>>:
        plan : UsePlan <- resolve_use(head, substitutions)
        rest : List<&2, UsePlan> <- resolve_uses(tail, substitutions)
        return plan <> rest

def rename(mapping: NatIndex.Index<Nat>, predicate: M.Predicate) -> Result<&2, &2, M.Diagnostic, M.Predicate>:
  transform(predicate, Rename{mapping, T.FreshVariables{}})

def rename_list(mapping: NatIndex.Index<Nat>, predicates: List<&2, M.Predicate>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
  transform_list(predicates, Rename{mapping, T.FreshVariables{}})

def parameterize(mapping: NatIndex.Index<Nat>, predicate: M.Predicate) -> Result<&2, &2, M.Diagnostic, M.Predicate>:
  transform(predicate, Rename{mapping, T.SchemeParameters{}})

def parameterize_list(mapping: NatIndex.Index<Nat>, predicates: List<&2, M.Predicate>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
  transform_list(predicates, Rename{mapping, T.SchemeParameters{}})

def relocate_free(predicates: List<&2, M.Predicate>, suffix: String) -> Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
  transform_list(predicates, RelocateFree{suffix})

def replace_source(predicates: List<&2, M.Predicate>, scope: String, name: String, variable: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
  transform_list(predicates, ReplaceSource{scope, name, variable})

def replace_variable(predicates: List<&2, M.Predicate>, index: Nat, variable: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
  transform_list(predicates, ReplaceVariable{index, variable})

def instantiate_parameters_sequential(arguments: List<&2, M.Ty>, predicates: List<&2, M.Predicate>, +index: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
  match arguments:
    case Nil{}:
      Done{predicates}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
        changed : List<&2, M.Predicate> <- transform_list(predicates, ReplaceParameter{index, head})
        instantiate_parameters_sequential(tail, changed, 1n+index)

# Freshly allocated variables contain no ParameterTy or RowParameter. Replacing
# every source parameter in one traversal therefore has the same result as the
# left-to-right loop, including repeated uses and ordered effect-row labels.
# Other arguments retain that loop because a later parameter replacement may
# need to traverse an earlier inserted argument.
def fresh_parameter_mapping(arguments: List<&2, M.Ty>, +index: Nat, mapping: NatIndex.Index<Nat>) -> Maybe<&2, NatIndex.Index<Nat>>:
  match arguments:
    case Nil{}:
      Some{mapping}
    case M.VariableTy{variable} <> tail:
      fresh_parameter_mapping(tail, 1n+index, NatIndex.set(Nat, mapping, index, variable))
    case other <> tail:
      None{}

def instantiate_parameters_selected(found: Maybe<&2, NatIndex.Index<Nat>>, arguments: List<&2, M.Ty>, predicates: List<&2, M.Predicate>, index: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
  match found:
    case Some{mapping}:
      transform_list(predicates, FreshParameters{mapping})
    case None{}:
      instantiate_parameters_sequential(arguments, predicates, index)

def instantiate_parameters(+arguments: List<&2, M.Ty>, predicates: List<&2, M.Predicate>, +index: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
  match arguments:
    case Nil{}:
      Done{predicates}
    case +head <> +tail:
      instantiate_parameters_selected(fresh_parameter_mapping(head <> tail, index, NatIndex.new(Nat)), head <> tail, predicates, index)

def row_annotation_names(rows: List<&2, M.EffectRow>) -> List<&2, M.Ty>:
  match rows:
    case Nil{}:
      Nil{}
    case head <> tail:
      List.append(&2, M.Ty, T.annotation_row_names(head), row_annotation_names(tail))

def annotation_names(predicates: List<&2, M.Predicate>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  match predicates:
    case Nil{}:
      Done{Nil{}}
    case +head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        types : List<&2, M.Ty> <- T.annotation_names(65536n, T.ManyTypes{predicate_types(head)})
        rest : List<&2, M.Ty> <- annotation_names(tail)
        return List.append(&2, M.Ty, types, List.append(&2, M.Ty, row_annotation_names(predicate_rows(head)), rest))

def predicate_members(predicates: List<&2, M.Predicate>) -> List<&2, String>:
  match predicates:
    case Nil{}:
      Nil{}
    case M.AssociatedPredicate{member, templates, left, right, result, row} <> tail:
      member <> predicate_members(tail)
    case M.ReceiverPredicate{member, templates, receiver, argument, result, row} <> tail:
      member <> predicate_members(tail)
    case M.FieldPredicate{member, receiver, result} <> tail:
      member <> predicate_members(tail)
    case M.UpdatePredicate{member, receiver, assigned, result, row} <> tail:
      member <> predicate_members(tail)
    case head <> tail:
      predicate_members(tail)

def predicate_templates(predicates: List<&2, M.Predicate>) -> List<&2, M.TypeId>:
  match predicates:
    case Nil{}:
      Nil{}
    case M.AssociatedPredicate{member, templates, left, right, result, row} <> tail:
      List.append(&2, M.TypeId, templates, predicate_templates(tail))
    case M.ReceiverPredicate{member, templates, receiver, argument, result, row} <> tail:
      List.append(&2, M.TypeId, templates, predicate_templates(tail))
    case M.OperationPredicate{template, arguments, function_type} <> tail:
      template <> predicate_templates(tail)
    case head <> tail:
      predicate_templates(tail)

def same_predicate(left: M.Predicate, right: M.Predicate) -> Bool:
  CoreCompare.same_predicate(left, right)

def same_type_ids(left: List<&2, M.TypeId>, right: List<&2, M.TypeId>) -> Bool:
  match left right:
    case Nil{} Nil{}:
      True{}
    case a <> left_tail b <> right_tail:
      Bool.and(M.type_id_equal(a, b), same_type_ids(left_tail, right_tail))
    case _ _:
      False{}

def same_head(left: M.Predicate, right: M.Predicate) -> Bool:
  match left right:
    case M.AssociatedPredicate{lm, lt, a, b, c, lr} M.AssociatedPredicate{rm, rt, d, e, f, rr}:
      Bool.and(M.name_equal(lm, rm), same_type_ids(lt, rt))
    case M.ReceiverPredicate{lm, lt, a, b, c, lr} M.ReceiverPredicate{rm, rt, d, e, f, rr}:
      Bool.and(M.name_equal(lm, rm), same_type_ids(lt, rt))
    case M.ReceiverPredicate{lm, Nil{}, a, M.UnitTy{}, c, lr} M.FieldPredicate{rm, d, e}:
      M.name_equal(lm, rm)
    case M.FieldPredicate{lm, a, b} M.FieldPredicate{rm, c, d}:
      M.name_equal(lm, rm)
    case M.UpdatePredicate{lm, a, b, c, lr} M.UpdatePredicate{rm, d, e, f, rr}:
      M.name_equal(lm, rm)
    case M.OperationPredicate{lt, a, b} M.OperationPredicate{rt, c, d}:
      M.type_id_equal(lt, rt)
    case M.TypeRepPredicate{a} M.TypeRepPredicate{b}:
      True{}
    case M.EffectRepPredicate{a} M.EffectRepPredicate{b}:
      True{}
    case _ _:
      False{}

def row_shapes(rows: List<&2, M.EffectRow>) -> List<&2, M.Ty>:
  match rows:
    case Nil{}:
      Nil{}
    case row <> tail:
      M.FunctionTy{M.UnitTy{}, M.UnitTy{}, row} <> row_shapes(tail)

def shape_parts(parts: List<&2, M.Ty>) -> M.Ty:
  match parts:
    case Nil{}:
      M.UnitTy{}
    case single <> Nil{}:
      single
    case multiple:
      M.ProductTy{multiple}

def shape_type(+predicate: M.Predicate) -> M.Ty:
  shape_parts(List.append(&2, M.Ty, predicate_types(predicate), row_shapes(predicate_rows(predicate))))

type EntailShapes is Data:
  EntailShapes{required: M.Ty, declared: M.Ty}

def entail_shapes(required: M.Predicate, declared: M.Predicate) -> EntailShapes:
  match required declared:
    case M.ReceiverPredicate{member, Nil{}, receiver, M.UnitTy{}, result, row} M.FieldPredicate{field, owner, value}:
      EntailShapes{M.ProductTy{[receiver, result]}, M.ProductTy{[owner, value]}}
    case left right:
      EntailShapes{shape_type(left), shape_type(right)}

def contains_work(predicates: List<&2, M.Predicate>, matched: Bool, +wanted: M.Predicate) -> Bool:
  match predicates matched:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case head <> tail False{}:
      contains_work(tail, same_predicate(head, wanted), wanted)

def contains(predicates: List<&2, M.Predicate>, wanted: M.Predicate) -> Bool:
  contains_work(predicates, False{}, wanted)

def contains_head_work(predicates: List<&2, M.Predicate>, matched: Bool, +wanted: M.Predicate) -> Bool:
  match predicates matched:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case head <> tail False{}:
      contains_head_work(tail, same_head(wanted, head), wanted)

def contains_head(predicates: List<&2, M.Predicate>, wanted: M.Predicate) -> Bool:
  contains_head_work(predicates, False{}, wanted)

# Bucket keys are bounded, deliberately coarse structural prefixes. They never
# establish equality: the original budgeted predicate comparison still makes
# every membership decision, including collisions and exhausted comparisons.
def row_tail_bucket(row: M.EffectRow) -> String:
  match row:
    case M.EffectRow{labels, M.ClosedRow{}}:
      "c"
    case M.EffectRow{labels, M.RowVariable{index}}:
      "v" ++ Nat.show(index)
    case M.EffectRow{labels, M.RowParameter{index}}:
      "p" ++ Nat.show(index)
    case M.EffectRow{labels, M.FreeRow{scope, name}}:
      "f"

def type_bucket(depth: Nat, ty: M.Ty) -> String:
  match depth ty:
    case 0n _:
      "_"
    case 1n+rest M.UnitTy{}:
      "u"
    case 1n+rest M.U32Ty{}:
      "i"
    case 1n+rest M.F32Ty{}:
      "d"
    case 1n+rest M.BoolTy{}:
      "b"
    case 1n+rest M.NeverTy{}:
      "n"
    case 1n+rest M.VariableTy{index}:
      "v" ++ Nat.show(index)
    case 1n+rest M.ParameterTy{index}:
      "p" ++ Nat.show(index)
    case 1n+rest M.FreeTy{scope, name}:
      "f"
    case 1n+ +rest M.FunctionTy{parameter, result, effects}:
      "F" ++ type_bucket(rest, parameter) ++ ":" ++ type_bucket(rest, result) ++ ":" ++ row_tail_bucket(effects)
    case 1n+rest M.ProductTy{Nil{}}:
      "P0"
    case 1n+rest M.ProductTy{head <> tail}:
      "P" ++ type_bucket(rest, head)
    case 1n+rest M.AppliedTy{identity, Nil{}}:
      "A0"
    case 1n+rest M.AppliedTy{identity, head <> tail}:
      "A" ++ type_bucket(rest, head)
    case 1n+rest M.ArrayTy{element}:
      "R" ++ type_bucket(rest, element)
    case 1n+rest M.ProviderTy{identity, effects}:
      "V" ++ row_tail_bucket(effects)
    case 1n+rest M.StateProviderTy{read, write, state}:
      "S" ++ type_bucket(rest, state)
    case 1n+rest M.EffectDescriptorTy{}:
      "D"
    case 1n+rest M.EffectSetTy{}:
      "E"

def predicate_bucket(predicate: M.Predicate) -> String:
  match predicate:
    case M.AssociatedPredicate{member, templates, left, right, result, invocation}:
      "A" ++ member ++ "|" ++ type_bucket(3n, left) ++ "|" ++ type_bucket(3n, right) ++ "|" ++ type_bucket(3n, result) ++ "|" ++ row_tail_bucket(invocation)
    case M.ReceiverPredicate{member, templates, receiver, argument, result, invocation}:
      "R" ++ member ++ "|" ++ type_bucket(3n, receiver) ++ "|" ++ type_bucket(3n, argument) ++ "|" ++ type_bucket(3n, result) ++ "|" ++ row_tail_bucket(invocation)
    case M.FieldPredicate{member, receiver, result}:
      "F" ++ member ++ "|" ++ type_bucket(3n, receiver) ++ "|" ++ type_bucket(3n, result)
    case M.UpdatePredicate{member, receiver, assigned, result, invocation}:
      "U" ++ member ++ "|" ++ type_bucket(3n, receiver) ++ "|" ++ type_bucket(3n, assigned) ++ "|" ++ type_bucket(3n, result) ++ "|" ++ row_tail_bucket(invocation)
    case M.OperationPredicate{M.TypeId{module_name, declaration}, arguments, function_type}:
      "O" ++ module_name ++ "|" ++ declaration ++ "|" ++ type_bucket(3n, function_type)
    case M.TypeRepPredicate{represented}:
      "T" ++ type_bucket(3n, represented)
    case M.EffectRepPredicate{row}:
      "E" ++ row_tail_bucket(row)

def bucket_values(found: Maybe<&2, List<&2, M.Predicate>>) -> List<&2, M.Predicate>:
  match found:
    case None{}:
      Nil{}
    case Some{values}:
      values

def bucket_seed(seen: List<&2, M.Predicate>, +buckets: Map<&2, List<&2, M.Predicate>>) -> Map<&2, List<&2, M.Predicate>>:
  match seen:
    case Nil{}:
      buckets
    case +head <> tail:
      +key = predicate_bucket(head)
      +values = bucket_values(Index.find(List<&2, M.Predicate>, buckets, key))
      bucket_seed(tail, Map.set(&2, List<&2, M.Predicate>, buckets, key, head <> values))

type CanonicalBuckets is Data:
  CanonicalBuckets{seen: List<&2, M.Predicate>, buckets: Map<&2, List<&2, M.Predicate>>}

def canonical_next(present: Bool, +head: M.Predicate, seen: List<&2, M.Predicate>, buckets: Map<&2, List<&2, M.Predicate>>, key: String, values: List<&2, M.Predicate>) -> CanonicalBuckets:
  match present:
    case True{}:
      CanonicalBuckets{seen, buckets}
    case False{}:
      CanonicalBuckets{head <> seen, Map.set(&2, List<&2, M.Predicate>, buckets, key, head <> values)}

def canonical_indexed(pending: List<&2, M.Predicate>, state: CanonicalBuckets) -> List<&2, M.Predicate>:
  match pending state:
    case Nil{} CanonicalBuckets{seen, buckets}:
      List.reverse(&2, M.Predicate, seen)
    case +head <> tail CanonicalBuckets{seen, +buckets}:
      +key = predicate_bucket(head)
      +values = bucket_values(Index.find(List<&2, M.Predicate>, buckets, key))
      +next = canonical_next(contains(values, head), head, seen, buckets, key, values)
      canonical_indexed(tail, next)

def canonical_predicates(pending: List<&2, M.Predicate>, +seen: List<&2, M.Predicate>) -> List<&2, M.Predicate>:
  canonical_indexed(pending, CanonicalBuckets{seen, bucket_seed(seen, Map.new(&2, List<&2, M.Predicate>))})

def remove_one_work(predicates: List<&2, M.Predicate>, matched: Bool, reversed: List<&2, M.Predicate>, +wanted: M.Predicate) -> List<&2, M.Predicate>:
  match predicates matched reversed:
    case remaining True{} removed <> prefix:
      List.reverse.go(&2, M.Predicate, prefix, remaining)
    case remaining True{} Nil{}:
      remaining
    case Nil{} False{} kept:
      List.reverse(&2, M.Predicate, kept)
    case +head <> tail False{} kept:
      remove_one_work(tail, same_predicate(head, wanted), head <> kept, wanted)

def remove_one(predicates: List<&2, M.Predicate>, wanted: M.Predicate) -> List<&2, M.Predicate>:
  remove_one_work(predicates, False{}, Nil{}, wanted)

def remove_all(consumed: List<&2, M.Predicate>, predicates: List<&2, M.Predicate>) -> List<&2, M.Predicate>:
  match consumed:
    case Nil{}:
      predicates
    case head <> tail:
      remove_all(tail, remove_one(predicates, head))

def unplanned(plans: List<&2, UsePlan>, predicates: List<&2, M.Predicate>) -> List<&2, M.Predicate>:
  match plans:
    case Nil{}:
      predicates
    case UsePlan{site, subject, ty, owned} <> tail:
      unplanned(tail, remove_all(owned, predicates))

def owned(predicate: M.Predicate, quantified: List<&2, Nat>, environment_free: List<&2, Nat>) -> Result<&2, &2, M.Diagnostic, Bool>:
  do Result<&2, &2, M.Diagnostic, Bool>:
    vars : List<&2, Nat> <- free(predicate)
    return List.is_empty(&2, Nat, T.difference(vars, T.union(quantified, environment_free)))
