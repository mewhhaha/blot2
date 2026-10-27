import source_owned_parse;
import source_owned_verify;
import source_owned_core;
fn check(s:u8[:],want:bool) {var p=source_owned_parse::build(s);let ok=p.status==0 && source_owned_verify::verify(s,p.program);if ok!=want {print("unexpected ",p.status," expected ",want," source ",s);}assert(ok==want);}
fn main() {
 let unit="type Scalar[r: Region] = U32\nlet run: (Owned[Scalar[_]], Bool) -> Unit ! {release} = fn (h, flag) => do:\n  owned.close(h)\n  return ()\n";
 let moved="type Scalar[r: Region] = U32\nlet run: (Owned[Scalar[_]], Bool) -> Owned[Scalar[_]] ! {release} = fn (h, flag) => do:\n  if flag:\n    let next_owner = h\n    return next_owner\n  else:\n    return h\n";
 let opened="type Scalar[r: Region] = U32\nlet run: (Owned[Scalar[_]], Bool) -> U32 ! {release} = fn (h, flag) => do:\n  let value = owned.open(h) as r data in do:\n    break data\n  owned.close(h)\n  return value\n";
 check(unit,true);check(moved,true);check(opened,true);
 check("type Scalar[r: Region] = U32\nlet run: (Owned[Scalar[_]], U32) -> Unit ! {release} = fn (h, flag) => do:\n  owned.close(h)\n  return ()\n",false);
 check("type Scalar[r: Region] = U32\nlet run: (Owned[Scalar[_]], Bool) -> Unit ! {} = fn (h, flag) => do:\n  owned.close(h)\n  return ()\n",false);
 check("type Scalar[r: Region] = U32\nlet Scalar: (Owned[Scalar[_]], Bool) -> Unit ! {release} = fn (h, flag) => do:\n  owned.close(h)\n  return ()\n",false);
 check("type Scalar[r: Region] = U32\nlet run: (Owned[Scalar[_]], Bool) -> Unit ! {release} = fn (h, h) => do:\n  owned.close(h)\n  return ()\n",false);
 check("type Scalar[r: Region] = U32\nlet run: (Owned[Scalar[_]], Bool) -> U32 ! {release} = fn (h, flag) => do:\n  let value = owned.open(h) as r data in do:\n    owned.close(h)\n    break data\n  return value\n",false);
 check("type Scalar[r: Region] = U32\nlet run: (Owned[Scalar[_]], Bool) -> Unit ! {release} = fn (h, flag) => do:\n  if flag:\n    owned.close(h)\n  return ()\n",false);
 check("type Scalar[r: Region] = U32\nlet run: (Owned[Scalar[_]], Bool) -> Owned[Scalar[_]] ! {release} = fn (h, flag) => do:\n  let moved = h\n  return h\n",false);
 var p=source_owned_parse::build(opened);assert(p.status==0 && source_owned_verify::verify(opened,p.program));
 var h=p.program.head;h.mode=0;var q=source_owned_core::Program {source:copy(p.program.source),head:h,tree:copy(p.program.tree)};assert(!source_owned_verify::verify(opened,q));
 h=p.program.head;h.owner_start+=1;var q2=source_owned_core::Program {source:copy(p.program.source),head:h,tree:copy(p.program.tree)};assert(!source_owned_verify::verify(opened,q2));
 h=p.program.head;h.body+=1;var q3=source_owned_core::Program {source:copy(p.program.source),head:h,tree:copy(p.program.tree)};assert(!source_owned_verify::verify(opened,q3));
 var tree=copy(p.program.tree);tree.nodes[0].tag=99;var q4=source_owned_core::Program {source:copy(p.program.source),head:p.program.head,tree:copy(tree)};assert(!source_owned_verify::verify(opened,q4));
 print("source-derived owned function contract and lexical loans passed");
}
