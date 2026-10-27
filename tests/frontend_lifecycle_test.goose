import src.fingerprint;
import src.frontend;
import src.plan;
import src.validate;
import os;
fn frontend_planned(source: const u8[:], accepted: bool, code: u32) {
    with_core() { b =>
        var work = Work { .. }; var diagnostics: Diagnostic[>..] = [];
        let ok = frontend_complete(source, "frontend_lifecycle", b, work, diagnostics);
        if accepted {
            for d in diagnostics { print("unexpected frontend diagnostic ", d.code, " ", name_bytes(core_view(b), d.detail)); }
            if !ok { print(source); } assert(ok); let planned = build_plans(b, "", diagnostics); if !planned { for d in diagnostics { print("planning ", d.code, " ", d.origin, " ", d.related); } } assert(planned); assert(canonical_schemas(b, diagnostics)); assert(seal_completion(b)); var validation = Work { .. }; let valid = validator::validate_core(core_view(b), 0, validation, diagnostics); if !valid { for d in diagnostics { print("validation ", d.code, " ", d.origin, " ", d.related); } print(source); } assert(valid);
        } else { if ok || diagnostics.len == 0 || diagnostics[0].code != code { print("negative expected ", code, " got ", diagnostics, " source ", source); for d in diagnostics { print(name_bytes(core_view(b), d.detail)); } } assert(!ok); assert(diagnostics.len != 0); assert(diagnostics[0].code == code); }
    }
}
fn test_frontend_lifecycle_scopes() {
    frontend_planned("let bad: (forall [T:Type] => T -> T ! {} resources {depth:1,frame:0}) -> Unit ! {} resources {depth:1,frame:0} = fn callback => return ()\n", false, FE_UNSUPPORTED);
    for path in ["examples/region_unit.blot", "examples/owned_unit.blot", "examples/singleton.blot", "examples/closure.blot", "examples/generic_callback.blot"] {
        var source: u8[>..] = []; assert(read_file(path, source)); frontend_planned(source, true, 0);
    }
    frontend_planned("let bad: Unit -> Result[Unit,ReserveError] ! {reserve,release}\n= fn () => return region@[Unit](0) as r (owner,free) in do:\n  space.end(free)\n  break ()\n", false, FE_OWNERSHIP);
    frontend_planned("type P[r:Region] = Unit\nlet bad: Unit -> Unit ! {reserve,release} = fn () => do:\n  let unused = owned@[P[_],Unit](0) as r free in do:\n    return ()\n  return ()\n", false, FE_TARGET);
    frontend_planned("let bad: forall [r:Region] => Space[r] -> Unit ! {} resources {depth:2,frame:1024} = fn s => do:\n  let f = fn (x:Unit) => return s\n  return ()\n", false, FE_CAPTURE);
}
fn test_frontend_affine_control() {
    frontend_planned("let branch: forall [r:Region] => (Bool,Space[r]) -> Unit ! {} resources {depth:1,frame:1024} = fn (flag,s) => do:\n  if flag:\n    space.end(s)\n  else:\n    space.end(s)\n  return ()\n", true, 0);
    frontend_planned("let branch: forall [r:Region] => (Bool,Space[r]) -> Unit ! {} resources {depth:1,frame:1024} = fn (flag,s) => do:\n  if flag:\n    space.end(s)\n  return ()\n", false, FE_OWNERSHIP);
    frontend_planned("let branch: forall [r:Region] => (Bool,Space[r]) -> Unit ! {} resources {depth:1,frame:1024} = fn (flag,s) => do:\n  let x = do:\n    if flag:\n      break 1\n    break 2\n  space.end(s)\n  return ()\n", true, 0);
}
fn test_frontend_checked_and_scalar_control() {
    frontend_planned("pub let f: (U32,U32) -> U32 ! {} resources {depth:1,frame:1024} = fn (a,b) => do:\n  case U32.try_add(a,b):\n    #Ok(value) => return a+b\n    #Err(()) => return 0\n", true, 0);
    frontend_planned("pub let f: (U32,U32) -> Bool ! {} resources {depth:1,frame:1024} = fn (a,b) => return U32.fits_add(a,b) && a+b>0\n", true, 0);
    frontend_planned("pub let f: U32 -> U32 ! {} resources {depth:1,frame:1024} = fn x => do:\n  case x:\n    0 => return 9\n    1 => return 8\n    _ => return 7\n", true, 0);
    frontend_planned("pub let f: Bool -> U32 ! {} resources {depth:1,frame:1024} = fn x => do:\n  case x:\n    #True => return 9\n    #False => return 8\n", true, 0);
}
fn test_frontend_storage_transitions() {
    var reset: u8[>..] = []; assert(read_file("examples/region_reset.blot", reset)); frontend_planned(reset, true, 0);
    frontend_planned("let split: forall [r:Region,c:Nat] => Dest[r,U32,c] -> Unit ! {} requires [Le(1,c)] resources {depth:1,frame:1024} = fn target => do:\n  let (left,right) = dest.split(target,1)\n  dest.discard(left)\n  dest.discard(right)\n  return ()\n", true, 0);
    frontend_planned("let shorten: forall [r:Region] => Builder[r,U32,2,4,Resize] -> U32 ! {read r,write r} resources {depth:1,frame:1024} = fn initial => do:\n  let shorter = builder.truncate(initial,1)\n  let value = shorter[0]\n  builder.discard(shorter)\n  return value\n", true, 0);
    frontend_planned("let read: forall [r:Region,n:Nat,d:Domain] => (View[r,U32,n,d],U32) -> Option[U32] ! {read r} resources {depth:1,frame:1024} = fn (values,i) => return view.try_read(values,i)\n", true, 0);
    frontend_planned("let read: forall [r:Region,n:Nat,d:Domain] => (View[r,U32,n,d],Index[d,n]) -> U32 ! {read r} resources {depth:1,frame:1024} = fn (values,i) => return values[i.value]\n", true, 0);
    frontend_planned("pub let divide: (U32,U32) -> U32 ! {} resources {depth:1,frame:256} = fn (x,y) => do:\n  if !(y==0):\n    return x/y\n  return 0\n", true, 0);
}
fn test_frontend_static_and_capture_laws() {
    for path in ["examples/static.blot", "examples/static_loop.blot", "examples/static_pattern.blot", "examples/static_closure.blot", "examples/guarded_closure.blot", "examples/nested_closure.blot", "examples/owned_closure.blot"] { var source: u8[>..] = []; assert(read_file(path, source)); frontend_planned(source, true, 0); }
    frontend_planned("pub let run: Unit -> U32 ! {} resources {depth:1,frame:128} = fn () => do:\n  static let x = 19\n  static let y = x+23\n  return y\n", true, 0);
    frontend_planned("let bad: U32 -> U32 = fn x => do:\n  static let y = x\n  return y\n", false, FE_STATIC_LIMIT);
    frontend_planned("let bad = fn (x:U32) => return fn (y:U32) => return U32.wrapping_add(x,y)\n", false, FE_LIFETIME);
    frontend_planned("pub let discard: (Fn[static,Once,Unit,Unit] ! {} resources {depth:1,frame:0}) -> Unit ! {} resources {depth:1,frame:64} = fn f => do:\n  let _ = f\n  return ()\n", true, 0);
    frontend_planned("pub let equal: (Bool,Bool) -> Bool ! {} resources {depth:1,frame:64} = fn (a,b) => return a==b\n", true, 0);
    frontend_planned("pub let difference: (U32,U32) -> U32 ! {} resources {depth:1,frame:64} = fn (a,b) => do:\n  if !U32.fits_sub(a,b):\n    return b-a\n  return 0\n", true, 0);
}

