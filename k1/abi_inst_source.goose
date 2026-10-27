// Exact-source one-module experiment; no general generic checker.
namespace abi_inst_source;
import abi_product_schema;
import abi_product_check;
fn generic()->u8[:] {return "pub let identity: forall [T: Type] => Fn[static, Many, T, T] ! {} resources {depth: 1, frame: 256} = fn x => return x\n";}
fn head()->u8[:] {return "pub let apply: Fn[static, Many, ";}
struct Type {ok:bool=false,start:i64=0,end:i64=0,count:i64=0}
fn parse(module:u8[:])->Type {
 if module.len>4096 || module.len<generic().len+head().len || module[..generic().len]!=generic() || module[generic().len..generic().len+head().len]!=head(){return Type {};}
 let start=generic().len+head().len;var end=start;while end<module.len && module[end]!=')' {end+=1;}if end>=module.len{return Type {};}end+=1;
 let n=abi_product_schema::count(module[start..end]);if n==0{return Type {};}
 return Type {ok:true,start:start,end:end,count:n};
}
// Independently build the entire canonical declaration from the source tuple;
// there can be no unparsed extra declaration, shadowed name or caller token.
fn verify(module:u8[:],t:Type)->bool {
 let base=generic().len+head().len;if !t.ok || t.start!=base || t.end<t.start || t.end>module.len{return false;}
 let typ=module[t.start..t.end];let n=abi_product_check::count(typ);if n==0 || n!=t.count{return false;}
 var canonical:u8[>..]=[];canonical.append(generic());canonical.append(head());canonical.append(typ);canonical.append(", ");canonical.append(typ);
 canonical.append("] ! {} resources {depth: 2, frame: 256} = fn x => return identity@[");canonical.append(typ);canonical.append("](x)\n");
 return canonical[..]==module;
}
