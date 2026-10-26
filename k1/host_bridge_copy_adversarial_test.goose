import host_bridge_copy;
fn next(seed: u32&) -> u32 { seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5; return seed; }
fn word(s: u8[:], p: i64) -> u32 { return s[p] as u32 | (s[p+1] as u32 << 8) | (s[p+2] as u32 << 16) | (s[p+3] as u32 << 24); }
fn put(s: u8[:], p: i64, n: u32) { for i in 4 { s[p+i] = (n >> (8*i) & 255) as u8; } }
// Independent decoder specialized to the single concrete manifest, including
// descriptor extent and every unclaimed padding byte.
fn accepts(s: u8[:], export_id: u32, input_bytes: u32, capacity: u32) -> bool {
    if export_id != 17 || input_bytes < 32 || input_bytes > 128 || capacity > 96 { return false; }
    let payload = input_bytes - 32;
    if word(s,0) != 0x4b310001 || word(s,4) != 17 || word(s,8) != 0 || word(s,12) != payload ||
       word(s,16) != 0 || word(s,20) != 0 || word(s,24) != 0 || word(s,28) != 0 || payload < 12 { return false; }
    let count = word(s,36); let off = word(s,40);
    if count > 4 || off % 4 != 0 || off < 12 || off > payload || count * 4 > payload - off { return false; }
    for p in 12..payload { if !(p >= off && p < off + count * 4) && s[32 + p] != 0 { return false; } }
    return true;
}
fn main() {
 var seed: u32 = 0x7ac3419b; var valid = 0; var invalid = 0; var small = 0; var ok = 0;
 for trial in 12000 {
  var state = host_bridge_copy::State {}; state.frames = 7;
  for p in 128 { state.egress[p] = 0xa5; }
  let count = next(seed) % 5; let off = 12 + (next(seed) % 5) * 4;
  let payload = off + count * 4 + (next(seed) % 3) * 4;
  put(state.ingress,0,0x4b310001); put(state.ingress,4,17); put(state.ingress,12,payload);
  put(state.ingress,32,next(seed)); put(state.ingress,36,count); put(state.ingress,40,off);
  for i in count { put(state.ingress,32 + off as i64 + i as i64 * 4,next(seed)); }
  var input_bytes = 32 + payload; var cap = next(seed) % 30; var id: u32 = 17;
  let mutation = next(seed) % 7;
  if mutation == 1 { let pos = next(seed) % 128; state.ingress[pos] ^= (next(seed) % 255 + 1) as u8; }
  if mutation == 2 { put(state.ingress, 36, next(seed)); }
  if mutation == 3 { put(state.ingress, 40, next(seed)); }
  if mutation == 4 { input_bytes = next(seed) % 160; }
  if mutation == 5 { cap = next(seed) % 150; }
  if mutation == 6 { id = next(seed); }
  let before_input = copy(state.ingress); let before_out = copy(state.egress); let pre = accepts(state.ingress,id,input_bytes,cap);
  let got = host_bridge_copy::invoke(state,id,input_bytes,cap,0);
  assert(state.ingress[..] == before_input[..]);
  assert(!state.busy && state.frames == 7 && state.bitmap[0] == 0 && state.slots[0].state == 0);
  assert(word(state.egress,0) == 0x4b310001 && word(state.egress,4) == 17 && word(state.egress,28) == 0);
  if !pre {
    invalid += 1; assert(got == 1 && word(state.egress,8) == 1 && word(state.egress,12) == 0 && word(state.egress,16) == 0 && word(state.egress,20) == 0 && word(state.egress,24) == 0);
    assert(state.calls == 0 && state.egress[32..] == before_out[32..]);
  } else {
    valid += 1; let n = word(state.ingress,36); let o = word(state.ingress,40); let mask = word(state.ingress,32); let need = 8 + n * 4;
    assert(state.calls == 1);
    if cap < need {
      small += 1; assert(got == 2 && word(state.egress,8) == 2 && word(state.egress,12) == 0 && word(state.egress,16) == need && word(state.egress,20) == n);
      assert(state.egress[32..] == before_out[32..]);
    } else {
      ok += 1; assert(got == 0 && word(state.egress,8) == 0 && word(state.egress,12) == need && word(state.egress,16) == need && word(state.egress,20) == n);
      assert(word(state.egress,32) == n && word(state.egress,36) == 8);
      for i in n { assert(word(state.egress,40 + i as i64 * 4) == (word(state.ingress,32 + o as i64 + i as i64 * 4) ^ mask)); }
      for p in 32 + need..128 { assert(state.egress[p] == 0xa5); }
    }
  }
 }
 assert(valid > 0 && invalid > 0 && small > 0 && ok > 0);
 print("independent bridge fuzz: valid ",valid,", invalid ",invalid,", too-small ",small,", ok ",ok);
}
