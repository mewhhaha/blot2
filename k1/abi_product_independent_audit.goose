import abi_product_schema;
import abi_product_check;
import abi_product_link;
fn main(){
 let source="pub let identity: forall [T: Type] => Fn[static, Many, T, T] ! {} resources {depth: 1, frame: 256} = fn x => return x\n";
 for base in ["(U32,U32)","( U32 , U32 , U32 )","(U32,U32,U32,U32)"] {for i in base.len {for v in 128 {var s:u8[>..]=[];s.append(base);s[i]=v as u8;let a=abi_product_schema::count(s);let b=abi_product_check::count(s);assert(a==b);let c=abi_product_schema::canonical(s);if a==0 {assert(c.len==0);}else {assert(abi_product_check::verify(s,c));}}}}
 let typ="(U32,U32,U32)";var c=abi_product_link::make(source,typ,7);assert(c.status==0 && abi_product_link::verify(c,source,typ,7));
 for i in c.source.len {var q=copy(c);q.source[i]^=1;assert(!abi_product_link::verify(q,source,typ,7));}
 for i in c.policy_hash.len {var q=copy(c);q.policy_hash[i]^=1;assert(!abi_product_link::verify(q,source,typ,7));}
 for i in c.target.len {var q=copy(c);q.target[i]^=1;assert(!abi_product_link::verify(q,source,typ,7));}
 assert(!abi_product_link::verify(c,source,"(U32,U32)",7));assert(!abi_product_link::verify(c,source,typ,8));assert(!abi_product_link::public_eligible(c));
 print("independent product schema lexer, policy, source and target controls passed");
}
