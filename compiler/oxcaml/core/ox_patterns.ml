(* Native semantic port of compiler/patterns.bend.

   Source SHA-256: 319193e2fe1bc84ebb56b4c14b0e5e397a85e551c942dd0fbbd6abd8a7f8d724

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module T = Ox_types

module D = Ox_type_data

module I = Ox_infer

type t_Head =
  | UnitHead
  | BoolHead of bool
  | ConstructorHead of Base.text * bool
  | ProductHead of int
  | DefaultHead
and t_Work =
  | Cover of (M.t_Ty) list * ((M.t_Pattern) list) list
  | Check of bool * (M.t_Ty) list * ((M.t_Pattern) list) list
  | DataCases of (M.t_DataType) option * (M.t_Ty) list * (M.t_Ty) list * ((M.t_Pattern) list) list
  | Constructors of (M.t_Constructor) list * (M.t_Ty) list * (M.t_Ty) list * ((M.t_Pattern) list) list

let s_0 = Base.text_of_utf8 "pattern_complexity"

let s_1 = Base.text_of_utf8 "inference"

let s_2 = Base.text_of_utf8 "pattern coverage exceeds compiler traversal limit"

let s_3 = Base.text_of_utf8 "internal_error"

let s_4 = Base.text_of_utf8 "coverage references an unknown data type"

let s_5 = Base.text_of_utf8 ""

let s_6 = Base.text_of_utf8 ", "

let s_7 = Base.text_of_utf8 "non_exhaustive_match"

let s_8 = Base.text_of_utf8 "pattern rows do not cover every value of ("

let s_9 = Base.text_of_utf8 ")"

let s_10 = Base.text_of_utf8 "value_pattern_type"

let s_11 = Base.text_of_utf8 "value patterns require U32 or Bool; annotate an otherwise unconstrained parameter"

let rec (* patterns.bend:7 *)
f_wildcard_row : (M.t_Pattern) list -> bool =
fun v_patterns ->
(match v_patterns with
| [] ->
true
| (M.WildcardPattern :: v_tail) ->
(f_wildcard_row (v_tail))
| ((M.BindingPattern (v_name)) :: v_tail) ->
(f_wildcard_row (v_tail))
| (v_other :: v_tail) ->
false)
and (* patterns.bend:18 *)
f_has_wildcard_row_work : ((M.t_Pattern) list) list -> bool -> bool =
fun v_rows v_found ->
(match (v_rows, v_found) with
| (_, true) ->
true
| ([], false) ->
false
| ((v_row :: v_tail), false) ->
(f_has_wildcard_row_work (v_tail) ((f_wildcard_row (v_row)))))
and (* patterns.bend:27 *)
f_has_wildcard_row : ((M.t_Pattern) list) list -> bool =
fun v_rows ->
(f_has_wildcard_row_work (v_rows) (false))
and (* patterns.bend:30 *)
f_has_never_column : (M.t_Ty) list -> bool =
fun v_types ->
(match v_types with
| [] ->
false
| (M.NeverTy :: v_tail) ->
true
| (v_other :: v_tail) ->
(f_has_never_column (v_tail)))
and (* patterns.bend:46 *)
f_wildcard_fields : int -> (M.t_Pattern) list -> (M.t_Pattern) list =
fun v_count v_tail ->
(match v_count with
| 0 ->
v_tail
| __nat_1 when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(f_wildcard_fields (v_rest) ((M.WildcardPattern :: v_tail)))))
and (* patterns.bend:53 *)
f_select_head : t_Head -> M.t_Pattern -> (M.t_Pattern) list -> ((M.t_Pattern) list) option =
fun v_head v_pattern v_remaining ->
(match (v_head, v_pattern) with
| ((ConstructorHead (v_name, true)), M.WildcardPattern) ->
(Some ((M.WildcardPattern :: v_remaining)))
| ((ConstructorHead (v_name, true)), (M.BindingPattern (v_binding))) ->
(Some ((M.WildcardPattern :: v_remaining)))
| ((ProductHead (v_arity)), M.WildcardPattern) ->
(Some ((f_wildcard_fields (v_arity) (v_remaining))))
| ((ProductHead (v_arity)), (M.BindingPattern (v_binding))) ->
(Some ((f_wildcard_fields (v_arity) (v_remaining))))
| (_, M.WildcardPattern) ->
(Some (v_remaining))
| (_, (M.BindingPattern (v_name))) ->
(Some (v_remaining))
| (UnitHead, M.UnitPattern) ->
(Some (v_remaining))
| ((BoolHead (v_a)), (M.BoolPattern (v_b))) ->
(Base.bool_pick ((Base.bool_not ((Base.bool_xor (v_a) (v_b))))) ((Some (v_remaining))) (None))
| ((ConstructorHead (v_name, false)), (M.ConstructorPattern (v_found, None))) ->
(Base.bool_pick ((M.f_name_equal (v_name) (v_found))) ((Some (v_remaining))) (None))
| ((ConstructorHead (v_name, true)), (M.ConstructorPattern (v_found, (Some (v_payload))))) ->
(Base.bool_pick ((M.f_name_equal (v_name) (v_found))) ((Some ((v_payload :: v_remaining)))) (None))
| ((ProductHead (v_arity)), (M.ProductPattern (v_elements))) ->
(Base.bool_pick ((Base.nat_is_eq (v_arity) ((Base.list_length (v_elements))))) ((Some ((Base.list_reverse_go ((Base.list_reverse (v_elements))) (v_remaining))))) (None))
| (_, _) ->
None)
and (* patterns.bend:80 *)
f_add_selected : ((M.t_Pattern) list) option -> ((M.t_Pattern) list) list -> ((M.t_Pattern) list) list =
fun v_selected v_rows ->
(match v_selected with
| None ->
v_rows
| (Some (v_row)) ->
(v_row :: v_rows))
and (* patterns.bend:87 *)
f_specialize : ((M.t_Pattern) list) list -> t_Head -> ((M.t_Pattern) list) list =
fun v_rows v_head ->
(match v_rows with
| [] ->
[]
| ([] :: v_tail) ->
(f_specialize (v_tail) (v_head))
| ((v_pattern :: v_remaining) :: v_tail) ->
(f_add_selected ((f_select_head (v_head) (v_pattern) (v_remaining))) ((f_specialize (v_tail) (v_head)))))
and (* patterns.bend:104 *)
f_coverage : int -> t_Work -> (M.t_DataType) list -> (M.t_Diagnostic, bool) Base.result_ =
fun v_fuel v_work v_types ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_0, s_1, s_2))))
| (__nat_2, (Cover (v_inferred, v_rows))) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_coverage (v_rest) ((Check ((Base.bool_or ((f_has_never_column (v_inferred))) ((f_has_wildcard_row (v_rows)))), v_inferred, v_rows))) (v_types)))
| (__nat_3, (Check (true, v_inferred, v_rows))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(Done (true)))
| (__nat_4, (Check (false, (M.NeverTy :: v_remaining), v_rows))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(Done (true)))
| (__nat_5, (Check (false, v_inferred, []))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(Done (false)))
| (__nat_6, (Check (false, [], v_rows))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(Done (false)))
| (__nat_7, (Check (false, (M.BoolTy :: v_remaining), v_rows))) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(match (f_coverage (v_rest) ((Cover (v_remaining, (f_specialize (v_rows) ((BoolHead (true))))))) (v_types)) with
| Fail __error -> Fail __error
| Done v_yes ->
(match (f_coverage (v_rest) ((Cover (v_remaining, (f_specialize (v_rows) ((BoolHead (false))))))) (v_types)) with
| Fail __error -> Fail __error
| Done v_no ->
(Done ((Base.bool_and (v_yes) (v_no)))))))
| (__nat_8, (Check (false, (M.UnitTy :: v_remaining), v_rows))) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(f_coverage (v_rest) ((Cover (v_remaining, (f_specialize (v_rows) (UnitHead))))) (v_types)))
| (__nat_9, (Check (false, ((M.AppliedTy (v_identity, v_arguments)) :: v_remaining), v_rows))) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(f_coverage (v_rest) ((DataCases ((D.f_lookup (v_types) (v_identity)), v_arguments, v_remaining, v_rows))) (v_types)))
| (__nat_10, (Check (false, ((M.ProductTy (v_elements)) :: v_remaining), v_rows))) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(f_coverage (v_rest) ((Cover ((Base.list_reverse_go ((Base.list_reverse (v_elements))) (v_remaining)), (f_specialize (v_rows) ((ProductHead ((Base.list_length (v_elements))))))))) (v_types)))
| (__nat_11, (Check (false, (v_other :: v_remaining), v_rows))) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(f_coverage (v_rest) ((Cover (v_remaining, (f_specialize (v_rows) (DefaultHead))))) (v_types)))
| (__nat_12, (DataCases (None, v_arguments, v_remaining, v_rows))) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(Fail ((M.Diagnostic (s_3, s_1, s_4)))))
| (__nat_13, (DataCases ((Some ((M.DataType (v_identity, v_count, v_constructors)))), v_arguments, v_remaining, v_rows))) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(f_coverage (v_rest) ((Constructors (v_constructors, v_arguments, v_remaining, v_rows))) (v_types)))
| (__nat_14, (Constructors ([], v_arguments, v_remaining, v_rows))) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(Done (true)))
| (__nat_15, (Constructors (((M.Constructor (v_name, None, v_fields)) :: v_tail), v_arguments, v_remaining, v_rows))) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(match (f_coverage (v_rest) ((Cover (v_remaining, (f_specialize (v_rows) ((ConstructorHead (v_name, false))))))) (v_types)) with
| Fail __error -> Fail __error
| Done v_current ->
(match (f_coverage (v_rest) ((Constructors (v_tail, v_arguments, v_remaining, v_rows))) (v_types)) with
| Fail __error -> Fail __error
| Done v_following ->
(Done ((Base.bool_and (v_current) (v_following)))))))
| (__nat_16, (Constructors (((M.Constructor (v_name, (Some (v_payload)), v_fields)) :: v_tail), v_arguments, v_remaining, v_rows))) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(match (T.f_parameters (v_arguments) (0) (v_payload)) with
| Fail __error -> Fail __error
| Done v_ty ->
(match (f_coverage (v_rest) ((Cover ((v_ty :: v_remaining), (f_specialize (v_rows) ((ConstructorHead (v_name, true))))))) (v_types)) with
| Fail __error -> Fail __error
| Done v_current ->
(match (f_coverage (v_rest) ((Constructors (v_tail, v_arguments, v_remaining, v_rows))) (v_types)) with
| Fail __error -> Fail __error
| Done v_following ->
(Done ((Base.bool_and (v_current) (v_following)))))))))
and (* patterns.bend:150 *)
f_types_show : (M.t_Ty) list -> Base.text =
fun v_types ->
(match v_types with
| [] ->
s_5
| (v_head :: []) ->
(M.f_type_show (v_head))
| (v_head :: (v_next :: v_tail)) ->
(Base.string_append (M.f_type_show (v_head)) (Base.string_append s_6 (f_types_show ((v_next :: v_tail))))))
and (* patterns.bend:159 *)
f_require : bool -> (M.t_Ty) list -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_complete v_types v_subject ->
(match v_complete with
| true ->
(Done (()))
| false ->
(Fail ((M.Diagnostic (s_7, v_subject, (Base.string_append s_8 (Base.string_append (f_types_show (v_types)) s_9)))))))
and (* patterns.bend:166 *)
f_value_pattern_type : M.t_Ty -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_ty v_subject ->
(match v_ty with
| M.U32Ty ->
(Done (()))
| M.BoolTy ->
(Done (()))
| _ ->
(Fail ((M.Diagnostic (s_10, v_subject, s_11)))))
and (* patterns.bend:175 *)
f_check : (I.t_Coverage) list -> T.t_Substitutions -> (M.t_DataType) list -> (M.t_Diagnostic, unit) Base.result_ =
fun v_constraints v_substitutions v_types ->
(match v_constraints with
| [] ->
(Done (()))
| ((I.OperationNeed (v_identity, v_template, v_arguments, v_function_type, v_subject)) :: v_tail) ->
(f_check (v_tail) (v_substitutions) (v_types))
| ((I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient, v_subject)) :: v_tail) ->
(f_check (v_tail) (v_substitutions) (v_types))
| ((I.LetGeneralized (v_witness)) :: v_tail) ->
(f_check (v_tail) (v_substitutions) (v_types))
| ((I.QualifiedBoundary (v_offset, v_declared, v_subject)) :: v_tail) ->
(f_check (v_tail) (v_substitutions) (v_types))
| ((I.QualifiedNeed (v_site, v_predicate, v_subject)) :: v_tail) ->
(f_check (v_tail) (v_substitutions) (v_types))
| ((I.ValuePatternType (v_inferred, v_subject)) :: v_tail) ->
(match (T.f_resolve (v_substitutions) (v_inferred)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (f_value_pattern_type (v_resolved) (v_subject)) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_check (v_tail) (v_substitutions) (v_types))))
| ((I.Coverage (v_inferred, v_patterns, v_subject)) :: v_tail) ->
(match (T.f_resolve_work (v_substitutions) ((Base.u32_to_nat ((Base.W32 0x10000)))) ((T.ManyTypes (v_inferred)))) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (f_coverage ((Base.u32_to_nat ((Base.W32 0x10000)))) ((Cover (v_resolved, v_patterns))) (v_types)) with
| Fail __error -> Fail __error
| Done v_complete ->
(match (f_require (v_complete) (v_resolved) (v_subject)) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_check (v_tail) (v_substitutions) (v_types))))))