fn test_frontend_f32_pattern_laws() {
    frontend_planned("pub let sign: F32 -> U32 ! {} resources {depth:1,frame:128} = fn x => do:\n  case x:\n    -1.0 => return 1\n    -0.0 => return 2\n    _ => return 3\n", true, 0);
    frontend_planned("pub let sign: F32 -> U32 ! {} resources {depth:1,frame:128} = fn x => do:\n  case x:\n    -0.0 => return 1\n    0.0 => return 2\n    _ => return 3\n", false, FE_CASE);
}
fn test_frontend_local_type_aliases() {
    frontend_planned("pub let run: U32 -> U32 ! {} resources {depth:1,frame:256} = fn value => do:\n  type Pair[T:Type] where [Share(T)] = (T,T)\n  let pair: Pair[U32] = (value,value)\n  type Number = U32\n  let result: Number = pair.0\n  return result\n", true, 0);
    frontend_planned("let bad: Unit -> Unit = fn () => do:\n  type Recursive = (U32,Recursive)\n  return ()\n", false, FE_RECURSION);
    frontend_planned("let bad: Unit -> Unit = fn () => do:\n  let x = do:\n    type Number = U32\n    break 1\n  let y: Number = x\n  return ()\n", false, FE_UNBOUND);
    frontend_planned("type Pair[T:Type] = (T,T)\nlet bad: Pair -> Unit = fn p => return ()\n", false, FE_KIND);
}
fn test_frontend_short_circuit_proofs() {
    var source: u8[>..] = []; assert(read_file("examples/short_circuit.blot", source)); frontend_planned(source, true, 0);
    frontend_planned("let bad: (U32,U32) -> U32 = fn (x,y) => do:\n  if x<100 || y<100:\n    return x+1\n  return 0\n", false, FE_ARITHMETIC);
    frontend_planned("let bad: (U32,U32) -> U32 = fn (x,y) => do:\n  if !(x<100 && y<100):\n    return x+1\n  return 0\n", false, FE_ARITHMETIC);
}
fn test_frontend_finite_reachability() {
    frontend_planned("pub let literal: U32 -> U32 ! {} resources {depth:1,frame:128} = fn value => do:\n  if #True:\n    return value\n", true, 0);
    frontend_planned("pub let bounds: U32 -> U32 ! {} resources {depth:1,frame:128} = fn value => do:\n  if value<0:\n    let invalid = value+4294967295\n  else:\n    return value\n", true, 0);
    frontend_planned("pub let contradictory: U32 -> U32 ! {} resources {depth:1,frame:128} = fn value => do:\n  if value<10:\n    if value>=10:\n      let invalid = value+4294967295\n    else:\n      return value\n  else:\n    return value\n", true, 0);
    frontend_planned("pub let skipped: U32 -> Bool ! {} resources {depth:1,frame:128} = fn value => return #False && value+1>0\n", true, 0);
    frontend_planned("let missing: U32 -> U32 = fn value => do:\n  if value<10:\n    return value\n", false, FE_RETURN);
    frontend_planned("let both: forall [r:Region] => (Bool,Space[r]) -> Unit ! {} resources {depth:1,frame:128} = fn (condition,input) => do:\n  let token = input\n  if condition:\n    space.end(token)\n    return ()\n  else:\n    space.end(token)\n    return ()\n", true, 0);
}
