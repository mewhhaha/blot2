import i08_parse;
import i08_verify;
fn main(){
 let src="fn (a,b,c) => do:\n  return a + b * c\n";var t,e=i08_parse::parse(src);assert(e==0 && i08_verify::verify(t,src));
 let root=t.nodes[t.root-1];let ret=t.nodes[root.a-1];let add=t.nodes[ret.a-1];assert(add.tag==21 && t.nodes[add.a-1].tag==1 && t.nodes[add.b-1].tag==25);
 let grouped="fn (a,b,c) => do:\n  return (a + b) * c\n";var z,status=i08_parse::parse(grouped);assert(status==0 && i08_verify::verify(z,grouped));let fnroot=z.nodes[z.root-1];let r=z.nodes[fnroot.a-1];let mul=z.nodes[r.a-1];assert(mul.tag==25 && z.nodes[mul.a-1].tag==20 && z.nodes[z.nodes[mul.a-1].a-1].tag==21);
 for bad in ["fn (builder,x) => do:\n  return builder.append(x,x)\n","fn (source) => do:\n  for i in 0..source.length do:\n    continue\n  return source[i].x\n","fn (source,x) => do:\n  if x:\n    let y = source[0].x\n  return y\n"] {let _,st=i08_parse::parse(bad);assert(st!=0);}
 print("independent I08 precedence and lexical scope controls passed");
}
