import generic_fn_frontend;
import generic_fn_verify;
import generic_fn_wasm;

fn accepted(s:u8[:]) {
 let p=generic_fn_frontend::parse(s);
 if p.status!=0 {print("unexpected reject ",p.status," ",s);}assert(p.status==0 && generic_fn_verify::verify(s,p.program));
 assert(generic_fn_wasm::emit(s,p.program).len>0);
}
fn rejected(s:u8[:]) {
 let p=generic_fn_frontend::parse(s);
 assert(p.status!=0 && p.program.source.len==0);
}
fn main() {
 for name in ["f", "renamed", "value_42"] {
  for depth in ["1", "128"] {
   for frame in ["0", "4294967295"] {
    accepted(str("pub let ",name,": Fn[static, Many, U32, U32] ! {} resources {depth: ",depth,", frame: ",frame,"} = fn x => do:\n  return x\n"));
    accepted(str("pub let ",name,": U32 -> U32 ! {} resources {depth: ",depth,", frame: ",frame,"} = fn x => do:\n  return x\n"));
   }
  }
 }
 for depth in ["0", "129", "4294967296"] {rejected(str("pub let f: Fn[static,Many,U32,U32] ! {} resources {depth: ",depth,", frame: 0} = fn x => do:\n  return x\n"));}
 rejected("pub let f: Fn[static,Many,U32,U32] ! {} resources {depth: 1, frame: 4294967296} = fn x => do:\n  return x\n");
 rejected("pub let f: Fn[static,Many,Bool,U32] ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n");
 rejected("pub let f: Fn[static,Many,U32,U32] ! {write r} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n");
 rejected("pub let f: Fn[static,Many,U32,U32] ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x\npub let g: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n");
 let src="pub let f: Fn[static,Many,U32,U32] ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n";
 let p=generic_fn_frontend::parse(src);assert(p.status==0);
 let changed="pub let f: Fn[static,Many,U32,U32] ! {} resources {depth: 2, frame: 0} = fn x => do:\n  return x\n";
 assert(!generic_fn_verify::verify(changed,p.program) && generic_fn_wasm::emit(changed,p.program).len==0);
 print("independent callable signature boundary and source controls passed");
}
