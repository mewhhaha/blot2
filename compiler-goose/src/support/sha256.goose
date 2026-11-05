// Streaming SHA-256 for the memory-profile/live-instance fingerprint.
namespace blot_support_sha256;
let initial:u32[8]=[0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
let constants:u32[64]=[
0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
struct State {words:u32[8]=initial,block:u8[64]=[0;64],used:i64=0,bytes:u64=0}
fn init()->State {return State{..};}
fn rotate(value:u32,bits:u32)->u32 {return (value>>bits)|(value<<(32-bits));}
fn compress(self:State&) {
    var schedule:u32[64]=[0;64];for index in 16 {let at=index*4;schedule[index]=(self.block[at] as u32<<24)|(self.block[at+1] as u32<<16)|(self.block[at+2] as u32<<8)|self.block[at+3];}
    for index in 16..64 {let x=schedule[index-15];let y=schedule[index-2];let a=rotate(x,7)^rotate(x,18)^(x>>3);let b=rotate(y,17)^rotate(y,19)^(y>>10);schedule[index]=schedule[index-16]+a+schedule[index-7]+b;}
    var a=self.words[0];var b=self.words[1];var c=self.words[2];var d=self.words[3];var e=self.words[4];var f=self.words[5];var g=self.words[6];var h=self.words[7];
    for index in 64 {let choice=(e&f)^((e^0xffffffff)&g);let first=h+(rotate(e,6)^rotate(e,11)^rotate(e,25))+choice+constants[index]+schedule[index];let majority=(a&b)^(a&c)^(b&c);let second=(rotate(a,2)^rotate(a,13)^rotate(a,22))+majority;h=g;g=f;f=e;e=d+first;d=c;c=b;b=a;a=first+second;}
    self.words[0]+=a;self.words[1]+=b;self.words[2]+=c;self.words[3]+=d;self.words[4]+=e;self.words[5]+=f;self.words[6]+=g;self.words[7]+=h;
}
fn update(self:State&,bytes:const u8[:]) {self.bytes+=bytes.len as u64;for byte in bytes {self.block[self.used]=byte;self.used++;if self.used==64 {self.compress();self.used=0;}}}
fn final(source:State)->u8[32] {var self=source;let bits=self.bytes*8;self.block[self.used]=0x80;self.used++;if self.used>56 {for index in self.used..64 {self.block[index]=0;}self.compress();self.used=0;}for index in self.used..56 {self.block[index]=0;}for index in 8 {self.block[56+index]=(bits>>((7-index)*8)) as! u8;}self.compress();var result:u8[32]=[0;32];for word,index in self.words {for byte in 4 {result[index*4+byte]=(word>>((3-byte)*8)) as! u8;}}return result;}
