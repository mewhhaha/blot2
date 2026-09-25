import Base
import ./model.bend as M
import ./infer.bend as I
import ./index.bend as Index
import ./effect_rows.bend as Rows

type Selection is Data:
  Candidates{}
  Resolved{}

type ConstantSelection is Data:
  ConstantSelection{constants: List<&2, M.Constant>, wrappers: List<&2, M.Function>}

def export_name(+name: String) -> String:
  Bool.pick(String, String.starts_with(name, "$public:"), String.drop(name, 8n), name)

def scalar(ty: M.Ty) -> Bool:
  match ty:
    case M.UnitTy{}:
      True{}
    case M.U32Ty{}:
      True{}
    case M.F32Ty{}:
      True{}
    case M.BoolTy{}:
      True{}
    case _:
      False{}

def value(ty: M.Ty) -> Bool:
  match ty:
    case M.ArrayTy{M.U32Ty{}}:
      True{}
    case M.ArrayTy{M.F32Ty{}}:
      True{}
    case other:
      scalar(other)

def callback_row(row: M.EffectRow) -> Bool:
  match row:
    case M.EffectRow{identity <> Nil{}, M.ClosedRow{}}:
      M.is_foreign(identity)
    case _:
      False{}

# Associated calls can constrain an input or result only during specialization.
# Do not discard those entry points before dispatch resolves their signatures.
def result(ty: M.Ty, selection: Selection) -> Bool:
  match ty selection:
    case M.VariableTy{index} Candidates{}:
      True{}
    case M.ParameterTy{index} Candidates{}:
      True{}
    case M.ArrayTy{M.VariableTy{index}} Candidates{}:
      True{}
    case M.ArrayTy{M.ParameterTy{index}} Candidates{}:
      True{}
    case other _:
      value(other)

def parameter(ty: M.Ty, selection: Selection) -> Bool:
  match ty selection:
    case M.FunctionTy{input, output, row} Resolved{}:
      Bool.and(callback_row(row), Bool.and(value(input), value(output)))
    case M.FunctionTy{input, output, row} Candidates{}:
      Bool.and(result(input, Candidates{}), result(output, Candidates{}))
    case other mode:
      result(other, mode)

def foreign_operations(operations: List<&2, M.TypeId>) -> Bool:
  match operations:
    case Nil{}:
      True{}
    case head <> tail:
      Bool.and(M.is_foreign(head), foreign_operations(tail))

def effects(input: M.Ty, row: M.EffectRow, selection: Selection) -> Bool:
  match input row selection:
    case _ _ Candidates{}:
      True{}
    case _ M.EffectRow{Nil{}, M.ClosedRow{}} Resolved{}:
      True{}
    case M.FunctionTy{parameter, result, callback_effects} M.EffectRow{operations, M.ClosedRow{}} Resolved{}:
      foreign_operations(operations)
    case _ _ _:
      False{}

def callable(ty: M.Ty, +selection: Selection) -> Bool:
  match ty:
    case M.FunctionTy{+input, output, row}:
      Bool.and(parameter(input, selection), Bool.and(result(output, selection), effects(input, row, selection)))
    case _:
      False{}

def binding_index(bindings: List<&2, I.Binding>, index: Map<&2, I.Binding>) -> Map<&2, I.Binding>:
  match bindings:
    case Nil{}:
      index
    case I.Binding{+name, ty, variables} <> tail:
      binding_index(tail, Map.set(&2, I.Binding, index, name, I.Binding{name, ty, variables}))

def inferred(found: Maybe<&2, I.Binding>, name: String) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match found:
    case Some{I.Binding{name, ty, variables}}:
      Done{ty}
    case None{}:
      Fail{M.Diagnostic{"internal_error", name, "missing inferred type while selecting public entry points"}}

def functions(pending: List<&2, M.Function>, +types: Map<&2, I.Binding>, +selection: Selection) -> Result<&2, &2, M.Diagnostic, List<&2, M.Function>>:
  match pending:
    case Nil{}:
      Done{Nil{}}
    case M.Function{+name, True{}, argument, input, output, body} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Function>>:
        ty : M.Ty <- inferred(Index.find(I.Binding, types, name), name)
        rest : List<&2, M.Function> <- functions(tail, types, selection)
        return M.Function{name, callable(ty, selection), argument, input, output, body} <> rest
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Function>>:
        rest : List<&2, M.Function> <- functions(tail, types, selection)
        return head <> rest

def constant_type(ty: M.Ty, selection: Selection) -> Bool:
  match ty selection:
    case M.VariableTy{index} Candidates{}:
      True{}
    case M.ParameterTy{index} Candidates{}:
      True{}
    case M.FunctionTy{input, output, effects} Candidates{}:
      callable(M.FunctionTy{input, output, effects}, Candidates{})
    case other _:
      scalar(other)

