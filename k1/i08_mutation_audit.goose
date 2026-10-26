import std;
import i08_parse;
import i08_verify;
fn main(){
 let source="fn (source,dt,initial) => do:\n  let built = for i in 0..source.length carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: source[i].x + source[i].vx * dt, y: source[i].y + source[i].vy * dt}))\n  return builder.freeze(built)\n";
 var original,status=i08_parse::parse(source);assert(status==0 && i08_verify::verify(original,source));
 var bytes:u8[>..]=[];bytes.append(source);let replacements:u8[12]=['[',']',')','.', 'x',' ', '0','?', '/', '\n','*','+'];var accepted=0;var rejected=0;
 for i in bytes.len {let old=bytes[i];for c in replacements {bytes[i]=c;var tree,st=i08_parse::parse(bytes);if st==0 {accepted+=1;assert(i08_verify::verify(tree,bytes));} else {rejected+=1;}if c!=old {assert(!i08_verify::verify(original,bytes));}}bytes[i]=old;}
 print(str("independent I08 mutation parity: ",accepted," accepted, ",rejected," rejected"));
}
