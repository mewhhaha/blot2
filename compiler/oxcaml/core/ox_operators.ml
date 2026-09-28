(* Native semantic port of compiler/operators.bend.

   Source SHA-256: e1b5d834876d36094988872f59e991ac017307913844bec21373c97f7ef7a857

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module C = Ox_cst

type t_Associativity =
  | Left
  | Right
  | NonAssociative
and t_Fixity =
  | Fixity of Base.text * bool * Base.word32 * t_Associativity * M.t_Expr
and t_Operator =
  | Operator of Base.word32 * t_Associativity * M.t_Expr * int
and t_Tail =
  | Tail of t_Operator * M.t_Expr
and t_Decision =
  | Push
  | Reduce
  | Conflict
and t_Work =
  | Read of (t_Tail) list
  | Insert of t_Decision * t_Operator * M.t_Expr * (t_Tail) list
  | Finish

let s_0 = Base.text_of_utf8 "infixl"

let s_1 = Base.text_of_utf8 "infixr"

let s_2 = Base.text_of_utf8 "internal_cst"

let s_3 = Base.text_of_utf8 "parser"

let s_4 = Base.text_of_utf8 "operator chain exhausted its work bound"

let s_5 = Base.text_of_utf8 "operator_associativity"

let s_6 = Base.text_of_utf8 "offset:"

let s_7 = Base.text_of_utf8 "operators at equal precedence need compatible associativity or explicit parentheses"

let s_8 = Base.text_of_utf8 "invalid operator stack"

let rec (* operators.bend:29 *)
f_parse_associativity : Base.text -> t_Associativity =
fun v_name ->
(Base.bool_pick ((M.f_name_equal (v_name) (s_0))) (Left) ((Base.bool_pick ((M.f_name_equal (v_name) (s_1))) (Right) (NonAssociative))))
and (* operators.bend:33 *)
f_same_direction : t_Associativity -> t_Associativity -> bool =
fun v_left v_right ->
(match (v_left, v_right) with
| (Left, Left) ->
true
| (Right, Right) ->
true
| (_, _) ->
false)
and (* operators.bend:42 *)
f_equal_decision : t_Associativity -> bool -> t_Decision =
fun v_association v_compatible ->
(match (v_association, v_compatible) with
| (Left, true) ->
Reduce
| (Right, true) ->
Push
| (_, _) ->
Conflict)
and (* operators.bend:51 *)
f_decision : t_Operator -> (t_Operator) list -> t_Decision =
fun v_operator v_stack ->
(match (v_operator, v_stack) with
| (_, []) ->
Push
| ((Operator (v_precedence, v_association, v_target, v_offset)), ((Operator (v_top_precedence, v_top_association, v_top_target, v_top_offset)) :: v_rest)) ->
(Base.bool_pick ((Base.u32_is_lt (v_top_precedence) (v_precedence))) (Push) ((Base.bool_pick ((Base.u32_is_lt (v_precedence) (v_top_precedence))) (Reduce) ((f_equal_decision (v_association) ((f_same_direction (v_association) (v_top_association)))))))))
and (* operators.bend:59 *)
f_invoke : M.t_Expr -> M.t_Expr -> M.t_Expr =
fun v_callee v_argument ->
(match v_callee with
| (M.FunctionExpr (v_name)) ->
(M.CallExpr (v_name, v_argument))
| (M.InstantiationExpr (v_site, (M.FunctionExpr (v_name)))) ->
(M.InstantiationExpr (v_site, (M.CallExpr (v_name, v_argument))))
| (M.SourceExpr (v_offset, v_annotation, (M.InstantiationExpr (v_site, (M.FunctionExpr (v_name)))))) ->
(M.SourceExpr (v_offset, v_annotation, (M.InstantiationExpr (v_site, (M.CallExpr (v_name, v_argument))))))
| v_value ->
(M.ApplyExpr (v_value, v_argument)))
and (* operators.bend:70 *)
f_reduce : t_Operator -> M.t_Expr -> M.t_Expr -> M.t_Expr =
fun v_operator v_left v_right ->
(let (Operator (v_precedence, v_associativity, v_target, v_offset)) = v_operator in
(let v_base = (Base.nat_mul (v_offset) (16)) in
(M.SourceExpr (v_offset, None, (M.InstantiationExpr ((Base.nat_add (v_base) (5)), (M.ApplyExpr ((M.InstantiationExpr ((Base.nat_add (v_base) (4)), (f_invoke (v_target) (v_left)))), v_right))))))))
and (* operators.bend:75 *)
f_resolve : int -> t_Work -> (M.t_Expr) list -> (t_Operator) list -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_fuel v_work v_values v_operators ->
(match v_fuel with
| 0 ->
(Fail ((M.Diagnostic (s_2, s_3, s_4))))
| __nat_1 when __nat_1 >= 1 ->
(let v_remaining = (__nat_1 - 1) in
(match (v_work, v_values, v_operators) with
| ((Read ([])), v_values, v_operators) ->
(f_resolve (v_remaining) (Finish) (v_values) (v_operators))
| ((Read (((Tail (v_operator, v_right)) :: v_rest))), v_values, v_operators) ->
(f_resolve (v_remaining) ((Insert ((f_decision (v_operator) (v_operators)), v_operator, v_right, v_rest))) (v_values) (v_operators))
| ((Insert (Push, v_operator, v_right, v_rest)), v_values, v_operators) ->
(f_resolve (v_remaining) ((Read (v_rest))) ((v_right :: v_values)) ((v_operator :: v_operators)))
| ((Insert (Conflict, (Operator (v_precedence, v_association, v_target, v_offset)), v_right, v_rest)), v_values, v_operators) ->
(Fail ((M.Diagnostic (s_5, (Base.string_append s_6 (Base.nat_show (v_offset))), s_7))))
| ((Insert (Reduce, v_operator, v_right, v_rest)), (v_previous_right :: (v_previous_left :: v_values)), (v_top :: v_operators)) ->
(f_resolve (v_remaining) ((Insert ((f_decision (v_operator) (v_operators)), v_operator, v_right, v_rest))) (((f_reduce (v_top) (v_previous_left) (v_previous_right)) :: v_values)) (v_operators))
| (Finish, (v_value :: []), []) ->
(Done (v_value))
| (Finish, (v_right :: (v_left :: v_values)), (v_top :: v_operators)) ->
(f_resolve (v_remaining) (Finish) (((f_reduce (v_top) (v_left) (v_right)) :: v_values)) (v_operators))
| (_, _, _) ->
(Fail ((M.Diagnostic (s_2, s_3, s_8)))))))
and (* operators.bend:98 *)
f_same_bool : bool -> bool -> bool =
fun v_left v_right ->
(match (v_left, v_right) with
| (true, true) ->
true
| (false, false) ->
true
| (_, _) ->
false)
and (* operators.bend:107 *)
f_lookup : (t_Fixity) list -> Base.text -> bool -> (t_Fixity) option =
fun v_fixities v_name v_named ->
(match v_fixities with
| [] ->
None
| ((Fixity (v_spelling, v_is_named, v_precedence, v_association, v_target)) :: v_rest) ->
(Base.bool_pick ((Base.bool_and ((M.f_name_equal (v_spelling) (v_name))) ((f_same_bool (v_is_named) (v_named))))) ((Some ((Fixity (v_spelling, v_is_named, v_precedence, v_association, v_target))))) ((f_lookup (v_rest) (v_name) (v_named)))))
and (* operators.bend:114 *)
f_from_fixity : t_Fixity -> int -> t_Operator =
fun v_fixity v_offset ->
(let (Fixity (v_name, v_named, v_precedence, v_associativity, v_target)) = v_fixity in
(Operator (v_precedence, v_associativity, v_target, v_offset)))