# Apply the retained closure through a separate entry point. This preserves
# the single evaluation of its const initializer or runtime factory.
def select_constant(ty: M.Ty, selection: Selection, constant: M.Constant, rest: ConstantSelection) -> ConstantSelection:
  match ty selection:
    case M.FunctionTy{+input, +output, effects} Resolved{}:
      M.Constant{+name, exported, annotation, expression} = constant
      ConstantSelection{constants, +wrappers} = rest
      +supported = callable(M.FunctionTy{input, output, effects}, Resolved{})
      wrapper = {M.Function{"$public:" ++ name, True{}, "$argument", Some{input}, Some{output}, M.ApplyExpr{M.ConstantExpr{name}, M.LocalExpr{"$argument"}}} : M.Function}
      ConstantSelection{M.Constant{name, False{}, annotation, expression} <> constants, Bool.pick(List<&2, M.Function>, supported, wrapper <> wrappers, wrappers)}
    case other mode:
      M.Constant{name, exported, annotation, expression} = constant
      ConstantSelection{constants, wrappers} = rest
      ConstantSelection{M.Constant{name, constant_type(other, mode), annotation, expression} <> constants, wrappers}

def prepend_constant(constant: M.Constant, rest: ConstantSelection) -> ConstantSelection:
  ConstantSelection{constants, wrappers} = rest
  ConstantSelection{constant <> constants, wrappers}

def constants(pending: List<&2, M.Constant>, +types: Map<&2, I.Binding>, +selection: Selection) -> Result<&2, &2, M.Diagnostic, ConstantSelection>:
  match pending:
    case Nil{}:
      Done{ConstantSelection{Nil{}, Nil{}}}
    case M.Constant{+name, True{}, annotation, expression} <> tail:
      do Result<&2, &2, M.Diagnostic, ConstantSelection>:
        ty : M.Ty <- inferred(Index.find(I.Binding, types, name), name)
        rest : ConstantSelection <- constants(tail, types, selection)
        return select_constant(ty, selection, M.Constant{name, True{}, annotation, expression}, rest)
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, ConstantSelection>:
        rest : ConstantSelection <- constants(tail, types, selection)
        return prepend_constant(head, rest)

def selected_module(constants: ConstantSelection, functions: List<&2, M.Function>, types: List<&2, M.DataType>, operations: List<&2, M.Operation>) -> M.Module:
  ConstantSelection{values, wrappers} = constants
  M.Module{values, List.append(&2, M.Function, functions, wrappers), types, operations}

def wrapper_names(functions: List<&2, M.Function>) -> List<&2, String>:
  match functions:
    case Nil{}:
      Nil{}
    case M.Function{+name, exported, parameter, input, output, body} <> tail:
      +rest = wrapper_names(tail)
      Bool.pick(List<&2, String>, String.starts_with(name, "$public:"), name <> rest, rest)

def wrapper_binding(existing: Maybe<&2, I.Binding>, original: Maybe<&2, I.Binding>, name: String) -> Result<&2, &2, M.Diagnostic, List<&2, I.Binding>>:
  match existing original:
    case Some{binding} _:
      Done{Nil{}}
    case None{} Some{I.Binding{source, ty, variables}}:
      Done{[I.Binding{name, ty, variables}]}
    case None{} None{}:
      Fail{M.Diagnostic{"internal_error", name, "missing inferred binding for public callable value"}}

def wrapper_bindings(names: List<&2, String>, +index: Map<&2, I.Binding>, bindings: List<&2, I.Binding>) -> Result<&2, &2, M.Diagnostic, List<&2, I.Binding>>:
  match names:
    case Nil{}:
      Done{bindings}
    case +name <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, I.Binding>>:
        alias : List<&2, I.Binding> <- wrapper_binding(Index.find(I.Binding, index, name), Index.find(I.Binding, index, export_name(name)), name)
        rest : List<&2, I.Binding> <- wrapper_bindings(tail, index, bindings)
        return List.append(&2, I.Binding, alias, rest)

def add_wrapper_bindings(names: List<&2, String>, +bindings: List<&2, I.Binding>) -> Result<&2, &2, M.Diagnostic, List<&2, I.Binding>>:
  match names:
    case Nil{}:
      Done{bindings}
    case head <> tail:
      wrapper_bindings(head <> tail, binding_index(bindings, MTip{}), bindings)

def generated_bindings(module: M.Module, bindings: List<&2, I.Binding>) -> Result<&2, &2, M.Diagnostic, List<&2, I.Binding>>:
  M.Module{constants, functions, types, operations} = module
  add_wrapper_bindings(wrapper_names(functions), bindings)

