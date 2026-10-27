import os;
import abi_product_link;
import abi_product_check;
import abi_product_schema;
fn main(){
 let source="pub let identity: forall [T: Type] => Fn[static, Many, T, T] ! {} resources {depth: 1, frame: 256} = fn x => return x\n";
 for n in 2..17 {var typ:u8[>..]=[];typ.push('(');for i in n {if i>0 {typ.push(',');}typ.append("U32");}typ.push(')');
  var c=abi_product_link::make(source,typ,7);assert(c.status==0 && abi_product_link::verify(c,source,typ,7) && !abi_product_link::public_eligible(c));
  assert(c.dictionary.dictionary.size==4*n && c.dictionary.dictionary.flags==3);
  for i in c.schema.len {var b=copy(c);b.schema[i]^=1;assert(!abi_product_link::verify(b,source,typ,7));assert(!abi_product_check::verify(typ,c.schema[..i]));}
  for i in c.target.len {var b=copy(c);b.target[i]^=1;assert(!abi_product_link::verify(b,source,typ,7));}
  for i in c.dictionary.schema.len {var b=copy(c);b.dictionary.schema[i]^=1;assert(!abi_product_link::verify(b,source,typ,7));}
  for i in c.type_source.len {var b=copy(c);b.type_source[i]^=1;assert(!abi_product_link::verify(b,source,typ,7));}
  assert(!abi_product_link::verify(c,source,typ,8));var b=copy(c);b.dictionary.dictionary.size+=1;assert(!abi_product_link::verify(b,source,typ,7));
  assert(write_file("abi-product.wasm",c.target));
 }
 for bad in ["()","(U32)","(U32,)","(U32,F32)","(U32,U32)junk","(U32,U32)//comment","(U32,\nU32)"] {assert(abi_product_schema::canonical(bad).len==0 && abi_product_check::count(bad)==0 && abi_product_link::make(source,bad,7).status!=0);}
 let spaced="( U32 , U32 )";assert(abi_product_link::make(source,spaced,7).status==0);
 print("private U32 product schema binds exact generic source, dictionary and target");
}
