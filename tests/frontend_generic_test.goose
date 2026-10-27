import tests.frontend_lifecycle_test;
fn test_frontend_local_forall_boundaries() {
    frontend_planned("let run: U32 -> U32 = fn value => do:\n  let identity: forall [T:Type] => Fn[local,Many,T,T] ! {} resources {depth:1,frame:256} = fn input => return input\n  return identity@[U32](value)\n", true, 0);
    for path in ["examples/local_generic.blot", "examples/local_generic_capture.blot", "examples/local_generic_ambient.blot", "examples/local_generic_nat.blot"] { var source: u8[>..] = []; assert(read_file(path, source)); frontend_planned(source, true, 0); }
    frontend_planned("pub let run: U32 -> U32 ! {} resources {depth:1,frame:64} = fn x => do:\n  if x<100:\n    let unused: forall [T:Type] where [Plain(T)] => Fn[local,Many,T,U32] ! {} resources {depth:1,frame:256} = fn value => do:\n      let _ = value\n      return x+1\n    return 0\n  return 0\n", true, 0);
    frontend_planned("let identity: forall [T:Type] => T -> T ! {} resources {depth:1,frame:256} = fn value => return value\nlet run: Unit -> Unit = fn () => do:\n  let identity = 1\n  let bad = identity@[U32]\n  return ()\n", false, FE_KIND);
    frontend_planned("let run: Unit -> Unit = fn () => do:\n  let identity = fn x => return x\n  return ()\n", false, FE_INTERFACE);
    frontend_planned("let run: Unit -> Unit = fn () => do:\n  let identity: forall [T:Type] => T -> T ! {} resources {depth:1,frame:256} = fn value => return value\n  let bad = identity\n  return ()\n", false, FE_INTERFACE);
    frontend_planned("let run: Unit -> Unit = fn () => do:\n  let identity: forall [T:Type] => T -> T ! {} resources {depth:1,frame:256} = fn value => return value\n  let escaped: T = ()\n  return ()\n", false, FE_UNBOUND);
    frontend_planned("let run: Unit -> Unit = fn () => do:\n  let recursive: forall [T:Type] => T -> T ! {} resources {depth:1,frame:256} = fn value => return recursive@[T](value)\n  return ()\n", false, FE_RECURSION);
    frontend_planned("let run: Unit -> Unit = fn () => do:\n  let unused: forall [T:Type] => T -> T ! {} resources {depth:1,frame:256} = fn value => return 0\n  return ()\n", false, FE_TYPE);
    frontend_planned("let run: Unit -> Unit = fn () => do:\n  let identity: forall [T:Type] => T -> T ! {} resources {depth:1,frame:256} = fn value => return value\n  let bad = identity@[U32,U32](0)\n  return ()\n", false, FE_KIND);
    frontend_planned("let run: Unit -> Unit = fn () => do:\n  if #True:\n    let identity: forall [T:Type] => T -> T ! {} resources {depth:1,frame:256} = fn value => return value\n  let bad = identity@[U32](0)\n  return ()\n", false, FE_UNBOUND);
}
fn test_frontend_reverse_alias_schedule() {
    var source: u8[>..] = [];
    for i in 1499 { source.append(str("type A", i, " = A", i + 1, "\n")); }
    source.append("type A1499 = U32\npub let run: A0 -> A0 ! {} resources {depth:1,frame:0} = fn input => return input\n");
    frontend_planned(source, true, 0);
    frontend_planned("type T[T:Type] = T\nlet run: T[U32] -> U32 = fn input => return input\n", true, 0);
    frontend_planned("type A = B\ntype B = A\n", false, FE_RECURSION);
    frontend_planned("type A[T:Type] = B[T]\ntype B[T:Type] = A[T]\n", false, FE_RECURSION);
}
fn test_frontend_value_dependency_schedule() {
    var source: u8[>..] = [];
    for i in 1499 { source.append(str("let f", i, ": U32 -> U32 ! {} resources {depth:1,frame:0} = fn value => return f", i + 1, "(value)\n")); }
    source.append("let f1499: U32 -> U32 ! {} resources {depth:1,frame:0} = fn value => return value\n");
    frontend_planned(source, false, FE_RESOURCE);
    var values: u8[>..] = [];
    for i in 199 { values.append(str("let f", i, ": Unit -> Unit ! {} resources {depth:1,frame:64} = fn () => do:\n  let _ = f", i + 1, "\n  return ()\n")); }
    values.append("let f199: Unit -> Unit ! {} resources {depth:1,frame:64} = fn () => return ()\n");
    frontend_planned(values, true, 0);
    frontend_planned("let identity: U32 -> U32 = fn identity => return identity\n", true, 0);
    frontend_planned("let f: Unit -> Unit = fn () => do:\n  let f = fn (u:Unit) => return ()\n  f(())\n  return ()\n", true, 0);
    frontend_planned("let f: Unit -> Unit = fn () => do:\n  if #False:\n    f(())\n  return ()\n", false, FE_RECURSION);
}
fn test_frontend_local_forall_shares_body() {
    var source: u8[>..] = []; assert(read_file("examples/local_generic.blot", source));
    with_core() { b => var w = Work { .. }; var ds: Diagnostic[>..] = []; assert(frontend_complete(source, "local-body-sharing", b, w, ds)); var function_id: u32 = 0; var markers: u32 = 0; var constructors: u32 = 0;
        for op in b.ops { if op.tag == OP_GENERIC_BIND { function_id = op.imm0; markers++; assert(op.results.count == 0); } }
        assert(markers == 1 && function_id != 0 && b.contracts[b.functions[function_id].contract].binders.count == 1);
        assert(b.functions[function_id].environment_bindings.count == 0);
        for op in b.ops { if op.tag == OP_CLOSURE && op.imm0 == function_id { constructors++; assert(op.substitutions.count == 1); } }
        assert(constructors == 2 && b.functions.len == 3);
        for value, id in b.values { if id != 0 { assert(b.types[value.type_id].tag != TY_FORALL); } }
    }
}