def select(module: M.Module, bindings: List<&2, I.Binding>, +selection: Selection) -> Result<&2, &2, M.Diagnostic, M.Module>:
  M.Module{cs, fs, types, operations} = module
  +inferred = binding_index(bindings, MTip{})
  do Result<&2, &2, M.Diagnostic, M.Module>:
    selected_functions : List<&2, M.Function> <- functions(fs, inferred, selection)
    selected_constants : ConstantSelection <- constants(cs, inferred, selection)
    return selected_module(selected_constants, selected_functions, types, operations)

# Once the expanded program is checked, export selection needs only its final
# signatures. The wrapper applies the already evaluated constant exactly once;
# its signature and effect metadata follow directly from that constant's type.
type CheckedConstantSelection is Data:
  CheckedConstantSelection{constants: List<&2, M.CheckedConstant>, wrappers: List<&2, M.CheckedFunction>}

def checked_wrapper(+name: String, +input: M.Ty, +output: M.Ty, variables: List<&2, Nat>, +row: M.EffectRow) -> M.CheckedFunction:
  +exported = "$public:" ++ name
  function = {M.Function{exported, True{}, "$argument", Some{input}, Some{output}, M.ApplyExpr{M.ConstantExpr{name}, M.LocalExpr{"$argument"}}} : M.Function}
  M.CheckedFunction{function, M.Signature{exported, input, output, variables, row}, Rows.metadata(Rows.operation_set(row))}

def checked_functions(functions: List<&2, M.CheckedFunction>) -> List<&2, M.CheckedFunction>:
  match functions:
    case Nil{}:
      Nil{}
    case M.CheckedFunction{M.Function{name, True{}, argument, input, output, body}, M.Signature{+declared, +p, +r, +variables, +row}, effects} <> tail:
      M.CheckedFunction{M.Function{name, callable(M.FunctionTy{p, r, row}, Resolved{}), argument, input, output, body}, M.Signature{declared, p, r, variables, row}, effects} <> checked_functions(tail)
    case head <> tail:
      head <> checked_functions(tail)

def prepend_checked_constant(constant: M.CheckedConstant, rest: CheckedConstantSelection) -> CheckedConstantSelection:
  CheckedConstantSelection{constants, wrappers} = rest
  CheckedConstantSelection{constant <> constants, wrappers}

def select_checked_constant(ty: M.Ty, +name: String, annotation: Maybe<&2, M.Ty>, expression: M.Expr, +variables: List<&2, Nat>, rest: CheckedConstantSelection) -> CheckedConstantSelection:
  match ty:
    case M.FunctionTy{+input, +output, +row}:
      CheckedConstantSelection{constants, +wrappers} = rest
      +supported = callable(M.FunctionTy{input, output, row}, Resolved{})
      wrapper = checked_wrapper(name, input, output, variables, row)
      CheckedConstantSelection{M.CheckedConstant{M.Constant{name, False{}, annotation, expression}, M.FunctionTy{input, output, row}, variables} <> constants, Bool.pick(List<&2, M.CheckedFunction>, supported, wrapper <> wrappers, wrappers)}
    case +other:
      prepend_checked_constant(M.CheckedConstant{M.Constant{name, constant_type(other, Resolved{}), annotation, expression}, other, variables}, rest)

def checked_constants(constants: List<&2, M.CheckedConstant>) -> CheckedConstantSelection:
  match constants:
    case Nil{}:
      CheckedConstantSelection{Nil{}, Nil{}}
    case M.CheckedConstant{M.Constant{name, True{}, annotation, expression}, ty, variables} <> tail:
      select_checked_constant(ty, name, annotation, expression, variables, checked_constants(tail))
    case head <> tail:
      prepend_checked_constant(head, checked_constants(tail))

def selected_checked_module(constants: CheckedConstantSelection, functions: List<&2, M.CheckedFunction>, types: List<&2, M.DataType>, operations: List<&2, M.Operation>) -> M.CheckedModule:
  CheckedConstantSelection{values, wrappers} = constants
  M.CheckedModule{values, List.append(&2, M.CheckedFunction, functions, wrappers), types, operations}

def select_checked(module: M.CheckedModule) -> M.CheckedModule:
  M.CheckedModule{constants, functions, types, operations} = module
  selected_checked_module(checked_constants(constants), checked_functions(functions), types, operations)

def unchecked_functions(functions: List<&2, M.CheckedFunction>) -> List<&2, M.Function>:
  match functions:
    case Nil{}:
      Nil{}
    case M.CheckedFunction{function, signature, effects} <> tail:
      function <> unchecked_functions(tail)

def unchecked_constants(constants: List<&2, M.CheckedConstant>) -> List<&2, M.Constant>:
  match constants:
    case Nil{}:
      Nil{}
    case M.CheckedConstant{constant, ty, variables} <> tail:
      constant <> unchecked_constants(tail)

def unchecked_module(module: M.CheckedModule) -> M.Module:
  M.CheckedModule{constants, functions, types, operations} = module
  M.Module{unchecked_constants(constants), unchecked_functions(functions), types, operations}
