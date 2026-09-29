(* Experimental checking kernel, not yet the source compiler's default solver.
   Task-local type graphs. No mutable cell escapes through the sealed API.
   Links, level changes and path compression participate in nested rollback.
   A frozen scheme may be moved to another arena only without weak variables. *)
module Arena : sig
  type kind = Value | Effect_row
  type atom = Unit | U32 | F32 | Bool | Never | Type_descriptor | Effect_set
  type tag =
    | Atom of atom | Function | Array | Product | Nominal of int
    | Provider of int | State_provider of int * int | Rigid of int
    | Row of int list | Empty_row | Rigid_row of int
  type error = Kind_mismatch | Constructor_mismatch | Arity_mismatch
             | Infinite_type | Infinite_row | Row_mismatch | Work_limit
  exception Error of error
  type t
  type ty
  type checkpoint
  type scheme
  type view = Variable of kind * int | Structure of tag * ty list
  type statistics = {
    allocations : int; active_nodes : int; equations : int; find_steps : int;
    occurs_visits : int; level_lowerings : int; rollbacks : int;
  }
  type scheme_statistics = {
    nodes : int; quantified_values : int; quantified_rows : int; weak_variables : int;
  }
  val create : ?max_nodes:int -> ?max_work:int -> unit -> t
  val fresh : t -> kind -> level:int -> ty
  val term : t -> tag -> ty list -> ty
  val row : t -> int list -> ty -> ty
  val checkpoint : t -> checkpoint
  val commit : t -> checkpoint -> unit
  val rollback : t -> checkpoint -> unit
  val transaction : t -> (unit -> 'a) -> 'a
  val clear : t -> unit
  val view : t -> ty -> view
  val unify : t -> ty -> ty -> unit
  val protect : t -> level:int -> ty list -> unit
  val generalize : t -> level:int -> ty list -> scheme
  val instantiate : t -> level:int -> scheme -> ty list
  (* Representation equality after following links. Row-label order is not
     normalized here; use unification for scoped-row semantic comparison. *)
  val equivalent : t -> ty -> ty -> bool
  val statistics : t -> statistics
  val scheme_statistics : scheme -> scheme_statistics
end = struct
  type kind = Value | Effect_row
  type atom = Unit | U32 | F32 | Bool | Never | Type_descriptor | Effect_set
  type tag =
    | Atom of atom | Function | Array | Product | Nominal of int
    | Provider of int | State_provider of int * int | Rigid of int
    | Row of int list | Empty_row | Rigid_row of int
  type error = Kind_mismatch | Constructor_mismatch | Arity_mismatch
             | Infinite_type | Infinite_row | Row_mismatch | Work_limit
  exception Error of error
  type ty = { owner : unit ref; index : int; generation : int; kind : kind }
  type description = Var of int * int | Link of ty | Term of tag * ty array
  type slot = { generation : int; mutable description : description }
  type checkpoint = { owner : unit ref; serial : int; trail_size : int; node_count : int }
  type undo = int * description
  type t = {
    owner : unit ref; mutable slots : slot option array; mutable size : int;
    mutable generation : int; mutable serial : int; max_nodes : int; max_work : int;
    mutable trail : undo list; mutable trail_size : int; mutable checkpoints : checkpoint list;
    mutable allocations : int; mutable equations : int; mutable find_steps : int;
    mutable occurs_visits : int; mutable level_lowerings : int; mutable rollbacks : int;
  }
  type view = Variable of kind * int | Structure of tag * ty list
  type frozen_node = Generic of kind * int | Weak of ty | Frozen of tag * int array
  type scheme = {
    owner : unit ref; nodes : frozen_node array; roots : int list;
    value_count : int; row_count : int; weak_count : int;
  }
  type statistics = {
    allocations : int; active_nodes : int; equations : int; find_steps : int;
    occurs_visits : int; level_lowerings : int; rollbacks : int;
  }
  type scheme_statistics = {
    nodes : int; quantified_values : int; quantified_rows : int; weak_variables : int;
  }
  let create ?(max_nodes=1_048_576) ?(max_work=1_048_576) () =
    if max_nodes < 1 || max_work < 1 then invalid_arg "type arena limits must be positive";
    {owner=ref ();slots=Stdlib.Array.make (min 64 max_nodes) None;size=0;generation=0;serial=0;
     max_nodes;max_work;trail=[];trail_size=0;checkpoints=[];allocations=0;equations=0;
     find_steps=0;occurs_visits=0;level_lowerings=0;rollbacks=0}
  let check_level level = if level < 0 then invalid_arg "negative inference level"
  let slot (arena:t) (ty:ty) =
    if ty.owner != arena.owner || ty.index < 0 || ty.index >= arena.size then
      invalid_arg "foreign or invalidated type handle";
    match arena.slots.(ty.index) with
    | Some slot when slot.generation = ty.generation -> slot
    | _ -> invalid_arg "invalidated type handle"
  let allocate (arena:t) kind description =
    if arena.size >= arena.max_nodes || arena.generation = max_int then raise(Error Work_limit);
    if arena.size = Stdlib.Array.length arena.slots then begin
      let growth = if arena.size > arena.max_nodes / 2 then arena.max_nodes else 2 * arena.size in
      let capacity = min arena.max_nodes (max (arena.size+1) growth) in
      let slots = Stdlib.Array.make capacity None in
      Stdlib.Array.blit arena.slots 0 slots 0 arena.size; arena.slots <- slots
    end;
    let index=arena.size and generation=arena.generation in
    arena.generation <- generation+1; arena.size <- index+1;
    arena.allocations <- arena.allocations+1;
    arena.slots.(index) <- Some {generation;description};
    {owner=arena.owner;index;generation;kind}
  let fresh arena kind ~level = check_level level; allocate arena kind (Var(level,0))
  let tag_kind = function Row _ | Empty_row | Rigid_row _ -> Effect_row | _ -> Value
  let expect_kind kind (ty:ty) = if ty.kind <> kind then raise(Error Kind_mismatch)
  let term arena tag children =
    if List.length children > arena.max_work then raise(Error Work_limit);
    (match tag with
     | Nominal id | Provider id | Rigid id | Rigid_row id when id<0 -> invalid_arg "negative semantic identity"
     | State_provider(a,b) when a<0 || b<0 -> invalid_arg "negative semantic identity"
     | Row labels when List.length labels > arena.max_work -> raise(Error Work_limit)
     | Row labels when List.exists(fun id -> id<0) labels -> invalid_arg "negative semantic identity"
     | _ -> ());
    List.iter (fun ty -> ignore(slot arena ty)) children;
    let expected = match tag,children with
      | Function,[_;_;_] -> [Value;Value;Effect_row]
      | (Array | State_provider _),[_] -> [Value]
      | Provider _,[_] | Row _,[_] -> [Effect_row]
      | (Product | Nominal _),_ -> List.map (fun _ -> Value) children
      | (Atom _ | Rigid _ | Empty_row | Rigid_row _),[] -> []
      | _ -> raise(Error Arity_mismatch)
    in
    List.iter2 expect_kind expected children;
    allocate arena (tag_kind tag) (Term(tag,Stdlib.Array.of_list children))
  let row arena labels tail =
    ignore(slot arena tail); expect_kind Effect_row tail;
    if labels=[] then tail else term arena (Row labels) [tail]
  let checkpoint (arena:t) =
    if arena.serial=max_int then raise(Error Work_limit);
    let token={owner=arena.owner;serial=arena.serial;trail_size=arena.trail_size;node_count=arena.size} in
    arena.serial <- arena.serial+1; arena.checkpoints <- token::arena.checkpoints; token
  let check_checkpoint (arena:t) (token:checkpoint) =
    match arena.checkpoints with
    | top::rest when token.owner==arena.owner && top.serial=token.serial -> rest
    | _ -> invalid_arg "checkpoint must be active, local and innermost"
  let commit (arena:t) token =
    let rest=check_checkpoint arena token in
    arena.checkpoints <- rest;
    if rest=[] then (arena.trail<-[];arena.trail_size<-0)
  let rollback (arena:t) token =
    let rest=check_checkpoint arena token in
    while arena.trail_size > token.trail_size do
      match arena.trail with
      | (index,description)::tail ->
        (match arena.slots.(index) with Some slot -> slot.description<-description | None -> assert false);
        arena.trail <- tail; arena.trail_size <- arena.trail_size-1
      | [] -> assert false
    done;
    for index=token.node_count to arena.size-1 do arena.slots.(index)<-None done;
    arena.size<-token.node_count; arena.checkpoints<-rest; arena.rollbacks<-arena.rollbacks+1;
    if rest=[] then (arena.trail<-[];arena.trail_size<-0)
  let transaction arena body =
    let token=checkpoint arena in
    try
      let answer=body () in commit arena token; answer
    with error ->
      let trace=Printexc.get_raw_backtrace () in
      (* An abandoned nested checkpoint must not hide the original exception
         or leave the transaction partially applied. Successful callbacks must
         close their explicit inner checkpoints. *)
      let rec unwind () = match arena.checkpoints with
        | top::_ when top.serial<>token.serial -> rollback arena top; unwind ()
        | _ -> rollback arena token
      in
      unwind (); Printexc.raise_with_backtrace error trace
  let clear (arena:t) =
    if arena.checkpoints<>[] then invalid_arg "cannot clear an arena with active checkpoints";
    for index=0 to arena.size-1 do arena.slots.(index)<-None done;
    arena.size<-0; arena.trail<-[]; arena.trail_size<-0
  let write (arena:t) ty description =
    let target=slot arena ty in
    if arena.checkpoints<>[] then begin
      arena.trail<-(ty.index,target.description)::arena.trail;arena.trail_size<-arena.trail_size+1
    end;
    target.description<-description
  let tick work = if !work=0 then raise(Error Work_limit) else decr work
  let repr (arena:t) work start =
    let current=ref start and path=ref [] and searching=ref true in
    while !searching do
      tick work; arena.find_steps<-arena.find_steps+1;
      match (slot arena !current).description with
      | Link parent -> path:= !current :: !path; current:=parent
      | _ -> searching:=false
    done;
    let root= !current in
    List.iter(fun ty -> match (slot arena ty).description with
      | Link parent when parent.index<>root.index -> write arena ty (Link root)
      | _ -> ()) !path;
    root
  let view arena ty =
    let root=repr arena (ref arena.max_work) ty in
    match (slot arena root).description with
    | Var(level,_) -> Variable(root.kind,level)
    | Term(tag,children) -> Structure(tag,Stdlib.Array.to_list children)
    | Link _ -> assert false
  let lower arena work ~level ~occurs roots =
    let seen=Hashtbl.create 32 and pending=ref roots in
    while !pending<>[] do
      let ty=List.hd !pending in pending:=List.tl !pending;
      let root=repr arena work ty in
      if Some root.index=occurs then
        raise(Error(if root.kind=Effect_row then Infinite_row else Infinite_type));
      if not(Hashtbl.mem seen root.index) then begin
        Hashtbl.add seen root.index (); arena.occurs_visits<-arena.occurs_visits+1;
        match (slot arena root).description with
        | Var(previous,rank) when previous>level ->
          write arena root (Var(level,rank));arena.level_lowerings<-arena.level_lowerings+1
        | Term(_,children) ->
          for index=Stdlib.Array.length children-1 downto 0 do pending:=children.(index):: !pending done
        | Var _ -> ()
        | Link _ -> assert false
      end
    done
  let protect arena ~level roots =
    check_level level;
    transaction arena (fun () -> lower arena (ref arena.max_work) ~level ~occurs:None roots)
  let bind arena work variable target =
    expect_kind variable.kind target;
    match (slot arena variable).description,(slot arena target).description with
    | Var(level,rank),Var(other,other_rank) ->
      let chosen,old,new_rank =
        if rank>other_rank || (rank=other_rank && variable.index<target.index)
        then variable,target,(if rank=other_rank then rank+1 else rank)
        else target,variable,(if rank=other_rank then other_rank+1 else other_rank)
      in
      let minimum=min level other in
      write arena chosen (Var(minimum,new_rank));write arena old (Link chosen)
    | Var(level,_),_ ->
      lower arena work ~level ~occurs:(Some variable.index) [target];
      write arena variable (Link target)
    | _ -> invalid_arg "binding a nonvariable"
  let flatten_row arena work start =
    let labels=ref [] and current=ref start and more=ref true in
    while !more do
      let root=repr arena work !current in current:=root;
      match (slot arena root).description with
      | Term(Row prefix,children) ->
        List.iter(fun _ -> tick work) prefix;
        labels:=List.rev_append prefix !labels;current:=children.(0)
      | _ -> more:=false
    done;
    List.rev !labels,!current
  let cancel_labels work left right =
    let counts=Hashtbl.create 16 in
    List.iter(fun label -> tick work;Hashtbl.replace counts label
      (1+Option.value(Hashtbl.find_opt counts label)~default:0)) right;
    let left_only=List.filter(fun label ->
      tick work;
      let count=Option.value(Hashtbl.find_opt counts label)~default:0 in
      if count=0 then true else (Hashtbl.replace counts label (count-1);false)) left
    in
    (* Consume in reverse to preserve exactly the uncancelled suffix witnesses
       when a label occurs several times. Labels themselves are immutable IDs. *)
    let right_only=List.fold_left(fun rest label ->
      tick work;
      let count=Option.value(Hashtbl.find_opt counts label)~default:0 in
      if count=0 then rest else (Hashtbl.replace counts label(count-1);label::rest)) [] (List.rev right)
    in left_only,right_only
  let same_root a b = a.index=b.index && a.generation=b.generation
  let is_variable arena ty = match (slot arena ty).description with Var _ -> true | _ -> false
  let variable_level arena ty = match (slot arena ty).description with Var(level,_) -> level | _ -> assert false
  let unify_rows arena work left right =
    let ls,lt=flatten_row arena work left in
    let rs,rt=flatten_row arena work right in
    let ls,rs=cancel_labels work ls rs in
    if same_root lt rt then begin
      if ls<>[] || rs<>[] then raise(Error(if is_variable arena lt then Infinite_row else Row_mismatch))
    end else
    match is_variable arena lt,is_variable arena rt with
    | true,true when ls=[] && rs=[] -> bind arena work lt rt
    | true,true ->
      let level=min(variable_level arena lt)(variable_level arena rt) in
      let shared=fresh arena Effect_row ~level in
      bind arena work lt (row arena rs shared);
      bind arena work rt (row arena ls shared)
    | true,false ->
      if ls<>[] then raise(Error Row_mismatch);
      bind arena work lt (row arena rs rt)
    | false,true ->
      if rs<>[] then raise(Error Row_mismatch);
      bind arena work rt (row arena ls lt)
    | false,false ->
      let tags_equal=match (slot arena lt).description,(slot arena rt).description with
        | Term(a,_),Term(b,_) -> a=b | _ -> false in
      if not tags_equal || ls<>[] || rs<>[] then raise(Error Row_mismatch)
  let unify arena left right = transaction arena (fun () ->
    let work=ref arena.max_work and pending=ref [left,right] and seen=Hashtbl.create 32 in
    while !pending<>[] do
      let left,right=List.hd !pending in pending:=List.tl !pending;
      let a=repr arena work left in let b=repr arena work right in
      arena.equations<-arena.equations+1;expect_kind a.kind b;
      if not(same_root a b) then begin
        let key=if a.index<b.index then a.index,b.index else b.index,a.index in
        if not(Hashtbl.mem seen key) then begin
          Hashtbl.add seen key ();
          if a.kind=Effect_row then unify_rows arena work a b else
          match (slot arena a).description,(slot arena b).description with
          | Term(Atom Never,_),_ | _,Term(Atom Never,_) -> ()
          | Var _,_ -> bind arena work a b
          | _,Var _ -> bind arena work b a
          | Term(at,ac),Term(bt,bc) ->
            if at<>bt then raise(Error Constructor_mismatch);
            if Stdlib.Array.length ac<>Stdlib.Array.length bc then raise(Error Arity_mismatch);
            for index=Stdlib.Array.length ac-1 downto 0 do pending:=(ac.(index),bc.(index)):: !pending done
          | _ -> assert false
        end
      end
    done)
  type freeze_work = Enter of ty | Finish of ty * tag * ty array
  let generalize arena ~level roots =
    if level < -1 then invalid_arg "invalid generalization level";
    let work=ref arena.max_work and known=Hashtbl.create 64 and pending=ref(List.map(fun x->Enter x) roots) in
    let reversed=ref [] and length=ref 0 and values=ref 0 and rows=ref 0 and weak=ref 0 in
    let save root node = Hashtbl.add known root.index !length;incr length;reversed:=node:: !reversed in
    while !pending<>[] do
      let step=List.hd !pending in pending:=List.tl !pending;
      match step with
      | Enter ty ->
        let root=repr arena work ty in
        if not(Hashtbl.mem known root.index) then begin
          match (slot arena root).description with
          | Var(at,_) when at>level ->
            let index= !values+ !rows in
            if root.kind=Value then incr values else incr rows;
            save root (Generic(root.kind,index))
          | Var _ -> incr weak;save root (Weak root)
          | Term(tag,children) ->
            pending:=Finish(root,tag,children):: !pending;
            for index=Stdlib.Array.length children-1 downto 0 do pending:=Enter children.(index):: !pending done
          | Link _ -> assert false
        end
      | Finish(root,tag,children) ->
        let indices=Stdlib.Array.map(fun ty -> Hashtbl.find known (repr arena work ty).index) children in
        save root (Frozen(tag,indices))
    done;
    {owner=arena.owner;nodes=Stdlib.Array.of_list(List.rev !reversed);
     roots=List.map(fun ty -> Hashtbl.find known (repr arena work ty).index) roots;
     value_count= !values;row_count= !rows;weak_count= !weak}
  let instantiate (arena:t) ~level (scheme:scheme) =
    check_level level;
    if scheme.weak_count>0 && arena.owner!=scheme.owner then invalid_arg "weak scheme belongs to another arena";
    transaction arena (fun () ->
      if Stdlib.Array.length scheme.nodes > arena.max_work then raise(Error Work_limit);
      let work=ref arena.max_work in
      let result=Stdlib.Array.make (Stdlib.Array.length scheme.nodes) None in
      let get index=match result.(index) with Some ty -> ty | None -> assert false in
      Stdlib.Array.iteri(fun index node ->
        tick work;
        let ty=match node with
        | Generic(kind,_) -> fresh arena kind ~level
        | Weak ty -> ignore(slot arena ty);ty
        | Frozen(tag,children) ->
          let count=Stdlib.Array.length children in
          if count> !work then raise(Error Work_limit);
          work:= !work-count;
          term arena tag (Stdlib.Array.to_list(Stdlib.Array.map get children))
        in result.(index)<-Some ty) scheme.nodes;
      List.map get scheme.roots)
  let equivalent arena left right =
    let work=ref arena.max_work and pending=ref[left,right] and equal=ref true and seen=Hashtbl.create 32 in
    while !equal && !pending<>[] do
      let left,right=List.hd !pending in pending:=List.tl !pending;
      let a=repr arena work left in let b=repr arena work right in
      if a.kind<>b.kind then equal:=false else
      if not(same_root a b) && not(Hashtbl.mem seen (a.index,b.index)) then begin
        Hashtbl.add seen (a.index,b.index) ();
        match (slot arena a).description,(slot arena b).description with
        | Term(at,ac),Term(bt,bc) when at=bt && Stdlib.Array.length ac=Stdlib.Array.length bc ->
          for index=Stdlib.Array.length ac-1 downto 0 do pending:=(ac.(index),bc.(index)):: !pending done
        | _ -> equal:=false
      end
    done; !equal
  let statistics (arena:t) : statistics =
    {allocations=arena.allocations;active_nodes=arena.size;equations=arena.equations;
     find_steps=arena.find_steps;occurs_visits=arena.occurs_visits;
     level_lowerings=arena.level_lowerings;rollbacks=arena.rollbacks}
  let scheme_statistics (scheme:scheme) : scheme_statistics =
    {nodes=Stdlib.Array.length scheme.nodes;quantified_values=scheme.value_count;
     quantified_rows=scheme.row_count;weak_variables=scheme.weak_count}
end
include Arena
