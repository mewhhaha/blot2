(* Differential checks use the actual semantic model and independently built
   reference functions. They compare constraint satisfiability, not only a toy
   surface language. Legacy rigid/free forms are explicitly outside this bridge. *)
module M=Sem_model
module T=Sem_types
module R=Sem_effect_rows
module V=Core_graph_verify
let checks=ref 0
let check name ok = incr checks;if not ok then failwith name
let text=Base.text_of_utf8
let identity n=M.make_TypeId (text "test") (text(string_of_int n))
let row labels tail = M.make_EffectRow(List.map identity labels)tail
let rv index=M.make_RowVariable index
let tv index=M.make_VariableTy index
let accepted = function Base.Done _ -> true | Base.Fail _ -> false
let agrees name answer = function
  | V.Accepted -> check name answer
  | V.Rejected _ -> check name(not answer)
  | V.Not_checked _ -> failwith(name^": unexpected skip")
let () =
  let rng=Random.State.make[|101;52|] in
  for _=1 to 6000 do
    let labels ()=List.init(Random.State.int rng 8)(fun _->Random.State.int rng 4) in
    let tail ()=match Random.State.int rng 5 with
      | 0 -> M.ClosedRow
      | 1 -> M.make_RowParameter(Random.State.int rng 3)
      | _ -> rv(Random.State.int rng 6) in
    let left=row(labels())(tail()) and right=row(labels())(tail()) in
    let expected=R.f_unify left right [] 100 (text "row oracle") in
    agrees "reference effect-row agreement" (accepted expected) (V.probe (V.Effect left) (V.Effect right))
  done;
  let rec make depth =
    match Random.State.int rng (if depth=0 then 8 else 14) with
    | 0 -> M.UnitTy | 1 -> M.U32Ty | 2 -> M.F32Ty | 3 -> M.BoolTy
    | 4 -> M.EffectDescriptorTy | 5 -> M.EffectSetTy | 6 -> M.NeverTy
    | 7 -> tv(Random.State.int rng 8)
    | 8 -> M.make_ArrayTy(make(depth-1))
    | 9 -> M.make_ProductTy(List.init(Random.State.int rng 4)(fun _->make(depth-1)))
    | 10 -> M.make_AppliedTy(identity(Random.State.int rng 3))(List.init(Random.State.int rng 3)(fun _->make(depth-1)))
    | 11 -> M.make_ProviderTy(identity(Random.State.int rng 3))(make_row())
    | 12 -> M.make_StateProviderTy(identity 1)(identity 2)(make(depth-1))
    | _ -> M.make_FunctionTy(make(depth-1))(make(depth-1))(make_row())
  and make_row ()=row(List.init(Random.State.int rng 4)(fun _->Random.State.int rng 4))
    (if Random.State.bool rng then M.ClosedRow else rv(8+Random.State.int rng 4))
  in
  for _=1 to 10000 do
    let left=make 4 and right=make 4 in
    let expected=T.f_unify_at_reference left right (T.f_empty()) 100 (text "type oracle") in
    agrees "reference type agreement" (accepted expected) (V.probe(V.Value left)(V.Value right))
  done;
  (* Prior immutable substitution versions normalize first. Do not treat
     historical replacement lists as unification equations. *)
  let snapshots=[
    [];
    [T.Substitution(0,tv 1)];
    [T.Substitution(0,tv 1);T.Substitution(1,M.U32Ty)];
    [T.Substitution(0,M.U32Ty);T.Substitution(0,M.BoolTy)];
    [T.RowSubstitution(8,row[1](rv 9));T.RowSubstitution(9,row[2]M.ClosedRow)];
  ] in
  for _=1 to 2000 do
    let left=make 3 and right=make 3 in
    List.iter(fun history ->
      let subs=T.f_from_list history in
      match T.f_resolve subs left,T.f_resolve subs right with
      | Base.Done a,Base.Done b ->
        let expected=T.f_unify_at_reference left right subs 100 (text "snapshot oracle") in
        agrees "normalized historical snapshot agreement" (accepted expected) (V.probe(V.Value a)(V.Value b))
      | _ -> failwith "unexpected snapshot resolution failure") snapshots
  done;
  let param=M.make_ParameterTy 1 in
  check "parameter form explicitly not checked"
    (V.probe(V.Value param)(V.Value param)=V.Not_checked V.Rigid_value);
  let free=row [] (M.make_FreeRow(text "scope")(text "effect")) in
  check "free row explicitly not checked"
    (V.probe(V.Effect free)(V.Effect free)=V.Not_checked V.Free_row);
  let mixed=M.make_FunctionTy(tv 1)M.U32Ty(row[](rv 1)) in
  check "mixed kind index explicitly not checked"
    (V.probe(V.Value mixed)(V.Value mixed)=V.Not_checked V.Mixed_kind);
  (* Same nominal text is still identical with interning deliberately disabled. *)
  let original= !Core_nodes.enabled in Core_nodes.enabled:=false;
  let a=M.make_AppliedTy(identity 9)[M.U32Ty] and b=M.make_AppliedTy(identity 9)[M.U32Ty] in
  Core_nodes.enabled:=original;
  check "nominal content witnesses" (V.probe(V.Value a)(V.Value b)=V.Accepted);
  let raised=try
    V.verify (text "injected disagreement") (Error "type_mismatch") (V.Value M.U32Ty)(V.Value M.U32Ty);false
    with Failure message -> String.starts_with ~prefix:"CORE_GRAPH_MISMATCH" message in
  check "disagreements fail hard" raised;
  check "disagreements have independent accounting" (Atomic.get V.mismatches=1);
  Printf.printf "%d semantic-model graph comparisons passed\n%!" !checks
