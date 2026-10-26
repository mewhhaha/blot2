import tests.frontend_lifecycle_test;
fn frontend_category_law(source: const u8[:], category: const u8[:]) {
    with_core() { b => var work = Work { .. }; var ds: Diagnostic[>..] = []; var ok = frontend_complete(source, "source-conformance", b, work, ds); if ok { ok = build_plans(b, "", ds); } if ok { ok = canonical_schemas(b, ds); } if ok { assert(seal_completion(b)); var validation = Work { .. }; ok = validator::validate_core(core_view(b), 0, validation, ds); }
        var found = false; for d in ds { let name = if d.code < 2000 { frontend_diagnostic_name(d.code) } else if d.code < 3000 { validator::validator_diagnostic_name(d.code) } else { integration_diagnostic_name(d.code) }; if name == category { assert(id_ok(d.origin, b.origins.len)); let location = b.origins[d.origin]; assert(location.start < location.end && location.end <= source.len); found = true; } }
        if ok || !found { print("expected ", category, " got ", ds, "\n", source); for d in ds { print(d.code, " ", name_bytes(core_view(b), d.detail)); } } assert(!ok && found);
    }
}
fn test_frontend_exec_bounds_laws() {
    let signature = "let read: forall [r:Region,n:Nat,d:Domain] => (View[r,U32,n,d],U32) -> U32 ! {read r} resources {depth:2,frame:1024} = fn (a,i) => do:\n";
    frontend_planned(str(signature, "  if i>=a.length:\n    return 0\n  return a[i]\n"), true, 0); // BND-A02
    frontend_planned(str(signature, "  if i<a.length:\n    return view.read(a,i)\n  return 0\n"), true, 0);
    frontend_category_law(str(signature, "  return view.read(a,i)\n"), "k1_bounds_not_established");
    frontend_planned("let read: forall [r:Region,n:Nat,d:Domain] => (View[r,U32,n,d],Index[d,n]) -> U32 ! {read r} resources {depth:1,frame:1024} = fn (values,position) => return view.read(values,position)\n", true, 0);
    frontend_category_law(str(signature, "  return a[i]\n"), "k1_bounds_not_established"); // BND-R01
    frontend_category_law(str(signature, "  if a.length<10 && i<10:\n    return a[i]\n  return 0\n"), "k1_bounds_not_established"); // BND-R02, including n=3,i=7,N=10
    frontend_category_law(str(signature, "  if i<a.length:\n    let _ = a[i]\n  return a[i]\n"), "k1_bounds_not_established"); // BND-R03
    frontend_category_law(str("let looks_safe: (U32,U32) -> Bool ! {} resources {depth:1,frame:0} = fn (length,position) => return position<length\n", signature, "  if looks_safe(a.length,i):\n    return a[i]\n  return 0\n"), "k1_bounds_not_established"); // BND-R04
    frontend_category_law(str(signature, "  if i<a.length:\n    return open view.slice(a,0,0) as [short] shortened in do:\n      break shortened[i]\n  return 0\n"), "k1_bounds_not_established"); // BND-R05
    frontend_category_law("let bad: forall [r:Region] => (Builder[r,U32,0,10,Resize],U32) -> U32 ! {read r} resources {depth:1,frame:1024} = fn (b,i) => do:\n  if i<b.capacity:\n    let value = b[i]\n    builder.discard(b)\n    return value\n  builder.discard(b)\n  return 0\n", "k1_bounds_not_established"); // BND-R06
}
fn test_frontend_exec_usage_and_closure_laws() {
    frontend_category_law("let bad: U32 -> U32 = fn value => do:\n  let wrapped = U32.wrapping_add(value,1)\n  if wrapped<100:\n    return value+1\n  return 0\n", "k1_arithmetic_not_established"); // NUM-A02 no wrapping monotonicity
    frontend_category_law("type One[r:Region] = exists [d:Domain] => View[r,U32,1,d]\nlet bad: forall [r:Region] => One[r] -> Unit = fn package => do:\n  let escaped = open package as [d] values in do:\n    break values\n  return ()\n", "k1_lifetime_escape"); // DOM-R02
    frontend_category_law("let bad: forall [r:Region] => Dest[r,U32,1] -> Unit = fn target => do:\n  dest.discard(target)\n  dest.discard(target)\n  return ()\n", "k1_use_after_move"); // MEM-R02
    frontend_category_law("let bad: (Fn[static,Once,Unit,Unit] ! {} resources {depth:1,frame:0}) -> Unit ! {} resources {depth:2,frame:256} = fn callback => do:\n  callback(())\n  callback(())\n  return ()\n", "k1_use_after_move"); // FN-R02
    frontend_category_law("let copy: forall [T:Type] => T -> (T,T) ! {} resources {depth:1,frame:1024} = fn value => return (value,value)\n", "k1_usage_not_permitted"); // GEN-R01
    frontend_category_law("let drop: forall [T:Type] => T -> Unit ! {} resources {depth:1,frame:1024} = fn value => do:\n  let _ = value\n  return ()\n", "k1_usage_not_permitted");
    frontend_category_law("let bad: Unit -> U32 = fn () => do:\n  let escaped = do:\n    let seed = 1\n    break fn (u:Unit) => return seed\n  return escaped(())\n", "k1_lifetime_escape"); // FN-R06 block activation
    frontend_category_law("let bad: Unit -> U32 = fn () => do:\n  let callback = for i in 0..1 carry (f = fn (u:Unit) => return 0) do:\n    next (fn (u:Unit) => return i)\n  return callback(())\n", "k1_lifetime_escape"); // FN-R06 loop activation
    frontend_category_law("let bad: (Fn[static,Many,Unit,Unit] ! {}) -> Unit ! {} resources {depth:2,frame:256} = fn callback => do:\n  callback(())\n  return ()\n", "k1_resource_bound"); // FN-R04 incomplete callback resources
    frontend_category_law("let bad: (Fn[static,Many,Unit,Unit] ! {} resources {depth:2,frame:128}) -> Unit ! {} resources {depth:2,frame:128} = fn callback => do:\n  callback(())\n  return ()\n", "k1_resource_bound"); // FN-R04 insufficient call depth
}
fn test_frontend_exec_owned_and_loan_laws() {
    frontend_category_law("let bad: Owned[Owned[Unit]] -> Unit ! {release} = fn handle => do:\n  owned.close(handle)\n  return ()\n", "k1_invalid_owned_payload"); // OWN-R01 nested backing
    frontend_category_law("let bad: Owned[Fn[_,Once,Unit,Unit] ! {} resources {depth:1,frame:0}] -> Unit ! {release} = fn handle => do:\n  owned.close(handle)\n  return ()\n", "k1_invalid_owned_payload"); // OWN-R01 affine callback
    frontend_category_law("let bad: forall [r:Region] => Owned[Fn[r,Many,Unit,Unit] ! {} resources {depth:1,frame:0}] -> Unit ! {release} = fn handle => do:\n  owned.close(handle)\n  return ()\n", "k1_invalid_owned_payload"); // OWN-R01 foreign captured environment
    frontend_category_law("type P[r:Region] = Unit\nlet bad: Owned[P[_]] -> Unit ! {release} = fn handle => do:\n  let moved = handle\n  owned.close(handle)\n  owned.close(moved)\n  return ()\n", "k1_use_after_move"); // OWN-R02
    frontend_category_law("type P[r:Region] = Unit\nlet bad: Owned[P[_]] -> Unit ! {release} = fn handle => do:\n  let result = owned.open(handle) as r payload in do:\n    owned.close(handle)\n    break ()\n  return ()\n", "k1_loan_conflict"); // MEM-R03 active Owned loan
    frontend_category_law("let bad: forall [r:Region,n:Nat,d:Domain] => (RegionOwner[r],View[r,U32,n,d]) -> U32 ! {read r,release} requires [Lt(0,n)] resources {depth:4,frame:4096} = fn (owner,values) => do:\n  region.close(owner)\n  return values[0]\n", "k1_loan_conflict"); // MEM-R03 close with live view
    frontend_category_law("let bad: forall [r:Region,n:Nat,d:Domain] => (RegionOwner[r],View[r,U32,n,d]) -> U32 ! {read r,reset r,release} requires [Lt(0,n)] resources {depth:4,frame:4096} = fn (owner,values) => do:\n  let (fresh,free) = region.reset(owner)\n  let value = values[0]\n  space.end(free)\n  region.close(fresh)\n  return value\n", "k1_loan_conflict");
}

fn test_frontend_collection_transition_bounds() {
    frontend_category_law("let bad: forall [r:Region,d:Domain] => View[r,U32,0,d] -> Unit = fn values => do:\n  let _ = view.slice(values,1,0)\n  return ()\n", "k1_bounds_not_established");
    frontend_category_law("let bad: forall [r:Region] => Builder[r,U32,0,1,Resize] -> Unit ! {write r} = fn initial => do:\n  let changed = builder.set(initial,0,1)\n  builder.discard(changed)\n  return ()\n", "k1_bounds_not_established");
    frontend_category_law("let bad: forall [r:Region] => Dest[r,U32,0] -> Unit = fn target => do:\n  let (left,right) = dest.split(target,1)\n  dest.discard(left)\n  dest.discard(right)\n  return ()\n", "k1_bounds_not_established");
    frontend_category_law("let bad: forall [r:Region] => Dest[r,U32,0] -> Unit ! {write r} = fn target => do:\n  let _ = array.in(target,#[1])\n  return ()\n", "k1_bounds_not_established");
}
