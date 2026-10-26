import abi_profile_build;
import abi_profile_verify;
import abi_profile_manifest_build;
import abi_profile_manifest_verify;
import m12_adapter_schema;
import blake3;
fn source(x:u8[:],y:u8[:])->u8[] {
    var out:u8[>..]=[];
    out.append("pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: ");
    out.append(x);out.append(", y: ");out.append(y);out.append("}))\n  return builder.freeze(built)\n");return out;
}


fn main() {
 let profile=abi_profile_build::canonical();let digest=abi_profile_build::digest();assert(profile.len>0 && abi_profile_verify::verify_digest(profile,digest));
 let frozen:u8[32]=[0xd6,0xb5,0x74,0xeb,0x25,0xe6,0xd7,0x9f,0x92,0x0f,0x0e,0xe8,0x55,0xb8,0x6d,0x0b,
  0xcc,0x8a,0xae,0x11,0xd3,0x84,0xc6,0xee,0x82,0xa0,0x4e,0x1e,0x32,0x3b,0xdb,0x9e];
 assert(digest[..]==frozen[..]);
 assert(abi_profile_verify::matching_fields(profile,digest,digest,digest,digest));
 var wrong=digest;wrong[31]^=1;
 assert(!abi_profile_verify::matching_fields(profile,wrong,digest,digest,digest));
 assert(!abi_profile_verify::matching_fields(profile,digest,wrong,digest,digest));
 assert(!abi_profile_verify::matching_fields(profile,digest,digest,wrong,digest));
 assert(!abi_profile_verify::matching_fields(profile,digest,digest,digest,wrong));
 assert(!abi_profile_verify::matching_fields(profile,digest[..31],digest,digest,digest));
 for i in profile.len {var altered:u8[>..]=[];altered.append(profile);altered[i]^=1;let recomputed=blake3::hash(altered);
  assert(!abi_profile_verify::verify(altered) && !abi_profile_verify::verify_digest(altered,recomputed));}
 for i in profile.len {assert(!abi_profile_verify::verify(profile[..i]));}
 var badhash=digest;badhash[0]^=1;assert(!abi_profile_verify::verify_digest(profile,badhash));
 let kernel=source("source[i].x + source[i].vx * dt","source[i].y + source[i].vy * dt");let adapter=m12_adapter_schema::source();
 let envelope=abi_profile_manifest_build::make(kernel,adapter,"pkg","project.blot");
 assert(envelope.len>0 && abi_profile_manifest_verify::verify(envelope,kernel,adapter,"pkg","project.blot"));
 let other=source("source[i].vx","source[i].x");assert(!abi_profile_manifest_verify::verify(envelope,other,adapter,"pkg","project.blot"));
 assert(!abi_profile_manifest_verify::verify(envelope,kernel,adapter,"wrong","project.blot"));
 for i in envelope.len {var altered:u8[>..]=[];altered.append(envelope);altered[i]^=1;
  assert(!abi_profile_manifest_verify::verify(altered,kernel,adapter,"pkg","project.blot"));}
 for i in envelope.len {assert(!abi_profile_manifest_verify::verify(envelope[..i],kernel,adapter,"pkg","project.blot"));}
 var extra:u8[>..]=[];extra.append(envelope);extra.push(0);assert(!abi_profile_manifest_verify::verify(extra,kernel,adapter,"pkg","project.blot"));
 print("private compiler-owned ABI profile and manifest corruption checks passed");
}
