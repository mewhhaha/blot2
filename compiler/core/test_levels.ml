open Core_levels
let checks=ref 0
let check label condition = incr checks; if not condition then failwith label
let expect label predicate action =
  incr checks;
  match action () with
  | _ -> failwith (label ^ ": expected failure")
  | exception error -> if not (predicate error) then raise error
let error expected = function Error actual -> expected=actual | _ -> false
let invalid = function Invalid_argument _ -> true | _ -> false
let unit_ a = term a (Atom Unit) []
let u32 a = term a (Atom U32) []
let bool a = term a (Atom Bool) []
let empty a = term a Empty_row []
let fn a x y r = term a Function [x;y;r]
let array a x = term a Array [x]
let product a xs = term a Product xs
let variable a t k level = match view a t with Variable(k',l) -> k=k' && l=level | _ -> false
let only = function [x] -> x | _ -> failwith "expected one type"
let get_fn a t = match view a t with Structure(Function,[x;y;r]) -> x,y,r | _ -> failwith "expected function"

let basics () =
  let a=create () in
  let u=u32 a and b=bool a and r=empty a in
  List.iter(fun atom -> let x=term a (Atom atom) [] in unify a x x)
    [Unit;U32;F32;Bool;Never;Type_descriptor;Effect_set];
  expect "different atoms" (error Constructor_mismatch) (fun()->unify a u b);
  expect "different kinds" (error Kind_mismatch) (fun()->unify a u r);
  expect "arity" (error Arity_mismatch) (fun()->term a Function [u]);
  expect "child kinds" (error Kind_mismatch) (fun()->term a Function [u;u;u]);
  expect "nominal ids" invalid (fun()->term a (Nominal (-1)) []);
  expect "row ids" invalid (fun()->row a [-1] r);
  List.iter(fun tag ->
    let children=match tag with
      | Nominal _ | Product -> [u;b]
      | Array | State_provider _ -> [u]
      | Provider _ -> [r]
      | Rigid _ | Rigid_row _ -> []
      | _ -> assert false in
    let x=term a tag children and y=term a tag children in
    check "constructor equal" (equivalent a x y);unify a x y)
    [Nominal 42;Product;Array;Provider 9;State_provider(1,2);Rigid 3;Rigid_row 3];
  expect "nominal identity" (error Constructor_mismatch)
    (fun()->unify a (term a (Nominal 1) [u]) (term a (Nominal 2) [u]));
  expect "product arity" (error Arity_mismatch)
    (fun()->unify a (product a [u]) (product a [u;b]));
  let v=fresh a Value ~level:3 in
  unify a (term a (Atom Never) []) v;
  check "bottom does not bind unknown" (variable a v Value 3);
  let recursive=array a v in
  expect "occurs" (error Infinite_type) (fun()->unify a v recursive);
  check "occurs leaves variable" (variable a v Value 3);
  let other=create() in
  expect "foreign handle" invalid (fun()->unify a u (u32 other))

let schemes () =
  let a=create() in
  let x=fresh a Value ~level:1 and effects=fresh a Effect_row ~level:1 in
  let identity=fn a x x effects in
  let s=generalize a ~level:0 [identity] in
  let counts=scheme_statistics s in
  check "generalize values and rows" (counts.quantified_values=1 && counts.quantified_rows=1 && counts.weak_variables=0);
  let first=only(instantiate a ~level:2 s) and second=only(instantiate a ~level:2 s) in
  let xp,yp,rp=get_fn a first and xq,yq,rq=get_fn a second in
  unify a xp (u32 a);unify a xq (bool a);
  check "generic sharing within instance" (equivalent a xp yp && equivalent a xq yq);
  check "distinct instantiations" (not(equivalent a xp xq));
  unify a rp (row a [1] (empty a));unify a rq (row a [2;2] (empty a));
  let outer=fresh a Value ~level:0 and inner=fresh a Value ~level:2 in
  unify a outer (array a inner);
  check "levels lower through structure" (variable a inner Value 0);
  let s=generalize a ~level:1 [outer;inner] in
  check "outer variables not generalized" ((scheme_statistics s).weak_variables=1);
  let roots=instantiate a ~level:2 s in
  unify a inner (u32 a);
  check "weak variable remains shared" (equivalent a (List.nth roots 1) (u32 a));
  let weak=fresh a Value ~level:0 and local=fresh a Value ~level:2 in
  let s=generalize a ~level:0 [product a [weak;local]] in
  expect "weak scheme cannot migrate" invalid (fun()->instantiate (create()) ~level:1 s);
  let predicate=fresh a Value ~level:2 and ambient=fresh a Effect_row ~level:2 in
  protect a ~level:0 [ambient];
  let s=generalize a ~level:0 [u32 a;predicate;ambient;predicate] in
  let stats=scheme_statistics s in
  check "predicate roots and ambient exclusions" (stats.quantified_values=1 && stats.quantified_rows=0 && stats.weak_variables=1);
  let instantiated=instantiate a ~level:1 s in
  check "multiple roots preserve identity" (equivalent a (List.nth instantiated 1) (List.nth instantiated 3));
  let portable=generalize a ~level:(-1) [identity] in
  clear a;
  expect "clear invalidates handles" invalid (fun()->view a identity);
  let new_arena=create() in
  check "fully frozen schemes outlive source arena" (List.length(instantiate new_arena ~level:0 portable)=1)

let snapshots () =
  let a=create() in let x=fresh a Value ~level:3 and u=u32 a in
  let before=(statistics a).active_nodes in
  let outer=checkpoint a in
  let removed=fresh a Value ~level:4 in
  let inner=checkpoint a in unify a x u; commit a inner;
  check "inner commit visible" (equivalent a x u);
  rollback a outer;
  check "outer rollback undoes inner commit" (variable a x Value 3);
  check "allocation rewind" ((statistics a).active_nodes=before);
  let replacement=fresh a Value ~level:4 in
  expect "ABA handle is rejected" invalid (fun()->unify a removed replacement);
  expect "spent checkpoint" invalid (fun()->rollback a outer);
  let outer=checkpoint a in let inner=checkpoint a in
  expect "non-LIFO checkpoint" invalid (fun()->commit a outer);
  let b=create() in expect "foreign checkpoint" invalid (fun()->rollback b inner);
  expect "clear with snapshot" invalid (fun()->clear a);
  rollback a inner;commit a outer;
  let y=fresh a Value ~level:5 and wrong=bool a in
  let left=product a [x;y;u] and right=product a [u;u;wrong] in
  expect "late mismatch" (error Constructor_mismatch) (fun()->unify a left right);
  check "late failure restores both binds" (variable a x Value 3 && variable a y Value 5);
  let outer=checkpoint a in
  let v=Stdlib.Array.init 64(fun _ -> fresh a Value ~level:3) in
  (* Force union-by-rank trees, then compress them under another snapshot. *)
  for round=0 to 5 do
    let step=1 lsl round in
    for i=0 to 63 do if i mod (2*step)=0 then unify a v.(i) v.(i+step) done
  done;
  let compressed=checkpoint a in unify a v.(63) u; ignore(view a v.(47));rollback a compressed;
  check "path compression restores" (variable a v.(47) Value 3);
  rollback a outer;
  let signal=Failure "transaction signal" in
  expect "nested abandoned transaction" (fun e -> e==signal) (fun()->transaction a(fun()->
    ignore(checkpoint a);unify a x u;raise signal));
  check "nested exception rolled back" (variable a x Value 3);
  expect "unclosed successful transaction" invalid (fun()->transaction a(fun()->ignore(checkpoint a);unify a x u));
  check "unclosed success rolled back" (variable a x Value 3);
  let snap=checkpoint a in let weak=fresh a Value ~level:0 in
  let s=generalize a ~level:0 [weak] in rollback a snap;
  let nodes=(statistics a).active_nodes in
  expect "weak scheme with stale handle" invalid (fun()->instantiate a ~level:1 s);
  check "failed instantiation atomic" ((statistics a).active_nodes=nodes)

let rows () =
  let a=create() in
  let closed labels=row a labels (empty a) in
  unify a (closed [1;2;1;3]) (closed [3;1;1;2]);
  check "permuted duplicate rows unify" true;
  expect "multiplicity matters" (error Row_mismatch) (fun()->unify a (closed [1;1]) (closed [1]));
  let r=fresh a Effect_row ~level:3 in
  let row1=row a [1;2] r in
  unify a row1 (closed [2;3;1;3]);
  unify a r (closed [3;3]);check "open row fills residual" true;
  let r=fresh a Effect_row ~level:3 and s=fresh a Effect_row ~level:2 in
  unify a (row a [1] r) (row a [2] s);
  unify a r (closed [2;7;7]);unify a s (closed [1;7;7]);check "open rows share tail" true;
  let r=fresh a Effect_row ~level:2 in
  expect "same tail residual mismatch" (error Row_mismatch) (fun()->unify a (row a [1] r) r);
  check "row failure atomic" (variable a r Effect_row 2);
  (* A row cycle nested inside a function must fail through the value occurs check. *)
  let t=fresh a Value ~level:2 in
  let recursive=fn a (u32 a) t (empty a) in
  expect "function cycle" (error Infinite_type) (fun()->unify a t recursive);
  let rigid=term a (Rigid_row 4) [] in
  let r=fresh a Effect_row ~level:3 in
  unify a (row a [2] r) (row a [2;8] rigid);
  unify a r (row a [8] rigid);check "rigid tail substitution" true;
  expect "rigid tails distinct" (error Row_mismatch)
    (fun()->unify a rigid (term a (Rigid_row 5) []));
  let rng=Random.State.make[|45;23|] in
  for _=1 to 4000 do
    let left=List.init(Random.State.int rng 14)(fun _->Random.State.int rng 6) in
    let right=List.init(Random.State.int rng 14)(fun _->Random.State.int rng 6) in
    let expected=List.sort compare left=List.sort compare right in
    let found=try unify a (closed left) (closed right);true with Error Row_mismatch->false in
    check "multiset row oracle" (found=expected)
  done

(* Independent persistent-substitution oracle. It does not reuse arena code,
   lexical levels, rollback, ranks or frozen scheme representations. *)
type syntax=V of int | C of int | A of syntax | P of syntax list
exception Unsolvable
let rec resolve subst = function
  | V id as original -> (match List.assoc_opt id subst with None->original | Some t->resolve subst t)
  | A x -> A(resolve subst x)
  | P xs -> P(List.map(resolve subst)xs)
  | C _ as x -> x
let rec occurs id = function V v->v=id | C _->false | A t->occurs id t | P ts->List.exists(occurs id)ts
let solve subst left right =
  let rec equations subst = function
    | [] -> subst
    | (left,right)::tail ->
      let a=resolve subst left and b=resolve subst right in
      if a=b then equations subst tail else
      match a,b with
      | V id,t | t,V id -> if occurs id t then raise Unsolvable else equations ((id,t)::subst) tail
      | A a,A b -> equations subst ((a,b)::tail)
      | P xs,P ys when List.length xs=List.length ys -> equations subst (List.combine xs ys @ tail)
      | _ -> raise Unsolvable
  in equations subst [left,right]
let randomized () =
  let rng=Random.State.make[|2048;72|] in
  for _=1 to 2000 do
    let a=create() and subst=ref [] and equations=ref [] in
    let variables=Stdlib.Array.init 12(fun _->fresh a Value ~level:2) in
    let rec make depth =
      let choice=Random.State.int rng (if depth=0 then 2 else 4) in
      match choice with
      | 0 -> V(Random.State.int rng 12)
      | 1 -> C(Random.State.int rng 3)
      | 2 -> A(make (depth-1))
      | _ -> P(List.init(Random.State.int rng 4)(fun _->make(depth-1))) in
    let rec convert = function
      | V id -> variables.(id)
      | C id -> term a (Atom (match id with 0->U32 | 1->Bool | _->F32)) []
      | A t -> array a (convert t)
      | P ts -> product a (List.map convert ts) in
    for _=1 to 24 do
      let left=make 3 and right=make 3 in
      let l=convert left and r=convert right in
      let expected=try Some(solve !subst left right) with Unsolvable -> None in
      let success=try unify a l r;true with Error(Constructor_mismatch|Arity_mismatch|Infinite_type)->false in
      check "independent unifier agreement" (success=Option.is_some expected);
      (match expected with Some next -> subst:=next;equations:=(l,r):: !equations | None -> ());
      List.iter(fun(l,r)->check "accepted equations remain equal" (equivalent a l r)) !equations
    done
  done

let limits_and_shapes () =
  let a=create ~max_nodes:4 () in let u=u32 a in
  let snap=checkpoint a in ignore(array a u);rollback a snap;
  ignore(array a u);ignore(array a u);ignore(array a u);
  expect "node limit" (error Work_limit) (fun()->fresh a Value ~level:0);
  let a=create ~max_work:30 () in
  let x=fresh a Value ~level:3 and y=fresh a Value ~level:0 in
  let deep=ref x in for _=1 to 40 do deep:=array a !deep done;
  let nodes=(statistics a).active_nodes in
  expect "work limit" (error Work_limit) (fun()->unify a y !deep);
  check "work limit preserves nodes" ((statistics a).active_nodes=nodes);
  check "work limit preserves levels" (variable a x Value 3 && variable a y Value 0);
  let a=create() in
  let x=fresh a Value ~level:1 in
  let deep=ref x in for _=1 to 20_000 do deep:=array a !deep done;
  let s=generalize a ~level:0 [!deep] in
  check "deep type frozen stack-safely" ((scheme_statistics s).nodes=20_001);
  let first=only(instantiate a ~level:1 s) and second=only(instantiate a ~level:1 s) in
  unify a first second;
  check "deep instances unify stack-safely" (equivalent a first second);
  let a=create() in let x=fresh a Value ~level:1 in
  let dag=ref x in for _=1 to 30 do dag:=product a [!dag;!dag] done;
  let s=generalize a ~level:0 [!dag] in
  check "DAG freeze does not expand a tree" ((scheme_statistics s).nodes=31);
  let before=(statistics a).allocations in
  let instance=only(instantiate a ~level:2 s) in
  check "DAG instantiate linear allocation" ((statistics a).allocations-before=31);
  unify a instance !dag;
  check "DAG unification linear work" ((statistics a).equations<=61)

let parallel () =
  let work id =
    let a=create() in
    for _=1 to 2000 do
      clear a;
      let x=fresh a Value ~level:1 in
      let s=generalize a ~level:0 [array a x] in
      let y=only(instantiate a ~level:2 s) in
      unify a y (array a (term a (Nominal id) []))
    done; true
  in
  let workers=List.init 4(fun i->Domain.spawn(fun()->work i)) in
  List.iter(fun job->check "independent worker arenas" (Domain.join job))workers
let () =
  Printexc.record_backtrace true;
  basics();schemes();snapshots();rows();randomized();limits_and_shapes();parallel();
  Printf.printf "%d type-graph checks passed\n%!" !checks
