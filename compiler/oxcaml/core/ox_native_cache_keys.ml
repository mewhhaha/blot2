(* Native semantic port of compiler/native_cache_keys.bend.

   Source SHA-256: 7b272df54f85b3f7d83ace2b1ac088d1082b402bc767899ac9fe9d17f581d70b

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module C = Ox_cst

module L = Ox_lower

module T = Ox_source_types

module A = Ox_source_arguments

module O = Ox_operators

module G = Ox_groups

module D = Ox_dependency

module I = Ox_codegen_ir

module W = Ox_wasm

module R = Ox_native_response

type t_Work =
  | Field of R.t_Work
  | OperationGlobal of M.t_TypeId
  | OperationTemplateGlobal of M.t_TypeId * (A.t_Pattern) list
  | EffectFamilyGlobal of (M.t_TypeId) list * (A.t_Pattern) list
  | RecordConstructorGlobal of (Base.text) list
  | Globals of (L.t_Global) list
  | Headers of (T.t_Header) list
  | TypePattern of A.t_Pattern
  | TypePatterns of (A.t_Pattern) list
  | TypeVariables of (T.t_Variable) list
  | VariableKind of T.t_VariableKind
  | Predicate of M.t_Predicate
  | Predicates of (M.t_Predicate) list
  | Fixities of (O.t_Fixity) list
  | Locals of (L.t_Local) list
  | OptionalNatural of (int) option
  | Functions of (M.t_Function) list
  | Constants of (M.t_Constant) list
  | DataTypes of (M.t_DataType) list
  | Constructors of (M.t_Constructor) list
  | Operations of (M.t_Operation) list
  | Operation of M.t_Operation
  | Expression of M.t_Expr
  | Expressions of (M.t_Expr) list
  | OptionalExpression of (M.t_Expr) option
  | ExpressionArms of ((M.t_Expr) M.t_MatchArm) list
  | Dispatch of M.t_Dispatch
  | Identities of (M.t_TypeId) list
  | DependencyNodes of (D.t_Node) list
  | Usages of (G.t_DeclarationUsage) list
  | TypeDependencies of (G.t_TypeDependencies) list
  | Interfaces of (G.t_Interface) list
  | Runtime of I.t_Expr
  | Runtimes of (I.t_Expr) list
  | OptionalRuntime of (I.t_Expr) option
  | RuntimeArms of ((I.t_Expr) M.t_MatchArm) list
and t_CstComparison =
  | NodePair of C.t_Cst * C.t_Cst
  | ChildrenPair of (C.t_Cst) list * (C.t_Cst) list

let s_0 = Base.text_of_utf8 "cache_key_complexity"

let s_1 = Base.text_of_utf8 "native_session"

let s_2 = Base.text_of_utf8 "cache key traversal exceeded its bound"

let rec (* native_cache_keys.bend:55 *)
f_flag : bool -> t_Work =
fun v_value ->
(Field ((R.Word ((R.f_bool_word (v_value))))))
and (* native_cache_keys.bend:58 *)
f_global_kind : L.t_GlobalKind -> t_Work =
fun v_value ->
(match v_value with
| L.ConstantName ->
(Field ((R.Word (0x00000000l))))
| L.FunctionName ->
(Field ((R.Word (0x00000001l))))
| L.ConstructorName ->
(Field ((R.Word (0x00000002l))))
| (L.OperationName (v_identity)) ->
(OperationGlobal (v_identity))
| (L.OperationTemplateName (v_identity, v_parameters)) ->
(OperationTemplateGlobal (v_identity, v_parameters))
| (L.EffectFamilyName (v_members, v_parameters)) ->
(EffectFamilyGlobal (v_members, v_parameters))
| (L.RecordConstructorName (v_fields)) ->
(RecordConstructorGlobal (v_fields)))
and (* native_cache_keys.bend:75 *)
f_association : O.t_Associativity -> t_Work =
fun v_value ->
(match v_value with
| O.Left ->
(Field ((R.Word (0x00000000l))))
| O.Right ->
(Field ((R.Word (0x00000001l))))
| O.NonAssociative ->
(Field ((R.Word (0x00000002l)))))
and (* native_cache_keys.bend:84 *)
f_interface_kind : G.t_InterfaceKind -> t_Work =
fun v_value ->
(match v_value with
| G.FunctionInterface ->
(Field ((R.Word (0x00000000l))))
| G.ConstantInterface ->
(Field ((R.Word (0x00000001l)))))
and (* native_cache_keys.bend:91 *)
f_flatten : int -> (t_Work) list -> (R.t_Work) list -> (M.t_Diagnostic, (R.t_Work) list) Base.result_ =
fun v_fuel v_pending v_reversed ->
(match (v_fuel, v_pending) with
| (_, []) ->
(Done ((Base.list_reverse (v_reversed))))
| (0, _) ->
(Fail ((M.Diagnostic (s_0, s_1, s_2))))
| (__nat_1, ((Field (v_value)) :: v_tail)) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(f_flatten (v_rest) (v_tail) ((v_value :: v_reversed))))
| (__nat_2, ((OperationGlobal (v_identity)) :: v_tail)) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000003l)))) :: ((Field ((R.Identity (v_identity)))) :: v_tail))) (v_reversed)))
| (__nat_3, ((OperationTemplateGlobal (v_identity, v_parameters)) :: v_tail)) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000005l)))) :: ((Field ((R.Identity (v_identity)))) :: ((TypePatterns (v_parameters)) :: v_tail)))) (v_reversed)))
| (__nat_4, ((EffectFamilyGlobal (v_members, v_parameters)) :: v_tail)) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000006l)))) :: ((Field ((R.Identities (v_members)))) :: ((TypePatterns (v_parameters)) :: v_tail)))) (v_reversed)))
| (__nat_5, ((RecordConstructorGlobal (v_fields)) :: v_tail)) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000004l)))) :: ((Field ((R.Strings (v_fields)))) :: v_tail))) (v_reversed)))
| (__nat_6, ((Globals ([])) :: v_tail)) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_7, ((Globals (((L.Global (v_source, v_core, v_kind)) :: v_following))) :: v_tail)) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Field ((R.Text (v_source)))) :: ((Field ((R.Text (v_core)))) :: ((f_global_kind (v_kind)) :: ((Globals (v_following)) :: v_tail)))))) (v_reversed)))
| (__nat_8, ((Headers ([])) :: v_tail)) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_9, ((Headers (((T.Header (v_source, v_identity, v_parameters)) :: v_following))) :: v_tail)) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Field ((R.Text (v_source)))) :: ((Field ((R.Identity (v_identity)))) :: ((TypePatterns (v_parameters)) :: ((Headers (v_following)) :: v_tail)))))) (v_reversed)))
| (__nat_10, ((TypePatterns ([])) :: v_tail)) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_11, ((TypePatterns ((v_head :: v_following))) :: v_tail)) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((TypePattern (v_head)) :: ((TypePatterns (v_following)) :: v_tail)))) (v_reversed)))
| (__nat_12, ((TypePattern ((A.Binding (v_name)))) :: v_tail)) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: ((Field ((R.Text (v_name)))) :: v_tail))) (v_reversed)))
| (__nat_13, ((TypePattern ((A.TuplePattern (v_elements)))) :: v_tail)) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((TypePatterns (v_elements)) :: v_tail))) (v_reversed)))
| (__nat_14, ((TypePattern ((A.ArrayPattern (v_elements)))) :: v_tail)) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000002l)))) :: ((TypePatterns (v_elements)) :: v_tail))) (v_reversed)))
| (__nat_15, ((TypePattern ((A.RecordPattern (v_names, v_fields)))) :: v_tail)) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000003l)))) :: ((Field ((R.Strings (v_names)))) :: ((TypePatterns (v_fields)) :: v_tail)))) (v_reversed)))
| (__nat_16, ((TypeVariables ([])) :: v_tail)) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_17, ((TypeVariables (((T.Variable (v_name, v_ty, v_kind)) :: v_following))) :: v_tail)) when __nat_17 >= 1 ->
(let v_rest = (__nat_17 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Field ((R.Text (v_name)))) :: ((Field ((R.TypeValue (v_ty)))) :: ((VariableKind (v_kind)) :: ((TypeVariables (v_following)) :: v_tail)))))) (v_reversed)))
| (__nat_18, ((VariableKind (T.TypeKind)) :: v_tail)) when __nat_18 >= 1 ->
(let v_rest = (__nat_18 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_19, ((VariableKind (T.RowKind)) :: v_tail)) when __nat_19 >= 1 ->
(let v_rest = (__nat_19 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: v_tail)) (v_reversed)))
| (__nat_20, ((Fixities ([])) :: v_tail)) when __nat_20 >= 1 ->
(let v_rest = (__nat_20 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_21, ((Fixities (((O.Fixity (v_name, v_named, v_precedence, v_associativity, v_target)) :: v_following))) :: v_tail)) when __nat_21 >= 1 ->
(let v_rest = (__nat_21 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Field ((R.Text (v_name)))) :: ((f_flag (v_named)) :: ((Field ((R.Word (v_precedence)))) :: ((f_association (v_associativity)) :: ((Expression (v_target)) :: ((Fixities (v_following)) :: v_tail)))))))) (v_reversed)))
| (__nat_22, ((Locals ([])) :: v_tail)) when __nat_22 >= 1 ->
(let v_rest = (__nat_22 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_23, ((Locals (((L.Local (v_source, v_core)) :: v_following))) :: v_tail)) when __nat_23 >= 1 ->
(let v_rest = (__nat_23 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Field ((R.Text (v_source)))) :: ((Field ((R.Text (v_core)))) :: ((Locals (v_following)) :: v_tail))))) (v_reversed)))
| (__nat_24, ((OptionalNatural (None)) :: v_tail)) when __nat_24 >= 1 ->
(let v_rest = (__nat_24 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_25, ((OptionalNatural ((Some (v_value)))) :: v_tail)) when __nat_25 >= 1 ->
(let v_rest = (__nat_25 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Field ((R.Natural (v_value)))) :: v_tail))) (v_reversed)))
| (__nat_26, ((Functions ([])) :: v_tail)) when __nat_26 >= 1 ->
(let v_rest = (__nat_26 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_27, ((Functions (((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_following))) :: v_tail)) when __nat_27 >= 1 ->
(let v_rest = (__nat_27 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Field ((R.Text (v_name)))) :: ((f_flag (v_exported)) :: ((Field ((R.Text (v_parameter)))) :: ((Field ((R.OptionalType (v_p)))) :: ((Field ((R.OptionalType (v_r)))) :: ((Expression (v_body)) :: ((Functions (v_following)) :: v_tail))))))))) (v_reversed)))
| (__nat_28, ((Constants ([])) :: v_tail)) when __nat_28 >= 1 ->
(let v_rest = (__nat_28 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_29, ((Constants (((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_following))) :: v_tail)) when __nat_29 >= 1 ->
(let v_rest = (__nat_29 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Field ((R.Text (v_name)))) :: ((f_flag (v_exported)) :: ((Field ((R.OptionalType (v_annotation)))) :: ((Expression (v_value)) :: ((Constants (v_following)) :: v_tail))))))) (v_reversed)))
| (__nat_30, ((DataTypes ([])) :: v_tail)) when __nat_30 >= 1 ->
(let v_rest = (__nat_30 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_31, ((DataTypes (((M.DataType (v_identity, v_parameters, v_constructors)) :: v_following))) :: v_tail)) when __nat_31 >= 1 ->
(let v_rest = (__nat_31 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Field ((R.Identity (v_identity)))) :: ((Field ((R.Natural (v_parameters)))) :: ((Constructors (v_constructors)) :: ((DataTypes (v_following)) :: v_tail)))))) (v_reversed)))
| (__nat_32, ((Constructors ([])) :: v_tail)) when __nat_32 >= 1 ->
(let v_rest = (__nat_32 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_33, ((Constructors (((M.Constructor (v_name, v_payload, v_fields)) :: v_following))) :: v_tail)) when __nat_33 >= 1 ->
(let v_rest = (__nat_33 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Field ((R.Text (v_name)))) :: ((Field ((R.OptionalType (v_payload)))) :: ((Field ((R.Strings (v_fields)))) :: ((Constructors (v_following)) :: v_tail)))))) (v_reversed)))
| (__nat_34, ((Operations ([])) :: v_tail)) when __nat_34 >= 1 ->
(let v_rest = (__nat_34 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_35, ((Operations ((v_head :: v_following))) :: v_tail)) when __nat_35 >= 1 ->
(let v_rest = (__nat_35 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Operation (v_head)) :: ((Operations (v_following)) :: v_tail)))) (v_reversed)))
| (__nat_36, ((Operation ((M.Operation (v_identity, v_parameter, v_result)))) :: v_tail)) when __nat_36 >= 1 ->
(let v_rest = (__nat_36 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: ((Field ((R.Identity (v_identity)))) :: ((Field ((R.TypeValue (v_parameter)))) :: ((Field ((R.TypeValue (v_result)))) :: v_tail))))) (v_reversed)))
| (__nat_37, ((Operation ((M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result)))) :: v_tail)) when __nat_37 >= 1 ->
(let v_rest = (__nat_37 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Field ((R.Identity (v_identity)))) :: ((Field ((R.Natural (v_parameters)))) :: ((Field ((R.TypeValue (v_parameter)))) :: ((Field ((R.TypeValue (v_result)))) :: v_tail)))))) (v_reversed)))
| (__nat_38, ((Operation ((M.OperationInstance (v_template, v_arguments)))) :: v_tail)) when __nat_38 >= 1 ->
(let v_rest = (__nat_38 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000002l)))) :: ((Field ((R.Identity (v_template)))) :: ((Field ((R.Types (v_arguments)))) :: v_tail)))) (v_reversed)))
| (__nat_39, ((Predicates ([])) :: v_tail)) when __nat_39 >= 1 ->
(let v_rest = (__nat_39 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_40, ((Predicates ((v_head :: v_following))) :: v_tail)) when __nat_40 >= 1 ->
(let v_rest = (__nat_40 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Predicate (v_head)) :: ((Predicates (v_following)) :: v_tail)))) (v_reversed)))
| (__nat_41, ((Predicate ((M.AssociatedPredicate (v_member, v_templates, v_left, v_right, v_result, v_invocation)))) :: v_tail)) when __nat_41 >= 1 ->
(let v_rest = (__nat_41 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: ((Field ((R.Text (v_member)))) :: ((Identities (v_templates)) :: ((Field ((R.TypeValue (v_left)))) :: ((Field ((R.TypeValue (v_right)))) :: ((Field ((R.TypeValue (v_result)))) :: ((Field ((R.Row (v_invocation)))) :: v_tail)))))))) (v_reversed)))
| (__nat_42, ((Predicate ((M.ReceiverPredicate (v_member, v_templates, v_receiver, v_argument, v_result, v_invocation)))) :: v_tail)) when __nat_42 >= 1 ->
(let v_rest = (__nat_42 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Field ((R.Text (v_member)))) :: ((Identities (v_templates)) :: ((Field ((R.TypeValue (v_receiver)))) :: ((Field ((R.TypeValue (v_argument)))) :: ((Field ((R.TypeValue (v_result)))) :: ((Field ((R.Row (v_invocation)))) :: v_tail)))))))) (v_reversed)))
| (__nat_43, ((Predicate ((M.FieldPredicate (v_member, v_receiver, v_result)))) :: v_tail)) when __nat_43 >= 1 ->
(let v_rest = (__nat_43 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000002l)))) :: ((Field ((R.Text (v_member)))) :: ((Field ((R.TypeValue (v_receiver)))) :: ((Field ((R.TypeValue (v_result)))) :: v_tail))))) (v_reversed)))
| (__nat_44, ((Predicate ((M.UpdatePredicate (v_member, v_receiver, v_assigned, v_result, v_invocation)))) :: v_tail)) when __nat_44 >= 1 ->
(let v_rest = (__nat_44 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000003l)))) :: ((Field ((R.Text (v_member)))) :: ((Field ((R.TypeValue (v_receiver)))) :: ((Field ((R.TypeValue (v_assigned)))) :: ((Field ((R.TypeValue (v_result)))) :: ((Field ((R.Row (v_invocation)))) :: v_tail))))))) (v_reversed)))
| (__nat_45, ((Predicate ((M.OperationPredicate (v_template, v_arguments, v_function_type)))) :: v_tail)) when __nat_45 >= 1 ->
(let v_rest = (__nat_45 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000004l)))) :: ((Field ((R.Identity (v_template)))) :: ((Field ((R.Types (v_arguments)))) :: ((Field ((R.TypeValue (v_function_type)))) :: v_tail))))) (v_reversed)))
| (__nat_46, ((Predicate ((M.TypeRepPredicate (v_represented)))) :: v_tail)) when __nat_46 >= 1 ->
(let v_rest = (__nat_46 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000005l)))) :: ((Field ((R.TypeValue (v_represented)))) :: v_tail))) (v_reversed)))
| (__nat_47, ((Predicate ((M.EffectRepPredicate (v_row)))) :: v_tail)) when __nat_47 >= 1 ->
(let v_rest = (__nat_47 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000006l)))) :: ((Field ((R.Row (v_row)))) :: v_tail))) (v_reversed)))
| (__nat_48, ((Expression (M.UnitExpr)) :: v_tail)) when __nat_48 >= 1 ->
(let v_rest = (__nat_48 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_49, ((Expression ((M.U32Expr (v_value)))) :: v_tail)) when __nat_49 >= 1 ->
(let v_rest = (__nat_49 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Field ((R.Word (v_value)))) :: v_tail))) (v_reversed)))
| (__nat_50, ((Expression ((M.BoolExpr (v_value)))) :: v_tail)) when __nat_50 >= 1 ->
(let v_rest = (__nat_50 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000002l)))) :: ((f_flag (v_value)) :: v_tail))) (v_reversed)))
| (__nat_51, ((Expression ((M.LocalExpr (v_name)))) :: v_tail)) when __nat_51 >= 1 ->
(let v_rest = (__nat_51 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000003l)))) :: ((Field ((R.Text (v_name)))) :: v_tail))) (v_reversed)))
| (__nat_52, ((Expression ((M.ConstantExpr (v_name)))) :: v_tail)) when __nat_52 >= 1 ->
(let v_rest = (__nat_52 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000004l)))) :: ((Field ((R.Text (v_name)))) :: v_tail))) (v_reversed)))
| (__nat_53, ((Expression ((M.FunctionExpr (v_name)))) :: v_tail)) when __nat_53 >= 1 ->
(let v_rest = (__nat_53 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000005l)))) :: ((Field ((R.Text (v_name)))) :: v_tail))) (v_reversed)))
| (__nat_54, ((Expression ((M.ConstructorRefExpr (v_constructor)))) :: v_tail)) when __nat_54 >= 1 ->
(let v_rest = (__nat_54 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000006l)))) :: ((Field ((R.Text (v_constructor)))) :: v_tail))) (v_reversed)))
| (__nat_55, ((Expression ((M.ConstructExpr (v_constructor, v_payload)))) :: v_tail)) when __nat_55 >= 1 ->
(let v_rest = (__nat_55 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000007l)))) :: ((Field ((R.Text (v_constructor)))) :: ((OptionalExpression (v_payload)) :: v_tail)))) (v_reversed)))
| (__nat_56, ((Expression ((M.LambdaExpr (v_identity, v_parameter, v_parameter_type, v_result_type, v_body)))) :: v_tail)) when __nat_56 >= 1 ->
(let v_rest = (__nat_56 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000008l)))) :: ((Field ((R.Natural (v_identity)))) :: ((Field ((R.Text (v_parameter)))) :: ((Field ((R.OptionalType (v_parameter_type)))) :: ((Field ((R.OptionalType (v_result_type)))) :: ((Expression (v_body)) :: v_tail))))))) (v_reversed)))
| (__nat_57, ((Expression ((M.ApplyExpr (v_callee, v_argument)))) :: v_tail)) when __nat_57 >= 1 ->
(let v_rest = (__nat_57 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000009l)))) :: ((Expression (v_callee)) :: ((Expression (v_argument)) :: v_tail)))) (v_reversed)))
| (__nat_58, ((Expression ((M.TagExpr (v_offset, v_callee, v_argument)))) :: v_tail)) when __nat_58 >= 1 ->
(let v_rest = (__nat_58 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000002fl)))) :: ((Field ((R.Natural (v_offset)))) :: ((Expression (v_callee)) :: ((Expression (v_argument)) :: v_tail))))) (v_reversed)))
| (__nat_59, ((Expression ((M.CallExpr (v_callee, v_argument)))) :: v_tail)) when __nat_59 >= 1 ->
(let v_rest = (__nat_59 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000000al)))) :: ((Field ((R.Text (v_callee)))) :: ((Expression (v_argument)) :: v_tail)))) (v_reversed)))
| (__nat_60, ((Expression ((M.ScalarExpr (v_operator, v_left, v_right)))) :: v_tail)) when __nat_60 >= 1 ->
(let v_rest = (__nat_60 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000000bl)))) :: ((Field ((R.Operator (v_operator)))) :: ((Expression (v_left)) :: ((Expression (v_right)) :: v_tail))))) (v_reversed)))
| (__nat_61, ((Expression ((M.LetExpr (v_name, v_value, v_body)))) :: v_tail)) when __nat_61 >= 1 ->
(let v_rest = (__nat_61 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000000cl)))) :: ((Field ((R.Text (v_name)))) :: ((Expression (v_value)) :: ((Expression (v_body)) :: v_tail))))) (v_reversed)))
| (__nat_62, ((Expression ((M.UseExpr (v_name, v_value, v_body)))) :: v_tail)) when __nat_62 >= 1 ->
(let v_rest = (__nat_62 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000000dl)))) :: ((Field ((R.Text (v_name)))) :: ((Expression (v_value)) :: ((Expression (v_body)) :: v_tail))))) (v_reversed)))
| (__nat_63, ((Expression ((M.IfExpr (v_condition, v_consequent, v_alternative)))) :: v_tail)) when __nat_63 >= 1 ->
(let v_rest = (__nat_63 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000000el)))) :: ((Expression (v_condition)) :: ((Expression (v_consequent)) :: ((Expression (v_alternative)) :: v_tail))))) (v_reversed)))
| (__nat_64, ((Expression ((M.SequenceExpr (v_first, v_next)))) :: v_tail)) when __nat_64 >= 1 ->
(let v_rest = (__nat_64 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000000fl)))) :: ((Expression (v_first)) :: ((Expression (v_next)) :: v_tail)))) (v_reversed)))
| (__nat_65, ((Expression ((M.MatchExpr (v_values, v_arms)))) :: v_tail)) when __nat_65 >= 1 ->
(let v_rest = (__nat_65 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000010l)))) :: ((Expressions (v_values)) :: ((ExpressionArms (v_arms)) :: v_tail)))) (v_reversed)))
| (__nat_66, ((Expression ((M.GuardExpr (v_pattern, v_value, v_alternative, v_body)))) :: v_tail)) when __nat_66 >= 1 ->
(let v_rest = (__nat_66 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000011l)))) :: ((Field ((R.Pattern (v_pattern)))) :: ((Expression (v_value)) :: ((Expression (v_alternative)) :: ((Expression (v_body)) :: v_tail)))))) (v_reversed)))
| (__nat_67, ((Expression ((M.BlockExpr (v_label, v_body)))) :: v_tail)) when __nat_67 >= 1 ->
(let v_rest = (__nat_67 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000012l)))) :: ((Field ((R.Natural (v_label)))) :: ((Expression (v_body)) :: v_tail)))) (v_reversed)))
| (__nat_68, ((Expression ((M.ReturnExpr (v_label, v_value)))) :: v_tail)) when __nat_68 >= 1 ->
(let v_rest = (__nat_68 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000013l)))) :: ((Field ((R.Natural (v_label)))) :: ((Expression (v_value)) :: v_tail)))) (v_reversed)))
| (__nat_69, ((Expression ((M.SourceExpr (v_offset, v_annotation, v_value)))) :: v_tail)) when __nat_69 >= 1 ->
(let v_rest = (__nat_69 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000014l)))) :: ((Field ((R.Natural (v_offset)))) :: ((Field ((R.OptionalType (v_annotation)))) :: ((Expression (v_value)) :: v_tail))))) (v_reversed)))
| (__nat_70, ((Expression ((M.QualifiedExpr (v_offset, v_annotation, v_predicates, v_value)))) :: v_tail)) when __nat_70 >= 1 ->
(let v_rest = (__nat_70 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000030l)))) :: ((Field ((R.Natural (v_offset)))) :: ((Field ((R.TypeValue (v_annotation)))) :: ((Predicates (v_predicates)) :: ((Expression (v_value)) :: v_tail)))))) (v_reversed)))
| (__nat_71, ((Expression ((M.InstantiationExpr (v_site, v_value)))) :: v_tail)) when __nat_71 >= 1 ->
(let v_rest = (__nat_71 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000031l)))) :: ((Field ((R.Natural (v_site)))) :: ((Expression (v_value)) :: v_tail)))) (v_reversed)))
| (__nat_72, ((Expression ((M.F32Expr (v_value)))) :: v_tail)) when __nat_72 >= 1 ->
(let v_rest = (__nat_72 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000015l)))) :: ((Field ((R.Word ((Base.f32_bits (v_value)))))) :: v_tail))) (v_reversed)))
| (__nat_73, ((Expression ((M.UnaryExpr (v_operator, v_value)))) :: v_tail)) when __nat_73 >= 1 ->
(let v_rest = (__nat_73 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000016l)))) :: ((Field ((R.UnaryOperator (v_operator)))) :: ((Expression (v_value)) :: v_tail)))) (v_reversed)))
| (__nat_74, ((Expression ((M.PanicExpr (v_message)))) :: v_tail)) when __nat_74 >= 1 ->
(let v_rest = (__nat_74 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000017l)))) :: ((Field ((R.Text (v_message)))) :: v_tail))) (v_reversed)))
| (__nat_75, ((Expression ((M.OperationExpr (v_identity)))) :: v_tail)) when __nat_75 >= 1 ->
(let v_rest = (__nat_75 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000018l)))) :: ((Field ((R.Identity (v_identity)))) :: v_tail))) (v_reversed)))
| (__nat_76, ((Expression ((M.ProviderExpr (v_identity, v_implementation)))) :: v_tail)) when __nat_76 >= 1 ->
(let v_rest = (__nat_76 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000019l)))) :: ((Field ((R.Identity (v_identity)))) :: ((Expression (v_implementation)) :: v_tail)))) (v_reversed)))
| (__nat_77, ((Expression ((M.HandleExpr (v_provider, v_body)))) :: v_tail)) when __nat_77 >= 1 ->
(let v_rest = (__nat_77 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000001al)))) :: ((Expression (v_provider)) :: ((Expression (v_body)) :: v_tail)))) (v_reversed)))
| (__nat_78, ((Expression ((M.OperationDescriptorExpr (v_identity)))) :: v_tail)) when __nat_78 >= 1 ->
(let v_rest = (__nat_78 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000001bl)))) :: ((Field ((R.Identity (v_identity)))) :: v_tail))) (v_reversed)))
| (__nat_79, ((Expression ((M.FunctionEffectsExpr (v_callee)))) :: v_tail)) when __nat_79 >= 1 ->
(let v_rest = (__nat_79 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000001cl)))) :: ((Field ((R.Text (v_callee)))) :: v_tail))) (v_reversed)))
| (__nat_80, ((Expression ((M.EffectHasExpr (v_set, v_operation)))) :: v_tail)) when __nat_80 >= 1 ->
(let v_rest = (__nat_80 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000001dl)))) :: ((Expression (v_set)) :: ((Expression (v_operation)) :: v_tail)))) (v_reversed)))
| (__nat_81, ((Expression ((M.EffectCountExpr (v_set)))) :: v_tail)) when __nat_81 >= 1 ->
(let v_rest = (__nat_81 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000001el)))) :: ((Expression (v_set)) :: v_tail))) (v_reversed)))
| (__nat_82, ((Expression ((M.EffectSameExpr (v_left, v_right)))) :: v_tail)) when __nat_82 >= 1 ->
(let v_rest = (__nat_82 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000001fl)))) :: ((Expression (v_left)) :: ((Expression (v_right)) :: v_tail)))) (v_reversed)))
| (__nat_83, ((Expression ((M.ProductExpr (v_elements)))) :: v_tail)) when __nat_83 >= 1 ->
(let v_rest = (__nat_83 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000020l)))) :: ((Expressions (v_elements)) :: v_tail))) (v_reversed)))
| (__nat_84, ((Expression ((M.ProjectExpr (v_value, v_index)))) :: v_tail)) when __nat_84 >= 1 ->
(let v_rest = (__nat_84 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000021l)))) :: ((Expression (v_value)) :: ((Field ((R.Natural (v_index)))) :: v_tail)))) (v_reversed)))
| (__nat_85, ((Expression ((M.ArrayExpr (v_elements)))) :: v_tail)) when __nat_85 >= 1 ->
(let v_rest = (__nat_85 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000022l)))) :: ((Expressions (v_elements)) :: v_tail))) (v_reversed)))
| (__nat_86, ((Expression ((M.ArrayGetExpr (v_array, v_index)))) :: v_tail)) when __nat_86 >= 1 ->
(let v_rest = (__nat_86 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000023l)))) :: ((Expression (v_array)) :: ((Expression (v_index)) :: v_tail)))) (v_reversed)))
| (__nat_87, ((Expression ((M.ArraySetExpr (v_array, v_index, v_value)))) :: v_tail)) when __nat_87 >= 1 ->
(let v_rest = (__nat_87 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000024l)))) :: ((Expression (v_array)) :: ((Expression (v_index)) :: ((Expression (v_value)) :: v_tail))))) (v_reversed)))
| (__nat_88, ((Expression ((M.ArrayLengthExpr (v_array)))) :: v_tail)) when __nat_88 >= 1 ->
(let v_rest = (__nat_88 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000025l)))) :: ((Expression (v_array)) :: v_tail))) (v_reversed)))
| (__nat_89, ((Expression ((M.ArrayFillExpr (v_count, v_value)))) :: v_tail)) when __nat_89 >= 1 ->
(let v_rest = (__nat_89 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000026l)))) :: ((Expression (v_count)) :: ((Expression (v_value)) :: v_tail)))) (v_reversed)))
| (__nat_90, ((Expression ((M.ArrayGenerateExpr (v_count, v_generator)))) :: v_tail)) when __nat_90 >= 1 ->
(let v_rest = (__nat_90 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000027l)))) :: ((Expression (v_count)) :: ((Expression (v_generator)) :: v_tail)))) (v_reversed)))
| (__nat_91, ((Expression ((M.AssociatedExpr (v_identity, v_dispatch, v_member, v_templates, v_left, v_right)))) :: v_tail)) when __nat_91 >= 1 ->
(let v_rest = (__nat_91 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000028l)))) :: ((Field ((R.Natural (v_identity)))) :: ((Dispatch (v_dispatch)) :: ((Field ((R.Text (v_member)))) :: ((Identities (v_templates)) :: ((Expression (v_left)) :: ((Expression (v_right)) :: v_tail)))))))) (v_reversed)))
| (__nat_92, ((Expression ((M.ForExpr (v_index, v_start, v_end, v_state, v_initial, v_body)))) :: v_tail)) when __nat_92 >= 1 ->
(let v_rest = (__nat_92 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000029l)))) :: ((Field ((R.Text (v_index)))) :: ((Expression (v_start)) :: ((Expression (v_end)) :: ((Field ((R.Text (v_state)))) :: ((Expression (v_initial)) :: ((Expression (v_body)) :: v_tail)))))))) (v_reversed)))
| (__nat_93, ((Expression ((M.ForeverExpr (v_state, v_initial, v_body)))) :: v_tail)) when __nat_93 >= 1 ->
(let v_rest = (__nat_93 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000002el)))) :: ((Field ((R.Text (v_state)))) :: ((Expression (v_initial)) :: ((Expression (v_body)) :: v_tail))))) (v_reversed)))
| (__nat_94, ((Expression ((M.StateProviderExpr (v_read, v_write, v_initial)))) :: v_tail)) when __nat_94 >= 1 ->
(let v_rest = (__nat_94 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000002al)))) :: ((Field ((R.Identity (v_read)))) :: ((Field ((R.Identity (v_write)))) :: ((Expression (v_initial)) :: v_tail))))) (v_reversed)))
| (__nat_95, ((Expression ((M.GenericOperationExpr (v_identity, v_template, v_arguments)))) :: v_tail)) when __nat_95 >= 1 ->
(let v_rest = (__nat_95 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000002bl)))) :: ((Field ((R.Natural (v_identity)))) :: ((Field ((R.Identity (v_template)))) :: ((Field ((R.Types (v_arguments)))) :: v_tail))))) (v_reversed)))
| (__nat_96, ((Expression ((M.RuntimeInitExpr (v_value)))) :: v_tail)) when __nat_96 >= 1 ->
(let v_rest = (__nat_96 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000002cl)))) :: ((Expression (v_value)) :: v_tail))) (v_reversed)))
| (__nat_97, ((Expression ((M.SpecializeOperationExpr (v_template, v_arguments, v_body)))) :: v_tail)) when __nat_97 >= 1 ->
(let v_rest = (__nat_97 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000002dl)))) :: ((Field ((R.Identity (v_template)))) :: ((Field ((R.Types (v_arguments)))) :: ((Expression (v_body)) :: v_tail))))) (v_reversed)))
| (__nat_98, ((Expressions ([])) :: v_tail)) when __nat_98 >= 1 ->
(let v_rest = (__nat_98 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_99, ((Expressions ((v_head :: v_following))) :: v_tail)) when __nat_99 >= 1 ->
(let v_rest = (__nat_99 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Expression (v_head)) :: ((Expressions (v_following)) :: v_tail)))) (v_reversed)))
| (__nat_100, ((OptionalExpression (None)) :: v_tail)) when __nat_100 >= 1 ->
(let v_rest = (__nat_100 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_101, ((OptionalExpression ((Some (v_value)))) :: v_tail)) when __nat_101 >= 1 ->
(let v_rest = (__nat_101 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Expression (v_value)) :: v_tail))) (v_reversed)))
| (__nat_102, ((ExpressionArms ([])) :: v_tail)) when __nat_102 >= 1 ->
(let v_rest = (__nat_102 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_103, ((ExpressionArms (((M.MatchArm (v_patterns, v_body)) :: v_following))) :: v_tail)) when __nat_103 >= 1 ->
(let v_rest = (__nat_103 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Field ((R.Patterns (v_patterns)))) :: ((Expression (v_body)) :: ((ExpressionArms (v_following)) :: v_tail))))) (v_reversed)))
| (__nat_104, ((Dispatch (M.BinaryDispatch)) :: v_tail)) when __nat_104 >= 1 ->
(let v_rest = (__nat_104 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_105, ((Dispatch (M.MemberDispatch)) :: v_tail)) when __nat_105 >= 1 ->
(let v_rest = (__nat_105 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: v_tail)) (v_reversed)))
| (__nat_106, ((Dispatch (M.FieldUpdateDispatch)) :: v_tail)) when __nat_106 >= 1 ->
(let v_rest = (__nat_106 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000002l)))) :: v_tail)) (v_reversed)))
| (__nat_107, ((Identities ([])) :: v_tail)) when __nat_107 >= 1 ->
(let v_rest = (__nat_107 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_108, ((Identities ((v_head :: v_following))) :: v_tail)) when __nat_108 >= 1 ->
(let v_rest = (__nat_108 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Field ((R.Identity (v_head)))) :: ((Identities (v_following)) :: v_tail)))) (v_reversed)))
| (__nat_109, ((DependencyNodes ([])) :: v_tail)) when __nat_109 >= 1 ->
(let v_rest = (__nat_109 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_110, ((DependencyNodes (((D.Node (v_name, v_references, v_lambdas)) :: v_following))) :: v_tail)) when __nat_110 >= 1 ->
(let v_rest = (__nat_110 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Field ((R.Text (v_name)))) :: ((Field ((R.Strings (v_references)))) :: ((Field ((R.Naturals (v_lambdas)))) :: ((DependencyNodes (v_following)) :: v_tail)))))) (v_reversed)))
| (__nat_111, ((Usages ([])) :: v_tail)) when __nat_111 >= 1 ->
(let v_rest = (__nat_111 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_112, ((Usages (((G.DeclarationUsage (v_name, (G.Usage (v_nominals)))) :: v_following))) :: v_tail)) when __nat_112 >= 1 ->
(let v_rest = (__nat_112 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Field ((R.Text (v_name)))) :: ((Identities (v_nominals)) :: ((Usages (v_following)) :: v_tail))))) (v_reversed)))
| (__nat_113, ((TypeDependencies ([])) :: v_tail)) when __nat_113 >= 1 ->
(let v_rest = (__nat_113 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_114, ((TypeDependencies (((G.TypeDependencies (v_identity, v_references)) :: v_following))) :: v_tail)) when __nat_114 >= 1 ->
(let v_rest = (__nat_114 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Field ((R.Identity (v_identity)))) :: ((Identities (v_references)) :: ((TypeDependencies (v_following)) :: v_tail))))) (v_reversed)))
| (__nat_115, ((Interfaces ([])) :: v_tail)) when __nat_115 >= 1 ->
(let v_rest = (__nat_115 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_116, ((Interfaces (((G.Interface (v_name, v_kind, v_template, v_parameters, v_effects, v_predicates)) :: v_following))) :: v_tail)) when __nat_116 >= 1 ->
(let v_rest = (__nat_116 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Field ((R.Text (v_name)))) :: ((f_interface_kind (v_kind)) :: ((Field ((R.TypeValue (v_template)))) :: ((Field ((R.Natural (v_parameters)))) :: ((Field ((R.Effects (v_effects)))) :: ((Predicates (v_predicates)) :: ((Interfaces (v_following)) :: v_tail))))))))) (v_reversed)))
| (__nat_117, ((Runtime (I.UnitExpr)) :: v_tail)) when __nat_117 >= 1 ->
(let v_rest = (__nat_117 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_118, ((Runtime ((I.U32Expr (v_value)))) :: v_tail)) when __nat_118 >= 1 ->
(let v_rest = (__nat_118 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Field ((R.Word (v_value)))) :: v_tail))) (v_reversed)))
| (__nat_119, ((Runtime ((I.BoolExpr (v_value)))) :: v_tail)) when __nat_119 >= 1 ->
(let v_rest = (__nat_119 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000002l)))) :: ((f_flag (v_value)) :: v_tail))) (v_reversed)))
| (__nat_120, ((Runtime ((I.LocalExpr (v_name)))) :: v_tail)) when __nat_120 >= 1 ->
(let v_rest = (__nat_120 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000003l)))) :: ((Field ((R.Text (v_name)))) :: v_tail))) (v_reversed)))
| (__nat_121, ((Runtime ((I.ConstantExpr (v_name)))) :: v_tail)) when __nat_121 >= 1 ->
(let v_rest = (__nat_121 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000004l)))) :: ((Field ((R.Text (v_name)))) :: v_tail))) (v_reversed)))
| (__nat_122, ((Runtime ((I.ClosureExpr (v_key, v_captures)))) :: v_tail)) when __nat_122 >= 1 ->
(let v_rest = (__nat_122 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000005l)))) :: ((Field ((R.Text (v_key)))) :: ((Field ((R.Strings (v_captures)))) :: v_tail)))) (v_reversed)))
| (__nat_123, ((Runtime ((I.ConstructExpr (v_constructor, v_payload)))) :: v_tail)) when __nat_123 >= 1 ->
(let v_rest = (__nat_123 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000006l)))) :: ((Field ((R.Text (v_constructor)))) :: ((OptionalRuntime (v_payload)) :: v_tail)))) (v_reversed)))
| (__nat_124, ((Runtime ((I.ApplyExpr (v_callee, v_argument)))) :: v_tail)) when __nat_124 >= 1 ->
(let v_rest = (__nat_124 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000007l)))) :: ((Runtime (v_callee)) :: ((Runtime (v_argument)) :: v_tail)))) (v_reversed)))
| (__nat_125, ((Runtime ((I.CallExpr (v_key, v_argument)))) :: v_tail)) when __nat_125 >= 1 ->
(let v_rest = (__nat_125 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000008l)))) :: ((Field ((R.Text (v_key)))) :: ((Runtime (v_argument)) :: v_tail)))) (v_reversed)))
| (__nat_126, ((Runtime ((I.ScalarExpr (v_operator, v_left, v_right)))) :: v_tail)) when __nat_126 >= 1 ->
(let v_rest = (__nat_126 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000009l)))) :: ((Field ((R.Operator (v_operator)))) :: ((Runtime (v_left)) :: ((Runtime (v_right)) :: v_tail))))) (v_reversed)))
| (__nat_127, ((Runtime ((I.LetExpr (v_name, v_value, v_body)))) :: v_tail)) when __nat_127 >= 1 ->
(let v_rest = (__nat_127 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000000al)))) :: ((Field ((R.Text (v_name)))) :: ((Runtime (v_value)) :: ((Runtime (v_body)) :: v_tail))))) (v_reversed)))
| (__nat_128, ((Runtime ((I.IfExpr (v_condition, v_consequent, v_alternative)))) :: v_tail)) when __nat_128 >= 1 ->
(let v_rest = (__nat_128 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000000bl)))) :: ((Runtime (v_condition)) :: ((Runtime (v_consequent)) :: ((Runtime (v_alternative)) :: v_tail))))) (v_reversed)))
| (__nat_129, ((Runtime ((I.SequenceExpr (v_first, v_next)))) :: v_tail)) when __nat_129 >= 1 ->
(let v_rest = (__nat_129 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000000cl)))) :: ((Runtime (v_first)) :: ((Runtime (v_next)) :: v_tail)))) (v_reversed)))
| (__nat_130, ((Runtime ((I.MatchExpr (v_values, v_arms)))) :: v_tail)) when __nat_130 >= 1 ->
(let v_rest = (__nat_130 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000000dl)))) :: ((Runtimes (v_values)) :: ((RuntimeArms (v_arms)) :: v_tail)))) (v_reversed)))
| (__nat_131, ((Runtime ((I.GuardExpr (v_pattern, v_value, v_alternative, v_body)))) :: v_tail)) when __nat_131 >= 1 ->
(let v_rest = (__nat_131 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000000el)))) :: ((Field ((R.Pattern (v_pattern)))) :: ((Runtime (v_value)) :: ((Runtime (v_alternative)) :: ((Runtime (v_body)) :: v_tail)))))) (v_reversed)))
| (__nat_132, ((Runtime ((I.BlockExpr (v_label, v_body)))) :: v_tail)) when __nat_132 >= 1 ->
(let v_rest = (__nat_132 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000000fl)))) :: ((Field ((R.Natural (v_label)))) :: ((Runtime (v_body)) :: v_tail)))) (v_reversed)))
| (__nat_133, ((Runtime ((I.ReturnExpr (v_label, v_value)))) :: v_tail)) when __nat_133 >= 1 ->
(let v_rest = (__nat_133 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000010l)))) :: ((Field ((R.Natural (v_label)))) :: ((Runtime (v_value)) :: v_tail)))) (v_reversed)))
| (__nat_134, ((Runtime ((I.F32Expr (v_value)))) :: v_tail)) when __nat_134 >= 1 ->
(let v_rest = (__nat_134 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000011l)))) :: ((Field ((R.Word ((Base.f32_bits (v_value)))))) :: v_tail))) (v_reversed)))
| (__nat_135, ((Runtime ((I.UnaryExpr (v_operator, v_value)))) :: v_tail)) when __nat_135 >= 1 ->
(let v_rest = (__nat_135 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000012l)))) :: ((Field ((R.UnaryOperator (v_operator)))) :: ((Runtime (v_value)) :: v_tail)))) (v_reversed)))
| (__nat_136, ((Runtime ((I.StateProviderExpr (v_read, v_write, v_initial)))) :: v_tail)) when __nat_136 >= 1 ->
(let v_rest = (__nat_136 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000020l)))) :: ((Field ((R.Identity (v_read)))) :: ((Field ((R.Identity (v_write)))) :: ((Runtime (v_initial)) :: v_tail))))) (v_reversed)))
| (__nat_137, ((Runtime ((I.ProviderExpr (v_identity, v_implementation)))) :: v_tail)) when __nat_137 >= 1 ->
(let v_rest = (__nat_137 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000013l)))) :: ((Field ((R.Identity (v_identity)))) :: ((Runtime (v_implementation)) :: v_tail)))) (v_reversed)))
| (__nat_138, ((Runtime ((I.HandleExpr (v_provider, v_body)))) :: v_tail)) when __nat_138 >= 1 ->
(let v_rest = (__nat_138 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000014l)))) :: ((Runtime (v_provider)) :: ((Runtime (v_body)) :: v_tail)))) (v_reversed)))
| (__nat_139, ((Runtime ((I.InvokeOperationExpr (v_identity, v_argument)))) :: v_tail)) when __nat_139 >= 1 ->
(let v_rest = (__nat_139 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000015l)))) :: ((Field ((R.Identity (v_identity)))) :: ((Runtime (v_argument)) :: v_tail)))) (v_reversed)))
| (__nat_140, ((Runtime ((I.PanicExpr (v_message)))) :: v_tail)) when __nat_140 >= 1 ->
(let v_rest = (__nat_140 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000016l)))) :: ((Field ((R.Text (v_message)))) :: v_tail))) (v_reversed)))
| (__nat_141, ((Runtime ((I.ProductExpr (v_elements)))) :: v_tail)) when __nat_141 >= 1 ->
(let v_rest = (__nat_141 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000017l)))) :: ((Runtimes (v_elements)) :: v_tail))) (v_reversed)))
| (__nat_142, ((Runtime ((I.ProjectExpr (v_value, v_index)))) :: v_tail)) when __nat_142 >= 1 ->
(let v_rest = (__nat_142 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000018l)))) :: ((Runtime (v_value)) :: ((Field ((R.Natural (v_index)))) :: v_tail)))) (v_reversed)))
| (__nat_143, ((Runtime ((I.ArrayExpr (v_elements)))) :: v_tail)) when __nat_143 >= 1 ->
(let v_rest = (__nat_143 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000019l)))) :: ((Runtimes (v_elements)) :: v_tail))) (v_reversed)))
| (__nat_144, ((Runtime ((I.ForExpr (v_index, v_start, v_end, v_state, v_initial, v_body)))) :: v_tail)) when __nat_144 >= 1 ->
(let v_rest = (__nat_144 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000001fl)))) :: ((Field ((R.Text (v_index)))) :: ((Runtime (v_start)) :: ((Runtime (v_end)) :: ((Field ((R.Text (v_state)))) :: ((Runtime (v_initial)) :: ((Runtime (v_body)) :: v_tail)))))))) (v_reversed)))
| (__nat_145, ((Runtime ((I.ForeverExpr (v_state, v_initial, v_body, v_compact)))) :: v_tail)) when __nat_145 >= 1 ->
(let v_rest = (__nat_145 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000022l)))) :: ((Field ((R.Text (v_state)))) :: ((Runtime (v_initial)) :: ((Runtime (v_body)) :: ((f_flag (v_compact)) :: v_tail)))))) (v_reversed)))
| (__nat_146, ((Runtime ((I.ArrayGenerateExpr (v_count, v_generator)))) :: v_tail)) when __nat_146 >= 1 ->
(let v_rest = (__nat_146 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000001el)))) :: ((Runtime (v_count)) :: ((Runtime (v_generator)) :: v_tail)))) (v_reversed)))
| (__nat_147, ((Runtime ((I.ArrayFillExpr (v_count, v_value)))) :: v_tail)) when __nat_147 >= 1 ->
(let v_rest = (__nat_147 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000001dl)))) :: ((Runtime (v_count)) :: ((Runtime (v_value)) :: v_tail)))) (v_reversed)))
| (__nat_148, ((Runtime ((I.ArrayGetExpr (v_array, v_index)))) :: v_tail)) when __nat_148 >= 1 ->
(let v_rest = (__nat_148 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000001al)))) :: ((Runtime (v_array)) :: ((Runtime (v_index)) :: v_tail)))) (v_reversed)))
| (__nat_149, ((Runtime ((I.ArraySetExpr (v_array, v_index, v_value)))) :: v_tail)) when __nat_149 >= 1 ->
(let v_rest = (__nat_149 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000001bl)))) :: ((Runtime (v_array)) :: ((Runtime (v_index)) :: ((Runtime (v_value)) :: v_tail))))) (v_reversed)))
| (__nat_150, ((Runtime ((I.ArrayReuseExpr (v_array, v_index, v_value)))) :: v_tail)) when __nat_150 >= 1 ->
(let v_rest = (__nat_150 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000021l)))) :: ((Runtime (v_array)) :: ((Runtime (v_index)) :: ((Runtime (v_value)) :: v_tail))))) (v_reversed)))
| (__nat_151, ((Runtime ((I.ArrayLengthExpr (v_array)))) :: v_tail)) when __nat_151 >= 1 ->
(let v_rest = (__nat_151 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x0000001cl)))) :: ((Runtime (v_array)) :: v_tail))) (v_reversed)))
| (__nat_152, ((Runtimes ([])) :: v_tail)) when __nat_152 >= 1 ->
(let v_rest = (__nat_152 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_153, ((Runtimes ((v_head :: v_following))) :: v_tail)) when __nat_153 >= 1 ->
(let v_rest = (__nat_153 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Runtime (v_head)) :: ((Runtimes (v_following)) :: v_tail)))) (v_reversed)))
| (__nat_154, ((OptionalRuntime (None)) :: v_tail)) when __nat_154 >= 1 ->
(let v_rest = (__nat_154 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_155, ((OptionalRuntime ((Some (v_value)))) :: v_tail)) when __nat_155 >= 1 ->
(let v_rest = (__nat_155 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Runtime (v_value)) :: v_tail))) (v_reversed)))
| (__nat_156, ((RuntimeArms ([])) :: v_tail)) when __nat_156 >= 1 ->
(let v_rest = (__nat_156 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000000l)))) :: v_tail)) (v_reversed)))
| (__nat_157, ((RuntimeArms (((M.MatchArm (v_patterns, v_body)) :: v_following))) :: v_tail)) when __nat_157 >= 1 ->
(let v_rest = (__nat_157 - 1) in
(f_flatten (v_rest) (((Field ((R.Word (0x00000001l)))) :: ((Field ((R.Patterns (v_patterns)))) :: ((Runtime (v_body)) :: ((RuntimeArms (v_following)) :: v_tail))))) (v_reversed))))
and (* native_cache_keys.bend:415 *)
f_encode_limited : int -> (t_Work) list -> int -> (M.t_Diagnostic, (int32) list) Base.result_ =
fun v_fuel v_pending v_room ->
(match (f_flatten (v_fuel) (v_pending) ([])) with
| Fail __error -> Fail __error
| Done v_fields ->
(R.f_encode_work ((M.f_max_nat ())) (v_fields) (v_room) ([])))
and (* native_cache_keys.bend:420 *)
f_encode : (t_Work) list -> (M.t_Diagnostic, (int32) list) Base.result_ =
fun v_pending ->
(f_encode_limited ((M.f_max_nat ())) (v_pending) ((Base.u32_to_nat (0x01000000l))))
and (* native_cache_keys.bend:423 *)
f_same_go : (int32) list -> (int32) list -> bool -> bool =
fun v_left v_right v_equal ->
(match (v_left, v_right, v_equal) with
| (_, _, false) ->
false
| ([], [], true) ->
true
| ((v_a :: v_xs), (v_b :: v_ys), true) ->
(f_same_go (v_xs) (v_ys) ((Base.u32_is_eq (v_a) (v_b))))
| (_, _, _) ->
false)
and (* native_cache_keys.bend:434 *)
f_same : (int32) list -> (int32) list -> bool =
fun v_left v_right ->
(f_same_go (v_left) (v_right) (true))
and (* native_cache_keys.bend:443 *)
f_compare_cst : int -> (t_CstComparison) list -> bool -> bool =
fun v_fuel v_pending v_equal ->
(match (v_fuel, v_pending, v_equal) with
| (_, _, false) ->
false
| (_, [], true) ->
true
| (0, _, _) ->
false
| (__nat_158, ((NodePair ((C.Cst (v_ak, v_af, v_at, v_ao, v_ac)), (C.Cst (v_bk, v_bf, v_bt, v_bo, v_bc)))) :: v_tail), true) when __nat_158 >= 1 ->
(let v_rest = (__nat_158 - 1) in
(f_compare_cst (v_rest) (((ChildrenPair (v_ac, v_bc)) :: v_tail)) ((Base.bool_and ((Base.bool_and ((M.f_name_equal (v_ak) (v_bk))) ((M.f_name_equal (v_af) (v_bf))))) ((Base.bool_and ((M.f_name_equal (v_at) (v_bt))) ((Base.nat_is_eq (v_ao) (v_bo)))))))))
| (__nat_159, ((ChildrenPair ([], [])) :: v_tail), true) when __nat_159 >= 1 ->
(let v_rest = (__nat_159 - 1) in
(f_compare_cst (v_rest) (v_tail) (true)))
| (__nat_160, ((ChildrenPair ((v_a :: v_xs), (v_b :: v_ys))) :: v_tail), true) when __nat_160 >= 1 ->
(let v_rest = (__nat_160 - 1) in
(f_compare_cst (v_rest) (((NodePair (v_a, v_b)) :: ((ChildrenPair (v_xs, v_ys)) :: v_tail))) (true)))
| (_, _, _) ->
false)
and (* native_cache_keys.bend:460 *)
f_same_cst : C.t_Cst -> C.t_Cst -> bool =
fun v_left v_right ->
(f_compare_cst ((M.f_max_nat ())) ([(NodePair (v_left, v_right))]) (true))
and (* native_cache_keys.bend:463 *)
f_scope : L.t_Context -> (M.t_Diagnostic, (int32) list) Base.result_ =
fun v_context ->
(let (L.Context (v_globals, v_headers, v_fixities, v_locals, v_return_label, v_annotation_variables)) = v_context in
(f_encode ([(Globals ((Base.map_values (v_globals)))); (Headers ((Base.map_values (v_headers)))); (Fixities (v_fixities)); (Locals (v_locals)); (OptionalNatural (v_return_label)); (TypeVariables (v_annotation_variables))])))
and (* native_cache_keys.bend:467 *)
f_module : M.t_Module -> (M.t_Diagnostic, (int32) list) Base.result_ =
fun v_module ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(f_encode ([(Constants (v_constants)); (Functions (v_functions)); (DataTypes (v_types)); (Operations (v_operations))])))
and (* native_cache_keys.bend:473 *)
f_operations : (M.t_Operation) list -> (M.t_Diagnostic, (int32) list) Base.result_ =
fun v_values ->
(f_encode ([(Operations (v_values))]))
and (* native_cache_keys.bend:476 *)
f_group_module : M.t_Module -> (int32) list -> (M.t_Diagnostic, (int32) list) Base.result_ =
fun v_module v_operation_key ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(match (f_encode ([(Constants (v_constants)); (Functions (v_functions)); (DataTypes (v_types))])) with
| Fail __error -> Fail __error
| Done v_body ->
(Done ((Base.list_append (v_body) (v_operation_key))))))
and (* native_cache_keys.bend:482 *)
f_planning : G.t_Planning -> (M.t_Diagnostic, (int32) list) Base.result_ =
fun v_plan ->
(let (G.Planning (v_nodes, v_usages, v_types, v_shared)) = v_plan in
(f_encode ([(DependencyNodes (v_nodes)); (Usages (v_usages)); (TypeDependencies (v_types)); (Identities (v_shared))])))
and (* native_cache_keys.bend:486 *)
f_interfaces : (G.t_Interface) list -> (M.t_Diagnostic, (int32) list) Base.result_ =
fun v_values ->
(f_encode ([(Interfaces (v_values))]))
and (* native_cache_keys.bend:489 *)
f_entry : W.t_CodegenJob -> (M.t_Diagnostic, (int32) list) Base.result_ =
fun v_job ->
(let (W.CodegenJob (v_key, v_parameter, v_body, v_captures)) = v_job in
(f_encode ([(Field ((R.Text (v_key)))); (Field ((R.Text (v_parameter)))); (Runtime (v_body)); (Field ((R.Strings (v_captures))))])))
