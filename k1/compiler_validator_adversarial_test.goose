import compiler_core;
import compiler_validate;
import iteration_core;
import iteration_parse;
fn main() {
    let source="let f: U32 -> U32 = fn x => do:\n  let result = for i in 0..x carry (v=x) do:\n    if #True:\n      next (v)\n    else:\n      stop (v)\n  return result\n";
    let prefix="let f: U32 -> U32 = ";var tree,status=iteration_parse::parse(source[prefix.len..]);assert(status==0);
    var p=compiler_core::Program {source:source,variant:2,name_start:4,name_end:5,fn_start:prefix.len,body:copy(tree)};
    assert(compiler_validate::verify(source,p));
    let values:i64[]=[-1,0,1,2,127,128,2048,99999999,9223372036854775807];
    for i in p.body.nodes.len {let old=p.body.nodes[i];
      for field in 11 {for v in values {p.body.nodes[i]=old;var prior:i64=0;
        if field==0 {prior=old.tag;p.body.nodes[i].tag=v;}else if field==1 {prior=old.start;p.body.nodes[i].start=v;}
        else if field==2 {prior=old.end;p.body.nodes[i].end=v;}else if field==3 {prior=old.a;p.body.nodes[i].a=v;}
        else if field==4 {prior=old.b;p.body.nodes[i].b=v;}else if field==5 {prior=old.c;p.body.nodes[i].c=v;}
        else if field==6 {prior=old.d;p.body.nodes[i].d=v;}else if field==7 {prior=old.e;p.body.nodes[i].e=v;}
        else if field==8 {prior=old.f;p.body.nodes[i].f=v;}else if field==9 {prior=old.g;p.body.nodes[i].g=v;}
        else {prior=old.target;p.body.nodes[i].target=v;}
        if prior!=v {assert(!compiler_validate::verify(source,p));}
      }}p.body.nodes[i]=old;
    }
    for i in p.body.bindings.len {let old=p.body.bindings[i];for field in 4 {for v in values {p.body.bindings[i]=old;var prior:i64=0;
      if field==0 {prior=old.start;p.body.bindings[i].start=v;}else if field==1 {prior=old.end;p.body.bindings[i].end=v;}
      else if field==2 {prior=old.kind;p.body.bindings[i].kind=v;}else {prior=old.scope;p.body.bindings[i].scope=v;}
      if prior!=v {assert(!compiler_validate::verify(source,p));}
    }}p.body.bindings[i]=old;}
    for i in source.len {let old=p.source[i];p.source[i]='?';if old!='?' {assert(!compiler_validate::verify(source,p));}p.source[i]=old;}
    let old=p.body.source[0];p.body.source[0]='?';assert(!compiler_validate::verify(source,p));p.body.source[0]=old;
    for v in [-1 as i64,0,1,99999999,9223372036854775807] {if v!=p.fn_start {let oldfn=p.fn_start;p.fn_start=v;assert(!compiler_validate::verify(source,p));p.fn_start=oldfn;}}
    assert(compiler_validate::verify(source,p));
    print("all compiler loop syntax, scope, target and source forgeries rejected");
}
