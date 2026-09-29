(* Verification bridge, never a substitute for source inference. Canonicalize
   nominal spelling pairs exactly, import a normalized constraint as a DAG,
   and compare satisfiability against the existing solver. No candidate result
   or diagnostic is used to compile the program. *)
module M = Sem_model
module G = Core_levels
let enabled = ref false
(* Installed by the executable before worker startup. Only the transport/main
   domain publishes after joining semantic work. It does not touch stdout. *)
let publish = ref (fun () -> ())

type skipped = Rigid_value | Free_row | Mixed_kind | Resource_limit
exception Skip of skipped
module Names = Hashtbl.Make(struct
  type t = Base.text * Base.text
  let equal (a,b) (c,d) = Base.string_eq a c && Base.string_eq b d
  let hash (a,b) = Core_nodes.mix (Base.text_hash a) (Base.text_hash b)
end)
type input = Value of M.t_Ty | Effect of M.t_EffectRow | Tail of M.t_RowTail
type step = Enter of input | Finish of input * G.tag * input list
type imported = {
  arena : G.t;
  variables : (int, G.kind * G.ty) Hashtbl.t;
  known : ((int * int), G.ty) Hashtbl.t;
  names : int Names.t;
  mutable next_name : int;
}
let key = function
  | Value ty -> 0,M.id_Ty ty
  | Effect row -> 1,M.id_EffectRow row
  | Tail tail -> 2,M.id_RowTail tail
let make () = {arena=G.create ~max_nodes:262144 ~max_work:1048576 ();
  variables=Hashtbl.create 32;known=Hashtbl.create 64;names=Names.create 16;next_name=0}
let nominal state (M.TypeId(_,module_name,declaration)) =
  let key=module_name,declaration in
  match Names.find_opt state.names key with
  | Some id -> id
  | None -> let id=state.next_name in state.next_name<-id+1;Names.add state.names key id;id
let variable state kind index =
  if index<0 then raise(Skip Mixed_kind);
  match Hashtbl.find_opt state.variables index with
  | Some(found,ty) -> if found<>kind then raise(Skip Mixed_kind) else ty
  | None -> let ty=G.fresh state.arena kind ~level:0 in Hashtbl.add state.variables index(kind,ty);ty
let import state roots =
  let todo=ref(List.map(fun input->Enter input)roots) and work=ref 0 in
  let remember input value=Hashtbl.add state.known(key input)value in
  let pending input tag children = todo:=Finish(input,tag,children):: !todo;
    todo:=List.fold_left(fun tail child -> Enter child::tail) !todo (List.rev children) in
  while !todo<>[] do
    incr work;if !work>262144 then raise(Skip Resource_limit);
    let step=List.hd !todo in todo:=List.tl !todo;
    match step with
    | Enter input when Hashtbl.mem state.known(key input) -> ()
    | Enter input ->
      (match input with
       | Value(M.VariableTy(_,_,index)) -> remember input(variable state G.Value index)
       | Value(M.ParameterTy _ | M.FreeTy _) -> raise(Skip Rigid_value)
       | Value ty ->
         let tag,children=match ty with
           | M.UnitTy -> G.Atom G.Unit,[]
           | M.U32Ty -> G.Atom G.U32,[]
           | M.F32Ty -> G.Atom G.F32,[]
           | M.BoolTy -> G.Atom G.Bool,[]
           | M.NeverTy -> G.Atom G.Never,[]
           | M.EffectDescriptorTy -> G.Atom G.Type_descriptor,[]
           | M.EffectSetTy -> G.Atom G.Effect_set,[]
           | M.FunctionTy(_,_,parameter,result,row) -> G.Function,[Value parameter;Value result;Effect row]
           | M.ArrayTy(_,_,element) -> G.Array,[Value element]
           | M.ProductTy(_,_,elements) -> G.Product,List.map(fun ty->Value ty)elements
           | M.AppliedTy(_,_,identity,args) -> G.Nominal(nominal state identity),List.map(fun ty->Value ty)args
           | M.ProviderTy(_,_,identity,row) -> G.Provider(nominal state identity),[Effect row]
           | M.StateProviderTy(_,_,read,write,ty) -> G.State_provider(nominal state read,nominal state write),[Value ty]
           | M.VariableTy _ | M.ParameterTy _ | M.FreeTy _ -> assert false
         in pending input tag children
       | Effect(M.EffectRow(_,labels,tail)) ->
         pending input (G.Row(List.map(nominal state)labels)) [Tail tail]
       | Tail(M.RowVariable(_,index)) -> remember input(variable state G.Effect_row index)
       | Tail(M.RowParameter(_,index)) -> remember input(G.term state.arena (G.Rigid_row index) [])
       | Tail M.ClosedRow -> remember input(G.term state.arena G.Empty_row [])
       | Tail(M.FreeRow _) -> raise(Skip Free_row))
    | Finish(input,tag,children) ->
      let children=List.map(fun input->Hashtbl.find state.known(key input))children in
      let value=match tag,children with G.Row labels,[tail]->G.row state.arena labels tail
        | _ -> G.term state.arena tag children in
      remember input value
  done;
  List.map(fun input->Hashtbl.find state.known(key input))roots

type verdict = Accepted | Rejected of G.error | Not_checked of skipped
let probe left right =
  let state=make() in
  try
    match import state [left;right] with
    | [a;b] -> G.unify state.arena a b;Accepted
    | _ -> assert false
  with
  | Skip why -> Not_checked why
  | G.Error G.Work_limit -> Not_checked Resource_limit
  | G.Error why -> Rejected why

let attempts=Atomic.make 0
let accepted=Atomic.make 0
let rejected=Atomic.make 0
let skipped_rigid=Atomic.make 0
let skipped_free_row=Atomic.make 0
let skipped_kind=Atomic.make 0
let skipped_resource=Atomic.make 0
let skipped_normalization=Atomic.make 0
let mismatches=Atomic.make 0
let count counter=ignore(Atomic.fetch_and_add counter 1)
let note_skip = function
  | Rigid_value -> count skipped_rigid
  | Free_row -> count skipped_free_row
  | Mixed_kind -> count skipped_kind
  | Resource_limit -> count skipped_resource
let normalization_failure () = count attempts;count skipped_normalization
let verify subject expected left right =
  count attempts;
  match expected with
  | Error "type_complexity" -> note_skip Resource_limit
  | _ ->
    match probe left right with
    | Not_checked reason -> note_skip reason
    | verdict ->
      let actual=verdict=Accepted and wanted=Result.is_ok expected in
      if actual<>wanted then begin
        count mismatches;
        failwith(Printf.sprintf "CORE_GRAPH_MISMATCH subject=%S expected=%s graph=%s"
          (Base.text_to_utf8 subject)
          (match expected with Ok()->"accepted"|Error code->code)
          (if actual then "accepted" else "rejected"))
      end;
      count (if actual then accepted else rejected)
let report () =
  Printf.sprintf "{\"attempts\":%d,\"accepted\":%d,\"rejected\":%d,\"skipped_rigid\":%d,\"skipped_free_row\":%d,\"skipped_kind\":%d,\"skipped_resource\":%d,\"skipped_normalization\":%d,\"mismatches\":%d}"
    (Atomic.get attempts)(Atomic.get accepted)(Atomic.get rejected)(Atomic.get skipped_rigid)
    (Atomic.get skipped_free_row)(Atomic.get skipped_kind)(Atomic.get skipped_resource)(Atomic.get skipped_normalization)(Atomic.get mismatches)
