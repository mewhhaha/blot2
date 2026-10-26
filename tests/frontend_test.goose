import src.frontend;
fn frontend_parse_ok(source: const u8[:]) {
    var nodes: AstNode[>..] = []; var refs: u32[>..] = [];
    let parsed = parse_source(source, nodes, refs);
    if parsed.root == 0 { print("parse rejected at ", parsed.start, ": ", parsed.category, " ", parsed.message, "\n", source); }
    assert(parsed.root != 0);
}
fn frontend_parse_reject(source: const u8[:], category: const u8[:]) {
    var nodes: AstNode[>..] = []; var refs: u32[>..] = [];
    let parsed = parse_source(source, nodes, refs); assert(parsed.root == 0); assert(parsed.category == category);
}
fn test_frontend() {
    frontend_parse_ok("let a: U32 -> U32 = fn x => return x\nlet b: U32 -> U32 = fn x => do:\n  return x\nlet c: U32 -> U32 = fn x => return do:\n  break x\n");
    frontend_parse_ok("pub let identity: forall [T: Type] =>\n  Fn[static, Many, T, T] ! {} resources {depth: 1, frame: 256}\n= fn x => return x\n");
    frontend_parse_ok("type Graph[r: Region, T: Type] where [Plain(T)] =\n  exists [d: Domain, n: Nat, e: Domain, m: Nat] =>\n    {nodes: View[r,T,n,d], edges: View[r,(Index[d,n],Index[d,n]),m,e]}\n");
    frontend_parse_ok("let f: U32 -> U32 = fn x => do:\n  if x < 5:\n    return x\n  else:\n    return 0\n");
    frontend_parse_ok("let f: Unit -> Unit = fn () => do:\n  let x = for i in 0..10 carry (b = 0)\n    invariant [Eq(b,i)] do:\n      next (b + 1)\n  return ()\n");
    frontend_parse_ok("let f: Unit -> Unit = fn () => do:\n  case #Some(1):\n    #Some(x) => return ()\n    #None => do:\n      return ()\n");
    frontend_parse_ok("let f: Unit -> Result[Unit,ReserveError] ! {reserve,release}\n= fn () => return region@[Unit](0) as r (owner,free) in do:\n  space.end(free)\n  region.close(owner)\n  break ()\n");
    frontend_parse_ok("let f: Unit -> Unit = fn () => do:\n  let x = owned@[Payload[_],#Cancelled](0) as r free in do:\n    seal(free,())\n  return ()\n");
    frontend_parse_ok("let f: Unit -> Unit = fn () => do:\n  let x = owned.open(handle) as r payload in do:\n    break payload\n  let y = open graph as [d,n,e,m] g in do:\n    break g.nodes[0]\n  return ()\n");
    frontend_parse_reject("let f = fn x => do:\n\treturn x\n", "k1_syntax");
    frontend_parse_reject("let x = 4294967296\n", "k1_syntax");
    frontend_parse_reject("let x = 1 < 2 < 3\n", "k1_syntax");
    frontend_parse_reject("let f: U32 -> U32 requires [Magic(arg,1)] = fn x => return x\n", "k1_unsupported_fact");
    frontend_parse_reject("let x = (1,2]\n", "k1_syntax");
    print("frontend syntax laws passed");
}

import src.validate;
fn frontend_semantic_law(source: const u8[:], error: u32) {
    with_core() { b =>
        var work = Work { .. }; var diagnostics: Diagnostic[>..] = [];
        let ok = frontend_complete(source, "frontend-law", b, work, diagnostics);
        if error == 0 {
            if !ok { for d in diagnostics { print("frontend unexpected ", frontend_diagnostic_name(d.code), " ", name_bytes(core_view(b), d.detail)); } }
            assert(ok); assert(seal_completion(b)); var validation_work = Work { .. };
            let valid = validator::validate_core(core_view(b), 0, validation_work, diagnostics);
            if !valid { for d in diagnostics { print("validation unexpected ", d.code, " related ", d.related); } }
            assert(valid); assert(b.phase.active == 0); assert(b.phase.created == b.phase.completed);
        } else { assert(!ok); assert(diagnostics.len > 0); assert(diagnostics[0].code == error); }
    }
}
fn test_frontend_semantics() {
    frontend_semantic_law("pub let a: U32 -> U32 ! {} resources {depth: 1, frame: 256} = fn x => return x\n", 0);
    frontend_semantic_law("pub let a: U32 -> U32 ! {} resources {depth: 1, frame: 256} = fn x => return do:\n  break x\n", 0);
    frontend_semantic_law("pub let a: (U32,U32) -> Result[U32,#Overflow] ! {} resources {depth: 1, frame: 256} = fn (x,y) => do:\n  if U32.fits_add(x,y):\n    return #Ok(x+y)\n  return #Err(#Overflow)\n", 0);
    frontend_semantic_law("pub let a: Result[U32,#Oops] -> U32 ! {} resources {depth: 1, frame: 256} = fn x => do:\n  case x:\n    #Ok(n) => return n\n    #Err(e) => return 0\n", 0);
    frontend_semantic_law("pub let identity: forall [T: Type] =>\n  Fn[static, Many, T, T] ! {} resources {depth: 1, frame: 256}\n= fn x => return x\npub let main: U32 -> U32 ! {} resources {depth: 2, frame: 512} = fn x => return identity@[U32](x)\n", 0);
    frontend_semantic_law("pub let lookup:\n  forall [r: Region, T: Type, n: Nat, d: Domain] where [Plain(T)] =>\n  Fn[static, Many, (View[r,T,n,d], U32), #None | #Some(T)]\n  ! {read r} resources {depth: 1, frame: 512}\n= fn (a,i) => do:\n  if i < a.length:\n    return #Some(a[i])\n  return #None\n", 0);
    frontend_semantic_law("let a: U32 -> U32 = fn x => do:\n  x\n", FE_RETURN);
    frontend_semantic_law("let a: U32 -> U32 = fn x => do:\n  break x\n", FE_TARGET);
    frontend_semantic_law("let a: (U32,U32) -> U32 = fn (x,y) => return x+y\n", FE_ARITHMETIC);
    frontend_semantic_law("let a: Result[U32,#Oops] -> Unit = fn x => do:\n  let _ = x\n  return ()\n", FE_RESULT);
    frontend_semantic_law("let a: U32 -> U32 = fn x => return a(x)\n", FE_RECURSION);
    frontend_semantic_law("pub let a: U32 -> U32 = fn x => return x\n", FE_INTERFACE);
    print("frontend semantic laws passed");
}
